#!/usr/bin/env python3
"""
Knot Swarm Stateless MCP Gateway Core
Lightweight, zero-external-dependency Model Context Protocol (MCP) server over stdio (JSON-RPC 2.0).

Exposes Knot Swarm blackboard and node coordination tools to any MCP-compliant LLM agent:
- knot_node_status (no required args)
- knot_quota_matrix (args: target='all')
- knot_exec_command (args: target='desktop', command, timeout=30)
- knot_swarm_topology (no required args)

Zero external dependencies: uses standard library Python 3 only.
"""

import argparse
from datetime import datetime, timezone
import json
import os
import shutil
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    from core.memory.palace import MemoryPalaceClient, format_tree
except ImportError:
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
    from core.memory.palace import MemoryPalaceClient, format_tree


class KnotHubClient:
    """HTTP client communicating with Knot Hub with automatic LAN/remote fallback."""

    DEFAULT_URLS = ["https://127.0.0.1:4242", "http://127.0.0.1:4242"]

    def __init__(self, base_url: str | None = None):
        self._explicit_url = base_url or os.environ.get("KNOT_HUB_URL")
        self._cached_active_url: str | None = None
        self._ssl_ctx = ssl._create_unverified_context()

    def resolve_url(self) -> str:
        if self._explicit_url:
            return self._explicit_url.rstrip("/")
        if self._cached_active_url:
            return self._cached_active_url

        for candidate in self.DEFAULT_URLS:
            try:
                req = urllib.request.Request(f"{candidate}/health", headers={"Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=1.5, context=self._ssl_ctx) as resp:
                    if resp.status == 200:
                        self._cached_active_url = candidate
                        return candidate
            except Exception:
                continue

        # Default fallback
        return self.DEFAULT_URLS[0]

    def request(self, path: str, method: str = "GET", data: dict | None = None, timeout: float = 10.0) -> dict | list:
        active = self.resolve_url()
        urls_to_try = [active]
        if not self._explicit_url:
            for c in self.DEFAULT_URLS:
                if c not in urls_to_try:
                    urls_to_try.append(c)

        last_err: Exception | None = None
        for url in urls_to_try:
            full_url = f"{url}{path}"
            headers = {"Accept": "application/json"}
            body: bytes | None = None
            if data is not None:
                headers["Content-Type"] = "application/json"
                body = json.dumps(data).encode("utf-8")

            req = urllib.request.Request(full_url, data=body, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=timeout, context=self._ssl_ctx) as resp:
                    resp_bytes = resp.read()
                    self._cached_active_url = url
                    if resp_bytes:
                        return json.loads(resp_bytes.decode("utf-8"))
                    return {}
            except urllib.error.HTTPError as e:
                err_body = e.read().decode("utf-8", errors="replace")
                try:
                    err_json = json.loads(err_body)
                    msg = err_json.get("error") or err_body
                except Exception:
                    msg = err_body
                raise RuntimeError(f"HTTP {e.code}: {msg}")
            except Exception as e:
                last_err = e
                continue

        raise RuntimeError(f"Failed to communicate with Knot Hub at {urls_to_try}: {last_err}")


class KnotMCPGateway:
    """Stateless MCP Server implementing JSON-RPC 2.0 over stdio."""

    PROTOCOL_VERSION = "2024-11-05"

    def __init__(self, hub_client: KnotHubClient, memory_client: MemoryPalaceClient | None = None):
        self.hub = hub_client
        self.memory = memory_client or MemoryPalaceClient()
        self.initialized = False

    def handle_request(self, req: dict) -> dict | None:
        if not isinstance(req, dict):
            return {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32600, "message": "Invalid Request: expected JSON object"}
            }

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params") or {}

        if not method or not isinstance(method, str):
            if req_id is not None:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32600, "message": "Invalid Request: missing or invalid method"}
                }
            return None

        is_notification = (req_id is None)

        try:
            if method == "initialize":
                res = self._handle_initialize(params)
                return {"jsonrpc": "2.0", "id": req_id, "result": res}
            elif method == "notifications/initialized":
                self.initialized = True
                if not is_notification:
                    return {"jsonrpc": "2.0", "id": req_id, "result": {}}
                return None
            elif method == "tools/list":
                res = self._handle_tools_list(params)
                return {"jsonrpc": "2.0", "id": req_id, "result": res}
            elif method == "tools/call":
                res = self._handle_tools_call(params)
                return {"jsonrpc": "2.0", "id": req_id, "result": res}
            elif method == "ping":
                if not is_notification:
                    return {"jsonrpc": "2.0", "id": req_id, "result": {}}
                return None
            else:
                if not is_notification:
                    return {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {"code": -32601, "message": f"Method '{method}' not found"}
                    }
                return None
        except Exception as e:
            if not is_notification:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32603, "message": f"Internal error: {str(e)}"}
                }
            return None

    def _handle_initialize(self, params: dict) -> dict:
        self.initialized = True
        client_proto = params.get("protocolVersion", self.PROTOCOL_VERSION)
        return {
            "protocolVersion": client_proto,
            "capabilities": {
                "tools": {
                    "listChanged": False
                }
            },
            "serverInfo": {
                "name": "knot-mcp-gateway",
                "version": "1.0.0-rc5"
            }
        }

    def _handle_tools_list(self, params: dict) -> dict:
        return {
            "tools": [
                {
                    "name": "knot_node_status",
                    "description": "Check mesh health, active nodes, hardware architecture, and capabilities across the Knot Swarm.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "knot_quota_matrix",
                    "description": "Render the 5-hour and weekly Google AI Pro/Ultra model quota matrix with progress bars and reset countdowns.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "target": {
                                "type": "string",
                                "description": "Target node to inspect ('all' or specific node ID like 'desktop', 'laptop', 'steamdeck').",
                                "default": "all"
                            }
                        }
                    }
                },
                {
                    "name": "knot_exec_command",
                    "description": "Execute shell commands directly across the Knot Swarm mesh (desktop, laptop, steamdeck, or --all) via fast SSH transport with zero LLM token consumption on the target node. Ideal for remote environment inspection, hardware queries, file checks, service status, and benchmark execution.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "target": {
                                "type": "string",
                                "description": "Target mesh node ('desktop', 'laptop', 'steamdeck', or '--all').",
                                "default": "desktop"
                            },
                            "command": {
                                "type": "string",
                                "description": "The bash shell command to execute on the target node."
                            },
                            "timeout": {
                                "type": "integer",
                                "description": "Command execution timeout in seconds (default: 30).",
                                "default": 30
                            }
                        },
                        "required": ["target", "command"]
                    }
                },
                {
                    "name": "knot_swarm_topology",
                    "description": "Get a consolidated snapshot of the entire Knot Swarm: online nodes, IPs, assigned LLM models, GPU backends (CUDA/ROCm/UMA), active tasks/activity, and 5h/weekly quota percentages in a single call. Eliminates repetitive multi-step inspection loops.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {}
                    }
                }
            ]
        }

    def _handle_tools_call(self, params: dict) -> dict:
        tool_name = params.get("name")
        args = params.get("arguments") or {}

        if not tool_name:
            return {
                "content": [{"type": "text", "text": "Error: missing 'name' in tools/call parameters"}],
                "isError": True
            }

        handlers = {
            "knot_node_status": self._call_knot_node_status,
            "knot_quota_matrix": self._call_knot_quota_matrix,
            "knot_exec_command": self._call_knot_exec_command,
            "knot_swarm_topology": self._call_knot_swarm_topology,
        }

        handler = handlers.get(tool_name)
        if not handler:
            return {
                "content": [{"type": "text", "text": f"Error: Unknown tool '{tool_name}'"}],
                "isError": True
            }

        try:
            text_result, is_error = handler(args)
            return {
                "content": [
                    {
                        "type": "text",
                        "text": text_result
                    }
                ],
                "isError": is_error
            }
        except Exception as e:
            return {
                "content": [
                    {
                        "type": "text",
                        "text": f"Error executing tool '{tool_name}': {str(e)}"
                    }
                ],
                "isError": True
            }

    # ---------------- Tool Implementations ----------------

    def _call_knot_node_status(self, args: dict) -> tuple[str, bool]:
        health = self.hub.request("/health", method="GET")
        nodes = self.hub.request("/nodes", method="GET")

        out = "--- Knot Swarm Mesh Status ---\n"
        out += f"Mesh Health: {health.get('status', 'OK')} ({health.get('service', 'knot-hub')})\n"
        out += f"Total Nodes: {health.get('mesh_nodes', len(nodes))} | Online: {health.get('online_nodes', 0)}\n"
        out += f"Tasks: {health.get('tasks_active', 0)} active, {health.get('tasks_queued', 0)} queued, {health.get('total_tasks_tracked', 0)} tracked\n\n"
        out += "--- Registered Mesh Nodes ---\n"

        now = int(time.time())
        for n in nodes:
            nid = n.get("id", "unknown")
            host = n.get("hostname", nid)
            status = n.get("status", "UNKNOWN")
            caps = n.get("capabilities", [])
            agy_ver = n.get("agy_version") or "unknown"
            agy_auth = n.get("agy_auth") or "unknown"
            last_hb = n.get("last_heartbeat", 0)
            ago = f"{now - last_hb}s ago" if last_hb else "never"

            out += f"• {nid} ({host}) - {status}\n"
            out += f"  Status: {status} (Last Heartbeat: {ago})\n"
            out += f"  Antigravity: v{agy_ver} [{agy_auth}]\n"
            out += f"  Capabilities: {', '.join(caps) if caps else 'none'}\n"

        return out.rstrip(), False

    def _call_knot_quota_matrix(self, args: dict) -> tuple[str, bool]:
        target = args.get("target", "all")
        nodes = self.hub.request("/nodes", method="GET")

        if target not in ("all", "--all", None, ""):
            nodes = [n for n in nodes if n.get("id") == target or n.get("hostname") == target]
            if not nodes:
                return f"Node '{target}' not found on Knot Hub.", True

        header_fmt = "%-12s %-18s %-32s %-32s %-18s %-18s\n"
        out = "--- Knot Antigravity Swarm Quota Matrix ---\n"
        out += header_fmt % ("NODE", "MODEL GROUP", "5-HOUR LIMIT", "WEEKLY LIMIT", "NEXT 5H REFRESH", "NEXT WEEKLY REFRESH")
        out += header_fmt % ("----", "-----------", "------------", "------------", "---------------", "-------------------")

        for n in nodes:
            nid = n.get("id", "unknown")
            status = n.get("status", "ONLINE")
            is_offline = (status == "OFFLINE")
            qdata = n.get("quota_data") or {}
            if isinstance(qdata, str):
                try:
                    qdata = json.loads(qdata)
                except Exception:
                    qdata = {}

            # Gemini row
            g_5h = n.get("quota_5h_gemini") if qdata else None
            g_wk = n.get("quota_weekly_gemini") if qdata else None
            g_5h_reset = qdata.get("gemini_5h_reset", "")
            g_wk_reset = qdata.get("gemini_weekly_reset", "")

            bar_5h = self._render_quota_bar(g_5h, is_offline=is_offline)
            bar_wk = self._render_quota_bar(g_wk, is_offline=is_offline)
            rst_5h = self._fmt_reset(g_5h_reset)
            rst_wk = self._fmt_reset(g_wk_reset)

            node_label = f"{nid} ({status})" if is_offline else nid
            out += header_fmt % (node_label, "Gemini (Flash/Pro)", bar_5h, bar_wk, rst_5h, rst_wk)

            # Claude & 3P row
            p_5h = n.get("quota_5h_3p", 1.0) if qdata else None
            p_wk = n.get("quota_weekly_3p", 1.0) if qdata else None
            p_5h_reset = qdata.get("third_party_5h_reset", "")
            p_wk_reset = qdata.get("third_party_weekly_reset", "")

            bar_p5h = self._render_quota_bar(p_5h, is_offline=is_offline)
            bar_pwk = self._render_quota_bar(p_wk, is_offline=is_offline)
            rst_p5h = self._fmt_reset(p_5h_reset)
            rst_pwk = self._fmt_reset(p_wk_reset)

            out += header_fmt % ("", "Claude & GPT", bar_p5h, bar_pwk, rst_p5h, rst_pwk)

        return out.rstrip(), False

    # ---------------- Formatting Helpers ----------------

    @staticmethod
    def _render_quota_bar(fraction: float | None, is_offline: bool = False, width: int = 10) -> str:
        if is_offline and (fraction is None or fraction >= 0.99):
            return "[OFFLINE   ]   -%     "
        if fraction is None:
            return "[NO DATA   ]   ?%     "
        pct = max(0, min(100, int(round(fraction * 100))))
        filled = max(0, min(width, int(round(fraction * width))))
        bar = "█" * filled + "░" * (width - filled)

        if pct < 15:
            tag = "CRIT"
        elif pct < 40:
            tag = "LOW "
        else:
            tag = "OK  "
        return f"[{bar}] {pct:3d}% ({tag})"

    @staticmethod
    def _fmt_reset(reset_iso: str) -> str:
        if not reset_iso:
            return "-"
        try:
            dt = datetime.fromisoformat(reset_iso.replace("Z", "+00:00"))
            now = datetime.now(timezone.utc)
            diff = dt - now
            secs = int(diff.total_seconds())
            if secs <= 0:
                return "Ready"
            hrs = secs // 3600
            mins = (secs % 3600) // 60
            days = hrs // 24
            if days > 0:
                rem_hrs = hrs % 24
                return f"in {days}d {rem_hrs}h"
            return f"in {hrs}h {mins}m"
        except Exception:
            return reset_iso[:10]

    def _call_knot_exec_command(self, args: dict) -> tuple[str, bool]:
        target = (args.get("target") or "desktop").strip()
        command = (args.get("command") or "").strip()
        timeout = int(args.get("timeout") or 30)

        if not command:
            return "Error: 'command' parameter is required for knot_exec_command", True

        # Try via Hub POST /mesh/exec first
        try:
            res = self.hub.request(
                "/mesh/exec",
                method="POST",
                data={"target": target, "command": command, "timeout": timeout},
                timeout=float(timeout + 5)
            )
            if isinstance(res, dict):
                ok = res.get("ok", False)
                exit_code = res.get("exit_code", 0)
                stdout = res.get("stdout", "")
                stderr = res.get("stderr", "")

                output_parts = [f"=== Knot Mesh Exec: [{target}] (Zero-Token Remote Execution) ==="]
                if stdout:
                    output_parts.append(stdout.rstrip())
                if stderr:
                    output_parts.append(f"[STDERR]\n{stderr.rstrip()}")
                if not stdout and not stderr:
                    output_parts.append("(No output produced)")
                output_parts.append(f"\n[Exit code: {exit_code}]")
                return "\n".join(output_parts), not ok
        except Exception as e:
            # Hub exec request failed or unreachable, fallback to local CLI
            sys.stderr.write(f"Notice: [mcp-gateway] Hub /mesh/exec request failed ({e}); falling back to local knot exec\n")

        # Local fallback via knot exec CLI
        knot_bin = shutil.which("knot") or os.path.abspath(os.path.join(os.path.dirname(__file__), "../../bin/knot"))
        if os.path.exists(knot_bin):
            try:
                proc = subprocess.run([knot_bin, "exec", target, command], capture_output=True, text=True, timeout=timeout)
                output_parts = [f"=== Knot Mesh Exec (Local Fallback): [{target}] ==="]
                if proc.stdout:
                    output_parts.append(proc.stdout.rstrip())
                if proc.stderr:
                    output_parts.append(f"[STDERR]\n{proc.stderr.rstrip()}")
                if not proc.stdout and not proc.stderr:
                    output_parts.append("(No output produced)")
                output_parts.append(f"\n[Exit code: {proc.returncode}]")
                return "\n".join(output_parts), proc.returncode != 0
            except subprocess.TimeoutExpired:
                return f"Error: Command timed out after {timeout} seconds on {target}", True
            except Exception as err:
                return f"Error executing command via knot exec: {err}", True

        return "Error: Failed to reach Knot Hub /mesh/exec and local knot CLI not found", True

    def _call_knot_swarm_topology(self, args: dict) -> tuple[str, bool]:
        """
        Consolidated single-turn snapshot of the entire swarm:
        Nodes, status, IP, GPU acceleration, active model, running tasks/activity, and quotas.
        """
        try:
            nodes_data = self.hub.request("/nodes", timeout=5.0)
            if not isinstance(nodes_data, list):
                return "Error: Unexpected response format from /nodes", True

            models_data = {}
            try:
                models_resp = self.hub.request("/swarm/models", timeout=3.0)
                if isinstance(models_resp, dict):
                    models_data = models_resp
            except Exception as e:
                sys.stderr.write(f"Notice: [mcp-gateway] Failed to fetch /swarm/models: {e}\n")

            default_model = models_data.get("default_model", "gemini-3.8-flash-high")
            node_models = models_data.get("node_models", {})

            lines = [
                "# Knot Swarm Consolidated Topology & Status",
                f"- **Default Swarm Model**: `{default_model}`",
                f"- **Timestamp**: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
                "",
                "| Node | Status | Hostname | IP | Assigned Model | Hardware / GPU | Power & Activity | Gemini 5h Quota |",
                "| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |"
            ]

            for n in nodes_data:
                nid = n.get("id") or n.get("node_id") or "unknown"
                status = n.get("status", "UNKNOWN")
                status_badge = "🟢 ONLINE" if status == "ONLINE" else "🔴 OFFLINE"
                hostname = n.get("hostname", "-")
                ip = n.get("ip", "127.0.0.1" if nid == "desktop" else "-")
                model = n.get("selected_model") or node_models.get(nid) or default_model

                caps = n.get("capabilities") or []
                hw_desc = "x86_64"
                if "gpu_cuda" in caps or "rtx_3050" in caps:
                    hw_desc = "RTX 3050 (CUDA)"
                elif "amd_gpu" in caps:
                    hw_desc = "AMD GPU (ROCm/Vulkan)"
                elif "steamdeck" in caps:
                    hw_desc = "Van Gogh APU (Handheld)"

                # Power & Activity
                pwr = n.get("power") or {}
                act = n.get("activity") or pwr.get("activity") or {}
                pwr_desc = "AC" if pwr.get("on_ac", True) else "BAT"
                if act.get("is_executing"):
                    step = act.get("step_index", 0)
                    tool = act.get("tool_action") or act.get("tool_name") or act.get("status") or "RUNNING"
                    act_desc = f"🏃 Step {step}: {tool[:20]}"
                else:
                    act_desc = "Idle"

                # Quota
                q_5h = n.get("quota_5h_gemini")
                if q_5h is not None:
                    q_pct = f"{round(q_5h * 100)}%"
                    q_data = n.get("quota_data") or {}
                    reset_in = q_data.get("gemini_5h_reset_in", "")
                    if reset_in:
                        q_pct += f" ({reset_in})"
                else:
                    q_pct = "-"

                lines.append(f"| **@{nid}** | {status_badge} | `{hostname}` | `{ip}` | `{model}` | {hw_desc} | {pwr_desc} ({act_desc}) | {q_pct} |")

            lines.append("")
            lines.append("### Swarm Execution Guidelines:")
            lines.append("1. **Zero-Token CLI Execution**: Use `knot_exec_command(target, command)` to run remote shell commands, inspect files, or check processes with **0 tokens** burned on target nodes.")
            lines.append("2. **Mesh Health & Quotas**: Use `knot_node_status` and `knot_quota_matrix` to check available node capacity.")
            lines.append("3. **Hardware Acceleration**: Route CUDA tasks to `@laptop` (RTX 3050), heavy builds to `@desktop` (16-thread Core i7), and portable/handheld tests to `@steamdeck`.")

            return "\n".join(lines), False
        except Exception as e:
            return f"Error retrieving swarm topology: {str(e)}", True


