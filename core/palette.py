#!/usr/bin/env python3
"""
Knot Mesh: Universal Palette & Dynamic Node Color Derivation Engine
Part of Knot Mesh GA Core Runtime.

Generates accessible, high-contrast, visually distinct colors deterministically
from each node's unique identifier/seed. Evaluates topological adjacency
from topology.json to avoid near-neighbor and co-edge color collisions
(e.g., adjacent screens on the same display edge like rog-ally and steamdeck).
"""

from __future__ import annotations

import argparse
import colorsys
from dataclasses import asdict, dataclass
import hashlib
import json
import math
import os
import sys
from typing import Any, Dict, List, Optional, Set, Tuple

# The Golden Angle in degrees (360 * (1 - 1/phi))
GOLDEN_ANGLE = 137.507764

# Dark theme canvas background reference (#0b0d1a)
CANVAS_BG_RGB = (11, 13, 26)


@dataclass(frozen=True)
class NodeColor:
    node_id: str
    hex: str
    rgb: Tuple[int, int, int]
    ansi: str
    emoji: str
    hue: float
    saturation: float
    lightness: float
    contrast_ratio: float
    shifts: int
    is_override: bool = False

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["rgb"] = list(self.rgb)
        return d


def relative_luminance(rgb: Tuple[int, int, int]) -> float:
    """Calculate WCAG relative luminance from sRGB tuple."""
    def channel_lum(val: int) -> float:
        c = val / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = rgb
    return 0.2126 * channel_lum(r) + 0.7152 * channel_lum(g) + 0.0722 * channel_lum(b)


