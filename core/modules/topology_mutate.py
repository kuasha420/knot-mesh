#!/usr/bin/env python3
"""
Knot Multi-Screen Declarative Topology Mutation Engine
Zero external dependencies (uses standard library Python 3).

Provides declarative operations:
- link: Add directional links with optional fractional spans and reciprocal edge generation.
- unlink: Prune targeted destination slices or all directional links along an edge.
- remove: Purge node from screens and remove all associated directional links across cluster.
- set-anchor: Update active anchor display node.
"""

import argparse
import json
import os
import sys
import tempfile
from typing import Any, Dict, List, Optional

DIR_MAP = {
    "left": "left",
    "right": "right",
    "up": "up",
    "above": "up",
    "down": "down",
    "below": "down",
}

OPPOSITE_DIR = {
    "left": "right",
    "right": "left",
    "up": "down",
    "down": "up",
}


def parse_span(span_str: str) -> List[int]:
    """
    Parse a span string formatted as 'MIN-MAX' into a [min_val, max_val] pair.
    Validates bounds: 0 <= min_val < max_val <= 100.
    """
    if not isinstance(span_str, str):
        raise ValueError(f"Span must be a string, got {type(span_str).__name__}")

    raw = span_str.strip()
    if raw.startswith("-"):
        raise ValueError(
            f"Invalid span '{span_str}': negative values are not allowed. Expected 0 <= MIN < MAX <= 100."
        )

    parts = raw.split("-")
    if len(parts) != 2:
        raise ValueError(
            f"Invalid span format '{span_str}'. Expected 'MIN-MAX' (e.g. '0-100', '0-50', '50-100')."
        )

    if not parts[0].isdigit() or not parts[1].isdigit():
        raise ValueError(
            f"Invalid span values '{span_str}'. Both MIN and MAX must be non-negative integers."
        )

    min_val = int(parts[0])
    max_val = int(parts[1])

    if not (0 <= min_val < max_val <= 100):
        raise ValueError(
            f"Span bounds violation in '{span_str}': required 0 <= MIN < MAX <= 100, got MIN={min_val}, MAX={max_val}."
        )

    return [min_val, max_val]


def intervals_overlap(a: List[int], b: List[int]) -> bool:
    """
    Check if two open/half-open intervals [A, B] and [C, D] overlap in their interior.
    Interior overlap occurs iff max(A, C) < min(B, D).
    Abutting intervals (e.g. [0, 50] and [50, 100]) do NOT overlap.
    """
    return max(a[0], b[0]) < min(a[1], b[1])


