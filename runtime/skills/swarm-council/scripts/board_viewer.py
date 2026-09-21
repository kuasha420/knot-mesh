#!/usr/bin/env python3
"""
Knot Swarm Council: Standalone DB Mesh Message Board Live Viewer
Zero-token terminal live viewer for Knot Mesh DB discussion threads and node replies.
Responsive layout optimized for handheld devices (Steam Deck 1280x800, ROG Ally) and large monitors.
Supports interactive live refresh loop and --render-once for scripting/testing.
"""

from __future__ import annotations

import os
import sys
import time
import json
import sqlite3
import shutil
import select
import signal
import urllib.request
import urllib.error
import http.client
import ssl
import argparse
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Tuple

DEFAULT_DB_PATH = os.path.expanduser("~/.config/knot/council.db")
DEFAULT_HUB_URL = os.environ.get("KNOT_HUB_URL", "https://127.0.0.1:4242")

# ANSI Color Codes
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_CYAN = "\033[36m"
C_BCYAN = "\033[1;36m"
C_GREEN = "\033[32m"
C_BGREEN = "\033[1;32m"
C_YELLOW = "\033[33m"
C_BYELLOW = "\033[1;33m"
C_BLUE = "\033[34m"
C_BBLUE = "\033[1;34m"
C_MAGENTA = "\033[35m"
C_BMAGENTA = "\033[1;35m"
C_RED = "\033[31m"
C_BRED = "\033[1;31m"
C_WHITE = "\033[37m"
C_BWHITE = "\033[1;37m"
C_REV = "\033[7m"

NODE_ICONS = {
    "desktop": "🟣",
    "laptop": "🟢",
    "rog-ally": "🔴",
    "steamdeck": "🎮",
    "anchor": "🟣",
}


def try_hub_request(path: str, hub_url: str = DEFAULT_HUB_URL, timeout: float = 1.5) -> Optional[Any]:
    """Queries Knot Hub REST API with proper TLS verification gating and narrow exception handling."""
    url = f"{hub_url.rstrip('/')}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"}, method="GET")

    ctx: Optional[ssl.SSLContext] = None
    if url.startswith("https://"):
        ctx = ssl.create_default_context()
        hub_ca = os.path.expanduser("~/.config/knot/tls/hub.crt")
        if not os.path.exists(hub_ca):
            hub_ca = "/etc/knot/tls/hub.crt"

        ca_loaded = False
        if os.path.exists(hub_ca):
            try:
                ctx.load_verify_locations(cafile=hub_ca)
                ca_loaded = True
            except (ssl.SSLError, OSError) as e:
                if os.environ.get("KNOT_DEBUG"):
                    sys.stderr.write(f"[DEBUG] Failed to load Hub CA cert ({hub_ca}): {e}\n")

        if not ca_loaded:
            allow_insecure = (
                os.environ.get("KNOT_INSECURE_TLS", "").lower() in ("1", "true", "yes")
                or os.environ.get("KNOT_SKIP_TLS_VERIFY", "").lower() in ("1", "true", "yes")
                or any(h in hub_url for h in ("127.0.0.1", "localhost", "::1"))
            )
            if allow_insecure:
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE

    try:
        kwargs: Dict[str, Any] = {"timeout": timeout}
        if ctx is not None:
            kwargs["context"] = ctx
        with urllib.request.urlopen(req, **kwargs) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, http.client.HTTPException, json.JSONDecodeError, TimeoutError, OSError) as e:
        if os.environ.get("KNOT_DEBUG"):
            sys.stderr.write(f"[DEBUG] Hub request to {url} failed: {e}\n")
        return None


