#!/usr/bin/env python3
"""
Knot Swarm Stateless MCP Gateway Core
Lightweight, zero-external-dependency Model Context Protocol (MCP) server over stdio (JSON-RPC 2.0).

Exposes Knot Swarm blackboard and node coordination tools to any MCP-compliant LLM agent:
- knot_task_post (args: title, prompt, target_plane='any')
- knot_task_wait (args: task_id, timeout=300)
- knot_task_list (args: status=None)
- knot_node_status (no required args)
- knot_quota_matrix (args: target='all')
- knot_gpu_status (args: target='laptop')

Zero external dependencies: uses standard library Python 3 only.
"""

import argparse
from datetime import datetime, timezone
import json
import os
import shutil
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


import ssl


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
                raise RuntimeError(f"Hub HTTP {e.code}: {msg}")
            except Exception as e:
                last_err = e
                continue

        raise RuntimeError(f"Failed to connect to Knot Hub (tried {urls_to_try}): {last_err}")


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
                "version": "1.0.0"
            }
        }

    def _handle_tools_list(self, params: dict) -> dict:
        return {
            "tools": [
                {
                    "name": "knot_task_post",
                    "description": "Post a new task to the Knot Swarm Blackboard (Linda OUT primitive) for distributed execution across mesh nodes.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "prompt": {
                                "type": "string",
                                "description": "The instruction / prompt to be executed by the assigned swarm worker."
                            },
                            "title": {
                                "type": "string",
                                "description": "Short human-readable title for blackboard tracking.",
                                "default": "Autonomous Swarm Task"
                            },
                            "target_plane": {
                                "type": "string",
                                "description": "Target execution plane or node ID (e.g. 'any', 'desktop', 'laptop', 'steamdeck', 'gpu_cuda').",
                                "default": "any"
                            }
                        },
                        "required": ["prompt"]
                    }
                },
                {
                    "name": "knot_task_wait",
                    "description": "Wait for a Knot Swarm task to finish execution and return its complete result output.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "task_id": {
                                "type": "string",
                                "description": "The unique UUID of the task to wait for."
                            },
                            "timeout": {
                                "type": "integer",
                                "description": "Maximum seconds to wait before timing out (default: 300).",
                                "default": 300
                            }
                        },
                        "required": ["task_id"]
                    }
                },
                {
                    "name": "knot_task_list",
                    "description": "List tracked tasks on the Knot Swarm Blackboard, optionally filtering by status.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "status": {
                                "type": "string",
                                "description": "Optional status filter ('QUEUED', 'CLAIMED', 'RUNNING', 'COMPLETED', 'ERROR', or None for all)."
                            }
                        }
                    }
                },
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
                    "name": "knot_gpu_status",
                    "description": "Query GPU hardware status, CUDA availability, driver versions, and telemetry for a target node (default: 'laptop').",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "target": {
                                "type": "string",
                                "description": "Target node to query GPU status for (default: 'laptop').",
                                "default": "laptop"
                            }
                        }
                    }
                },
                {
                    "name": "knot_memory_store",
                    "description": "Store a cognitive memory, learning, or architectural insight into the Knot Swarm Memory Palace (SurrealDB cognitive graph). Supports optional artifact closet archiving (PocketBase).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "wing": {
                                "type": "string",
                                "description": "High-level spatial domain (e.g. 'architecture', 'bugfixes', 'mesh', 'nodes', 'auth')."
                            },
                            "hall": {
                                "type": "string",
                                "description": "Subsystem or topic hall (e.g. 'security', 'mesh_core', 'quota', 'mcp')."
                            },
                            "drawer": {
                                "type": "string",
                                "description": "Contextual drawer category (e.g. 'decisions', 'incidents', 'learnings', 'prompts')."
                            },
                            "title": {
                                "type": "string",
                                "description": "Concise summary title of the memory nugget."
                            },
                            "content": {
                                "type": "string",
                                "description": "Detailed markdown explanation, rationale, or solution."
                            },
                            "tags": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Categorical tags for filtering and indexing."
                            },
                            "importance": {
                                "type": "number",
                                "description": "Importance weight (default: 1.0; higher weights resist decay).",
                                "default": 1.0
                            },
                            "artifact_name": {
                                "type": "string",
                                "description": "Optional name if archiving large payload / diff to PocketBase closet."
                            },
                            "artifact_content": {
                                "type": "string",
                                "description": "Optional raw file content, code diff, or execution log to archive to PocketBase."
                            }
                        },
                        "required": ["wing", "hall", "drawer", "title", "content"]
                    }
                },
                {
                    "name": "knot_memory_recall",
                    "description": "Recall cognitive memories from the Knot Swarm Memory Palace using keyword search, spatial filtering, or tags.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Keyword search string across memory titles and contents."
                            },
                            "wing": {
                                "type": "string",
                                "description": "Optional wing filter."
                            },
                            "hall": {
                                "type": "string",
                                "description": "Optional hall filter."
                            },
                            "drawer": {
                                "type": "string",
                                "description": "Optional drawer filter."
                            },
                            "tags": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "Optional list of tags to filter by."
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Maximum number of memories to return (default: 5).",
                                "default": 5
                            }
                        }
                    }
                },
                {
                    "name": "knot_memory_palace_map",
                    "description": "View the entire spatial hierarchy tree of the Knot Swarm Memory Palace (Wings -> Halls -> Drawers -> Memories).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "knot_memory_promote",
                    "description": "Promote a memory's importance in the Cognitive Palace to prevent cognitive decay and boost recall ranking.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "memory_id": {
                                "type": "string",
                                "description": "SurrealDB record ID of the memory (e.g. 'memory:abc123xyz')."
                            },
                            "boost": {
                                "type": "number",
                                "description": "Importance increment boost (default: 1.0).",
                                "default": 1.0
                            }
                        },
                        "required": ["memory_id"]
                    }
                },
                {
                    "name": "knot_memory_relate",
                    "description": "Create an associative cognitive graph edge between two memories in the Palace.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "source": {
                                "type": "string",
                                "description": "Source memory record ID (e.g. 'memory:123')."
                            },
                            "target": {
                                "type": "string",
                                "description": "Target memory record ID (e.g. 'memory:456')."
                            },
                            "type": {
                                "type": "string",
                                "description": "Relation semantic type (e.g. 'relates_to', 'influences', 'supersedes', 'resolves').",
                                "default": "relates_to"
                            },
                            "weight": {
                                "type": "number",
                                "description": "Associative connection strength (default: 1.0).",
                                "default": 1.0
                            }
                        },
                        "required": ["source", "target"]
                    }
                },
                {
                    "name": "knot_closet_store",
                    "description": "Upload a raw artifact, log, code snippet, or patch file directly to the PocketBase artifact vault.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Filename or descriptive name of the artifact."
                            },
                            "content": {
                                "type": "string",
                                "description": "Text content of the artifact or patch."
                            },
                            "artifact_type": {
                                "type": "string",
                                "description": "Artifact type descriptor (e.g. 'diff', 'code', 'log', 'config').",
                                "default": "text"
                            }
                        },
                        "required": ["name", "content"]
                    }
                },
                {
                    "name": "knot_closet_get",
                    "description": "Retrieve an artifact and its metadata from the PocketBase artifact closet by its record ID.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "artifact_id": {
                                "type": "string",
                                "description": "The unique 15-character PocketBase record ID."
                            }
                        },
                        "required": ["artifact_id"]
                    }
                },
                {
                    "name": "knot_task_fanout",
                    "description": "Divide-and-Conquer: Atomically post a batch of parallel subtasks and an optional barrier task that stays blocked until all subtasks finish.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "tasks": {
                                "type": "array",
                                "description": "List of subtask objects with keys: prompt (required), title (optional), target_plane (optional), lease_ttl (optional).",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "prompt": {"type": "string"},
                                        "title": {"type": "string"},
                                        "target_plane": {"type": "string"},
                                        "lease_ttl": {"type": "integer"}
                                    },
                                    "required": ["prompt"]
                                }
                            },
                            "barrier_task": {
                                "type": "object",
                                "description": "Optional aggregator task to execute after all subtasks complete. Hub will auto-inject a matrix of subtask results into its prompt.",
                                "properties": {
                                    "prompt": {"type": "string"},
                                    "title": {"type": "string"},
                                    "target_plane": {"type": "string"},
                                    "lease_ttl": {"type": "integer"}
                                },
                                "required": ["prompt"]
                            },
                            "wait_barrier": {
                                "type": "boolean",
                                "description": "If true, blocks until the barrier reducer task finishes execution (or times out). Default is false.",
                                "default": False
                            },
                            "timeout": {
                                "type": "integer",
                                "description": "Timeout in seconds when wait_barrier is true (default: 300).",
                                "default": 300
                            }
                        },
                        "required": ["tasks"]
                    }
                },
                {
                    "name": "knot_task_batch_status",
                    "description": "Query progress summary and individual subtask statuses for a fan-out batch ID.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "batch_id": {
                                "type": "string",
                                "description": "The unique UUID of the batch to inspect."
                            }
                        },
                        "required": ["batch_id"]
                    }
                },
                {
                    "name": "knot_artifact_lock",
                    "description": "Acquire or renew an atomic lease on an artifact to perform safe surgical edits (3-state: LOCKED_SURGERY).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Name of the artifact (e.g. 'implementation_plan.md', 'clipboard_spec.md')."
                            },
                            "node_id": {
                                "type": "string",
                                "description": "Node requesting the lock (defaults to local node ID)."
                            },
                            "ttl": {
                                "type": "integer",
                                "description": "Lease duration in seconds before automatic expiry (default: 120).",
                                "default": 120
                            },
                            "state": {
                                "type": "string",
                                "description": "Lock state (default: 'LOCKED_SURGERY').",
                                "default": "LOCKED_SURGERY"
                            }
                        },
                        "required": ["name"]
                    }
                },
                {
                    "name": "knot_artifact_commit",
                    "description": "Commit an artifact version into PocketBase and index it into SurrealDB Cognitive Palace, transitioning to VERIFIED_COMMITTED and releasing any active lease.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Name of the artifact."
                            },
                            "content": {
                                "type": "string",
                                "description": "The complete updated content of the artifact."
                            },
                            "node_id": {
                                "type": "string",
                                "description": "Author node committing the revision."
                            },
                            "state": {
                                "type": "string",
                                "description": "Final state (default: 'VERIFIED_COMMITTED').",
                                "default": "VERIFIED_COMMITTED"
                            },
                            "meta": {
                                "type": "object",
                                "description": "Optional metadata dictionary."
                            }
                        },
                        "required": ["name", "content"]
                    }
                },
                {
                    "name": "knot_chat_post",
                    "description": "Post a message to the Swarm Konversations channel (#knot-core) with support for @mentions (@swarm, @desktop, @laptop, @steamdeck).",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "content": {
                                "type": "string",
                                "description": "The message body to broadcast."
                            },
                            "sender": {
                                "type": "string",
                                "description": "Sender identifier (e.g. 'desktop', 'laptop', 'steamdeck', or user handle)."
                            },
                            "conv_id": {
                                "type": "string",
                                "description": "Channel ID (default: 'main').",
                                "default": "main"
                            },
                            "reply_to": {
                                "type": "string",
                                "description": "Optional message ID being replied to."
                            }
                        },
                        "required": ["content"]
                    }
                },
                {
                    "name": "knot_chat_read",
                    "description": "Read recent conversation messages and agent turns from the Swarm Konversations channel ledger.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "conv_id": {
                                "type": "string",
                                "description": "Channel ID to read (default: 'main').",
                                "default": "main"
                            },
                            "limit": {
                                "type": "integer",
                                "description": "Number of recent turns to fetch (default: 20).",
                                "default": 20
                            }
                        }
                    }
                },
                {
                    "name": "knot_project_list",
                    "description": "List all native Antigravity projects tracked by Knot Hub with workspace folder counts and default channels.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "knot_chat_list_conversations",
                    "description": "List Swarm Konversations channels/conversations, optionally filtered by native project ID.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "project_id": {
                                "type": "string",
                                "description": "Optional project UUID or name to filter channels."
                            }
                        }
                    }
                },
                {
                    "name": "knot_chat_create_conversation",
                    "description": "Create a new Swarm Konversations channel under a native Antigravity project.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "id": {
                                "type": "string",
                                "description": "Unique channel slug (e.g. 'incident-auth', 'refactor-mcp')."
                            },
                            "project_id": {
                                "type": "string",
                                "description": "Parent native Antigravity project ID (default: 'knot').",
                                "default": "knot"
                            },
                            "title": {
                                "type": "string",
                                "description": "Human-readable channel title."
                            },
                            "description": {
                                "type": "string",
                                "description": "Optional channel description or objective."
                            }
                        },
                        "required": ["id"]
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
            "knot_task_post": self._call_knot_task_post,
            "knot_task_wait": self._call_knot_task_wait,
            "knot_task_list": self._call_knot_task_list,
            "knot_node_status": self._call_knot_node_status,
            "knot_quota_matrix": self._call_knot_quota_matrix,
            "knot_gpu_status": self._call_knot_gpu_status,
            "knot_memory_store": self._call_knot_memory_store,
            "knot_memory_recall": self._call_knot_memory_recall,
            "knot_memory_palace_map": self._call_knot_memory_palace_map,
            "knot_memory_promote": self._call_knot_memory_promote,
            "knot_memory_relate": self._call_knot_memory_relate,
            "knot_closet_store": self._call_knot_closet_store,
            "knot_closet_get": self._call_knot_closet_get,
            "knot_task_fanout": self._call_knot_task_fanout,
            "knot_task_batch_status": self._call_knot_task_batch_status,
            "knot_artifact_lock": self._call_knot_artifact_lock,
            "knot_artifact_commit": self._call_knot_artifact_commit,
            "knot_chat_post": self._call_knot_chat_post,
            "knot_chat_read": self._call_knot_chat_read,
            "knot_project_list": self._call_knot_project_list,
            "knot_chat_list_conversations": self._call_knot_chat_list_conversations,
            "knot_chat_create_conversation": self._call_knot_chat_create_conversation,
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

    def _call_knot_task_post(self, args: dict) -> tuple[str, bool]:
        prompt = (args.get("prompt") or "").strip()
        if not prompt:
            return "Error: 'prompt' parameter is required for knot_task_post", True

        title = (args.get("title") or "Autonomous Swarm Task").strip()
        target_plane = (args.get("target_plane") or "any").strip()

        payload = {
            "title": title,
            "prompt": prompt,
            "target_plane": target_plane
        }
        res = self.hub.request("/tasks/post", method="POST", data=payload)
        task_id = res.get("id", "unknown")
        status = res.get("status", "QUEUED")

        out = (
            f"Task successfully posted to Knot Swarm Blackboard!\n"
            f"  Task ID:      {task_id}\n"
            f"  Title:        {title}\n"
            f"  Target Plane: {target_plane}\n"
            f"  Status:       {status}\n\n"
            f"To await results, call tool knot_task_wait with task_id=\"{task_id}\"."
        )
        return out, False

    def _call_knot_task_wait(self, args: dict) -> tuple[str, bool]:
        task_id = (args.get("task_id") or "").strip()
        if not task_id:
            return "Error: 'task_id' parameter is required for knot_task_wait", True

        try:
            timeout = float(args.get("timeout", 300))
        except (ValueError, TypeError):
            timeout = 300.0

        start_time = time.time()
        poll_interval = 2.0

        while True:
            try:
                task = self.hub.request(f"/tasks/{task_id}", method="GET")
            except Exception as e:
                if time.time() - start_time >= timeout:
                    return f"Error retrieving task {task_id}: {e}", True
                time.sleep(poll_interval)
                continue

            status = (task.get("status") or "").upper()
            if status in ("COMPLETED", "SUCCESS"):
                claimed_by = task.get("claimed_by") or "unknown"
                dur = task.get("duration_seconds") or 0.0
                tokens = task.get("tokens_used") or 0
                sess = task.get("session_id") or "none"
                result = task.get("result") or ""

                out = (
                    f"Task {task_id} completed successfully!\n"
                    f"  Executed By: {claimed_by}\n"
                    f"  Duration:    {dur:.2f}s\n"
                    f"  Tokens Used: {tokens}\n"
                    f"  Session ID:  {sess}\n\n"
                    f"--- Task Output ---\n"
                    f"{result}"
                )
                return out, False

            elif status in ("FAILED", "ERROR", "TIMEOUT"):
                claimed_by = task.get("claimed_by") or "unknown"
                result = task.get("result") or ""
                out = (
                    f"Task {task_id} finished with status: {status}\n"
                    f"  Executed By: {claimed_by}\n"
                    f"  Details:\n{result}"
                )
                return out, True

            elapsed = time.time() - start_time
            if elapsed >= timeout:
                claimed_by = task.get("claimed_by") or "unclaimed"
                return f"Task wait timed out after {int(timeout)}s. Current status: {status} (node: {claimed_by}).", True

            time.sleep(poll_interval)

    def _call_knot_task_list(self, args: dict) -> tuple[str, bool]:
        status_filter = args.get("status")
        path = "/tasks/list"
        if status_filter and str(status_filter).lower() not in ("none", "null", ""):
            path += f"?status={urllib.parse.quote(str(status_filter))}"

        tasks = self.hub.request(path, method="GET")
        if not tasks:
            msg = "No tasks currently found on Knot Swarm Blackboard"
            if status_filter:
                msg += f" with status '{status_filter}'"
            return msg + ".", False

        header_fmt = "%-10s %-26s %-12s %-12s %-12s %-8s\n"
        divider = "%-10s %-26s %-12s %-12s %-12s %-8s\n" % (
            "----------", "--------------------------", "------------", "------------", "------------", "--------"
        )
        out = "--- Knot Swarm Blackboard Tasks ---\n"
        out += header_fmt % ("TASK ID", "TITLE", "PLANE", "STATUS", "NODE", "DURATION")
        out += divider

        for t in tasks:
            tid = (t.get("id") or "")[:8]
            title = (t.get("title") or "")[:26]
            plane = (t.get("target_plane") or "")[:12]
            status = (t.get("status") or "")[:12]
            node = (t.get("claimed_by") or "-")[:12]
            dur_val = t.get("duration_seconds")
            dur = f"{dur_val:.1f}s" if dur_val is not None else "-"
            out += header_fmt % (tid, title, plane, status, node, dur)

        return out.rstrip(), False

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

    def _call_knot_gpu_status(self, args: dict) -> tuple[str, bool]:
        target = args.get("target", "laptop") or "laptop"
        nodes = self.hub.request("/nodes", method="GET")

        target_node = next((n for n in nodes if n.get("id") == target or n.get("hostname") == target), None)
        if not target_node:
            available = [n.get("id") for n in nodes]
            return f"Node '{target}' not found in Knot Hub mesh. Registered nodes: {', '.join(available)}", True

        nid = target_node.get("id")
        host = target_node.get("hostname")
        status = target_node.get("status", "UNKNOWN")
        caps = target_node.get("capabilities", [])

        gpu_caps = [c for c in caps if any(k in c.lower() for k in ("gpu", "cuda", "rtx", "radeon"))]

        out = f"--- Knot Swarm GPU Telemetry: {nid} ({host}) ---\n"
        out += f"Node Status:      {status}\n"
        out += f"GPU Capabilities: {', '.join(gpu_caps) if gpu_caps else 'none detected'}\n"

        # Search recent probe tasks on blackboard
        tasks = self.hub.request("/tasks/list", method="GET")
        latest_gpu_probe = None
        for t in tasks:
            if t.get("claimed_by") == nid and t.get("status") == "COMPLETED":
                t_title = (t.get("title") or "").lower()
                t_prompt = (t.get("prompt") or "").lower()
                if "gpu" in t_title or "gpu" in t_prompt or "cuda" in t_prompt or "probe" in t_title:
                    latest_gpu_probe = t
                    break

        if latest_gpu_probe:
            out += f"\n--- Latest GPU Probe ({latest_gpu_probe.get('title')}) ---\n"
            out += latest_gpu_probe.get("result", "").strip() + "\n"
        elif gpu_caps:
            out += "\nHardware Profile:\n"
            if "rtx_3050" in gpu_caps:
                out += "  - Model: NVIDIA GeForce RTX 3050 Laptop GPU (CUDA Compute Capable)\n"
            elif "amd_gpu" in gpu_caps:
                out += "  - Model: AMD GPU Architecture (Radeon/VanGogh Graphics)\n"

        # Local hardware probe if target matches this host
        my_host = os.uname().nodename
        if nid in my_host or host == my_host:
            try:
                p = subprocess.run(["lspci"], capture_output=True, text=True, timeout=2)
                vga_lines = [
                    line.strip()
                    for line in p.stdout.splitlines()
                    if any(k in line.lower() for k in ("vga", "3d", "display"))
                ]
                if vga_lines:
                    out += "\nLocal PCI GPU Controller:\n"
                    for vl in vga_lines:
                        out += f"  {vl}\n"
            except Exception:
                pass

        return out.rstrip(), False

    # ---------------- Memory Palace Tool Handlers ----------------

    def _call_knot_memory_store(self, args: dict) -> tuple[str, bool]:
        wing = (args.get("wing") or "").strip()
        hall = (args.get("hall") or "").strip()
        drawer = (args.get("drawer") or "").strip()
        title = (args.get("title") or "").strip()
        content = (args.get("content") or "").strip()

        if not (wing and hall and drawer and title and content):
            return "Error: 'wing', 'hall', 'drawer', 'title', and 'content' are required for knot_memory_store", True

        tags = args.get("tags") or []
        importance = float(args.get("importance", 1.0))
        pool = args.get("pool", "shared")
        art_content = args.get("artifact_content")
        art_name = args.get("artifact_name") or f"{title.lower().replace(' ', '_')}.txt"

        art_id = None
        if art_content:
            try:
                art_id = self.memory.store_artifact(
                    name=art_name,
                    content=art_content,
                    artifact_type=args.get("artifact_type", "text"),
                    meta={"wing": wing, "hall": hall, "drawer": drawer, "title": title}
                )
            except Exception as e:
                return f"Error archiving artifact to closet: {e}", True

        try:
            mem = self.memory.store(
                wing=wing,
                hall=hall,
                drawer=drawer,
                title=title,
                content=content,
                tags=tags,
                importance=importance,
                artifact_id=art_id,
                pool=pool
            )
            mid = mem.get("id", "stored")
            mem_pool = mem.get("pool", pool)
            out = (
                f"Memory successfully stored in Knot Cognitive Palace!\n"
                f"  Record ID:    {mid}\n"
                f"  Location:     🏛️ {wing} > 🏢 {hall} > 📂 {drawer}\n"
                f"  Pool:         {mem_pool}\n"
                f"  Title:        {title}\n"
                f"  Importance:   ⭐ {importance}\n"
                f"  Tags:         {', '.join(tags) if tags else 'none'}\n"
            )
            if art_id:
                out += f"  Vault Closet: {art_id} ({art_name})\n"
            return out, False
        except Exception as e:
            return f"Error storing memory in Knot Palace: {e}", True

    def _call_knot_memory_recall(self, args: dict) -> tuple[str, bool]:
        query = args.get("query")
        wing = args.get("wing")
        hall = args.get("hall")
        drawer = args.get("drawer")
        tags = args.get("tags")
        pool = args.get("pool")
        limit = int(args.get("limit", 5))

        try:
            mems = self.memory.recall(query=query, wing=wing, hall=hall, drawer=drawer, tags=tags, limit=limit, pool=pool)
            if not mems:
                return "No matching memories found in Palace.", False

            out = f"Recalled {len(mems)} cognitive memory item(s):\n"
            for m in mems:
                mid = m.get("id", "?")
                title = m.get("title", "Untitled")
                imp = m.get("importance", 1.0)
                recs = m.get("recall_count", 0)
                m_pool = m.get("pool", "shared")
                content = m.get("content", "")
                m_tags = m.get("tags") or []
                art_id = m.get("artifact_id")

                out += f"\n💡 [{mid}] {title} (⭐ {imp}, recalled: {recs}, pool: {m_pool})\n"
                out += f"   Content: {content}\n"
                if m_tags:
                    out += f"   Tags: {', '.join(m_tags)}\n"
                if art_id:
                    out += f"   Artifact Vault ID: {art_id}\n"
            return out.strip(), False
        except Exception as e:
            return f"Error recalling memory from Knot Palace: {e}", True

    def _call_knot_memory_palace_map(self, args: dict) -> tuple[str, bool]:
        try:
            pmap = self.memory.palace_map()
            tree = format_tree(pmap)
            return tree, False
        except Exception as e:
            return f"Error mapping Memory Palace: {e}", True

    def _call_knot_memory_promote(self, args: dict) -> tuple[str, bool]:
        memory_id = (args.get("memory_id") or "").strip()
        if not memory_id:
            return "Error: 'memory_id' is required for knot_memory_promote", True
        boost = float(args.get("boost", 1.0))
        to_shared = bool(args.get("to_shared", True))
        try:
            res = self.memory.promote(memory_id, boost, to_shared=to_shared)
            return f"Successfully promoted {memory_id} (boost: +{boost}): {res}", False
        except Exception as e:
            return f"Error promoting memory: {e}", True

    def _call_knot_memory_relate(self, args: dict) -> tuple[str, bool]:
        source = (args.get("source") or "").strip()
        target = (args.get("target") or "").strip()
        if not (source and target):
            return "Error: 'source' and 'target' memory IDs are required for knot_memory_relate", True
        rel_type = args.get("type", "relates_to")
        weight = float(args.get("weight", 1.0))
        try:
            res = self.memory.relate(source, target, rel_type, weight)
            return f"Associative link created: {source} -[{rel_type} (w={weight})]-> {target}", False
        except Exception as e:
            return f"Error linking memories in SurrealDB: {e}", True

    def _call_knot_closet_store(self, args: dict) -> tuple[str, bool]:
        name = (args.get("name") or "").strip()
        content = args.get("content") or ""
        if not name or not content:
            return "Error: 'name' and 'content' are required for knot_closet_store", True
        art_type = args.get("artifact_type", "text")
        try:
            aid = self.memory.store_artifact(name, content, art_type)
            return f"Artifact '{name}' ({len(content)} bytes) stored in PocketBase closet. ID: {aid}", False
        except Exception as e:
            return f"Error storing artifact in PocketBase: {e}", True

    def _call_knot_closet_get(self, args: dict) -> tuple[str, bool]:
        artifact_id = (args.get("artifact_id") or "").strip()
        if not artifact_id:
            return "Error: 'artifact_id' is required for knot_closet_get", True
        try:
            rec = self.memory.get_artifact(artifact_id)
            name = rec.get("name", "unnamed")
            atype = rec.get("artifact_type", "text")
            content = rec.get("content", "")
            out = (
                f"Artifact Record: {artifact_id}\n"
                f"  Name: {name}\n"
                f"  Type: {atype}\n"
                f"--- Content ---\n"
                f"{content}"
            )
            return out, False
        except Exception as e:
            return f"Error retrieving artifact from PocketBase: {e}", True

    def _call_knot_task_fanout(self, args: dict) -> tuple[str, bool]:
        tasks = args.get("tasks")
        if not tasks or not isinstance(tasks, list):
            return "Error: 'tasks' array is required and cannot be empty", True
        barrier_task = args.get("barrier_task")
        wait_barrier = bool(args.get("wait_barrier", False))
        timeout = int(args.get("timeout", 300))

        try:
            payload = {"tasks": tasks}
            if barrier_task:
                payload["barrier_task"] = barrier_task
            res = self.hub.request("/tasks/fanout", method="POST", data=payload)
            batch_id = res.get("batch_id")
            subtasks = res.get("subtasks", [])
            barrier = res.get("barrier_task")

            out_lines = [
                f"Divide-and-Conquer Batch Created! Batch ID: {batch_id}",
                f"Subtasks posted: {len(subtasks)}"
            ]
            for st in subtasks:
                out_lines.append(f"  - [{st.get('id', '')[:8]}] '{st.get('title')}' -> plane: {st.get('target_plane')}")

            if barrier:
                out_lines.append(f"Barrier Reducer Task: [{barrier.get('id', '')[:8]}] (BLOCKED_ON_DEPS until subtasks complete)")

            if wait_barrier and barrier:
                out_lines.append(f"\nWaiting for barrier join completion (timeout {timeout}s)...")
                barrier_id = barrier.get("id")
                start_t = time.time()
                while time.time() - start_t < timeout:
                    b_status = self.hub.request(f"/tasks/{barrier_id}", method="GET")
                    st = b_status.get("status")
                    if st in ("COMPLETED", "SUCCESS"):
                        out_lines.append(f"\n[+] Barrier task completed in {round(time.time() - start_t, 1)}s!")
                        out_lines.append(f"\nFinal Result:\n{b_status.get('result', '')}")
                        return "\n".join(out_lines), False
                    elif st in ("FAILED", "ERROR", "BLOCKED_FAILED", "TIMEOUT"):
                        out_lines.append(f"\n[!] Barrier task failed ({st}):\n{b_status.get('result', '')}")
                        return "\n".join(out_lines), True
                    time.sleep(2.0)
                return f"Batch posted (ID: {batch_id}), but barrier wait timed out after {timeout}s.", True

            return "\n".join(out_lines), False
        except Exception as e:
            return f"Error posting task fan-out: {e}", True

    def _call_knot_task_batch_status(self, args: dict) -> tuple[str, bool]:
        batch_id = (args.get("batch_id") or "").strip()
        if not batch_id:
            return "Error: 'batch_id' is required for knot_task_batch_status", True
        try:
            status = self.hub.request(f"/tasks/batch/{batch_id}", method="GET")
            total = status.get("total_tasks", 0)
            completed = status.get("completed", 0)
            running = status.get("running", 0)
            blocked = status.get("blocked_on_deps", 0)
            failed = status.get("failed", 0)
            is_done = status.get("is_done", False)

            lines = [
                f"Batch {batch_id} Status: {'DONE' if is_done else 'IN_PROGRESS'}",
                f"  Total: {total} | Completed: {completed} | Running: {running} | Blocked on DAG: {blocked} | Failed: {failed}",
                "\nTasks:"
            ]
            for t in status.get("tasks", []):
                t_id = t.get("id", "")[:8]
                title = t.get("title", "")
                st = t.get("status", "")
                plane = t.get("target_plane", "")
                claimed = f"(@{t['claimed_by']})" if t.get("claimed_by") else ""
                lines.append(f"  - [{t_id}] {st:<15} {title} -> {plane} {claimed}")

            return "\n".join(lines), False
        except Exception as e:
            return f"Error getting batch status: {e}", True

    def _call_knot_artifact_lock(self, args: dict) -> tuple[str, bool]:
        name = (args.get("name") or "").strip()
        if not name:
            return "Error: 'name' is required for knot_artifact_lock", True
        node_id = (args.get("node_id") or "").strip()
        if not node_id:
            node_id = self._detect_local_node()
        ttl = int(args.get("ttl", 120))
        state = args.get("state", "LOCKED_SURGERY")

        try:
            res = self.hub.request("/artifacts/lock", method="POST", data={
                "name": name,
                "node_id": node_id,
                "ttl": ttl,
                "state": state
            })
            if res.get("ok"):
                return f"Artifact lease acquired! '{name}' is now {state} by @{node_id} (expires in {ttl}s).", False
            else:
                return f"Failed to acquire lease: {res.get('error')}", True
        except Exception as e:
            return f"Error locking artifact: {e}", True

    def _call_knot_artifact_commit(self, args: dict) -> tuple[str, bool]:
        name = (args.get("name") or "").strip()
        content = args.get("content") or ""
        if not name or not content:
            return "Error: 'name' and 'content' are required for knot_artifact_commit", True
        node_id = (args.get("node_id") or "").strip()
        if not node_id:
            node_id = self._detect_local_node()
        state = args.get("state", "VERIFIED_COMMITTED")
        meta = args.get("meta") or {}

        try:
            aid = self.memory.store_artifact_version(
                name=name,
                content=content,
                state=state,
                author_node=node_id,
                meta=meta
            )
            self.hub.request("/artifacts/release", method="POST", data={
                "name": name,
                "node_id": node_id,
                "state": state
            })
            return f"Artifact '{name}' committed with state '{state}' by @{node_id}. PocketBase ID: {aid}", False
        except Exception as e:
            return f"Error committing artifact: {e}", True

    def _call_knot_chat_post(self, args: dict) -> tuple[str, bool]:
        content = (args.get("content") or "").strip()
        if not content:
            return "Error: 'content' is required for knot_chat_post", True
        sender = (args.get("sender") or "").strip()
        if not sender:
            sender = self._detect_local_node()
        conv_id = args.get("conv_id", "main")
        reply_to = args.get("reply_to")

        try:
            msg = self.hub.request("/chat/messages", method="POST", data={
                "sender": sender,
                "content": content,
                "conv_id": conv_id,
                "reply_to": reply_to
            })
            return f"Message posted to #{conv_id} as @{sender} (ID: {msg.get('id', '')[:8]}).", False
        except Exception as e:
            return f"Error posting chat message: {e}", True

    def _call_knot_chat_read(self, args: dict) -> tuple[str, bool]:
        conv_id = args.get("conv_id", "main")
        limit = int(args.get("limit", 20))

        try:
            messages = self.hub.request(f"/chat/messages?conv_id={conv_id}&limit={limit}", method="GET")
            if not messages:
                return f"No messages found in #{conv_id}.", False

            lines = [f"=== Swarm Konversations: #{conv_id} (last {len(messages)} turns) ==="]
            for m in messages:
                ts = datetime.fromtimestamp(m.get("created_at", 0), tz=timezone.utc).strftime("%H:%M:%S")
                sender = m.get("sender", "unknown")
                body = m.get("content", "")
                lines.append(f"[{ts}] @{sender}: {body}")

            return "\n".join(lines), False
        except Exception as e:
            return f"Error reading chat messages: {e}", True

    def _call_knot_project_list(self, args: dict) -> tuple[str, bool]:
        try:
            projects = self.hub.request("/projects", method="GET")
            if not projects:
                return "No projects registered in Knot Hub.", False
            lines = [f"=== Knot Native Antigravity Projects ({len(projects)}) ==="]
            lines.append(f"{'PROJECT ID':<26} {'NAME':<28} {'FOLDERS':<8} {'DEFAULT CHAN':<12}")
            lines.append(f"{'-'*26} {'-'*28} {'-'*8} {'-'*12}")
            for p in projects:
                pid = p.get("id", "")[:24]
                name = p.get("name", "")[:26]
                fcount = len(p.get("folders", []))
                dchan = f"#{p.get('default_channel', 'main')}"
                lines.append(f"{pid:<26} {name:<28} {fcount:<8} {dchan:<12}")
            return "\n".join(lines), False
        except Exception as e:
            return f"Error listing projects: {e}", True

    def _call_knot_chat_list_conversations(self, args: dict) -> tuple[str, bool]:
        project_id = args.get("project_id")
        path = "/chat/conversations"
        if project_id:
            path += f"?project_id={urllib.parse.quote(project_id)}"
        try:
            convs = self.hub.request(path, method="GET")
            if not convs:
                return "No conversations found.", False
            lines = [f"=== Knot Swarm Channels ({len(convs)}) ==="]
            lines.append(f"{'CHANNEL ID':<20} {'PROJECT':<22} {'TITLE':<24} {'MSGS':<6} {'CREATED BY':<12}")
            lines.append(f"{'-'*20} {'-'*22} {'-'*24} {'-'*6} {'-'*12}")
            for c in convs:
                cid = f"#{c.get('id', '')}"[:18]
                cproj = c.get("project_id", "")[:20]
                ctitle = c.get("title", "")[:22]
                cmsgs = str(c.get("message_count", 0))
                cby = f"@{c.get('created_by', '')}"[:10]
                lines.append(f"{cid:<20} {cproj:<22} {ctitle:<24} {cmsgs:<6} {cby:<12}")
            return "\n".join(lines), False
        except Exception as e:
            return f"Error listing conversations: {e}", True

    def _call_knot_chat_create_conversation(self, args: dict) -> tuple[str, bool]:
        cid = (args.get("id") or "").strip()
        if not cid:
            return "Error: 'id' is required for knot_chat_create_conversation", True
        project_id = (args.get("project_id") or "knot").strip()
        title = (args.get("title") or f"#{cid}").strip()
        desc = (args.get("description") or "").strip()
        sender = self._detect_local_node()

        try:
            res = self.hub.request("/chat/conversations", method="POST", data={
                "id": cid,
                "project_id": project_id,
                "title": title,
                "description": desc,
                "created_by": sender
            })
            return f"Channel #{cid} ('{title}') successfully created under project '{project_id}'.", False
        except Exception as e:
            return f"Error creating channel: {e}", True

    @staticmethod
    def _detect_local_node() -> str:
        import socket
        return socket.gethostname()

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
        except Exception:
            # Hub exec request failed or unreachable, fallback to local CLI
            pass

        # Local fallback via knot exec CLI
        knot_bin = shutil.which("knot") or os.path.expanduser("~/Dev/knot/bin/knot")
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
            except Exception:
                pass

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
            lines.append("2. **Autonomous Multi-Step Delegation**: Use `knot_task_fanout` or `knot_task_post` for autonomous AI problem-solving on remote nodes.")
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
        self.posted_tasks = []

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
                    "hostname": "devbox",
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
        elif path.startswith("/tasks/list"):
            return [
                {
                    "id": "test-task-1",
                    "title": "Laptop GPU Probe",
                    "prompt": "Report RTX 3050 GPU status",
                    "target_plane": "laptop",
                    "status": "COMPLETED",
                    "claimed_by": "laptop",
                    "result": "- GPU Model: NVIDIA GeForce RTX 3050 Laptop GPU (4 GB)\n- Driver: 610.57.04\n- Temp: 49C",
                    "duration_seconds": 11.2,
                    "tokens_used": 15000,
                    "session_id": "sess-test"
                }
            ]
        elif path == "/tasks/post":
            new_id = f"task-mock-{len(self.posted_tasks) + 1}"
            task = {
                "id": new_id,
                "title": (data or {}).get("title", "Autonomous Swarm Task"),
                "prompt": (data or {}).get("prompt", ""),
                "target_plane": (data or {}).get("target_plane", "any"),
                "status": "QUEUED"
            }
            self.posted_tasks.append(task)
            return task
        elif path == "/tasks/fanout":
            return {
                "batch_id": "batch-mock-1",
                "subtasks": [
                    {"id": "st-1", "title": "Sub 1", "target_plane": "desktop"},
                    {"id": "st-2", "title": "Sub 2", "target_plane": "laptop"}
                ],
                "barrier_task": {"id": "bar-1", "title": "Barrier Reducer", "target_plane": "desktop"}
            }
        elif path.startswith("/tasks/batch/"):
            return {
                "batch_id": "batch-mock-1",
                "total_tasks": 2,
                "completed": 2,
                "running": 0,
                "blocked_on_deps": 0,
                "failed": 0,
                "is_done": True,
                "tasks": [{"id": "st-1", "title": "Sub 1", "status": "COMPLETED", "target_plane": "desktop"}]
            }
        elif path == "/artifacts/lock":
            return {"ok": True, "lease": {"name": (data or {}).get("name"), "state": "LOCKED_SURGERY", "locked_by": "desktop"}}
        elif path == "/artifacts/release":
            return {"ok": True, "lease": {"name": (data or {}).get("name"), "state": "VERIFIED_COMMITTED"}}
        elif path == "/projects":
            return [
                {"id": "knot", "name": "knot", "folders": [os.path.expanduser("~/Dev/knot-mesh")], "default_channel": "main"},
                {"id": "mm-pu-core-connect-website", "name": "mm-pu-core-connect-website", "folders": ["/a", "/b", "/c"], "default_channel": "main"}
            ]
        elif path.startswith("/chat/conversations"):
            if method == "POST":
                return {"ok": True, "conversation": {"id": (data or {}).get("id", "test-chan"), "project_id": (data or {}).get("project_id", "knot")}}
            else:
                return [
                    {"id": "main", "project_id": "knot", "title": "Main Swarm", "message_count": 5, "created_by": "system"},
                    {"id": "incident-kvm", "project_id": "knot", "title": "KVM Deskflow Incident", "message_count": 1, "created_by": "human"}
                ]
        elif path.startswith("/chat/messages"):
            if method == "POST":
                return {"id": "msg-mock-1", "sender": (data or {}).get("sender", "desktop"), "content": (data or {}).get("content", ""), "created_at": 1788992000}
            else:
                return [{"id": "msg-mock-1", "sender": "desktop", "content": "Hello swarm", "created_at": 1788992000}]
        elif path.startswith("/tasks/"):
            tid = path.replace("/tasks/", "").strip()
            return {
                "id": tid,
                "title": "Mock Task",
                "prompt": "Test Prompt",
                "target_plane": "any",
                "status": "COMPLETED",
                "claimed_by": "laptop",
                "result": "Mock execution succeeded.",
                "duration_seconds": 4.2,
                "tokens_used": 1200,
                "session_id": "mock-session"
            }
        elif path == "/mesh/exec":
            return {
                "ok": True,
                "target": (data or {}).get("target", "desktop"),
                "command": (data or {}).get("command", ""),
                "exit_code": 0,
                "stdout": "Mock command execution output",
                "stderr": ""
            }
        elif path == "/swarm/models":
            return {
                "available_models": [
                    {"id": "gemini-3.8-flash-high", "name": "Gemini 3.8 Flash (High)", "tier": "flash", "provider": "google"}
                ],
                "default_model": "gemini-3.8-flash-high",
                "node_models": {"desktop": "gemini-3.8-flash-high"}
            }
        return {}


