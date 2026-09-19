#!/usr/bin/env python3
"""
Antigravity PreInvocation Lifecycle Hook: Swarm Council Coordinator
Injects ephemeral mesh coordination context only on Turn 1 (invocationNum == 1)
when KNOT_COUNCIL_RUN_ID is set. Completely inert (<2ms, 0 steps injected)
outside of council sessions and on subsequent turns.
"""

import os
import sys
import json

ROLE_HINTS = {
    "desktop": "Mesh Anchor & Coordinator",
    "laptop": "CUDA Compute & Roaming Strand",
    "rog-ally": "Handheld Strand (AMD APU)",
    "steamdeck": "Gaming Handheld Strand (SteamOS APU)"
}


def main():
    # 1. Read Antigravity stdin payload
    payload = {}
    try:
        if not sys.stdin.isatty():
            raw_input = sys.stdin.read()
            if raw_input.strip():
                payload = json.loads(raw_input)
    except Exception:
        payload = {}

    # 2. Strict Arena Isolation Check:
    # If not running in a Swarm Council session, exit immediately with 0 injected steps.
    council_run_id = os.environ.get("KNOT_COUNCIL_RUN_ID")
    if not council_run_id:
        print(json.dumps({"injectSteps": []}))
        return

    # 3. Turn-1 Gating Check:
    # Only inject the full coordination context on the first turn of each node's session.
    # Subsequent turns already retain this context in conversation history.
    invocation_num = payload.get("invocationNum", 1)
    if invocation_num > 1:
        print(json.dumps({"injectSteps": []}))
        return

    # 4. Resolve Node & Mesh Identity
    try:
        from resolve_node import resolve_local_node_id
        default_node = resolve_local_node_id()
    except Exception:
        default_node = "localhost"
    node_id = os.environ.get("KNOT_NODE_ID", default_node)
    peers = os.environ.get("KNOT_PEERS", "")
    db_backend = os.environ.get("KNOT_COUNCIL_DB", "mesh")
    hub_url = os.environ.get("KNOT_HUB_URL", "https://127.0.0.1:4242")
    project = os.environ.get("KNOT_PROJECT", "knot-mesh")
    role_title = ROLE_HINTS.get(node_id, "Strand Worker")

    registry_desc = f"knot://mesh/council/{council_run_id}" if db_backend == "mesh" else "GitHub Discussions"

    # 5. Build Ephemeral Steering & Coordination Context
    ephemeral_text = (
        f"🛰️ [Swarm Council Interactive Turn Active]\n"
        f"- Node Identifier: @[{node_id}] ({role_title})\n"
        f"- Council Run ID:  {council_run_id}\n"
        f"- Active Peers:    {peers or 'All online fleet'}\n"
        f"- Mesh Registry:   {registry_desc}\n"
        f"- Active Project:  {project}\n\n"
        f"AUTONOMOUS COORDINATION PROTOCOL:\n"
        f"1. You and your peer agents coordinate autonomously across the mesh. The human operator is here only to prompt and steer your execution.\n"
        f"2. Checkpoint Broadcasting: When you achieve milestones, discover anomalies, or reach verdicts, broadcast compact status updates (strictly under 15 lines):\n"
        f"   knot council reply {council_run_id} --node {node_id} --status <25%|50%|75%|ALERT|FINAL> --body '<compact update>'\n"
        f"3. Peer State Inquiries: To inspect peer updates and shared discoveries across the mesh, run:\n"
        f"   knot council status {council_run_id}\n"
        f"4. Peer Mentions: Address specific peer nodes using unambiguous markup: @[node:<target_node_id>].\n"
        f"5. Alert Blockers: Post STATUS: ALERT immediately upon encountering verified regressions or blockers.\n"
        f"6. Cockpit Inter-Agent Steering: To delegate a cognitive task or pass a challenge visibly into a co-located peer's pane, run:\n"
        f"   knot council steer <target_node_id> '<prompt>'\n"
        f"   (Never use headless ssh / knot exec to bypass an agent co-located in the cockpit)."
    )

    result = {
        "injectSteps": [
            {
                "ephemeralMessage": ephemeral_text
            }
        ]
    }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
