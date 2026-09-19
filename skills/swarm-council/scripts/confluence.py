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

script_dir = os.path.dirname(os.path.realpath(__file__))
knot_root = os.path.realpath(os.path.join(script_dir, "../../.."))
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


def generate_session_conf(run_id, nodes, missions_dir, knot_root, project_name="knot-mesh", tiling="grid", interactive=False, resume=False):
    knot_bin = os.path.join(knot_root, "bin/knot")
    if not os.path.isfile(knot_bin) or not os.access(knot_bin, os.X_OK):
        import shutil
        knot_bin = shutil.which("knot") or os.path.expanduser("~/.local/bin/knot")

    # Resolve dynamic palette with topological near-neighbor separation
    dynamic_palette = {}
    if resolve_swarm_palette:
        try:
            dynamic_palette = resolve_swarm_palette(node_ids=nodes)
        except Exception:
            pass

    tiling_layouts = {
        "grid": "layout grid",
        "sidebyside": "layout horizontal",
        "horizontal": "layout horizontal",
        "splits": "layout splits",
        "tall": "layout tall:bias=50;full_size=1",
        "fat": "layout fat:bias=50;full_size=1",
        "stacked": "layout vertical",
        "vertical": "layout vertical",
        "stack": "layout stack",
    }
    active_layout = tiling_layouts.get(tiling.lower(), "layout grid")

    lines = [
        "# Swarm Council Confluence Session",
        f"# Run ID: {run_id}",
        f"# Tiling Mode: {tiling} ({active_layout})",
        f"# Interactive Mode: {interactive}",
        f"# Resuming Session: {resume}",
        "# SIGHUP resilience: trap '' HUP",
        "enabled_layouts grid,splits,tall,fat,horizontal,vertical,stack",
        active_layout,
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
            if interactive:
                # Zero-Token Interactive Cockpit: drops directly into agy TUI
                if resume:
                    agy_cmd = f'exec agy --project "{project_name}" --dangerously-skip-permissions -c'
                    mode_label = "Resuming Session (agy -c)"
                else:
                    agy_cmd = f'exec agy --project "{project_name}" --dangerously-skip-permissions'
                    mode_label = "Zero-Token Standby (Prompt to steer)"

                if node in [local_host, "desktop", "localhost"]:
                    ps.write(f'export KNOT_NODE_ID="{node}"\n')
                    ps.write(f'export KNOT_COUNCIL_RUN_ID="{run_id}"\n')
                    ps.write(f'export KNOT_HUB_URL="https://127.0.0.1:4242"\n')
                    ps.write(f'export KNOT_COUNCIL_DB="mesh"\n')
                    ps.write(f'export KNOT_PROJECT="{project_name}"\n')
                    ps.write(f'export KNOT_PEERS="{",".join(nodes)}"\n')
                    ps.write(f'export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"\n')
                    ps.write(f'PDIR="$("{knot_root}/skills/swarm-council/scripts/resolve_project.py" "{project_name}" 2>/dev/null || echo "{knot_root}")"\n')
                    ps.write('if [ -d "$PDIR" ]; then cd "$PDIR"; fi\n')
                    ps.write(f'echo -e "\\033[1;36m╔══════════════════════════════════════════════════════════════════════╗\\033[0m"\n')
                    ps.write(f'echo -e "\\033[1;36m║\\033[0m  🛰️  \\033[1mKnot Swarm Interactive Cockpit: @[{node}]\\033[0m ({desc})"\n')
                    ps.write(f'echo -e "\\033[1;36m║\\033[0m  Project:   \\033[33m{project_name}\\033[0m ($PWD)"\n')
                    ps.write(f'echo -e "\\033[1;36m║\\033[0m  Registry:  \\033[35mknot://mesh/council/{run_id}\\033[0m"\n')
                    ps.write(f'echo -e "\\033[1;36m║\\033[0m  Mode:      \\033[32m{mode_label}\\033[0m"\n')
                    ps.write(f'echo -e "\\033[1;36m║\\033[0m  Commands:  \\033[32mknot council reply\\033[0m | \\033[32mknot council status\\033[0m"\n')
                    ps.write(f'echo -e "\\033[1;36m╚══════════════════════════════════════════════════════════════════════╝\\033[0m"\n')
                    ps.write('echo ""\n')
                    ps.write(f'{agy_cmd}\n')
                else:
                    if resume:
                        remote_agy = f'exec agy --project \\"{project_name}\\" --dangerously-skip-permissions -c'
                    else:
                        remote_agy = f'exec agy --project \\"{project_name}\\" --dangerously-skip-permissions'
                    remote_cmd = (
                        f"trap '' HUP; "
                        f"export KNOT_NODE_ID='{node}' KNOT_COUNCIL_RUN_ID='{run_id}' KNOT_HUB_URL='https://127.0.0.1:4242' KNOT_COUNCIL_DB='mesh' KNOT_PROJECT='{project_name}' KNOT_PEERS='{','.join(nodes)}' PATH=\"\\$HOME/.local/bin:/usr/local/bin:/usr/bin:\\$PATH\"; "
                        f"TARGET=\"\"; for c in \"\\$HOME/Dev/{project_name}\" \"\\$HOME/{project_name}\" \"\\$HOME/.local/share/{project_name}\" \"Dev/{project_name}\" \"{project_name}\"; do if [ -d \"\\$c\" ]; then TARGET=\"\\$c\"; break; fi; done; if [ -n \"\\$TARGET\" ]; then cd \"\\$TARGET\"; fi; "
                        f"echo -e '\\033[1;36m╔══════════════════════════════════════════════════════════════════════╗\\033[0m'; "
                        f"echo -e '\\033[1;36m║\\033[0m  🛰️  \\033[1mKnot Swarm Interactive Cockpit: @[{node}]\\033[0m ({desc})'; "
                        f"echo -e '\\033[1;36m║\\033[0m  Project:   \\033[33m{project_name}\\033[0m (\\$PWD)'; "
                        f"echo -e '\\033[1;36m║\\033[0m  Registry:  \\033[35mknot://mesh/council/{run_id}\\033[0m'; "
                        f"echo -e '\\033[1;36m║\\033[0m  Mode:      \\033[32m{mode_label}\\033[0m'; "
                        f"echo -e '\\033[1;36m║\\033[0m  Commands:  \\033[32mknot council reply\\033[0m | \\033[32mknot council status\\033[0m'; "
                        f"echo -e '\\033[1;36m╚══════════════════════════════════════════════════════════════════════╝\\033[0m'; "
                        f"echo ''; {remote_agy}"
                    )
                    ps.write(f'exec "{knot_bin}" exec -tt {node} "{remote_cmd}"\n')
            else:
                if node in [local_host, "desktop", "localhost"]:
                    ps.write(f'exec "{missions_dir}/launch.sh"\n')
                else:
                    ps.write(f'exec "{knot_bin}" exec -tt {node} "trap \'\' HUP; ~/.config/knot/missions/{run_id}/launch.sh; exec bash"\n')
        os.chmod(pane_script, 0o755)

        lines.append(f"launch --cwd={knot_root} {pane_script}")
        lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Swarm Council Confluence Session Engine")
    parser.add_argument("--run-id", required=True, help="Mission run ID")
    parser.add_argument("--nodes", default="", help="Comma-separated nodes")
    parser.add_argument("--project", default="knot-mesh", help="Antigravity project name")
    parser.add_argument("--tiling", default="grid", help="Cockpit window tiling layout: grid, sidebyside, splits, tall, fat, stacked")
    parser.add_argument("--interactive", action="store_true", help="Launch interactive multi-node cockpit without prompt dispatch")
    parser.add_argument("--resume", action="store_true", help="Resume previous conversations in cockpit via agy -c")
    parser.add_argument("--dry-run", action="store_true", help="Generate config without launching Kitty")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.realpath(__file__))
    knot_root = os.path.realpath(os.path.join(script_dir, "../../.."))
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
        project_name=args.project,
        tiling=args.tiling,
        interactive=args.interactive,
        resume=args.resume
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

    socket_path = f"/tmp/kitty-council-{args.run_id}.sock"
    meta_file = os.path.join(missions_dir, "meta.json")
    if os.path.exists(meta_file):
        try:
            with open(meta_file, "r") as mf:
                mdata = json.load(mf)
            mdata["socket"] = socket_path
            with open(meta_file, "w") as mf:
                json.dump(mdata, mf, indent=2)
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
                "-o", "allow_remote_control=yes",
                "--listen-on", f"unix:{socket_path}",
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
        print(f"Launched fullscreen Kitty Confluence cockpit (Socket: {socket_path}).")


if __name__ == "__main__":
    main()
