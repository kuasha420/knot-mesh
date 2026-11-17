#!/usr/bin/env python3
"""
Tests for Knot Mesh Zero-Token Live Viewers:
1. Standalone DB Mesh Message Board Live Viewer (board_viewer.py)
2. All-Node Live Antigravity Limit Visualizer (limit_visualizer.py)

Verifies:
- Offline / empty state rendering
- SQLite fallback queries and Hub REST API integration
- Handheld compact (Steam Deck / ROG Ally <=80 cols) and wide (>100 cols) layouts
- Countdown parsers and progress bar formatters
- CLI --render-once execution and zero external LLM token consumption
- PSL Rule 1 compliance
"""

import os
import sys
import json
import sqlite3
import subprocess
from datetime import datetime, timezone, timedelta
from unittest.mock import patch, MagicMock

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
COUNCIL_SCRIPTS = os.path.join(REPO_ROOT, "runtime", "skills", "swarm-council", "scripts")
if COUNCIL_SCRIPTS not in sys.path:
    sys.path.insert(0, COUNCIL_SCRIPTS)

import board_viewer
from board_viewer import (
    CouncilBoardModel,
    BoardViewerRenderer,
    format_status_badge,
    truncate_text,
)
from core.hub.limit_visualizer import (
    QuotaDataAggregator,
    LimitVisualizerRenderer,
    render_progress_bar,
    parse_countdown_seconds,
    format_countdown_string,
    format_power_string,
    extract_node_power,
)


# ==============================================================================
# 1. Message Board Tests
# ==============================================================================

def test_board_viewer_empty_db(tmp_path):
    nonexistent = str(tmp_path / "empty.db")
    model = CouncilBoardModel(db_path=nonexistent, hub_url="http://invalid.hub.local:9999")
    threads = model.fetch_threads()
    assert threads == []
    msgs = model.fetch_messages("none")
    assert msgs == []

    renderer = BoardViewerRenderer(model)
    snapshot = renderer.render_snapshot(width=80, height=24)
    assert "KNOT SWARM COUNCIL MESSAGE BOARD" in snapshot
    assert "No active council mission threads found" in snapshot


def test_board_viewer_sqlite_error(tmp_path):
    # Corrupt or invalid SQLite database file
    corrupt_db = str(tmp_path / "corrupt.db")
    with open(corrupt_db, "w", encoding="utf-8") as f:
        f.write("NOT A SQLITE FILE")

    model = CouncilBoardModel(db_path=corrupt_db, hub_url="http://invalid.hub.local:9999")
    assert model.fetch_threads() == []
    assert model.fetch_messages("any_thread") == []