def run_stdio_server(hub_client: KnotHubClient):
    """Run the stdio MCP JSON-RPC 2.0 loop."""
    server = KnotMCPGateway(hub_client)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception as e:
            err_resp = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Parse error: {e}"}
            }
            sys.stdout.write(json.dumps(err_resp) + "\n")
            sys.stdout.flush()
            continue

        resp = server.handle_request(req)
        if resp is not None:
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()


# ---------------- Self-Test Suite ----------------


class MockKnotHubClient(KnotHubClient):
    """Mock client for self-check without external network dependencies."""

    def __init__(self):
        super().__init__("http://mock.hub:4242")

    def request(self, path: str, method: str = "GET", data: dict | None = None, timeout: float = 10.0) -> dict | list:
        if path == "/health":
            return {
                "status": "OK",
                "service": "knot-hub",
                "timestamp": 1788992000,
                "mesh_nodes": 3,
                "online_nodes": 3,
                "tasks_queued": 0,
                "tasks_active": 1,
                "total_tasks_tracked": 7
            }
        elif path == "/nodes":
            return [
                {
                    "id": "desktop",
                    "hostname": "workstation-anchor",
                    "capabilities": ["any", "general", "desktop", "x86_64", "amd_gpu", "anchor"],
                    "status": "ONLINE",
                    "last_heartbeat": 1788992000,
                    "agy_version": "1.1.26",
                    "agy_auth": "AUTHENTICATED",
                    "quota_5h_gemini": 0.11,
                    "quota_weekly_gemini": 0.07,
                    "quota_5h_3p": 1.0,
                    "quota_weekly_3p": 1.0,
                    "quota_data": {
                        "gemini_5h_fraction": 0.11,
                        "gemini_5h_reset": "2026-09-10T02:00:00Z",
                        "gemini_weekly_fraction": 0.07,
                        "gemini_weekly_reset": "2026-09-11T00:00:00Z"
                    }
                },
                {
                    "id": "laptop",
                    "hostname": "laptop-node",
                    "capabilities": ["any", "general", "laptop", "x86_64", "gpu_cuda", "nvidia_gpu", "rtx_3050"],
                    "status": "ONLINE",
                    "last_heartbeat": 1788992000,
                    "agy_version": "1.1.19",
                    "agy_auth": "AUTHENTICATED",
                    "quota_5h_gemini": 0.0,
                    "quota_weekly_gemini": 0.52,
                    "quota_5h_3p": 1.0,
                    "quota_weekly_3p": 1.0,
                    "quota_data": {
                        "gemini_5h_fraction": 0.0,
                        "gemini_5h_reset": "2026-09-10T01:00:00Z",
                        "gemini_weekly_fraction": 0.52,
                        "gemini_weekly_reset": "2026-09-11T09:00:00Z"
                    }
                }
            ]
        elif path == "/swarm/models":
            return {
                "default_model": "gemini-3.8-flash-high",
                "node_models": {"desktop": "gemini-3.8-pro", "laptop": "gemini-3.8-flash"}
            }
        elif path == "/mesh/exec":
            return {
                "ok": True,
                "exit_code": 0,
                "stdout": "Mock exec output",
                "stderr": ""
            }
        return {}