def load_topology(topo_file: str) -> Dict[str, Any]:
    """
    Load topology JSON configuration from file, or initialize a default empty topology.
    """
    if os.path.isfile(topo_file):
        with open(topo_file, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if content:
                try:
                    data = json.loads(content)
                    if isinstance(data, dict):
                        return data
                except json.JSONDecodeError as err:
                    raise ValueError(f"Corrupt topology file at '{topo_file}': {err}") from err

    return {"anchor": "", "screens": [], "layout": {}, "locked": False}


def save_topology(topo_file: str, data: Dict[str, Any]) -> None:
    """
    Atomically write topology JSON configuration to disk via tempfile replacement.
    """
    abs_path = os.path.abspath(topo_file)
    dirname = os.path.dirname(abs_path)
    if dirname:
        os.makedirs(dirname, exist_ok=True)

    tmp_fd, tmp_path = tempfile.mkstemp(dir=dirname, prefix=".topo_", suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, abs_path)
    except Exception as exc:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise exc


def get_edge_links(layout: Dict[str, Any], node: str, direction: str) -> List[Dict[str, Any]]:
    """
    Retrieve all normalized link specifications for a given node and direction.
    Normalizes single dicts, lists, or legacy strings into a list of dicts.
    """
    node_layout = layout.get(node)
    if not isinstance(node_layout, dict):
        return []
    edge_val = node_layout.get(direction)
    if not edge_val:
        return []
    raw_list = edge_val if isinstance(edge_val, list) else [edge_val]
    normalized: List[Dict[str, Any]] = []
    for item in raw_list:
        if isinstance(item, str):
            normalized.append({"node": item, "span": [0, 100], "target_span": [0, 100]})
        elif isinstance(item, dict) and "node" in item:
            span = item.get("span", [0, 100])
            target_span = item.get("target_span", [0, 100])
            normalized.append({
                "node": item["node"],
                "span": list(span),
                "target_span": list(target_span),
            })
    return normalized


def set_edge_links(layout: Dict[str, Any], node: str, direction: str, links: List[Dict[str, Any]]) -> None:
    """
    Store links for a given node and direction in layout.
    Removes the direction key if links is empty.
    Stores as a dict if 1 link, or list of dicts (sorted by span start) if multiple.
    """
    if node not in layout:
        layout[node] = {}

    if not links:
        if direction in layout[node]:
            del layout[node][direction]
        return

    # Deterministic sorting by start coordinate of span
    links.sort(key=lambda x: x.get("span", [0, 100])[0])

    if len(links) == 1:
        layout[node][direction] = links[0]
    else:
        layout[node][direction] = links


def link(
    topo_file: str,
    src: str,
    direction: str,
    dst: str,
    span_str: str = "0-100",
    target_span_str: str = "0-100",
    reciprocal: bool = True,
) -> None:
    """
    Add a directional link between src and dst with validated fractional spans.
    Automatically generates reciprocal edge unless reciprocal=False.
    Rejects interior interval overlaps on src (direction) and dst (reciprocal direction).
    """
    if src == dst:
        raise ValueError(f"Cannot link node '{src}' to itself.")

    norm_dir = DIR_MAP.get(direction.lower())
    if not norm_dir:
        raise ValueError(
            f"Invalid direction '{direction}'. Must be one of: {', '.join(sorted(DIR_MAP.keys()))}"
        )

    span = parse_span(span_str)
    target_span = parse_span(target_span_str)

    topo = load_topology(topo_file)
    layout = topo.setdefault("layout", {})
    screens = topo.setdefault("screens", [])

    # Validate interval overlaps on source direction
    existing_src_links = get_edge_links(layout, src, norm_dir)
    for ex in existing_src_links:
        ex_span = ex.get("span", [0, 100])
        if intervals_overlap(span, ex_span):
            raise ValueError(
                f"Span [{span[0]}, {span[1]}] overlaps with existing link to '{ex.get('node')}' "
                f"[{ex_span[0]}, {ex_span[1]}] on '{src}' direction '{norm_dir}'."
            )

    # Validate reciprocal interval overlaps on destination opposite direction
    opp_dir = OPPOSITE_DIR[norm_dir]
    if reciprocal:
        existing_dst_links = get_edge_links(layout, dst, opp_dir)
        for ex in existing_dst_links:
            ex_span = ex.get("span", [0, 100])
            if intervals_overlap(target_span, ex_span):
                raise ValueError(
                    f"Reciprocal span [{target_span[0]}, {target_span[1]}] overlaps with existing link to '{ex.get('node')}' "
                    f"[{ex_span[0]}, {ex_span[1]}] on '{dst}' direction '{opp_dir}'."
                )

    # Ensure nodes are registered in screens
    if src not in screens:
        screens.append(src)
    if dst not in screens:
        screens.append(dst)

    # Default anchor to src if unset
    if not topo.get("anchor"):
        topo["anchor"] = src

    # Add source link
    new_src_link = {"node": dst, "span": span, "target_span": target_span}
    new_src_links = existing_src_links + [new_src_link]
    set_edge_links(layout, src, norm_dir, new_src_links)

    # Add reciprocal destination link
    if reciprocal:
        existing_dst_links = get_edge_links(layout, dst, opp_dir)
        new_dst_link = {"node": src, "span": target_span, "target_span": span}
        new_dst_links = existing_dst_links + [new_dst_link]
        set_edge_links(layout, dst, opp_dir, new_dst_links)

    save_topology(topo_file, topo)
    recip_info = f" (reciprocal: {dst} [{target_span[0]}-{target_span[1]}%] --{opp_dir}--> {src})" if reciprocal else ""
    print(
        f"Linked {src} [{span[0]}-{span[1]}%] --{norm_dir}--> {dst} [{target_span[0]}-{target_span[1]}%]{recip_info}"
    )


def unlink(
    topo_file: str,
    src: str,
    direction: str,
    dst: Optional[str] = None,
) -> None:
    """
    Remove link(s) on src in direction.
    If dst is specified, prunes only the link pointing to dst and its reciprocal.
    If dst is None, prunes all links on that direction and their reciprocals.
    """
    norm_dir = DIR_MAP.get(direction.lower())
    if not norm_dir:
        raise ValueError(
            f"Invalid direction '{direction}'. Must be one of: {', '.join(sorted(DIR_MAP.keys()))}"
        )

    topo = load_topology(topo_file)
    layout = topo.get("layout", {})
    existing_src_links = get_edge_links(layout, src, norm_dir)

    if not existing_src_links:
        raise ValueError(
            f"No links found for source '{src}' on direction '{norm_dir}'."
        )

    opp_dir = OPPOSITE_DIR[norm_dir]

    if dst is not None:
        matching = [l for l in existing_src_links if l.get("node") == dst]
        if not matching:
            raise ValueError(
                f"No link found from '{src}' to '{dst}' on direction '{norm_dir}'."
            )
        rem_src_links = [l for l in existing_src_links if l.get("node") != dst]
        set_edge_links(layout, src, norm_dir, rem_src_links)

        # Symmetrically prune reciprocal on dst
        for m in matching:
            dst_links = get_edge_links(layout, dst, opp_dir)
            m_tspan = m.get("target_span", [0, 100])
            # Prefer matching exact reciprocal link with identical span
            has_exact = any(
                l.get("node") == src and l.get("span") == m_tspan for l in dst_links
            )
            if has_exact:
                rem_dst_links = [
                    l for l in dst_links if not (l.get("node") == src and l.get("span") == m_tspan)
                ]
            else:
                rem_dst_links = [l for l in dst_links if l.get("node") != src]
            set_edge_links(layout, dst, opp_dir, rem_dst_links)

        save_topology(topo_file, topo)
        print(f"Unlinked {src} --{norm_dir}--> {dst} and reciprocal on {dst}.")
    else:
        # Full unlink: prune all links along norm_dir and their reciprocals
        for m in existing_src_links:
            target_node = m.get("node")
            if target_node:
                dst_links = get_edge_links(layout, target_node, opp_dir)
                m_tspan = m.get("target_span", [0, 100])
                has_exact = any(
                    l.get("node") == src and l.get("span") == m_tspan for l in dst_links
                )
                if has_exact:
                    rem_dst_links = [
                        l for l in dst_links if not (l.get("node") == src and l.get("span") == m_tspan)
                    ]
                else:
                    rem_dst_links = [l for l in dst_links if l.get("node") != src]
                set_edge_links(layout, target_node, opp_dir, rem_dst_links)

        set_edge_links(layout, src, norm_dir, [])

    # Clean links list if present in topology
    if "links" in topo and isinstance(topo["links"], list):
        opp_dir = OPPOSITE_DIR[norm_dir]
        if dst:
            topo["links"] = [
                l for l in topo["links"]
                if not (isinstance(l, dict) and (
                    ((l.get("from") == src or l.get("src") == src) and (l.get("to") == dst or l.get("dst") == dst) and DIR_MAP.get(str(l.get("direction", "")).lower()) == norm_dir) or
                    ((l.get("from") == dst or l.get("src") == dst) and (l.get("to") == src or l.get("dst") == src) and DIR_MAP.get(str(l.get("direction", "")).lower()) == opp_dir)
                ))
            ]
        else:
            topo["links"] = [
                l for l in topo["links"]
                if not (isinstance(l, dict) and (
                    ((l.get("from") == src or l.get("src") == src) and DIR_MAP.get(str(l.get("direction", "")).lower()) == norm_dir) or
                    ((l.get("to") == src or l.get("dst") == src) and DIR_MAP.get(str(l.get("direction", "")).lower()) == opp_dir)
                ))
            ]

    save_topology(topo_file, topo)
    if dst:
        print(f"Unlinked {src} --{norm_dir}--> {dst} and reciprocal.")
    else:
        print(f"Unlinked all {norm_dir} links from {src} and reciprocals.")


def remove(topo_file: str, node: str) -> None:
    """
    Remove node from screens, delete layout[node], and purge all incoming references to node.
    Rejects removal of active anchor with exit code 1.
    """
    topo = load_topology(topo_file)
    active_anchor = topo.get("anchor")
    if active_anchor == node:
        sys.stderr.write(f"Error: Cannot remove active Anchor node '{node}' from topology.\n")
        sys.exit(1)

    screens = topo.get("screens", [])
    if isinstance(screens, list):
        topo["screens"] = [s for s in screens if s != node]

    layout = topo.get("layout", {})
    if isinstance(layout, dict) and node in layout:
        del layout[node]

    # Purge all incoming directional links referencing node across other nodes
    if isinstance(layout, dict):
        for other_node in list(layout.keys()):
            node_layout = layout[other_node]
            if not isinstance(node_layout, dict):
                continue
            for d in list(node_layout.keys()):
                links = get_edge_links(layout, other_node, d)
                filtered = [l for l in links if l.get("node") != node]
                set_edge_links(layout, other_node, d, filtered)

    # 1. Prune from nodes dictionary (schema / legacy)
    if "nodes" in topo and isinstance(topo["nodes"], dict):
        topo["nodes"].pop(node, None)
        for nid, ndata in topo["nodes"].items():
            if isinstance(ndata, dict) and "screens" in ndata and isinstance(ndata["screens"], list):
                ndata["screens"] = [s for s in ndata["screens"] if s != node]

    # 2. Prune from links list if present
    if "links" in topo and isinstance(topo["links"], list):
        topo["links"] = [
            l for l in topo["links"]
            if not (isinstance(l, dict) and (l.get("from") == node or l.get("to") == node or l.get("src") == node or l.get("dst") == node))
        ]

    save_topology(topo_file, topo)
    print(f"Removed node '{node}' from topology.")


def set_anchor(topo_file: str, node: str) -> None:
    """
    Update active anchor display node and ensure node exists in screens.
    """
    if not node or not node.strip():
        raise ValueError("Node ID cannot be empty.")

    topo = load_topology(topo_file)
    screens = topo.setdefault("screens", [])
    if node not in screens:
        screens.append(node)
    topo["anchor"] = node
    save_topology(topo_file, topo)
    print(f"Set active anchor node to '{node}'.")


def resolve_topology_file(cli_arg: Optional[str]) -> str:
    """
    Resolve target topology.json path from CLI argument, env var, or active swarm directory.
    """
    if cli_arg:
        return os.path.abspath(cli_arg)
    env_topo = os.environ.get("KNOT_TOPOLOGY_FILE")
    if env_topo:
        return os.path.abspath(env_topo)
    active_swarm = os.environ.get("KNOT_ACTIVE_SWARM", "home")
    user_home = os.environ.get("HOME", os.path.expanduser("~"))
    return os.path.join(user_home, ".config", "knot", "swarms", active_swarm, "topology.json")


def build_parser() -> argparse.ArgumentParser:
    """
    Build CLI argument parser for topology mutation engine.
    """
    parser = argparse.ArgumentParser(
        prog="topology_mutate.py",
        description="Declarative spatial topology mutation engine for Knot Mesh",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: link
    link_parser = subparsers.add_parser("link", help="Link two nodes with directional edge")
    link_parser.add_argument("src", help="Source node ID")
    link_parser.add_argument("direction", help="Direction relative to source (left, right, up, down)")
    link_parser.add_argument("dst", help="Destination node ID")
    link_parser.add_argument("--span", default="0-100", help="Source fractional edge span (MIN-MAX, default: 0-100)")
    link_parser.add_argument("--target-span", default="0-100", help="Destination reciprocal span (MIN-MAX, default: 0-100)")
    link_parser.add_argument("--no-reciprocal", action="store_true", help="Do not automatically create reciprocal link")
    link_parser.add_argument("--topology", default=None, help="Path to topology.json")

    # Subcommand: unlink
    unlink_parser = subparsers.add_parser("unlink", help="Unlink directional edge")
    unlink_parser.add_argument("src", help="Source node ID")
    unlink_parser.add_argument("direction", help="Direction (left, right, up, down)")
    unlink_parser.add_argument("dst", nargs="?", default=None, help="Optional destination node ID to prune specific link")
    unlink_parser.add_argument("--topology", default=None, help="Path to topology.json")

    # Subcommand: remove
    remove_parser = subparsers.add_parser("remove", help="Remove node from screens and purge layout references")
    remove_parser.add_argument("node", help="Node ID to remove")
    remove_parser.add_argument("--topology", default=None, help="Path to topology.json")

    # Subcommand: set-anchor
    anchor_parser = subparsers.add_parser("set-anchor", help="Set active anchor node")
    anchor_parser.add_argument("node", help="Node ID to set as anchor")
    anchor_parser.add_argument("--topology", default=None, help="Path to topology.json")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    topo_file = resolve_topology_file(args.topology)

    try:
        if args.command == "link":
            link(
                topo_file,
                args.src,
                args.direction,
                args.dst,
                span_str=args.span,
                target_span_str=args.target_span,
                reciprocal=not args.no_reciprocal,
            )
        elif args.command == "unlink":
            unlink(
                topo_file,
                args.src,
                args.direction,
                dst=args.dst,
            )
        elif args.command == "remove":
            remove(topo_file, args.node)
        elif args.command == "set-anchor":
            set_anchor(topo_file, args.node)
        else:
            parser.print_help(sys.stderr)
            sys.exit(1)
    except ValueError as err:
        sys.stderr.write(f"Error: {err}\n")
        sys.exit(1)
    except Exception as err:
        sys.stderr.write(f"Unexpected error: {err}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