class CouncilBoardModel:
    """Data layer fetching threads and messages from Knot Hub or fallback SQLite."""

    def __init__(self, db_path: str = DEFAULT_DB_PATH, hub_url: str = DEFAULT_HUB_URL):
        self.db_path = db_path
        self.hub_url = hub_url
        self.using_hub = False

    def fetch_threads(self) -> List[Dict[str, Any]]:
        # Try Hub API first
        hub_data = try_hub_request("/council/threads", self.hub_url)
        if isinstance(hub_data, list):
            self.using_hub = True
            return sorted(hub_data, key=lambda t: t.get("created_at", ""), reverse=True)

        self.using_hub = False
        if not os.path.isfile(self.db_path):
            return []

        try:
            with sqlite3.connect(self.db_path, timeout=5.0) as conn:
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute("SELECT * FROM council_threads ORDER BY created_at DESC")
                return [dict(r) for r in cur.fetchall()]
        except sqlite3.Error as e:
            if os.environ.get("KNOT_DEBUG"):
                sys.stderr.write(f"[DEBUG] SQLite error fetching council threads from {self.db_path}: {e}\n")
            return []

    def fetch_messages(self, thread_id: str) -> List[Dict[str, Any]]:
        if self.using_hub:
            hub_msgs = try_hub_request(f"/council/threads/{thread_id}/messages", self.hub_url)
            if isinstance(hub_msgs, list):
                return sorted(hub_msgs, key=lambda m: m.get("created_at", ""))

        if not os.path.isfile(self.db_path):
            return []

        try:
            with sqlite3.connect(self.db_path, timeout=5.0) as conn:
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute(
                    "SELECT * FROM council_messages WHERE thread_id = ? OR run_id = ? ORDER BY created_at ASC",
                    (thread_id, thread_id),
                )
                return [dict(r) for r in cur.fetchall()]
        except sqlite3.Error as e:
            if os.environ.get("KNOT_DEBUG"):
                sys.stderr.write(f"[DEBUG] SQLite error fetching messages for thread {thread_id}: {e}\n")
            return []


def format_status_badge(status: str) -> str:
    s = (status or "").upper().strip()
    if s in ("FINAL", "SUCCESS", "100%"):
        return f"{C_BGREEN}[{s}]{C_RESET}"
    elif s in ("PROGRESS", "RUNNING") or "%" in s:
        return f"{C_BCYAN}[{s}]{C_RESET}"
    elif s in ("ALERT", "FAIL", "FAILED", "ERROR"):
        return f"{C_BRED}[{s}]{C_RESET}"
    elif s in ("STANDBY", "IDLE"):
        return f"{C_BYELLOW}[{s}]{C_RESET}"
    return f"{C_DIM}[{s}]{C_RESET}"


def truncate_text(text: str, max_len: int) -> str:
    if len(text) <= max_len:
        return text
    return text[: max_len - 1] + "…"