class MockMemoryPalaceClient(MemoryPalaceClient):
    """Mock Memory Palace & Vault client for offline self-test suites."""

    def __init__(self):
        self.artifacts = {}
        self.memories = {}
        self.my_node = "desktop"
        self.surreal_url = "http://mock.surreal:8000"
        self.pocketbase_url = "http://mock.pocketbase:8090"

    def store_artifact(self, name: str, content: str, artifact_type: str = "text", meta: dict | None = None) -> str:
        aid = f"mock-art-{len(self.artifacts)+1}"
        self.artifacts[aid] = {"name": name, "content": content, "artifact_type": artifact_type, "meta": meta or {}}
        return aid

    def get_artifact(self, artifact_id: str) -> dict:
        if artifact_id in self.artifacts:
            return self.artifacts[artifact_id]
        return {"name": "mock.txt", "artifact_type": "text", "content": "Mock artifact content"}

    def store(
        self,
        wing: str,
        hall: str,
        drawer: str,
        title: str,
        content: str,
        tags: list | None = None,
        importance: float = 1.0,
        artifact_id: str | None = None,
        pool: str = "shared",
        meta: dict | None = None
    ) -> dict:
        mid = f"memory:mock{len(self.memories)+1}"
        rec = {
            "id": mid,
            "wing": wing,
            "hall": hall,
            "drawer": drawer,
            "title": title,
            "content": content,
            "importance": importance,
            "artifact_id": artifact_id,
            "pool": pool,
            "meta": meta or {}
        }
        self.memories[mid] = rec
        return rec

    def recall(
        self,
        query: str | None = None,
        wing: str | None = None,
        hall: str | None = None,
        drawer: str | None = None,
        tags: list | None = None,
        limit: int = 5,
        pool: str | None = None
    ) -> list:
        return [{
            "id": "memory:mock1",
            "title": query or "Mock Memory",
            "content": "Mock memory content for self-test suite",
            "score": 1.0,
            "importance": 1.0,
            "recall_count": 1,
            "pool": pool or "shared",
            "wing": wing or "architecture",
            "hall": hall or "mesh_core",
            "drawer": drawer or "decisions"
        }]

    def palace_map(self, pool: str | None = None) -> dict:
        return {
            "wings": {
                "architecture": {
                    "halls": {
                        "mesh_core": {
                            "drawers": {
                                "decisions": [{"id": "memory:mock1", "title": "Mock", "importance": 1.0, "recall_count": 0, "pool": pool or "shared"}]
                            }
                        }
                    }
                }
            }
        }

    def promote(self, memory_id: str, boost: float = 1.0, to_shared: bool = True) -> float:
        return 2.0

    def relate(self, source: str, target: str, rel_type: str = "relates_to", weight: float = 1.0) -> dict:
        return {"ok": True, "source": source, "target": target}


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
    assert len(tools) == 24, f"Expected exactly 24 tools, got {len(tools)}"

    tool_names = {t["name"] for t in tools}
    expected_tools = {
        "knot_task_post",
        "knot_task_wait",
        "knot_task_list",
        "knot_node_status",
        "knot_quota_matrix",
        "knot_gpu_status",
        "knot_memory_store",
        "knot_memory_recall",
        "knot_memory_palace_map",
        "knot_memory_promote",
        "knot_memory_relate",
        "knot_closet_store",
        "knot_closet_get",
        "knot_task_fanout",
        "knot_task_batch_status",
        "knot_artifact_lock",
        "knot_artifact_commit",
        "knot_chat_post",
        "knot_chat_read",
        "knot_project_list",
        "knot_chat_list_conversations",
        "knot_chat_create_conversation",
        "knot_exec_command",
        "knot_swarm_topology",
    }
    assert tool_names == expected_tools, f"Tool names mismatch: {tool_names} vs {expected_tools}"

    # Verify tool schemas
    tools_by_name = {t["name"]: t for t in tools}
    assert "prompt" in tools_by_name["knot_task_post"]["inputSchema"]["required"]
    assert "task_id" in tools_by_name["knot_task_wait"]["inputSchema"]["required"]
    assert "status" in tools_by_name["knot_task_list"]["inputSchema"]["properties"]
    assert "target" in tools_by_name["knot_quota_matrix"]["inputSchema"]["properties"]
    assert "target" in tools_by_name["knot_gpu_status"]["inputSchema"]["properties"]
    assert "wing" in tools_by_name["knot_memory_store"]["inputSchema"]["required"]
    assert "query" in tools_by_name["knot_memory_recall"]["inputSchema"]["properties"]
    assert "name" in tools_by_name["knot_closet_store"]["inputSchema"]["required"]
    assert "tasks" in tools_by_name["knot_task_fanout"]["inputSchema"]["required"]
    assert "batch_id" in tools_by_name["knot_task_batch_status"]["inputSchema"]["required"]
    assert "name" in tools_by_name["knot_artifact_lock"]["inputSchema"]["required"]
    assert "content" in tools_by_name["knot_chat_post"]["inputSchema"]["required"]
    assert "id" in tools_by_name["knot_chat_create_conversation"]["inputSchema"]["required"]
    assert "command" in tools_by_name["knot_exec_command"]["inputSchema"]["required"]
    assert "properties" in tools_by_name["knot_swarm_topology"]["inputSchema"]
    print("  [PASS] JSON-RPC 'tools/list' (all 24 tools and schemas verified)", file=sys.stderr)

    # 4. Test tools/call
    test_calls = [
        ("knot_node_status", {}),
        ("knot_quota_matrix", {"target": "all"}),
        ("knot_gpu_status", {"target": "laptop"}),
        ("knot_task_list", {"status": None}),
        ("knot_task_post", {"title": "Test Task", "prompt": "echo swarm", "target_plane": "any"}),
        ("knot_task_wait", {"task_id": "test-task-1", "timeout": 5}),
        ("knot_closet_store", {"name": "mcp_test.txt", "content": "hello mcp"}),
        ("knot_memory_store", {
            "wing": "architecture",
            "hall": "mesh_core",
            "drawer": "decisions",
            "title": "MCP Gateway Integration",
            "content": "All 24 swarm coordination tools integrated cleanly"
        }),
        ("knot_memory_recall", {"query": "MCP Gateway"}),
        ("knot_memory_palace_map", {}),
        ("knot_task_fanout", {"tasks": [{"prompt": "Task 1", "title": "Subtask 1"}]}),
        ("knot_task_batch_status", {"batch_id": "batch-mock-1"}),
        ("knot_artifact_lock", {"name": "spec.md", "ttl": 60}),
        ("knot_chat_post", {"content": "Hello swarm from test suite"}),
        ("knot_chat_read", {"conv_id": "main", "limit": 5}),
        ("knot_project_list", {}),
        ("knot_chat_list_conversations", {"project_id": "knot"}),
        ("knot_chat_create_conversation", {"id": "test-channel", "project_id": "knot", "title": "Test Channel"}),
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

    # 5b. Missing required argument for knot_task_post
    missing_arg_call = {
        "jsonrpc": "2.0",
        "id": 100,
        "method": "tools/call",
        "params": {"name": "knot_task_post", "arguments": {}}
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
                ("knot_gpu_status", {"target": "laptop"}),
                ("knot_task_list", {})
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
