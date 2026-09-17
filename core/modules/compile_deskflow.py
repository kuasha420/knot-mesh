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
from typing import Dict, Any, List

DIR_MAP = {
    "left": "left",
    "right": "right",
    "up": "up",
    "above": "up",
    "down": "down",
    "below": "down"
}

OPP_MAP = {
    "left": "right",
    "right": "left",
    "up": "down",
    "down": "up"
}

def compile_deskflow(topology_file: str, nodes_dir: str, mode: str = "unlocked") -> str:
    if not os.path.isfile(topology_file):
        raise FileNotFoundError(f"Topology file not found: {topology_file}")

    with open(topology_file, "r") as f:
        topo = json.load(f)

    anchor = topo.get("anchor", "desktop")
    topo_nodes = topo.get("nodes", {})
    raw_screens = topo.get("screens", [])
    layout = topo.get("layout", {})
    links_list = topo.get("links", [])

    # Load node manifests to map node IDs to hostnames and identify headless nodes
    id_to_host: Dict[str, str] = {}
    host_to_id: Dict[str, str] = {}
    headless_nodes = set()

    if os.path.isdir(nodes_dir):
        for fname in sorted(os.listdir(nodes_dir)):
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
                    if (
                        data.get("role") == "headless"
                        or data.get("headless") is True
                        or ("display" in data and data.get("display") is None)
                    ):
                        if nid:
                            headless_nodes.add(nid)
            except Exception as e:
                sys.stderr.write(f"[compile_deskflow] Warning: failed reading manifest {fpath}: {e}\n")

    # Check topology nodes for headless property
    for nid, ndata in topo_nodes.items():
        if (
            ndata.get("headless") is True
            or ndata.get("role") == "headless"
            or ("display" in ndata and ndata.get("display") is None)
        ):
            headless_nodes.add(nid)

    # Determine candidate screen list
    candidate_screens = []
    if raw_screens:
        candidate_screens = raw_screens
    elif topo_nodes:
        candidate_screens = list(topo_nodes.keys())

    screen_hostnames: List[str] = []
    for s in candidate_screens:
        if s in headless_nodes or ":" in s:
            continue
        h = id_to_host.get(s, s)
        if h not in screen_hostnames:
            screen_hostnames.append(h)

    # Parse layout and links into unified layout dict:
    # full_layout[source_nid][direction] = [ { "target": target_nid, "span": [s1, s2], "target_span": [t1, t2] } ]
    full_layout: Dict[str, Dict[str, List[Dict[str, Any]]]] = {}

    def _add_link(src: str, d: str, tgt: str, span: List[int], target_span: List[int]):
        if src in headless_nodes or tgt in headless_nodes or not tgt:
            return
        if ":" in src or ":" in tgt:
            return
        if src not in full_layout:
            full_layout[src] = {}
        if d not in full_layout[src]:
            full_layout[src][d] = []
        # Check if already exists
        for existing in full_layout[src][d]:
            if existing["target"] == tgt and existing["span"] == span:
                return
        full_layout[src][d].append({
            "target": tgt,
            "span": span,
            "target_span": target_span
        })

    # 1. From layout dictionary
    for node_id, directions in layout.items():
        if node_id in headless_nodes:
            continue
        for d, spec in directions.items():
            norm_d = DIR_MAP.get(d.lower())
            if not norm_d:
                continue
            specs = spec if isinstance(spec, list) else [spec]
            for s in specs:
                target_node = s.get("node")
                span = s.get("span", [0, 100])
                target_span = s.get("target_span", [0, 100])
                _add_link(node_id, norm_d, target_node, span, target_span)

    # 2. From links list
    for link in links_list:
        source = link.get("from")
        target = link.get("to")
        d = link.get("direction")
        if not source or not target or not d:
            continue
        norm_d = DIR_MAP.get(d.lower())
        if not norm_d:
            continue
        span = link.get("span", [0, 100])
        target_span = link.get("target_span", [0, 100])
        _add_link(source, norm_d, target, span, target_span)

    # 3. Reciprocal link generation & span coordination
    for src, dirs in list(full_layout.items()):
        for d, link_list in list(dirs.items()):
            for info in link_list:
                tgt = info["target"]
                if tgt in headless_nodes:
                    continue
                opp_d = OPP_MAP.get(d)
                if not opp_d:
                    continue
                
                # Check if reciprocal link exists
                has_reciprocal = False
                if tgt in full_layout and opp_d in full_layout[tgt]:
                    for r_info in full_layout[tgt][opp_d]:
                        if r_info["target"] == src:
                            info["target_span"] = r_info["span"]
                            r_info["target_span"] = info["span"]
                            has_reciprocal = True
                            break
                
                if not has_reciprocal:
                    _add_link(tgt, opp_d, src, info.get("target_span", [0, 100]), info["span"])

    # 1. Section: screens
    lines = ["section: screens"]
    for h in screen_hostnames:
        lines.append(f"\t{h}:")
    lines.append("end\n")

    # 2. Section: aliases
    lines.append("section: aliases")
    for nid, hname in sorted(id_to_host.items()):
        if nid in headless_nodes:
            continue
        if nid != hname:
            lines.append(f"\t{hname}:")
            lines.append(f"\t\t{nid}")
    lines.append("end\n")

    # 3. Section: links
    lines.append("section: links")
    for hname in screen_hostnames:
        nid = host_to_id.get(hname, hname)
        lines.append(f"\t{hname}:")

        # If this is the anchor and mode is locked, omit outbound links to confine cursor
        is_anchor = (nid == anchor or hname == anchor or hname == id_to_host.get(anchor))
        if is_anchor and mode == "locked":
            continue

        node_links = full_layout.get(nid, {})
        for direction in ["left", "right", "up", "down"]:
            for spec in node_links.get(direction, []):
                target_node = spec["target"]
                target_host = id_to_host.get(target_node, target_node)
                if target_host not in screen_hostnames:
                    continue
                span = spec.get("span", [0, 100])
                target_span = spec.get("target_span", [0, 100])
                lines.append(f"\t\t{direction}({span[0]},{span[1]}) = {target_host}({target_span[0]},{target_span[1]})")
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
    parser.add_argument("--locked", type=str, choices=["true", "false", "True", "False"], default=None, help="KVM cursor confinement locked boolean")
    parser.add_argument("--output", help="Output file path (default: stdout)")

    args = parser.parse_args()

    mode = args.mode
    if args.locked is not None:
        mode = "locked" if args.locked.lower() == "true" else "unlocked"

    try:
        conf = compile_deskflow(args.topology, args.nodes_dir, mode=mode)
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
