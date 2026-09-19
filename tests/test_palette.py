#!/usr/bin/env python3
"""
Unit tests for Knot Mesh Universal Palette Engine (core/palette.py).
Verifies seed determinism, safe gamut contrast, topological collision avoidance,
and swarm scalability.
"""

import os
import sys
import pytest

# Ensure knot-mesh root is in path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from core.palette import (
    NodeColor,
    contrast_ratio,
    derive_node_seed_hsl,
    extract_topology_constraints,
    get_node_color,
    hex_to_rgb,
    hsl_to_rgb,
    hue_distance,
    hue_to_badge_emoji,
    relative_luminance,
    resolve_swarm_palette,
    rgb_to_hex,
    CANVAS_BG_RGB
)


def test_seed_determinism():
    """Seed generation must produce identical values across calls."""
    h1, s1, l1 = derive_node_seed_hsl("desktop")
    h2, s2, l2 = derive_node_seed_hsl("desktop")
    assert h1 == h2
    assert s1 == s2
    assert l1 == l2

    c1 = get_node_color("rog-ally", swarm_id="nonexistent")
    c2 = get_node_color("rog-ally", swarm_id="nonexistent")
    assert c1.hex == c2.hex
    assert c1.rgb == c2.rgb
    assert c1.hue == c2.hue


def test_safe_gamut_and_contrast():
    """Derived colors must have high vibrancy and accessible contrast against dark canvas."""
    test_nodes = ["desktop", "laptop", "rog-ally", "steamdeck", "worker-1", "pi-cluster", "macbook"]
    for nid in test_nodes:
        h, s, l = derive_node_seed_hsl(nid)
        # Saturation must be vibrant (80% - 95%)
        assert 80.0 <= s <= 95.0
        # Lightness must be legible on dark backgrounds (55% - 65%)
        assert 55.0 <= l <= 65.0

        rgb = hsl_to_rgb(h, s, l)
        cr = contrast_ratio(rgb, CANVAS_BG_RGB)
        # Contrast against dark #0b0d1a canvas must be at least 3.0:1
        assert cr >= 3.0


def test_hue_distance():
    """Hue distance on a 360° circle must be cyclic and shortest path."""
    assert hue_distance(10, 20) == 10
    assert hue_distance(20, 10) == 10
    assert hue_distance(350, 10) == 20
    assert hue_distance(10, 350) == 20
    assert hue_distance(0, 180) == 180


def test_topology_constraint_extraction():
    """Co-edge and direct edge pairs must be correctly detected from topology layout."""
    mock_topology = {
        "anchor": "desktop",
        "screens": ["desktop", "laptop", "rog-ally", "steamdeck"],
        "layout": {
            "desktop": {
                "left": {"node": "laptop"},
                "down": [
                    {"node": "rog-ally", "span": [15, 55]},
                    {"node": "steamdeck", "span": [55, 95]}
                ]
            }
        }
    }
    co_edge, direct, anchor = extract_topology_constraints(mock_topology)
    assert anchor == "desktop"
    assert ("rog-ally", "steamdeck") in co_edge or ("steamdeck", "rog-ally") in co_edge
    assert ("desktop", "laptop") in direct
    assert ("desktop", "rog-ally") in direct
    assert ("desktop", "steamdeck") in direct


def test_topological_collision_avoidance_rog_ally_steamdeck():
    """Co-edge nodes (e.g. rog-ally and steamdeck on bottom edge) must have distinct hues."""
    mock_topology = {
        "anchor": "desktop",
        "screens": ["desktop", "laptop", "rog-ally", "steamdeck"],
        "layout": {
            "desktop": {
                "left": {"node": "laptop"},
                "down": [
                    {"node": "rog-ally", "span": [15, 55]},
                    {"node": "steamdeck", "span": [55, 95]}
                ]
            }
        }
    }
    palette = resolve_swarm_palette(
        swarm_id="nonexistent_test",
        node_ids=["desktop", "laptop", "rog-ally", "steamdeck"],
        topology_path=None
    )
    # Even without topology, check pure seed distinction
    d_raw = hue_distance(palette["rog-ally"].hue, palette["steamdeck"].hue)
    assert d_raw >= 30.0

    # With co-edge constraints, separation must be >= 60°
    co_edge_pairs = {("rog-ally", "steamdeck"), ("steamdeck", "rog-ally")}
    # Test directly with custom topology
    tmp_top = "/tmp/test_top.json"
    import json
    with open(tmp_top, "w") as f:
        json.dump(mock_topology, f)
    try:
        palette_top = resolve_swarm_palette(
            swarm_id="nonexistent_test",
            node_ids=["desktop", "laptop", "rog-ally", "steamdeck"],
            topology_path=tmp_top,
            min_co_edge_delta=65.0
        )
        d_co_edge = hue_distance(palette_top["rog-ally"].hue, palette_top["steamdeck"].hue)
        assert d_co_edge >= 65.0
    finally:
        if os.path.exists(tmp_top):
            os.remove(tmp_top)


def test_swarm_scaling_no_deadlock():
    """Palette resolver must scale to 12 synthetic nodes without infinite loops."""
    nodes = [f"node-{i:02d}" for i in range(12)]
    palette = resolve_swarm_palette(
        swarm_id="nonexistent_test",
        node_ids=nodes
    )
    assert len(palette) == 12
    # Verify every node received a valid color
    for nid, c in palette.items():
        assert c.hex.startswith("#")
        assert len(c.hex) == 7
        assert len(c.rgb) == 3


def test_badge_emoji_mapping():
    """Hue must map to appropriate emoji badges."""
    assert hue_to_badge_emoji(0.0) == "🔴"
    assert hue_to_badge_emoji(30.0) == "🟠"
    assert hue_to_badge_emoji(60.0) == "🟡"
    assert hue_to_badge_emoji(120.0) == "🟢"
    assert hue_to_badge_emoji(180.0) == "🔵"
    assert hue_to_badge_emoji(240.0) == "🔷"
    assert hue_to_badge_emoji(280.0) == "🟣"