def contrast_ratio(rgb1: Tuple[int, int, int], rgb2: Tuple[int, int, int]) -> float:
    """Calculate WCAG contrast ratio between two colors."""
    l1 = relative_luminance(rgb1)
    l2 = relative_luminance(rgb2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def hsl_to_rgb(h_deg: float, s_pct: float, l_pct: float) -> Tuple[int, int, int]:
    """Convert HSL (degrees, 0-100%, 0-100%) to sRGB (0-255)."""
    h = (h_deg % 360.0) / 360.0
    s = max(0.0, min(100.0, s_pct)) / 100.0
    l = max(0.0, min(100.0, l_pct)) / 100.0
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (int(round(r * 255.0)), int(round(g * 255.0)), int(round(b * 255.0)))


def rgb_to_hex(rgb: Tuple[int, int, int]) -> str:
    """Format RGB tuple as uppercase hex string."""
    return f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"


def hex_to_rgb(hex_str: str) -> Tuple[int, int, int]:
    """Parse hex string to RGB tuple."""
    clean = hex_str.strip().lstrip("#")
    if len(clean) == 3:
        clean = "".join([c * 2 for c in clean])
    if len(clean) != 6:
        return (168, 85, 247)
    return (int(clean[0:2], 16), int(clean[2:4], 16), int(clean[4:6], 16))


def rgb_to_hsl(rgb: Tuple[int, int, int]) -> Tuple[float, float, float]:
    """Convert sRGB tuple to HSL (degrees, percent, percent)."""
    r, g, b = [c / 255.0 for c in rgb]
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return (round(h * 360.0, 1), round(s * 100.0, 1), round(l * 100.0, 1))


def hue_distance(h1: float, h2: float) -> float:
    """Calculate the shortest angular distance between two hues on the 360° circle."""
    d = abs((h1 % 360.0) - (h2 % 360.0))
    return min(d, 360.0 - d)


def hue_to_badge_emoji(hue: float) -> str:
    """Map hue degrees to a matching colored circle/diamond emoji."""
    h = hue % 360.0
    if h < 15.0 or h >= 345.0:
        return "🔴"  # Red / Rose
    elif h < 45.0:
        return "🟠"  # Orange
    elif h < 75.0:
        return "🟡"  # Amber / Yellow
    elif h < 165.0:
        return "🟢"  # Green / Emerald
    elif h < 210.0:
        return "🔵"  # Cyan / Electric Blue
    elif h < 265.0:
        return "🔷"  # Cobalt Blue
    else:
        return "🟣"  # Violet / Purple


def derive_node_seed_hsl(node_id: str) -> Tuple[float, float, float]:
    """
    Derive deterministic, accessible base HSL values from node identifier.
    Guarantees high vibrancy (S: 84-93%) and contrast against dark UI (L: 56-63%).
    """
    digest = hashlib.sha256(node_id.strip().lower().encode("utf-8")).hexdigest()
    raw_hue = (int(digest[0:8], 16) % 3600) / 10.0
    sat = 84.0 + (int(digest[8:12], 16) % 10)
    lit = 56.0 + (int(digest[12:16], 16) % 8)
    return (raw_hue, sat, lit)


def extract_topology_constraints(
    topology_data: Dict[str, Any]
) -> Tuple[Set[Tuple[str, str]], Set[Tuple[str, str]], str]:
    """
    Parse topology.json to extract:
    1. co_edge_pairs: screens co-located along the same edge of a display (e.g. rog-ally & steamdeck on desktop.down)
    2. direct_edge_pairs: screens directly connected across a boundary (e.g. desktop <-> laptop)
    3. anchor_id: the designated anchor node
    """
    co_edge_pairs: Set[Tuple[str, str]] = set()
    direct_edge_pairs: Set[Tuple[str, str]] = set()
    anchor_id = topology_data.get("anchor", "desktop")

    layout = topology_data.get("layout", {})
    for src_node, edges in layout.items():
        if not isinstance(edges, dict):
            continue
        for edge_dir, edge_spec in edges.items():
            specs = edge_spec if isinstance(edge_spec, list) else [edge_spec]
            edge_nodes = []
            for sp in specs:
                if not isinstance(sp, dict):
                    continue
                tgt = sp.get("node", sp.get("target", ""))
                if tgt:
                    edge_nodes.append(tgt)
                    direct_edge_pairs.add((src_node, tgt))
                    direct_edge_pairs.add((tgt, src_node))

            if len(edge_nodes) > 1:
                for i in range(len(edge_nodes)):
                    for j in range(i + 1, len(edge_nodes)):
                        n1, n2 = edge_nodes[i], edge_nodes[j]
                        co_edge_pairs.add((n1, n2))
                        co_edge_pairs.add((n2, n1))

    return co_edge_pairs, direct_edge_pairs, anchor_id


def resolve_swarm_palette(
    swarm_id: str = "home",
    topology_path: Optional[str] = None,
    nodes_dir: Optional[str] = None,
    node_ids: Optional[List[str]] = None,
    min_co_edge_delta: float = 65.0,
    min_direct_delta: float = 45.0,
    min_peer_delta: float = 30.0
) -> Dict[str, NodeColor]:
    """
    Resolve complete collision-free color palette for all nodes in the swarm.
    Applies deterministic seed generation + topological near-neighbor collision avoidance.
    """
    home = os.path.expanduser("~")
    swarm_root = os.path.join(home, ".config/knot/swarms", swarm_id)

    if not topology_path:
        candidate_top = os.path.join(swarm_root, "topology.json")
        if os.path.exists(candidate_top):
            topology_path = candidate_top

    topology_data: Dict[str, Any] = {}
    if topology_path and os.path.exists(topology_path):
        try:
            with open(topology_path, "r") as f:
                topology_data = json.load(f)
        except Exception:
            topology_data = {}

    co_edge_pairs, direct_edge_pairs, anchor_id = extract_topology_constraints(topology_data)

    if not nodes_dir:
        candidate_nodes = os.path.join(swarm_root, "nodes")
        if os.path.isdir(candidate_nodes):
            nodes_dir = candidate_nodes

    node_manifests: Dict[str, Dict[str, Any]] = {}
    if nodes_dir and os.path.isdir(nodes_dir):
        for fname in os.listdir(nodes_dir):
            if fname.endswith(".json"):
                nid = fname[:-5]
                try:
                    with open(os.path.join(nodes_dir, fname), "r") as f:
                        node_manifests[nid] = json.load(f)
                except Exception as e:
                    sys.stderr.write(f"Notice: [palette] Failed to parse node manifest {fname}: {e}\n")

    all_nodes_set: Set[str] = set()
    if node_ids:
        all_nodes_set.update(node_ids)
    all_nodes_set.update(node_manifests.keys())
    all_nodes_set.update(topology_data.get("screens", []))
    if not all_nodes_set:
        all_nodes_set = {"desktop", "laptop", "rog-ally", "steamdeck"}

    n_count = len(all_nodes_set)
    effective_peer_delta = min(min_peer_delta, max(15.0, 320.0 / max(1, n_count)))

    overrides: Dict[str, str] = {}
    for nid in all_nodes_set:
        m = node_manifests.get(nid, {})
        color_val = m.get("strip_color") or m.get("color")
        if color_val and isinstance(color_val, str) and color_val.startswith("#"):
            overrides[nid] = color_val

    def sort_key(n: str) -> Tuple[int, int, str]:
        has_override = 0 if n in overrides else 1
        is_anchor = 0 if n == anchor_id else 1
        return (has_override, is_anchor, n)

    ordered_nodes = sorted(list(all_nodes_set), key=sort_key)
    resolved: Dict[str, NodeColor] = {}

    for node in ordered_nodes:
        if node in overrides:
            ov_hex = overrides[node]
            rgb = hex_to_rgb(ov_hex)
            h, s, l = rgb_to_hsl(rgb)
            cr = contrast_ratio(rgb, CANVAS_BG_RGB)
            resolved[node] = NodeColor(
                node_id=node,
                hex=ov_hex.upper(),
                rgb=rgb,
                ansi=f"\033[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m",
                emoji=hue_to_badge_emoji(h),
                hue=h,
                saturation=s,
                lightness=l,
                contrast_ratio=round(cr, 2),
                shifts=0,
                is_override=True
            )
            continue

        base_h, base_s, base_l = derive_node_seed_hsl(node)
        curr_h = base_h
        shifts = 0
        max_shifts = 60

        while shifts < max_shifts:
            collision = False
            for prev_node, prev_color in resolved.items():
                dist = hue_distance(curr_h, prev_color.hue)
                is_co_edge = (node, prev_node) in co_edge_pairs
                is_direct = (node, prev_node) in direct_edge_pairs

                if is_co_edge and dist < min_co_edge_delta:
                    collision = True
                    break
                elif is_direct and dist < min_direct_delta:
                    collision = True
                    break
                elif dist < effective_peer_delta:
                    collision = True
                    break

            if not collision:
                break

            curr_h = (curr_h + GOLDEN_ANGLE) % 360.0
            shifts += 1

        rgb = hsl_to_rgb(curr_h, base_s, base_l)
        cr = contrast_ratio(rgb, CANVAS_BG_RGB)
        resolved[node] = NodeColor(
            node_id=node,
            hex=rgb_to_hex(rgb),
            rgb=rgb,
            ansi=f"\033[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m",
            emoji=hue_to_badge_emoji(curr_h),
            hue=round(curr_h, 1),
            saturation=round(base_s, 1),
            lightness=round(base_l, 1),
            contrast_ratio=round(cr, 2),
            shifts=shifts,
            is_override=False
        )

    return resolved


def get_node_color(
    node_id: str,
    swarm_id: str = "home",
    topology_path: Optional[str] = None
) -> NodeColor:
    """Retrieve resolved color for a single node."""
    palette = resolve_swarm_palette(swarm_id=swarm_id, topology_path=topology_path)
    if node_id in palette:
        return palette[node_id]
    h, s, l = derive_node_seed_hsl(node_id)
    rgb = hsl_to_rgb(h, s, l)
    cr = contrast_ratio(rgb, CANVAS_BG_RGB)
    return NodeColor(
        node_id=node_id,
        hex=rgb_to_hex(rgb),
        rgb=rgb,
        ansi=f"\033[38;2;{rgb[0]};{rgb[1]};{rgb[2]}m",
        emoji=hue_to_badge_emoji(h),
        hue=round(h, 1),
        saturation=round(s, 1),
        lightness=round(l, 1),
        contrast_ratio=round(cr, 2),
        shifts=0,
        is_override=False
    )


def main():
    parser = argparse.ArgumentParser(description="Knot Mesh Universal Color & Palette Engine")
    parser.add_argument("node", nargs="?", default="", help="Optional node ID to query")
    parser.add_argument("--swarm", default="home", help="Swarm identifier")
    parser.add_argument("--topology", default="", help="Path to custom topology.json")
    parser.add_argument("--hex-only", action="store_true", help="Print only the hex color code")
    parser.add_argument("--json", action="store_true", help="Output JSON structure")
    args = parser.parse_args()

    palette = resolve_swarm_palette(
        swarm_id=args.swarm,
        topology_path=args.topology or None
    )

    if args.node:
        c = palette.get(args.node) or get_node_color(args.node, swarm_id=args.swarm)
        if args.hex_only:
            print(c.hex)
            return
        if args.json:
            print(json.dumps(c.to_dict(), indent=2))
            return
        reset = "\033[0m"
        print(f"{c.ansi}{c.emoji} {c.node_id}{reset} -> {c.hex} (RGB: {c.rgb[0]}, {c.rgb[1]}, {c.rgb[2]} | Hue: {c.hue}° | Contrast: {c.contrast_ratio}:1)")
        return

    if args.json:
        out = {k: v.to_dict() for k, v in palette.items()}
        print(json.dumps(out, indent=2))
        return

    bold = "\033[1m"
    reset = "\033[0m"
    print(f"\n{bold}--- Knot Mesh Universal Palette Matrix ({args.swarm}) ---{reset}\n")
    print(f"{bold}{'NODE ID':<15} {'BADGE':<7} {'HEX':<10} {'RGB':<16} {'HUE':<8} {'CONTRAST':<10} {'STATUS'}{reset}")
    print("-" * 75)
    for nid, c in palette.items():
        status = "Override" if c.is_override else (f"Seed+{c.shifts}" if c.shifts > 0 else "Seed")
        rgb_str = f"({c.rgb[0]}, {c.rgb[1]}, {c.rgb[2]})"
        print(f"{c.ansi}{nid:<15} {c.emoji:<7} {c.hex:<10} {rgb_str:<16} {c.hue:<8.1f} {c.contrast_ratio:<10.1f} {status}{reset}")
    print("")


if __name__ == "__main__":
    main()