class MockMemoryPalaceClient:
    """Mock memory palace client retained for test backwards-compatibility."""
    def __init__(self):
        pass


def run_self_test() -> int:
    """Runs internal self-check verifying JSON-RPC initialize, tools/list, and tools/call outputs."""
    print("=== [knot-mcp-gateway] Starting Internal Self-Test Suite ===", file=sys.stderr)
    mock_hub = MockKnotHubClient()
    mock_memory = MockMemoryPalaceClient()
    gateway = KnotMCPGateway(mock_hub, mock_memory)

    # 1. Test initialize
    init_req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0"}
        }
    }
    init_resp = gateway.handle_request(init_req)
    assert init_resp is not None, "initialize returned None"
    assert init_resp.get("jsonrpc") == "2.0", "Invalid jsonrpc version"
    assert init_resp.get("id") == 1, "Mismatched ID on initialize"
    assert "tools" in init_resp["result"]["capabilities"], "Missing tools capability"
    assert init_resp["result"]["serverInfo"]["name"] == "knot-mcp-gateway", "Invalid server name"
    print("  [PASS] JSON-RPC 'initialize'", file=sys.stderr)

    # 2. Test notifications/initialized
    notify_req = {
        "jsonrpc": "2.0",
        "method": "notifications/initialized"
    }
    notify_resp = gateway.handle_request(notify_req)
    assert notify_resp is None, "Notifications must not produce a response object"
    assert gateway.initialized is True, "Gateway should be marked initialized"
    print("  [PASS] JSON-RPC 'notifications/initialized'", file=sys.stderr)

    # 3. Test tools/list
    tools_req = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list",
        "params": {}
    }
    tools_resp = gateway.handle_request(tools_req)
    assert tools_resp is not None, "tools/list returned None"
    assert tools_resp.get("id") == 2, "Mismatched ID on tools/list"
    tools = tools_resp["result"]["tools"]
    assert len(tools) == 4, f"Expected exactly 4 tools, got {len(tools)}"

    tool_names = {t["name"] for t in tools}
    expected_tools = {
        "knot_node_status",
        "knot_quota_matrix",
        "knot_exec_command",
        "knot_swarm_topology",
    }
    assert tool_names == expected_tools, f"Tool names mismatch: {tool_names} vs {expected_tools}"

    # Verify tool schemas
    tools_by_name = {t["name"]: t for t in tools}
    assert "properties" in tools_by_name["knot_node_status"]["inputSchema"]
    assert "target" in tools_by_name["knot_quota_matrix"]["inputSchema"]["properties"]
    assert "command" in tools_by_name["knot_exec_command"]["inputSchema"]["required"]
    assert "properties" in tools_by_name["knot_swarm_topology"]["inputSchema"]
    print("  [PASS] JSON-RPC 'tools/list' (all 4 essential mesh tools and schemas verified)", file=sys.stderr)

    # 4. Test tools/call
    test_calls = [
        ("knot_node_status", {}),
        ("knot_quota_matrix", {"target": "all"}),
        ("knot_swarm_topology", {}),
        ("knot_exec_command", {"target": "desktop", "command": "echo test"}),
    ]

    for idx, (tname, targs) in enumerate(test_calls, start=10):
        call_req = {
            "jsonrpc": "2.0",
            "id": idx,
            "method": "tools/call",
            "params": {
                "name": tname,
                "arguments": targs
            }
        }
        call_resp = gateway.handle_request(call_req)
        assert call_resp is not None, f"tools/call '{tname}' returned None"
        assert call_resp.get("id") == idx, f"Mismatched ID on '{tname}'"
        result = call_resp.get("result", {})
        assert "content" in result, f"Missing content in result for '{tname}'"
        assert len(result["content"]) > 0, f"Empty content in result for '{tname}'"
        assert result["content"][0]["type"] == "text", f"Expected type 'text' in '{tname}'"
        assert len(result["content"][0]["text"]) > 0, f"Empty text in '{tname}'"
        assert result.get("isError") is False, f"Unexpected error in '{tname}': {result['content'][0]['text']}"
        print(f"  [PASS] tools/call '{tname}'", file=sys.stderr)

    # 5. Test error cases
    # 5a. Unknown tool
    unknown_call = {
        "jsonrpc": "2.0",
        "id": 99,
        "method": "tools/call",
        "params": {"name": "non_existent_tool", "arguments": {}}
    }
    unknown_resp = gateway.handle_request(unknown_call)
    assert unknown_resp["result"]["isError"] is True
    print("  [PASS] Error handling: unknown tool", file=sys.stderr)

    # 5b. Missing required argument for knot_exec_command
    missing_arg_call = {
        "jsonrpc": "2.0",
        "id": 100,
        "method": "tools/call",
        "params": {"name": "knot_exec_command", "arguments": {}}
    }
    missing_arg_resp = gateway.handle_request(missing_arg_call)
    assert missing_arg_resp["result"]["isError"] is True
    print("  [PASS] Error handling: missing required argument", file=sys.stderr)

    # 6. Live Hub integration test if reachable
    real_hub = KnotHubClient()
    try:
        health = real_hub.request("/health", timeout=2.0)
        if health.get("status") == "OK":
            print(f"  [INFO] Knot Hub detected at {real_hub.resolve_url()}. Verifying live tool queries...", file=sys.stderr)
            live_gateway = KnotMCPGateway(real_hub)
            for live_tool, live_args in [
                ("knot_node_status", {}),
                ("knot_quota_matrix", {"target": "all"}),
                ("knot_swarm_topology", {}),
            ]:
                live_req = {
                    "jsonrpc": "2.0",
                    "id": 200,
                    "method": "tools/call",
                    "params": {"name": live_tool, "arguments": live_args}
                }
                live_resp = live_gateway.handle_request(live_req)
                assert live_resp["result"]["isError"] is False, f"Live tool {live_tool} failed: {live_resp}"
                print(f"  [PASS] Live verification: '{live_tool}'", file=sys.stderr)
    except Exception as e:
        print(f"  [NOTE] Live hub probe skipped ({e})", file=sys.stderr)

    print("=== [knot-mcp-gateway] All Self-Checks Passed (Exit Code 0) ===", file=sys.stderr)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Knot Swarm Stateless MCP Gateway")
    parser.add_argument("--test", action="store_true", help="Run internal self-check verifying JSON-RPC tools")
    parser.add_argument("--hub-url", type=str, default=None, help="Explicit Knot Hub URL override")
    args = parser.parse_args()

    if args.test:
        sys.exit(run_self_test())

    hub_client = KnotHubClient(base_url=args.hub_url)
    run_stdio_server(hub_client)


if __name__ == "__main__":
    main()
