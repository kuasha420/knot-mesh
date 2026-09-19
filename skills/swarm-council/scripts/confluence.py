#!/usr/bin/env python3
"""
Swarm Council: Stage 5 Blockbuster Confluence Mode
Generates a Kitty session file faithfully mapping physical workspace topology
and launches a GPU-accelerated fullscreen Kitty cockpit.
"""

import os
import sys
import json
import argparse
import subprocess

def load_topology(knot_root):
    home = os.path.expanduser("~")
    top_candidates = [
        os.path.join(home, ".config/knot/swarms/home/topology.json"),
        os.path.join(home, ".config/knot/swarms/office/topology.json")
    ]
    for c in top_candidates:
        if os.path.exists(c):
            try:
                with open(c) as f:
                    return json.load(f)
            except Exception:
                pass
    return {
        "anchor": "desktop",
        "screens": ["desktop", "laptop", "rog-ally", "steamdeck"]
    }

def generate_session_conf(run_id, nodes, missions_dir, knot_root, project_name="knot-mesh"):
    knot_bin = os.path.join(knot_root, "bin/knot")
    lines = [
        "# Swarm Council Confluence Session",
        f"# Run ID: {run_id}",
        "layout splits",
        ""
    ]

    left_node = "laptop" if "laptop" in nodes else None
    anchor_node = "desktop" if "desktop" in nodes else nodes[0]
    bottom_nodes = [n for n in nodes if n not in [left_node, anchor_node]]

    # 1. Left pane: Laptop
    if left_node:
        lines.append(f"title {left_node} (CUDA / Roaming Strand)")
        cmd = f'{knot_bin} exec -t {left_node} "trap \'\' HUP; ~/.config/knot/missions/{run_id}/launch.sh; exec bash"'
        lines.append(f'launch --cwd={knot_root} bash -c {json.dumps(cmd)}')
        lines.append("")

    # 2. Right Pane: Desktop Anchor
    lines.append(f"title {anchor_node} (Anchor / Coordinator)")
    loc = "vsplit" if left_node else "hsplit"
    cmd_anchor = f'{missions_dir}/launch.sh; exec bash'
    lines.append(f'launch --location={loc} --cwd={knot_root} bash -c {json.dumps(cmd_anchor)}')
    lines.append("")

    # 3. Bottom Panes: ROG Ally & Steam Deck
    for b_node in bottom_nodes:
        lines.append(f"title {b_node} (Handheld / Auxiliary Strand)")
        cmd_b = f'{knot_bin} exec -t {b_node} "trap \'\' HUP; ~/.config/knot/missions/{run_id}/launch.sh; exec bash"'
        lines.append(f'launch --location=hsplit --cwd={knot_root} bash -c {json.dumps(cmd_b)}')
        lines.append("")

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Swarm Council Confluence Session Engine")
    parser.add_argument("--run-id", required=True, help="Mission run ID")
    parser.add_argument("--nodes", default="", help="Comma-separated nodes")
    parser.add_argument("--project", default="knot-mesh", help="Antigravity project name")
    parser.add_argument("--dry-run", action="store_true", help="Generate config without launching Kitty")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    knot_root = os.path.abspath(os.path.join(script_dir, "../../.."))
    missions_dir = os.path.expanduser(f"~/.config/knot/missions/{args.run_id}")

    if args.nodes:
        nodes = [n.strip() for n in args.nodes.split(",") if n.strip()]
    else:
        nodes = ["desktop", "laptop", "rog-ally", "steamdeck"]

    session_content = generate_session_conf(
        run_id=args.run_id,
        nodes=nodes,
        missions_dir=missions_dir,
        knot_root=knot_root,
        project_name=args.project
    )

    os.makedirs(missions_dir, exist_ok=True)
    session_file = os.path.join(missions_dir, "kitty_session.conf")
    with open(session_file, "w") as f:
        f.write(session_content)

    print(f"Generated Kitty session: {session_file}")

    if not args.dry_run:
        env = os.environ.copy()
        env.setdefault("DISPLAY", ":0")
        env.setdefault("WAYLAND_DISPLAY", "wayland-0")
        subprocess.Popen(
            ["kitty", "--start-as=fullscreen", "--session", session_file],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        print("Launched fullscreen Kitty Confluence cockpit.")

if __name__ == "__main__":
    main()