class BoardViewerRenderer:
    """Renders the message board in compact (handheld) or wide (multi-pane) mode."""

    def __init__(self, model: CouncilBoardModel):
        self.model = model
        self.selected_thread_idx = 0
        self.scroll_offset = 0

    def render_snapshot(self, width: Optional[int] = None, height: Optional[int] = None, thread_override: Optional[str] = None) -> str:
        term_width, term_height = shutil.get_terminal_size((100, 30))
        w = width or term_width
        h = height or term_height

        threads = self.model.fetch_threads()
        if thread_override:
            for idx, t in enumerate(threads):
                if t.get("id") == thread_override or t.get("run_id") == thread_override:
                    self.selected_thread_idx = idx
                    break

        if not threads:
            return self._render_empty_state(w, h)

        if self.selected_thread_idx >= len(threads):
            self.selected_thread_idx = len(threads) - 1
        if self.selected_thread_idx < 0:
            self.selected_thread_idx = 0

        active_thread = threads[self.selected_thread_idx]
        thread_id = active_thread.get("id") or active_thread.get("run_id", "")
        messages = self.model.fetch_messages(thread_id)

        if w < 100:
            return self._render_compact(w, h, threads, active_thread, messages)
        else:
            return self._render_wide(w, h, threads, active_thread, messages)

    def _render_empty_state(self, w: int, h: int) -> str:
        lines = []
        lines.append(f"{C_BCYAN}{'═' * w}{C_RESET}")
        header_text = "🛰️  KNOT SWARM COUNCIL MESSAGE BOARD (LIVE)"
        lines.append(f"{C_BOLD}{header_text.center(w)}{C_RESET}")
        lines.append(f"{C_CYAN}{'─' * w}{C_RESET}")
        lines.append("")
        msg = "(No active council mission threads found in Mesh DB or Knot Hub)"
        lines.append(f"{C_DIM}{msg.center(w)}{C_RESET}")
        lines.append("")
        sub = f"Backend: {'Knot Hub TLS (:4242)' if self.model.using_hub else self.model.db_path}"
        lines.append(f"{C_DIM}{sub.center(w)}{C_RESET}")
        lines.append(f"{C_CYAN}{'═' * w}{C_RESET}")
        return "\n".join(lines)

    def _render_compact(
        self,
        w: int,
        h: int,
        threads: List[Dict[str, Any]],
        active_thread: Dict[str, Any],
        messages: List[Dict[str, Any]],
    ) -> str:
        """Handheld compact layout (Steam Deck 1280x800 / mobile terminal)."""
        lines = []
        # Header line
        title_str = "🛰️ KNOT COUNCIL BOARD"
        mode_str = f"{C_BGREEN}● LIVE{C_RESET}"
        backend_str = f"{C_CYAN}HUB{C_RESET}" if self.model.using_hub else f"{C_YELLOW}LOCAL{C_RESET}"
        time_str = datetime.now().strftime("%H:%M:%S")
        head_line = f"{C_BOLD}{title_str}{C_RESET} [{backend_str}] {mode_str} {C_DIM}{time_str}{C_RESET}"
        lines.append(head_line)

        # Tab strip of threads
        tabs = []
        for idx, t in enumerate(threads[:5]):
            t_id = t.get("run_id") or t.get("id", "")
            short_id = t_id.split("_")[-1] if "_" in t_id else t_id[:8]
            is_active = (idx == self.selected_thread_idx)
            if is_active:
                tabs.append(f"{C_REV}{C_BOLD} #{idx + 1} {short_id} {C_RESET}")
            else:
                tabs.append(f"{C_DIM}#{idx + 1} {short_id}{C_RESET}")
        lines.append(f"THREADS: {' '.join(tabs)}")

        # Active Thread Summary
        run_label = active_thread.get("run_id") or active_thread.get("id")
        t_title = truncate_text(active_thread.get("title", "Council Mission"), w - 10)
        lines.append(f"{C_CYAN}{'─' * w}{C_RESET}")
        lines.append(f"{C_BOLD}Mission:{C_RESET} {C_BCYAN}{run_label}{C_RESET} — {t_title}")
        lines.append(f"{C_CYAN}{'─' * w}{C_RESET}")

        # Messages Stream
        max_msg_lines = max(5, h - 8)
        content_lines = []

        if not messages:
            content_lines.append(f"{C_DIM}  (No node replies posted yet in this thread){C_RESET}")
        else:
            for m in messages:
                node = m.get("node_id", "unknown")
                icon = NODE_ICONS.get(node, "🛰️")
                status = m.get("status", "PROGRESS")
                status_badge = format_status_badge(status)
                time_part = str(m.get("created_at", ""))[-8:]
                content_lines.append(
                    f"{icon} {C_BOLD}@{node}{C_RESET} {status_badge} {C_DIM}{time_part}{C_RESET}"
                )
                body = m.get("body", "").strip()
                for bline in body.split("\n"):
                    bline_clean = bline.strip()
                    if not bline_clean:
                        continue
                    if bline_clean.startswith("<!--"):
                        continue
                    if bline_clean.startswith("###"):
                        content_lines.append(f"  {C_BOLD}{bline_clean[3:].strip()}{C_RESET}")
                    elif bline_clean.startswith("- "):
                        content_lines.append(f"    {C_CYAN}•{C_RESET} {truncate_text(bline_clean[2:], w - 6)}")
                    else:
                        content_lines.append(f"    {truncate_text(bline_clean, w - 6)}")
                content_lines.append(f"{C_DIM}{'·' * (w - 4)}{C_RESET}")

        # Scroll window to bottom by default
        visible_chunk = content_lines[-max_msg_lines:] if len(content_lines) > max_msg_lines else content_lines
        lines.extend(visible_chunk)

        # Footer help bar
        footer = f"{C_REV}[q] Quit  [Tab/←/→] Thread  [r] Refresh  [a] Auto-ref{C_RESET}"
        lines.append(footer)
        return "\n".join(lines)

    def _render_wide(
        self,
        w: int,
        h: int,
        threads: List[Dict[str, Any]],
        active_thread: Dict[str, Any],
        messages: List[Dict[str, Any]],
    ) -> str:
        """Wide monitor layout with left thread sidebar and right message detail pane."""
        lines = []
        # Header line
        title_str = "🛰️  KNOT SWARM COUNCIL MESSAGE BOARD (LIVE)"
        mode_str = f"{C_BGREEN}● LIVE AUTO-REFRESH (2s){C_RESET}"
        backend_str = f"{C_BCYAN}Knot Hub TLS (:4242){C_RESET}" if self.model.using_hub else f"{C_YELLOW}Local SQLite ({self.model.db_path}){C_RESET}"
        time_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        lines.append(f"{C_BOLD}{title_str}{C_RESET} | Backend: {backend_str} | {mode_str} | {C_DIM}{time_str}{C_RESET}")
        lines.append(f"{C_CYAN}{'═' * w}{C_RESET}")

        sidebar_width = 32
        detail_width = w - sidebar_width - 3

        # Prepare left sidebar rows
        sidebar_rows = []
        sidebar_rows.append(f"{C_BOLD}COUNCIL THREADS ({len(threads)}){C_RESET}")
        sidebar_rows.append(f"{C_DIM}{'─' * sidebar_width}{C_RESET}")

        for idx, t in enumerate(threads):
            t_id = t.get("run_id") or t.get("id", "")
            short_id = t_id[:26]
            is_active = (idx == self.selected_thread_idx)
            marker = "▶" if is_active else " "
            color = C_REV if is_active else ""
            reset = C_RESET if is_active else ""
            sidebar_rows.append(f"{color}{marker} #{idx + 1} {truncate_text(short_id, sidebar_width - 6)}{reset}")
            t_title = t.get("title", "Untitled")
            sidebar_rows.append(f"  {C_DIM}{truncate_text(t_title, sidebar_width - 3)}{C_RESET}")

        # Prepare right detail pane rows
        detail_rows = []
        run_id_val = active_thread.get("run_id") or active_thread.get("id")
        t_title_val = active_thread.get("title", "")
        detail_rows.append(f"{C_BCYAN}Mission:{C_RESET} {C_BOLD}{run_id_val}{C_RESET} — {t_title_val}")
        detail_rows.append(f"{C_DIM}URL: {active_thread.get('url', '')} | Started: {active_thread.get('created_at', '')[:19]}{C_RESET}")
        detail_rows.append(f"{C_CYAN}{'─' * detail_width}{C_RESET}")

        if not messages:
            detail_rows.append(f"{C_DIM}(No replies posted yet in this council run){C_RESET}")
        else:
            for m in messages:
                node = m.get("node_id", "unknown")
                icon = NODE_ICONS.get(node, "🛰️")
                status = m.get("status", "PROGRESS")
                status_badge = format_status_badge(status)
                time_str = str(m.get("created_at", ""))[:19]
                detail_rows.append(
                    f"{icon} {C_BOLD}@{node}{C_RESET} {status_badge}  {C_DIM}posted at {time_str}{C_RESET}"
                )
                body = m.get("body", "").strip()
                for bline in body.split("\n"):
                    bline_clean = bline.strip()
                    if not bline_clean or bline_clean.startswith("<!--"):
                        continue
                    if bline_clean.startswith("###"):
                        detail_rows.append(f"  {C_BOLD}{bline_clean[3:].strip()}{C_RESET}")
                    elif bline_clean.startswith("- "):
                        detail_rows.append(f"    {C_CYAN}•{C_RESET} {truncate_text(bline_clean[2:], detail_width - 6)}")
                    else:
                        detail_rows.append(f"    {truncate_text(bline_clean, detail_width - 6)}")
                detail_rows.append(f"{C_DIM}{'─' * detail_width}{C_RESET}")

        # Combine sidebar and detail rows
        body_height = max(10, h - 5)
        for i in range(body_height):
            s_row = sidebar_rows[i] if i < len(sidebar_rows) else ""
            d_row = detail_rows[i] if i < len(detail_rows) else ""
            # Pad sidebar text (accounting for ANSI color escapes)
            lines.append(f"{s_row:<{sidebar_width}} {C_CYAN}│{C_RESET} {d_row}")

        # Footer line
        lines.append(f"{C_CYAN}{'═' * w}{C_RESET}")
        footer_text = f"{C_REV} [q] Quit  [Tab/↑/↓] Switch Thread  [r] Force Refresh  [k] Kitty Launch {C_RESET}"
        lines.append(footer_text)
        return "\n".join(lines)


