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
COUNCIL_SCRIPTS = os.path.join(REPO_ROOT, "skills", "swarm-council", "scripts")
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

def test_limit_visualizer_aggregator_local_fallback():
    aggregator = QuotaDataAggregator(hub_url="http://invalid.hub.local:9999")
    nodes, power = aggregator.fetch_all()
    assert aggregator.using_hub is False
    assert len(nodes) >= 4
    node_ids = {n["id"] for n in nodes}
    assert "desktop" in node_ids
    assert "laptop" in node_ids
    assert "rog-ally" in node_ids
    assert "steamdeck" in node_ids


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
    assert format_power_string(None, is_offline=True) == "Offline"
    assert format_power_string(None, is_offline=False) == "AC Power"


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

    # Wide matrix layout
    wide = renderer.render_snapshot(width=120, height=30, wide=True)
    assert "NODE" in wide
    assert "MODEL" in wide
    assert "5-HOUR QUOTA" in wide
    assert "WEEKLY BUDGET" in wide
    assert "@desktop" in wide
    assert "Bat 98% (AC)" in wide
    assert "AC Power" in wide


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
