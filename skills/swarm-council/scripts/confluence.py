#!/usr/bin/env python3
"""
Swarm Council: Stage 5 Blockbuster Confluence Mode
Generates a Kitty session file faithfully mapping physical workspace topology
and launches a GPU-accelerated fullscreen Kitty cockpit.
"""

import os
import sys
import json
import glob
import re
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
        "enabled_layouts grid,splits,tall,fat",
        "layout grid",
        ""
    ]

    # Deterministic spatial order for optimal cockpit visibility:
    # 1. Anchor (desktop / coordinator) -> Top-Left
    # 2. CUDA / Roaming Strand (laptop) -> Top-Right
    # 3. Handheld Strand 1 (rog-ally) -> Bottom-Left
    # 4. Handheld Strand 2 (steamdeck) -> Bottom-Right
    priority = ["desktop", "laptop", "rog-ally", "steamdeck"]
    ordered_nodes = []
    for p in priority:
        if p in nodes:
            ordered_nodes.append(p)
    for n in nodes:
        if n not in ordered_nodes:
            ordered_nodes.append(n)

    descriptions = {
        "desktop": ("🟣", "Anchor / Coordinator", "#A855F7"),
        "laptop": ("🔵", "CUDA / Roaming Strand", "#00F0FF"),
        "rog-ally": ("🔴", "Handheld Strand (AMD APU)", "#F43F5E"),
        "steamdeck": ("🟠", "Gaming Handheld (SteamOS APU)", "#FFAA00")
    }

    try:
        local_host = subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip()
    except Exception:
        local_host = "desktop"

    for node in ordered_nodes:
        meta = descriptions.get(node, ("⚪", "Strand Worker", "#7047EB"))
        emoji, desc, color = meta
        lines.append(f"title {emoji} {node} ({desc})")
        if node in [local_host, "desktop", "localhost"]:
            cmd = f'{missions_dir}/launch.sh; exec bash'
        else:
            cmd = f'{knot_bin} exec -t {node} "trap \'\' HUP; ~/.config/knot/missions/{run_id}/launch.sh; exec bash"'
        lines.append(f'launch --cwd={knot_root} bash -c {json.dumps(cmd)}')
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
        prompts = glob.glob(os.path.join(missions_dir, "*_prompt.md"))
        if prompts:
            nodes = [re.sub(r"_prompt\.md$", "", os.path.basename(p)) for p in prompts]
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
            [
                "kitty",
                "--start-as=fullscreen",
                "-o", "font_size=9.0",
                "-o", "window_border_width=3pt",
                "-o", "window_margin_width=3",
                "-o", "window_padding_width=8",
                "-o", "active_border_color=#A855F7",
                "-o", "inactive_border_color=#1E2238",
                "--session", session_file
            ],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        print("Launched fullscreen Kitty Confluence cockpit.")

if __name__ == "__main__":
    main()