def run_interactive_loop(model: CouncilBoardModel, poll_interval: float = 2.0) -> None:
    """Live interactive loop using non-blocking terminal IO."""
    renderer = BoardViewerRenderer(model)

    # Save terminal state if in interactive TTY
    is_tty = sys.stdin.isatty()
    old_term_settings = None
    if is_tty:
        try:
            import termios
            import tty
            old_term_settings = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
        except (ImportError, OSError) as e:
            if os.environ.get("KNOT_DEBUG"):
                sys.stderr.write(f"[DEBUG] Terminal raw mode setup failed: {e}\n")

    # Alternate screen buffer & hide cursor
    sys.stdout.write("\033[?1049h\033[?25l")
    sys.stdout.flush()

    def cleanup():
        # Restore main screen buffer & cursor
        sys.stdout.write("\033[?25h\033[?1049l")
        sys.stdout.flush()
        if is_tty and old_term_settings:
            try:
                import termios
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term_settings)
            except (ImportError, OSError) as e:
                if os.environ.get("KNOT_DEBUG"):
                    sys.stderr.write(f"[DEBUG] Terminal reset failed: {e}\n")

    try:
        threads = model.fetch_threads()
        num_threads = max(1, len(threads))

        while True:
            # Clear screen and draw
            snapshot = renderer.render_snapshot()
            sys.stdout.write("\033[H" + snapshot)
            sys.stdout.flush()

            # Wait for keypress or timeout
            if is_tty:
                rlist, _, _ = select.select([sys.stdin], [], [], poll_interval)
                if rlist:
                    ch = sys.stdin.read(1)
                    if ch in ("q", "Q", "\x03"):  # q or Ctrl+C
                        break
                    elif ch in ("r", "R"):
                        continue
                    elif ch in ("\t", "n", "l"):  # Tab or next thread
                        threads = model.fetch_threads()
                        num_threads = max(1, len(threads))
                        renderer.selected_thread_idx = (renderer.selected_thread_idx + 1) % num_threads
                    elif ch in ("p", "h"):  # Previous thread
                        threads = model.fetch_threads()
                        num_threads = max(1, len(threads))
                        renderer.selected_thread_idx = (renderer.selected_thread_idx - 1) % num_threads
                    elif ch == "\x1b":  # Arrow escape sequence
                        seq = sys.stdin.read(2)
                        if seq == "[A":  # Up
                            renderer.selected_thread_idx = max(0, renderer.selected_thread_idx - 1)
                        elif seq == "[B":  # Down
                            threads = model.fetch_threads()
                            renderer.selected_thread_idx = min(len(threads) - 1, renderer.selected_thread_idx + 1)
            else:
                time.sleep(poll_interval)
    finally:
        cleanup()


