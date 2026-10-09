#!/usr/bin/env python3
"""
Test Suite: Long-Horizon DAG Task Dependencies & Barrier Join (Hermetic Pytest)
Verifies:
1. Subtasks are created in batch with batch_id.
2. Barrier task is held in BLOCKED_ON_DEPS.
3. Partial subtask completion leaves barrier in BLOCKED_ON_DEPS.
4. Once all subtasks complete, barrier task automatically unblocks to QUEUED
   and its prompt contains the synthesized Prerequisite Subtasks Matrix table.
5. Barrier task claims, executes, and resolves batch to completed state.
6. Prerequisite subtask failure propagates BLOCKED_FAILED to barrier task.
"""

from contextlib import contextmanager
import json
import os
import ssl
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import ThreadingHTTPServer

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from core.hub.hub import HubRequestHandler, Database
from core.hub.tls import ensure_hub_tls


def _make_ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def post_json(hub_url: str, path: str, data: dict) -> dict:
    url = f"{hub_url}{path}"
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    ctx = _make_ssl_context() if url.startswith("https://") else None
    with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get_json(hub_url: str, path: str) -> dict:
    url = f"{hub_url}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    ctx = _make_ssl_context() if url.startswith("https://") else None
    with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


@contextmanager
def hub_server_context():
    """
    Context manager yielding an HTTPS hub URL.
    Uses KNOT_HUB_URL if set, or spins up a hermetic in-process HTTPS server with temporary DB and TLS cert.
    """
    env_url = os.environ.get("KNOT_HUB_URL")
    if env_url:
        yield env_url
        return

    tmp_dir = tempfile.TemporaryDirectory()
    db_path = os.path.join(tmp_dir.name, "hub_test.db")
    tls_dir = os.path.join(tmp_dir.name, "tls")

    db = Database(db_path)
    HubRequestHandler.db = db

    httpd = ThreadingHTTPServer(("127.0.0.1", 0), HubRequestHandler)
    port = httpd.server_address[1]

    tls_info = ensure_hub_tls(custom_dir=tls_dir)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(certfile=tls_info["cert_path"], keyfile=tls_info["key_path"])
    httpd.socket = ssl_ctx.wrap_socket(httpd.socket, server_side=True)

    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()

    url = f"https://127.0.0.1:{port}"
    try:
        yield url
    finally:
        httpd.shutdown()
        httpd.server_close()
        HubRequestHandler.db = None
        tmp_dir.cleanup()


try:
    import pytest
except ImportError as _err:
    pytest = None

if pytest is not None:
    @pytest.fixture(scope="function")
    def hub_url():
        with hub_server_context() as url:
            yield url


def test_dag_fanout_creation_and_barrier_blocked(hub_url):
    payload = {
        "tasks": [
            {
                "title": "Subtask Alpha: Hostname Probe",
                "prompt": "Report the local hostname in one sentence.",
                "target_plane": "desktop"
            },
            {
                "title": "Subtask Beta: Architecture Probe",
                "prompt": "Report system architecture (uname -m).",
                "target_plane": "desktop"
            }
        ],
        "barrier_task": {
            "title": "Barrier Reducer: System Synthesis",
            "prompt": "Synthesize findings into bulleted summary.",
            "target_plane": "desktop"
        }
    }

    res = post_json(hub_url, "/tasks/fanout", payload)
    assert "batch_id" in res
    assert len(res["subtasks"]) == 2
    barrier = res["barrier_task"]
    assert barrier is not None

    b_info = get_json(hub_url, f"/tasks/{barrier['id']}")
    assert b_info["status"] == "BLOCKED_ON_DEPS"
    assert len(b_info["dependencies"]) == 2