def test_board_viewer_sqlite_flow(tmp_path):
    db_file = str(tmp_path / "council.db")
    conn = sqlite3.connect(db_file)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE council_threads (
            id TEXT PRIMARY KEY,
            title TEXT,
            run_id TEXT,
            status TEXT,
            created_at TEXT
        )
    """)
    cur.execute("""
        CREATE TABLE council_messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT,
            run_id TEXT,
            node_id TEXT,
            status TEXT,
            body TEXT,
            created_at TEXT
        )
    """)
    now_iso = datetime.now(timezone.utc).isoformat()
    cur.execute(
        "INSERT INTO council_threads VALUES (?, ?, ?, ?, ?)",
        ("run_20260920_053939_797884d6", "Grand Audit Thread", "run_20260920_053939_797884d6", "OPEN", now_iso)
    )
    cur.execute(
        "INSERT INTO council_messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("msg_1", "run_20260920_053939_797884d6", "run_20260920_053939_797884d6", "desktop", "PROGRESS", "### Verification\n- Running tests", now_iso)
    )
    cur.execute(
        "INSERT INTO council_messages VALUES (?, ?, ?, ?, ?, ?, ?)",
        ("msg_2", "run_20260920_053939_797884d6", "run_20260920_053939_797884d6", "laptop", "FINAL", "### Done\n- All tests pass", now_iso)
    )
    conn.commit()
    conn.close()

    model = CouncilBoardModel(db_path=db_file, hub_url="http://invalid.hub.local:9999")
    threads = model.fetch_threads()
    assert len(threads) == 1
    assert threads[0]["id"] == "run_20260920_053939_797884d6"

    msgs = model.fetch_messages("run_20260920_053939_797884d6")
    assert len(msgs) == 2
    assert msgs[0]["node_id"] == "desktop"
    assert msgs[1]["node_id"] == "laptop"

    renderer = BoardViewerRenderer(model)

    # Compact handheld mode (<100 cols)
    compact = renderer.render_snapshot(width=80, height=24)
    assert "KNOT COUNCIL BOARD" in compact
    assert "@desktop" in compact
    assert "@laptop" in compact
    assert "FINAL" in compact

    # Wide desktop mode (>=100 cols)
    wide = renderer.render_snapshot(width=120, height=30)
    assert "COUNCIL THREADS" in wide
    assert "Grand Audit Thread" in wide
    assert "@desktop" in wide
    assert "@laptop" in wide


def test_board_viewer_hub_mock():
    model = CouncilBoardModel(db_path="/dummy/db", hub_url="https://127.0.0.1:4242")
    mock_threads = [
        {"id": "run_mock_hub", "run_id": "run_mock_hub", "title": "Hub Live Thread", "created_at": "2026-09-20T06:00:00Z"}
    ]
    mock_msgs = [
        {"id": "m1", "thread_id": "run_mock_hub", "node_id": "rog-ally", "status": "ALERT", "body": "Low battery", "created_at": "2026-09-20T06:01:00Z"}
    ]

    with patch("board_viewer.try_hub_request") as mock_req:
        def side_effect(path, hub_url, timeout=1.5):
            if path == "/council/threads":
                return mock_threads
            if "/messages" in path:
                return mock_msgs
            return None

        mock_req.side_effect = side_effect

        threads = model.fetch_threads()
        assert model.using_hub is True
        assert len(threads) == 1
        assert threads[0]["id"] == "run_mock_hub"

        msgs = model.fetch_messages("run_mock_hub")
        assert len(msgs) == 1
        assert msgs[0]["node_id"] == "rog-ally"
        assert msgs[0]["status"] == "ALERT"


def test_board_viewer_helpers():
    assert "FINAL" in format_status_badge("FINAL")
    assert "PROGRESS" in format_status_badge("PROGRESS")
    assert "ALERT" in format_status_badge("ALERT")
    assert "75%" in format_status_badge("75%")
    assert "UNKNOWN" in format_status_badge("UNKNOWN")

    assert truncate_text("short", 10) == "short"
    assert truncate_text("this is very long text", 10) == "this is v…"


# ==============================================================================
# 2. Limit Visualizer Tests
# ==============================================================================

def test_limit_visualizer_aggregator_local_fallback(tmp_path, monkeypatch):
    # 1. With real manifests present, ONLY manifested nodes from active swarm are returned (no phantom rog-ally or /etc leak)
    nodes_dir = tmp_path / ".config" / "knot" / "swarms" / "home" / "nodes"
    nodes_dir.mkdir(parents=True)
    for nid in ("desktop", "laptop", "steamdeck"):
        (nodes_dir / f"{nid}.json").write_text(json.dumps({"id": nid, "hostname": nid}), encoding="utf-8")

    # Seed an inactive swarm to verify active-swarm scoping does not leak ghost nodes
    inactive_dir = tmp_path / ".config" / "knot" / "swarms" / "archive_swarm" / "nodes"
    inactive_dir.mkdir(parents=True)
    (inactive_dir / "ghost-node.json").write_text(json.dumps({"id": "ghost-node", "hostname": "ghost"}), encoding="utf-8")

    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("KNOT_ACTIVE_SWARM", "home")

    import glob as real_glob_mod
    real_glob = real_glob_mod.glob

    def hermetic_glob(pattern, *args, **kwargs):
        if str(pattern).startswith("/etc/knot/"):
            return []
        return real_glob(pattern, *args, **kwargs)

    aggregator = QuotaDataAggregator(hub_url="http://invalid.hub.local:9999")
    with patch("core.hub.limit_visualizer.glob.glob", side_effect=hermetic_glob):
        nodes, _ = aggregator.fetch_all()
    assert aggregator.using_hub is False
    node_ids = {n["id"] for n in nodes}
    assert node_ids == {"desktop", "laptop", "steamdeck"}
    assert "rog-ally" not in node_ids
    assert "ghost-node" not in node_ids

    # 2. When zero manifests exist at all, synthetic defaults are used for smoke rendering
    empty_home = tmp_path / "empty_home"
    empty_home.mkdir()
    monkeypatch.setenv("HOME", str(empty_home))
    with patch("core.hub.limit_visualizer.glob.glob", return_value=[]):
        nodes_empty, _ = aggregator.fetch_all()
        assert len(nodes_empty) >= 4
        assert {"desktop", "laptop", "rog-ally", "steamdeck"}.issubset({n["id"] for n in nodes_empty})


def test_limit_visualizer_aggregator_hub_mock():
    aggregator = QuotaDataAggregator(hub_url="https://127.0.0.1:4242")
    mock_nodes = [
        {
            "id": "steamdeck",
            "hostname": "steamdeck",
            "status": "ONLINE",
            "ip": "100.64.0.4",
            "selected_model": "gemini-3.8-flash-high",
            "quota_5h_gemini": 0.50,
            "quota_weekly_gemini": 0.90,
            "quota_data": {
                "gemini_5h_reset_in": "in 2h 10m",
                "gemini_weekly_reset_in": "in 4d 12h",
            },
        }
    ]
    mock_power = {
        "steamdeck": {"battery_percent": 84, "power_source": "BATTERY"}
    }

    with patch("core.hub.limit_visualizer.try_hub_request") as mock_req:
        def side_effect(path, hub_url, timeout=1.5):
            if path == "/nodes":
                return mock_nodes
            if path == "/power/status":
                return mock_power
            return None

        mock_req.side_effect = side_effect

        nodes, power = aggregator.fetch_all()
        assert aggregator.using_hub is True
        assert len(nodes) == 1
        assert nodes[0]["id"] == "steamdeck"
        assert power.get("steamdeck", {}).get("battery_percent") == 84


def test_limit_visualizer_helpers():
    # Progress bars
    bar_ok = render_progress_bar(0.8, is_offline=False, width=10)
    assert "80%" in bar_ok
    bar_low = render_progress_bar(0.25, is_offline=False, width=10)
    assert "25%" in bar_low
    bar_crit = render_progress_bar(0.05, is_offline=False, width=10)
    assert " 5%" in bar_crit
    bar_off = render_progress_bar(None, is_offline=True, width=10)
    assert "OFFLINE" in bar_off

    # Countdowns
    assert format_countdown_string(0) == "Ready"
    assert format_countdown_string(45) == "in 0m 45s"
    assert format_countdown_string(3725) == "in 1h 02m 05s"
    assert format_countdown_string(90000) == "in 1d 1h"

    # Future date parsing
    future_iso = (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat()
    secs = parse_countdown_seconds(future_iso)
    assert 580 <= secs <= 605

    # Power string derivation
    assert format_power_string({"battery_percent": 84, "power_source": "BATTERY"}) == "Bat 84%"
    assert format_power_string({"battery_percent": 98, "power_source": "AC"}) == "Bat 98% (AC)"
    assert format_power_string({"power_source": "AC"}) == "AC Power"
    assert format_power_string({"on_ac": False, "battery_percent": 90}) == "Bat 90%"
    assert format_power_string({"on_ac": False}) == "Battery"
    assert format_power_string({"on_ac": True, "battery_percent": 100}) == "Bat 100% (AC)"
    assert format_power_string({"on_ac": True}) == "AC Power"
    assert format_power_string(None, is_offline=True) == "Offline"
    assert format_power_string(None, is_offline=False) == "AC Power"

    # Nested live Hub /power/status schema extraction
    hub_power_payload = {
        "swarm_active": False,
        "nodes": [
            {"id": "steamdeck", "power": {"on_ac": False, "battery_percent": 90}},
            {"id": "desktop", "power": {"on_ac": True}},
        ],
    }
    assert extract_node_power({"id": "steamdeck"}, hub_power_payload) == {"on_ac": False, "battery_percent": 90}
    assert format_power_string(extract_node_power({"id": "steamdeck"}, hub_power_payload)) == "Bat 90%"
    assert format_power_string(extract_node_power({"id": "laptop", "power": {"on_ac": True, "battery_percent": 100}}, {})) == "Bat 100% (AC)"


def test_limit_visualizer_rendering():
    mock_aggregator = MagicMock()
    mock_aggregator.using_hub = True
    mock_aggregator.hub_url = "https://127.0.0.1:4242"
    mock_nodes = [
        {
            "id": "desktop",
            "hostname": "@desktop",
            "status": "ONLINE",
            "ip": "100.64.0.1",
            "selected_model": "gemini-3.1-pro-high",
            "quota_5h_gemini": 0.95,
            "quota_weekly_gemini": 1.0,
            "account": {"email": "primary@knot.mesh", "profile": "primary"},
            "quota_data": {
                "gemini_5h_reset_in": "Ready",
                "gemini_weekly_reset_in": "in 6d 02h",
            },
        },
        {
            "id": "laptop",
            "hostname": "laptop-box",
            "status": "ONLINE",
            "ip": "100.64.0.2",
            "selected_model": "gemini-3.8-flash-high",
            "quota_5h_gemini": 0.35,
            "quota_weekly_gemini": 0.80,
            "account": {"email": "work@knot.mesh", "profile": "work"},
            "quota_data": {
                "gemini_5h_reset_in": "in 1h 22m",
                "gemini_weekly_reset_in": "in 3d 14h",
            },
        },
    ]
    mock_power = {
        "laptop": {"battery_percent": 98, "power_source": "AC"},
        "desktop": {"power_source": "AC"},
    }
    mock_aggregator.fetch_all.return_value = (mock_nodes, mock_power)

    renderer = LimitVisualizerRenderer(mock_aggregator)

    # Compact handheld layout
    compact = renderer.render_snapshot(width=80, height=24, compact=True)
    assert "KNOT ANTIGRAVITY QUOTA MONITOR" in compact
    assert "desktop" in compact
    assert "laptop" in compact
    assert "gemini-3.1-pro-high" in compact
    assert "Valid (primary)" in compact
    assert "Valid (work)" in compact

    # Wide matrix layout
    wide = renderer.render_snapshot(width=120, height=30, wide=True)
    assert "NODE" in wide
    assert "MODEL" in wide
    assert "PROFILE / EMAIL" in wide
    assert "5-HOUR QUOTA" in wide
    assert "WEEKLY BUDGET" in wide
    assert "@desktop" in wide
    assert "primary (primary@knot.mesh)" in wide
    assert "work (work@knot.mesh)" in wide
    assert "Bat 98% (AC)" in wide
    assert "AC Power" in wide


def test_limit_visualizer_starter_quota_weekly_only():
    """Verify that nodes with Starter Quota (no 5h limit) render [WEEKLY ONLY] / N/A without crash or phantom bars."""
    mock_agg = MagicMock(spec=QuotaDataAggregator)
    mock_agg.using_hub = True
    starter_node = {
        "id": "steamdeck",
        "hostname": "steamdeck-eos",
        "status": "ONLINE",
        "selected_model": "gemini-3.8-flash-high",
        "quota_5h_gemini": None,
        "quota_weekly_gemini": 1.0,
        "quota_data": {
            "has_5h_limit": False,
            "gemini_weekly_reset_in": "in 6d 23h",
            "account": {"email": "starter@knot.mesh", "subscription": "Antigravity Starter Quota"},
        },
    }
    mock_agg.fetch_all.return_value = ([starter_node], {})
    renderer = LimitVisualizerRenderer(mock_agg)

    compact = renderer.render_snapshot(width=80, compact=True)
    assert "[ WEEKLY ONLY ]" in compact
    assert "N/A" in compact

    wide = renderer.render_snapshot(width=120, wide=True)
    assert "[WEEKLY ONLY]" in wide


# ==============================================================================
# 3. CLI Smoke & Zero-Token Audits
# ==============================================================================

def test_cli_smoke_render_once():
    cmd1 = [sys.executable, os.path.join(COUNCIL_SCRIPTS, "board_viewer.py"), "--render-once", "--compact"]
    res1 = subprocess.run(cmd1, capture_output=True, text=True, check=True)
    assert "KNOT" in res1.stdout

    cmd2 = [sys.executable, os.path.join(COUNCIL_SCRIPTS, "board_viewer.py"), "--render-once", "--wide"]
    res2 = subprocess.run(cmd2, capture_output=True, text=True, check=True)
    assert "KNOT" in res2.stdout

    cmd3 = [sys.executable, os.path.join(REPO_ROOT, "core", "hub", "limit_visualizer.py"), "--render-once", "--compact"]
    res3 = subprocess.run(cmd3, capture_output=True, text=True, check=True)
    assert "KNOT" in res3.stdout

    cmd4 = [sys.executable, os.path.join(REPO_ROOT, "core", "hub", "limit_visualizer.py"), "--render-once", "--wide"]
    res4 = subprocess.run(cmd4, capture_output=True, text=True, check=True)
    assert "KNOT" in res4.stdout


def test_zero_token_audit():
    """Verify that neither script imports or uses external LLM client libraries."""
    for script_path in [
        os.path.join(COUNCIL_SCRIPTS, "board_viewer.py"),
        os.path.join(REPO_ROOT, "core", "hub", "limit_visualizer.py"),
    ]:
        with open(script_path, "r", encoding="utf-8") as f:
            code = f.read()
        for forbidden in ["google.generativeai", "openai", "anthropic", "langchain", "llama_index"]:
            assert forbidden not in code, f"Forbidden LLM library '{forbidden}' found in {script_path}"


def test_display_launch_hub_url_injection():
    """Verify that knot display launch resolves and injects KNOT_HUB_URL into execution commands."""
    cmd = [
        os.path.join(REPO_ROOT, "bin", "knot"),
        "display",
        "launch",
        "laptop",
        "board",
        "--dry-run",
    ]
    env = os.environ.copy()
    env["KNOT_HUB_URL"] = "https://192.168.1.100:4242"
    res = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
    assert "KNOT_HUB_URL='https://192.168.1.100:4242'" in res.stdout
    assert "knot council board --compact" in res.stdout


def test_hub_filters_unregistered_ghost_nodes_and_deletes(tmp_path, monkeypatch):
    """Verify Hub list_nodes() excludes offboarded ghost nodes and delete_node() purges them from SQLite."""
    from core.hub import hub as hub_mod

    db_file = str(tmp_path / "hub.db")
    db = hub_mod.Database(db_file)
    db.register_node_heartbeat("desktop", "kuasha-z490ud", ["anchor"])
    db.register_node_heartbeat("steamdeck", "psl-0000", ["handheld"], power={"on_ac": False, "battery_percent": 90})
    db.register_node_heartbeat("rog-ally", "psl-0000", ["handheld"])

    # With active swarm manifests containing only desktop & steamdeck, rog-ally is filtered out
    with patch.object(hub_mod, "get_registered_swarm_node_ids", return_value={"desktop", "steamdeck"}):
        nodes = db.list_nodes()
        ids = {n["id"] for n in nodes}
        assert ids == {"desktop", "steamdeck"}
        assert "rog-ally" not in ids

    # delete_node() physically removes the row from SQLite
    deleted = db.delete_node("rog-ally")
    assert deleted >= 1
    with patch.object(hub_mod, "get_registered_swarm_node_ids", return_value=set()):
        nodes_after = db.list_nodes()
        assert "rog-ally" not in {n["id"] for n in nodes_after}


def test_hub_detect_local_wayland_display(tmp_path, monkeypatch):
    """Verify _detect_local_wayland_display() detects live sockets, validates S_ISSOCK, and sorts numerically."""
    import socket as sock_mod
    from core.hub import hub as hub_mod

    sock_10 = tmp_path / "wayland-10"
    sock_2 = tmp_path / "wayland-2"
    fake_env_file = tmp_path / "wayland-fake"
    fake_env_file.write_text("not a socket", encoding="utf-8")

    s10 = sock_mod.socket(sock_mod.AF_UNIX, sock_mod.SOCK_STREAM)
    s2 = sock_mod.socket(sock_mod.AF_UNIX, sock_mod.SOCK_STREAM)
    try:
        s10.bind(str(sock_10))
        s2.bind(str(sock_2))
        monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
        # Regular file in WAYLAND_DISPLAY must be rejected in favor of real socket, sorted numerically (2 < 10)
        monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-fake")
        assert hub_mod._detect_local_wayland_display(os.getuid()) == "wayland-2"
    finally:
        s10.close()
        s2.close()


def test_extract_node_power_key_collision_resistance():
    """Verify nested Hub /power/status nodes list takes precedence over top-level keys like 'activity'."""
    hub_payload = {
        "swarm_active": True,
        "activity": {"active": True, "reasons": ["recent_activity"]},
        "nodes": [
            {"id": "activity", "power": {"on_ac": False, "battery_percent": 72}},
            {"id": "desktop", "power": {"on_ac": True}},
        ],
    }
    assert extract_node_power({"id": "activity"}, hub_payload) == {"on_ac": False, "battery_percent": 72}
    assert format_power_string(extract_node_power({"id": "activity"}, hub_payload)) == "Bat 72%"

    # Even if node 'activity' has empty power inside nodes list, it must NOT collide with top-level 'activity'
    hub_payload_empty = {
        "swarm_active": True,
        "activity": {"active": True, "reasons": ["tasks_running"]},
        "nodes": [
            {"id": "activity", "power": {}},
        ],
    }
    assert extract_node_power({"id": "activity"}, hub_payload_empty) is None


def test_hub_post_nodes_remove_endpoint(tmp_path):
    """Verify POST /nodes/remove deletes valid nodes and rejects missing/null/non-string node_id with HTTP 400."""
    import threading
    import urllib.request
    import urllib.error
    from core.hub import hub as hub_mod

    db_file = str(tmp_path / "hub_remove.db")
    db = hub_mod.Database(db_file)
    db.register_node_heartbeat("rog-ally", "psl-0000", ["handheld"])
    db.set_node_activity("rog-ally", {"state": "active"})

    class TestHandler(hub_mod.HubRequestHandler):
        pass

    TestHandler.db = db
    server = hub_mod.ThreadingHTTPServer(("127.0.0.1", 0), TestHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def post_remove(payload):
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/nodes/remove",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read().decode("utf-8"))

    try:
        # 1. Valid node removal -> HTTP 200
        status_ok, body_ok = post_remove({"node_id": "rog-ally"})
        assert status_ok == 200
        assert body_ok["ok"] is True
        assert body_ok["node_id"] == "rog-ally"
        assert body_ok["deleted"] >= 1
        assert db.get_node_activity("rog-ally") == {}

        # 2. Missing node_id -> HTTP 400
        status_missing, _ = post_remove({})
        assert status_missing == 400

        # 3. Null node_id -> HTTP 400
        status_null, _ = post_remove({"node_id": None})
        assert status_null == 400

        # 4. Non-string node_id -> HTTP 400
        status_int, _ = post_remove({"node_id": 12345})
        assert status_int == 400
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_capture_node_screen_live_db_ip_disambiguation(tmp_path, monkeypatch):
    """Verify capture_node_screen() prefers live DB IP and disambiguates shared hostnames (psl-0000) by exact id."""
    from core.hub import hub as hub_mod

    db_file = str(tmp_path / "hub_screen.db")
    db = hub_mod.Database(db_file)
    db.register_node_heartbeat("steamdeck", "psl-0000", ["handheld"], ip="192.168.1.50")
    db.register_node_heartbeat("rog-ally", "psl-0000", ["handheld"], ip="192.168.1.99")

    # Make rog-ally's heartbeat strictly newer so a naive hostname query would pick 192.168.1.99
    conn = sqlite3.connect(db_file)
    conn.execute("UPDATE nodes SET last_heartbeat = last_heartbeat + 500 WHERE id = 'rog-ally'")
    conn.commit()
    conn.close()

    monkeypatch.setattr(hub_mod, "SCREEN_CACHE_DIR", str(tmp_path / "screens"))
    monkeypatch.setenv("KNOT_HUB_DB", db_file)

    captured_cmds = []
    fake_png = b"\x89PNG\r\n\x1a\n" + (b"\x00" * 600)

    def fake_run(cmd, *args, **kwargs):
        captured_cmds.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=fake_png, stderr=b"")

    manifest = {
        "id": "steamdeck",
        "hostname": "psl-0000",
        "role": "strand",
        "ip_hint": "192.168.1.10",
        "user": "deck",
        "port": 22,
    }
    with patch.object(hub_mod, "get_node_manifest", return_value=manifest), \
         patch.object(hub_mod.subprocess, "run", side_effect=fake_run):
        data, _ctype = hub_mod.capture_node_screen("steamdeck", force=True, db_path=db_file)

    assert data is not None
    assert len(captured_cmds) == 1
    ssh_cmd = captured_cmds[0]
    assert "deck@192.168.1.50" in ssh_cmd, f"Expected exact-id live IP 192.168.1.50, got {ssh_cmd}"
    assert "deck@192.168.1.99" not in ssh_cmd
    assert "deck@192.168.1.10" not in ssh_cmd
    # Remote command must be wrapped in POSIX sh -c and redirect spectacle stdout to stderr
    remote_arg = ssh_cmd[-1]
    assert remote_arg.startswith("sh -c "), f"Expected POSIX sh -c wrapper, got {remote_arg}"
    assert "spectacle -b -n -o /tmp/knot_screen_steamdeck.png >&2" in remote_arg