def launch_in_kitty(args: list[str]) -> None:
    """Spawns dedicated Kitty window if kitty binary is available."""
    kitty_bin = shutil.which("kitty")
    has_display = os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")

    if kitty_bin and has_display:
        script_path = os.path.abspath(__file__)
        cmd = [
            kitty_bin,
            "--title",
            "Knot Swarm Council — Live Message Board",
            "--override",
            "initial_window_width=110c",
            "--override",
            "initial_window_height=32c",
            sys.executable,
            script_path,
        ] + [a for a in args if a != "--kitty"]
        os.execvp(kitty_bin, cmd)
    else:
        sys.stderr.write(
            f"{C_YELLOW}[!] Kitty not found or no graphical display active. Running in current terminal.{C_RESET}\n"
        )


def main():
    parser = argparse.ArgumentParser(description="Knot Swarm Council Live Message Board Viewer")
    parser.add_argument("--db-path", default=DEFAULT_DB_PATH, help="Path to council SQLite database")
    parser.add_argument("--hub-url", default=DEFAULT_HUB_URL, help="Knot Hub REST API URL")
    parser.add_argument("--run-id", help="Select specific mission run ID")
    parser.add_argument("--interval", type=float, default=2.0, help="Live refresh polling interval (seconds)")
    parser.add_argument("--compact", action="store_true", help="Force handheld/compact layout")
    parser.add_argument("--wide", action="store_true", help="Force wide split-pane layout")
    parser.add_argument("--render-once", "--dry-run", dest="render_once", action="store_true", help="Render once and exit")
    parser.add_argument("--kitty", action="store_true", help="Launch inside a dedicated Kitty window")
    args = parser.parse_args()

    if args.kitty:
        launch_in_kitty(sys.argv[1:])
        return

    model = CouncilBoardModel(db_path=args.db_path, hub_url=args.hub_url)

    if args.render_once or not sys.stdin.isatty():
        renderer = BoardViewerRenderer(model)
        w, h = shutil.get_terminal_size((100, 30))
        if args.compact:
            w = 80
        elif args.wide:
            w = 120
        print(renderer.render_snapshot(width=w, height=h, thread_override=args.run_id))
        sys.exit(0)

    run_interactive_loop(model, poll_interval=args.interval)


if __name__ == "__main__":
    main()
