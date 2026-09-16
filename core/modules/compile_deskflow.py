#!/usr/bin/env python3
"""
Knot Dynamic Deskflow Server Configuration Compiler
Translates declarative topology.json and node manifests into deskflow-server.conf
Zero external dependencies (uses standard library Python 3).
"""

import sys
import os
import json
import argparse

def compile_deskflow(topology_file: str, nodes_dir: str, mode: str = "unlocked") -> str:
    if not os.path.isfile(topology_file):
        raise FileNotFoundError(f"Topology file not found: {topology_file}")

    with open(topology_file, "r") as f:
        topo = json.load(f)

    anchor = topo.get("anchor", "desktop")
    screens = topo.get("screens", [])
    layout = topo.get("layout", {})

    # Load node manifests to map node IDs to hostnames
    id_to_host = {}
    host_to_id = {}

    if os.path.isdir(nodes_dir):
        for fname in os.listdir(nodes_dir):
            if not fname.endswith(".json"):
                continue
            fpath = os.path.join(nodes_dir, fname)
            try:
                with open(fpath, "r") as mf:
                    data = json.load(mf)
                    nid = data.get("id")
                    hname = data.get("hostname")
                    if nid and hname:
                        id_to_host[nid] = hname
                        host_to_id[hname] = nid
            except Exception as e:
                sys.stderr.write(f"[compile_deskflow] Warning: failed reading manifest {fpath}: {e}\n")

    # Fallbacks for screens
    screen_hostnames = []
    for s in screens:
        h = id_to_host.get(s, s)
        if h not in screen_hostnames:
            screen_hostnames.append(h)

    # 1. Section: screens
    lines = ["section: screens"]
    for h in screen_hostnames:
        lines.append(f"\t{h}:")
    lines.append("end\n")

    # 2. Section: aliases
    lines.append("section: aliases")
    for nid, hname in id_to_host.items():
        if nid != hname:
            lines.append(f"\t{hname}:")
            lines.append(f"\t\t{nid}")
    lines.append("end\n")

    # 3. Section: links
    lines.append("section: links")
    for node_id, directions in layout.items():
        host = id_to_host.get(node_id, node_id)
        lines.append(f"\t{host}:")

        # If this is the anchor and mode is locked, omit outbound links to confine cursor
        if node_id == anchor and mode == "locked":
            continue

        for direction, spec in directions.items():
            target_node = spec.get("node")
            target_host = id_to_host.get(target_node, target_node)
            span = spec.get("span", [0, 100])
            span_str = f"({span[0]},{span[1]})"

            # In Deskflow: direction(span) = target_screen(target_span)
            # Find return span if specified in target's layout
            target_span_str = "(0,100)"
            target_layout = layout.get(target_node, {})
            opp_map = {"left": "right", "right": "left", "up": "down", "down": "up"}
            opp_dir = opp_map.get(direction)
            if opp_dir and opp_dir in target_layout:
                opp_spec = target_layout[opp_dir]
                if opp_spec.get("node") == node_id and "span" in opp_spec:
                    t_span = opp_spec["span"]
                    target_span_str = f"({t_span[0]},{t_span[1]})"

            lines.append(f"\t\t{direction}{span_str} = {target_host}{target_span_str}")
    lines.append("end\n")

    # 4. Section: options
    lines.append("section: options")
    lines.append("\trelativeMouseMoves = false")
    lines.append("\tclipboardSharing = false")
    lines.append("\tswitchCorners = none")
    lines.append("\tswitchCornerSize = 0")
    lines.append("\tswitchDelay = 0")
    lines.append("\tkeystroke(ScrollLock) = lockCursorToScreen(toggle)")
    lines.append("\tkeystroke(super+Escape) = lockCursorToScreen(toggle)")
    lines.append("end")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Compile Knot Deskflow server layout")
    parser.add_argument("--topology", required=True, help="Path to topology.json")
    parser.add_argument("--nodes-dir", required=True, help="Path to nodes manifests directory")
    parser.add_argument("--mode", choices=["unlocked", "locked"], default="unlocked", help="KVM cursor confinement mode")
    parser.add_argument("--output", help="Output file path (default: stdout)")

    args = parser.parse_args()

    try:
        conf = compile_deskflow(args.topology, args.nodes_dir, args.mode)
        if args.output:
            os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
            with open(args.output, "w") as f:
                f.write(conf)
        else:
            sys.stdout.write(conf)
    except Exception as e:
        sys.stderr.write(f"[compile_deskflow] Error: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
