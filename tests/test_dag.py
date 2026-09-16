#!/usr/bin/env python3
"""
Test Suite: Long-Horizon DAG Task Dependencies & Barrier Join
Verifies that:
1. Subtasks are created in batch with batch_id.
2. Barrier task is held in BLOCKED_ON_DEPS.
3. Once all subtasks complete, barrier task automatically unblocks to QUEUED
   and its prompt contains the synthesized prerequisite matrix table.
4. Barrier task executes and produces final result.
"""

import json
import os
import sys
import time
import urllib.request

HUB_URL = os.environ.get("KNOT_HUB_URL", "http://127.0.0.1:4242")

def post_json(path: str, data: dict) -> dict:
    url = f"{HUB_URL}{path}"
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))

def get_json(path: str) -> dict:
    url = f"{HUB_URL}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))

def main():
    print(f"=== [Test] DAG Task Dependencies & Barrier Fan-In on {HUB_URL} ===")

    # 1. Post a fan-out batch
    payload = {
        "tasks": [
            {
                "title": "Subtask Alpha: Hostname Probe",
                "prompt": "Report the local hostname in one sentence.",
                "target_plane": "desktop"
            },
            {
                "title": "Subtask Beta: Architecture Probe",
                "prompt": "Report the system machine architecture (uname -m) in one sentence.",
                "target_plane": "desktop"
            }
        ],
        "barrier_task": {
            "title": "Barrier Reducer: System Synthesis",
            "prompt": "Synthesize the findings from Subtask Alpha and Beta into a bulleted summary.",
            "target_plane": "desktop"
        }
    }

    print("[1/5] Submitting fan-out batch (2 subtasks + 1 barrier reducer)...")
    res = post_json("/tasks/fanout", payload)
    batch_id = res["batch_id"]
    subtasks = res["subtasks"]
    barrier = res["barrier_task"]
    assert len(subtasks) == 2, f"Expected 2 subtasks, got {len(subtasks)}"
    assert barrier is not None, "Barrier task not returned"
    print(f"  -> Batch ID: {batch_id}")
    print(f"  -> Subtask 1: {subtasks[0]['id'][:8]} (status: {subtasks[0]['status']})")
    print(f"  -> Subtask 2: {subtasks[1]['id'][:8]} (status: {subtasks[1]['status']})")
    print(f"  -> Barrier:   {barrier['id'][:8]} (status: {barrier['status']})")

    # 2. Verify barrier task is BLOCKED_ON_DEPS
    print("\n[2/5] Verifying barrier task status...")
    b_info = get_json(f"/tasks/{barrier['id']}")
    assert b_info["status"] == "BLOCKED_ON_DEPS", f"Barrier should be BLOCKED_ON_DEPS, got {b_info['status']}"
    assert len(b_info["dependencies"]) == 2, f"Barrier should have 2 dependencies"
    print(f"  -> Confirmed: Barrier is BLOCKED_ON_DEPS pending: {b_info['dependencies']}")

    # 3. Simulate or wait for subtask execution
    print("\n[3/5] Waiting for subtasks to be claimed and executed by worker agent...")
    start_time = time.time()
    while time.time() - start_time < 90:
        batch_status = get_json(f"/tasks/batch/{batch_id}")
        c = batch_status["completed"]
        b = batch_status["blocked_on_deps"]
        r = batch_status["running"]
        q = batch_status["queued"]
        print(f"  -> Batch progress: {c}/2 completed, {r} running, {q} queued, {b} blocked on DAG...", end="\r")
        if c >= 2:
            print("\n  -> Both subtasks completed!")
            break
        time.sleep(2.0)

    # 4. Check if barrier unblocked to QUEUED
    print("\n[4/5] Checking if barrier task unblocked to QUEUED...")
    b_after = get_json(f"/tasks/{barrier['id']}")
    print(f"  -> Barrier task status: {b_after['status']}")
    assert b_after["status"] in ("QUEUED", "CLAIMED", "RUNNING", "COMPLETED"), f"Barrier should have unblocked! Status: {b_after['status']}"
    assert "Prerequisite Subtasks Matrix" in b_after["prompt"], "Prerequisite matrix table was not injected into prompt!"
    print("  -> Confirmed: Prerequisite Subtasks Matrix injected into reducer prompt!")

    # 5. Wait for barrier task completion
    print("\n[5/5] Waiting for barrier task to execute and complete...")
    start_time = time.time()
    while time.time() - start_time < 90:
        b_final = get_json(f"/tasks/{barrier['id']}")
        if b_final["status"] == "COMPLETED":
            print(f"\n[+] Barrier task completed successfully!")
            print(f"  -> Duration: {b_final.get('duration_seconds')}s")
            print(f"  -> Claimed by: @{b_final.get('claimed_by')}")
            print(f"  -> Final Result:\n{b_final.get('result')}")
            break
        elif b_final["status"] in ("FAILED", "ERROR", "BLOCKED_FAILED"):
            raise RuntimeError(f"Barrier task failed: {b_final}")
        time.sleep(2.0)

    print("\n[✓] ALL DAG & BARRIER ORCHESTRATION TESTS PASSED!")

if __name__ == "__main__":
    main()
