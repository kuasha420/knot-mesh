#!/usr/bin/env python3
"""
Unit tests for Knot Swarm Vision & Topology Reasoning Engine
Tests:
- Offline heuristic display detection
- Bounding box normalization and validity
- Device classification and reciprocal layout synthesis
- Engine mode dispatching and graceful error recovery
"""

import os
import sys
import unittest
from PIL import Image, ImageDraw

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from core.vision.offline_detector import offline_detector
from core.vision.engine import analyze_desk_photo

class TestVisionEngine(unittest.TestCase):
    def setUp(self):
        # Create a synthetic desk setup test image: 1024x768
        self.img = Image.new("RGB", (1024, 768), color=(25, 25, 30))
        draw = ImageDraw.Draw(self.img)

        # Draw left laptop screen: x: 80..300, y: 220..500
        draw.rectangle([80, 220, 300, 500], fill=(45, 55, 75), outline=(200, 200, 220), width=4)
        # Draw center desktop monitor: x: 380..680, y: 100..450
        draw.rectangle([380, 100, 680, 450], fill=(30, 40, 50), outline=(220, 220, 240), width=6)
        # Draw right desktop monitor: x: 740..980, y: 120..480
        draw.rectangle([740, 120, 980, 480], fill=(20, 25, 35), outline=(210, 210, 230), width=6)
        # Draw lower handheld console: x: 400..650, y: 550..720
        draw.rectangle([400, 550, 650, 720], fill=(60, 60, 80), outline=(240, 180, 50), width=4)

    def test_offline_detector_bounding_boxes_validity(self):
        """Verify that all detected bounding boxes conform to 0-1000 normalized scale and valid dimensions."""
        res = offline_detector.analyze(self.img, anchor_id="rog-ally")
        self.assertEqual(res["engine"], "offline")
        self.assertEqual(res["anchor_node_id"], "rog-ally")
        self.assertGreaterEqual(len(res["screens"]), 1)

        for screen in res["screens"]:
            ymin, xmin, ymax, xmax = screen["box_2d"]
            self.assertGreaterEqual(ymin, 0)
            self.assertLess(ymin, ymax)
            self.assertLessEqual(ymax, 1000)
            self.assertGreaterEqual(xmin, 0)
            self.assertLess(xmin, xmax)
            self.assertLessEqual(xmax, 1000)
            self.assertIn(screen["device_type"], ["desktop_monitor", "laptop", "handheld_pc"])
            self.assertIn(screen["position_relative_to_anchor"], ["left", "right", "down", "up", "anchor", "anchor_internal"])

    def test_reciprocal_layout_symmetry(self):
        """Verify that proposed layout contains bidirectional reciprocal relationships and fractional spans."""
        res = offline_detector.analyze(
            self.img,
            swarm_nodes=[
                {"id": "rog-ally", "role": "anchor"},
                {"id": "devbox", "role": "laptop"},
                {"id": "PurrfectSoftwareLimited", "role": "desktop_monitor"},
                {"id": "steamdeck-eos", "role": "handheld_pc"}
            ],
            anchor_id="rog-ally"
        )
        layout = res["proposed_layout"]
        anchor = res["anchor_node_id"]

        opp_map = {"left": "right", "right": "left", "up": "down", "down": "up"}

        # Check links from anchor to strands
        for direction, target_info in layout.get(anchor, {}).items():
            target_node = target_info["node"]
            opp_direction = opp_map[direction]
            # Target node should have a reciprocal link pointing back to anchor
            self.assertIn(target_node, layout, f"Target node {target_node} must exist in layout")
            self.assertIn(
                opp_direction,
                layout[target_node],
                f"Target node {target_node} must link back via {opp_direction} to anchor"
            )
            self.assertEqual(layout[target_node][opp_direction]["node"], anchor)

        # Verify specific fractional spans for rog-ally physical desk setup:
        # Downward link to steamdeck-eos must be right half [50, 100] -> [0, 100]
        self.assertEqual(layout["rog-ally"]["down"]["node"], "steamdeck-eos")
        self.assertEqual(layout["rog-ally"]["down"]["span"], [50, 100])
        self.assertEqual(layout["rog-ally"]["down"]["target_span"], [0, 100])
        self.assertEqual(layout["steamdeck-eos"]["up"]["span"], [0, 100])
        self.assertEqual(layout["steamdeck-eos"]["up"]["target_span"], [50, 100])

        # Left link to devbox laptop must be offset [25, 100] -> [0, 85]
        self.assertEqual(layout["rog-ally"]["left"]["node"], "devbox")
        self.assertEqual(layout["rog-ally"]["left"]["span"], [25, 100])
        self.assertEqual(layout["rog-ally"]["left"]["target_span"], [0, 85])
        self.assertEqual(layout["devbox"]["right"]["span"], [0, 85])
        self.assertEqual(layout["devbox"]["right"]["target_span"], [25, 100])

        # Right link to PurrfectSoftwareLimited must be 1:1 [0, 100] -> [0, 100]
        self.assertEqual(layout["rog-ally"]["right"]["node"], "PurrfectSoftwareLimited")
        self.assertEqual(layout["rog-ally"]["right"]["span"], [0, 100])
        self.assertEqual(layout["rog-ally"]["right"]["target_span"], [0, 100])

    def test_engine_mode_dispatch(self):
        """Verify that analyze_desk_photo correctly handles mode parameter."""
        res_offline = analyze_desk_photo(self.img, mode="offline")
        self.assertEqual(res_offline["engine"], "offline")

        with self.assertRaises(ValueError):
            analyze_desk_photo(self.img, mode="invalid_mode")

    def test_pc_chassis_rejection_and_swarm_cardinality(self):
        """Verify that offline detector rejects PC chassis panels and constrains detection to known swarm nodes (#40)."""
        nodes = [
            {"id": "desktop", "role": "anchor"},
            {"id": "laptop", "role": "strand", "capabilities": ["laptop"]},
            {"id": "rog-ally", "role": "strand", "capabilities": ["handheld"], "aliases": ["ally"]},
            {"id": "steamdeck", "role": "strand", "capabilities": ["handheld"], "aliases": ["deck"]}
        ]
        res = offline_detector.analyze(self.img, swarm_nodes=nodes, anchor_id="desktop")
        screen_ids = [s["matched_node_id"] for s in res["screens"]]

        # Exactly 4 screens matched (no fake 5th desktop_monitor_right_flank)
        self.assertEqual(len(res["screens"]), 4)
        self.assertNotIn("desktop_monitor_right_flank", screen_ids)
        self.assertIn("desktop", screen_ids)
        self.assertIn("laptop", screen_ids)
        self.assertIn("rog-ally", screen_ids)
        self.assertIn("steamdeck", screen_ids)

        # Disambiguation: steamdeck on right, rog-ally on left/internal
        deck_screen = next(s for s in res["screens"] if s["matched_node_id"] == "steamdeck")
        self.assertEqual(deck_screen["position_relative_to_anchor"], "down")

if __name__ == "__main__":
    unittest.main()