def test_dag_subtask_execution_unblocks_barrier(hub_url):
    payload = {
        "tasks": [
            {
                "title": "Subtask 1: Echo Test",
                "prompt": "Echo step 1",
                "target_plane": "desktop"
            },
            {
                "title": "Subtask 2: Ping Test",
                "prompt": "Ping step 2",
                "target_plane": "desktop"
            }
        ],
        "barrier_task": {
            "title": "Barrier 1: Final Join",
            "prompt": "Synthesize subtask outputs.",
            "target_plane": "desktop"
        }
    }

    res = post_json(hub_url, "/tasks/fanout", payload)
    batch_id = res["batch_id"]
    subtasks = res["subtasks"]
    barrier = res["barrier_task"]

    # Claim Subtask 1
    c1 = post_json(hub_url, "/tasks/claim", {
        "node_id": "desktop",
        "capabilities": ["desktop"]
    })
    assert c1 is not None and c1.get("id") == subtasks[0]["id"]

    # Complete Subtask 1
    post_json(hub_url, "/tasks/result", {
        "task_id": c1["id"],
        "node_id": "desktop",
        "status": "COMPLETED",
        "result": "Hostname: mesh-desktop",
        "duration_seconds": 1.2
    })

    # Barrier must still be blocked after only 1 of 2 subtasks
    b_mid = get_json(hub_url, f"/tasks/{barrier['id']}")
    assert b_mid["status"] == "BLOCKED_ON_DEPS"

    # Claim Subtask 2
    c2 = post_json(hub_url, "/tasks/claim", {
        "node_id": "desktop",
        "capabilities": ["desktop"]
    })
    assert c2 is not None and c2.get("id") == subtasks[1]["id"]

    # Complete Subtask 2
    post_json(hub_url, "/tasks/result", {
        "task_id": c2["id"],
        "node_id": "desktop",
        "status": "COMPLETED",
        "result": "Arch: x86_64",
        "duration_seconds": 0.8
    })

    # Barrier must now be unblocked to QUEUED
    b_after = get_json(hub_url, f"/tasks/{barrier['id']}")
    assert b_after["status"] == "QUEUED"
    assert "Prerequisite Subtasks Matrix" in b_after["prompt"]
    assert "mesh-desktop" in b_after["prompt"]
    assert "x86_64" in b_after["prompt"]

    # Worker claims and completes the barrier task
    claimed = post_json(hub_url, "/tasks/claim", {
        "node_id": "desktop",
        "capabilities": ["desktop"]
    })
    assert claimed["id"] == barrier["id"]

    final_res = post_json(hub_url, "/tasks/result", {
        "task_id": barrier["id"],
        "node_id": "desktop",
        "status": "COMPLETED",
        "result": "Synthesis complete: mesh-desktop (x86_64)",
        "duration_seconds": 0.5
    })
    assert final_res["status"] == "COMPLETED"

    # Verify overall batch status
    batch_status = get_json(hub_url, f"/tasks/batch/{batch_id}")
    assert batch_status["is_done"] is True
    assert batch_status["completed"] == 3
    assert batch_status["blocked_on_deps"] == 0


def test_dag_dependency_failure_propagation(hub_url):
    payload = {
        "tasks": [
            {
                "title": "Subtask Alpha: Fragile Task",
                "prompt": "Run flaky task",
                "target_plane": "desktop"
            }
        ],
        "barrier_task": {
            "title": "Barrier Reducer: Guard",
            "prompt": "Reduce results",
            "target_plane": "desktop"
        }
    }

    res = post_json(hub_url, "/tasks/fanout", payload)
    barrier = res["barrier_task"]

    # Claim subtask
    c = post_json(hub_url, "/tasks/claim", {
        "node_id": "desktop",
        "capabilities": ["desktop"]
    })
    assert c is not None

    # Fail the prerequisite subtask
    post_json(hub_url, "/tasks/result", {
        "task_id": c["id"],
        "node_id": "desktop",
        "status": "FAILED",
        "result": "Out of memory error",
        "duration_seconds": 2.1
    })

    # Barrier task must transition to BLOCKED_FAILED
    b_info = get_json(hub_url, f"/tasks/{barrier['id']}")
    assert b_info["status"] == "BLOCKED_FAILED"
    assert "failed" in b_info["result"]


if __name__ == "__main__":
    try:
        import pytest
        sys.exit(pytest.main([__file__, "-v"]))
    except ImportError:
        print("=== Running DAG Test Suite (direct runner) ===")
        tests = [
            test_dag_fanout_creation_and_barrier_blocked,
            test_dag_subtask_execution_unblocks_barrier,
            test_dag_dependency_failure_propagation,
        ]
        for t in tests:
            print(f"-> {t.__name__}...", end=" ", flush=True)
            with hub_server_context() as test_url:
                t(test_url)
            print("PASSED")
        print("=== ALL DAG TESTS PASSED! ===")
        sys.exit(0)
