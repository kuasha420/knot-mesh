#!/usr/bin/env python3
"""
Swarm Council: Stage 5 Blockbuster Confluence Mode
Generates a Kitty session file faithfully mapping physical workspace topology,
dynamically computes display scaling and font size, resolves node color palettes,
and launches a GPU-accelerated fullscreen Kitty cockpit.
"""

import argparse
import glob
import json
import math
import os
import re
import subprocess
import sys

script_dir = os.path.dirname(os.path.abspath(__file__))
knot_root = os.path.abspath(os.path.join(script_dir, "../../.."))
if knot_root not in sys.path:
    sys.path.insert(0, knot_root)

try:
    from core.palette import resolve_swarm_palette
except ImportError:
    resolve_swarm_palette = None


def detect_display_scale() -> float:
    """Detect active Wayland/KDE display scale factor dynamically."""
    # 1. Check environment variables
    for var in ("QT_SCALE_FACTOR", "GDK_SCALE"):
        val = os.environ.get(var)
        if val:
            try:
                s = float(val)
                if s > 0:
                    return s
            except ValueError:
                pass

    # 2. Check kscreen-doctor -o (KDE Plasma 6 Wayland)
    try:
        out = subprocess.run(
            ["kscreen-doctor", "-o"],
            capture_output=True,
            text=True,
            timeout=2
        ).stdout
        clean = re.sub(r"\x1b\[[0-9;]*m", "", out)
        m = re.search(r"Scale:\s*([\d\.]+)", clean)
        if m:
            s = float(m.group(1))
            if s > 0:
                return s
    except Exception:
        pass

    # 3. Check wlr-randr (wlroots Wayland)
    try:
        out = subprocess.run(
            ["wlr-randr"],
            capture_output=True,
            text=True,
            timeout=2
        ).stdout
        m = re.search(r"Scale:\s+([\d\.]+)", out)
        if m:
            s = float(m.group(1))
            if s > 0:
                return s
    except Exception:
        pass

    return 1.0


def calculate_cockpit_font_size(scale: float) -> float:
    """
    Calculate optimal cockpit font size based on display scale.
    Linearly maps scale 1.0 -> 12.0pt, scale 1.5 -> 10.5pt, scale 2.0 -> 9.0pt.
    """
    size = 12.0 - (scale - 1.0) * 3.0
    return round(max(8.0, min(12.0, size)), 1)


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

    # Resolve dynamic palette with topological near-neighbor separation
    dynamic_palette = {}
    if resolve_swarm_palette:
        try:
            dynamic_palette = resolve_swarm_palette(node_ids=nodes)
        except Exception:
            pass

    lines = [
        "# Swarm Council Confluence Session",
        f"# Run ID: {run_id}",
        "# SIGHUP resilience: trap '' HUP",
        "enabled_layouts grid,splits,tall,fat",
        "layout grid",
        ""
    ]

    priority = ["desktop", "laptop", "rog-ally", "steamdeck"]
    ordered_nodes = []
    for p in priority:
        if p in nodes:
            ordered_nodes.append(p)
    for n in nodes:
        if n not in ordered_nodes:
            ordered_nodes.append(n)

    role_hints = {
        "desktop": "Anchor / Coordinator",
        "laptop": "CUDA / Roaming Strand",
        "rog-ally": "Handheld Strand (AMD APU)",
        "steamdeck": "Gaming Handheld (SteamOS APU)"
    }

    try:
        local_host = subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip()
    except Exception:
        local_host = "desktop"

    for node in ordered_nodes:
        if node in dynamic_palette:
            c = dynamic_palette[node]
            emoji = c.emoji
        else:
            emoji = "⚪"

        desc = role_hints.get(node, "Strand Worker")
        lines.append(f"title {emoji} {node} ({desc})")

        # Create isolated per-pane wrapper script to eliminate nested quote-escaping fragility
        pane_script = os.path.join(missions_dir, f"confluence_{node}.sh")
        with open(pane_script, "w") as ps:
            ps.write("#!/usr/bin/env bash\n")
            ps.write("trap '' HUP\n")
            if node in [local_host, "desktop", "localhost"]:
                ps.write(f'exec "{missions_dir}/launch.sh"\n')
            else:
                ps.write(f'exec "{knot_bin}" exec -t {node} "trap \'\' HUP; ~/.config/knot/missions/{run_id}/launch.sh; exec bash"\n')
        os.chmod(pane_script, 0o755)

        lines.append(f"launch --cwd={knot_root} {pane_script}")
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

    os.makedirs(missions_dir, exist_ok=True)

    session_content = generate_session_conf(
        run_id=args.run_id,
        nodes=nodes,
        missions_dir=missions_dir,
        knot_root=knot_root,
        project_name=args.project
    )

    session_file = os.path.join(missions_dir, "kitty_session.conf")
    with open(session_file, "w") as f:
        f.write(session_content)

    print(f"Generated Kitty session: {session_file}")

    # Dynamic display scale and font calculation
    scale = detect_display_scale()
    font_size = calculate_cockpit_font_size(scale)
    print(f"Detected display scale: {scale}x -> Cockpit font size: {font_size}pt")

    # Dynamic active border color from anchor node
    active_border = "#A855F7"
    if resolve_swarm_palette:
        try:
            p = resolve_swarm_palette(node_ids=nodes)
            if "desktop" in p:
                active_border = p["desktop"].hex
        except Exception:
            pass

    if not args.dry_run:
        env = os.environ.copy()
        env.setdefault("DISPLAY", ":0")
        env.setdefault("WAYLAND_DISPLAY", "wayland-0")
        subprocess.Popen(
            [
                "kitty",
                "--start-as=fullscreen",
                "-o", f"font_size={font_size}",
                "-o", "window_border_width=3pt",
                "-o", "window_margin_width=3",
                "-o", "window_padding_width=8",
                "-o", f"active_border_color={active_border}",
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
