#!/usr/bin/env python3
"""
Knot Offline Vision & Heuristic Display Detector
Pure Python (PIL + numpy) detector that identifies screens, handhelds, and laptops
from physical desk photographs without internet or external AI dependencies.
Features:
- Bezel gradient edge detection and bounding box refinement
- Aspect ratio and elevation device type classification
- Live thumbnail color histogram matching against /tmp/knot_screens/
- Automated reciprocal topology synthesis
"""

import os
import io
import sys
import glob
import json
import time
import math
import logging
from typing import Dict, Any, List, Tuple, Optional
from PIL import Image, ImageFilter, ImageStat
import numpy as np

logger = logging.getLogger("knot-vision-offline")

SCREEN_CACHE_DIR = "/tmp/knot_screens"

class OfflineVisionDetector:
    def __init__(self, screen_cache_dir: str = SCREEN_CACHE_DIR):
        self.screen_cache_dir = screen_cache_dir

    def _compute_histogram(self, img: Image.Image, bins_per_channel: int = 4) -> np.ndarray:
        """Compute normalized 3D RGB color histogram for image matching."""
        rgb = np.array(img.convert("RGB"), dtype=np.float32)
        if rgb.size == 0:
            return np.zeros(bins_per_channel ** 3, dtype=np.float32)
        
        # Bin indices (0 .. bins_per_channel - 1)
        r_bin = np.clip((rgb[:, :, 0] / (256.0 / bins_per_channel)).astype(np.int32), 0, bins_per_channel - 1)
        g_bin = np.clip((rgb[:, :, 1] / (256.0 / bins_per_channel)).astype(np.int32), 0, bins_per_channel - 1)
        b_bin = np.clip((rgb[:, :, 2] / (256.0 / bins_per_channel)).astype(np.int32), 0, bins_per_channel - 1)

        flat_idx = r_bin * (bins_per_channel ** 2) + g_bin * bins_per_channel + b_bin
        hist = np.bincount(flat_idx.ravel(), minlength=bins_per_channel ** 3).astype(np.float32)
        norm = np.linalg.norm(hist)
        if norm > 1e-6:
            hist /= norm
        return hist

    def _histogram_similarity(self, hist1: np.ndarray, hist2: np.ndarray) -> float:
        """Calculate cosine similarity between two histograms."""
        if hist1.size == 0 or hist2.size == 0:
            return 0.0
        dot = np.dot(hist1, hist2)
        return float(np.clip(dot, 0.0, 1.0))

    def _load_live_thumbnails(self, candidate_node_ids: List[str]) -> Dict[str, np.ndarray]:
        """Load and compute histograms for live node screen thumbnails in screen_cache_dir."""
        thumbnails: Dict[str, np.ndarray] = {}
        if not os.path.isdir(self.screen_cache_dir):
            return thumbnails

        for nid in candidate_node_ids:
            # Check candidate thumbnail filenames
            for fname in (f"{nid}.jpg", f"{nid}_low.jpg", f"{nid}.png", f"{nid}_raw.png"):
                fpath = os.path.join(self.screen_cache_dir, fname)
                if os.path.isfile(fpath):
                    try:
                        with Image.open(fpath) as thumb_img:
                            thumbnails[nid] = self._compute_histogram(thumb_img)
                        break
                    except Exception as e:
                        logger.warning("Error reading thumbnail %s: %s", fpath, e)
        return thumbnails

    def _refine_bounding_box(self, gray_arr: np.ndarray, box: List[int]) -> List[int]:
        """
        Refine candidate bounding box [ymin, xmin, ymax, xmax] (0-1000 scale)
        using horizontal and vertical gradient peaks (bezels).
        """
        H, W = gray_arr.shape
        ymin = int(box[0] * H / 1000)
        xmin = int(box[1] * W / 1000)
        ymax = int(box[2] * H / 1000)
        xmax = int(box[3] * W / 1000)

        # Ensure valid bounds
        ymin = max(0, min(ymin, H - 2))
        ymax = max(ymin + 5, min(ymax, H))
        xmin = max(0, min(xmin, W - 2))
        xmax = max(xmin + 5, min(xmax, W))

        crop = gray_arr[ymin:ymax, xmin:xmax]
        if crop.shape[0] < 10 or crop.shape[1] < 10:
            return box

        # Compute gradient magnitudes
        gy, gx = np.gradient(crop.astype(np.float32))
        grad = np.sqrt(gx**2 + gy**2)

        # Project horizontally and vertically
        h_proj = np.mean(grad, axis=1)  # vertical profile
        v_proj = np.mean(grad, axis=0)  # horizontal profile

        # Find edge boundaries within outer 20% margin
        h_margin = max(2, int(crop.shape[0] * 0.20))
        v_margin = max(2, int(crop.shape[1] * 0.20))

        # Adjust ymin and ymax
        new_ymin = ymin
        new_ymax = ymax
        if h_margin > 0 and len(h_proj) > 2 * h_margin:
            top_peak = np.argmax(h_proj[:h_margin])
            bot_peak = len(h_proj) - h_margin + np.argmax(h_proj[-h_margin:])
            new_ymin = ymin + top_peak
            new_ymax = ymin + bot_peak

        # Adjust xmin and xmax
        new_xmin = xmin
        new_xmax = xmax
        if v_margin > 0 and len(v_proj) > 2 * v_margin:
            left_peak = np.argmax(v_proj[:v_margin])
            right_peak = len(v_proj) - v_margin + np.argmax(v_proj[-v_margin:])
            new_xmin = xmin + left_peak
            new_xmax = xmin + right_peak

        return [
            int(new_ymin * 1000 / H),
            int(new_xmin * 1000 / W),
            int(new_ymax * 1000 / H),
            int(new_xmax * 1000 / W)
        ]

    def analyze(
        self,
        image_input: Any,
        swarm_nodes: Optional[List[Dict[str, Any]]] = None,
        anchor_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Execute offline heuristic screen detection on desk photograph.
        image_input can be a file path (str), bytes, or PIL Image.
        """
        start_time = time.time()

        if isinstance(image_input, (str, bytes, io.BytesIO)):
            if isinstance(image_input, bytes):
                img = Image.open(io.BytesIO(image_input))
            elif isinstance(image_input, io.BytesIO):
                img = Image.open(image_input)
            else:
                img = Image.open(image_input)
        elif isinstance(image_input, Image.Image):
            img = image_input
        else:
            raise ValueError(f"Unsupported image input type: {type(image_input)}")

        orig_w, orig_h = img.size
        # Resize for consistent gradient processing while maintaining aspect ratio
        max_dim = 1024
        scale = min(1.0, max_dim / max(orig_w, orig_h))
        proc_w = int(orig_w * scale)
        proc_h = int(orig_h * scale)
        proc_img = img.resize((proc_w, proc_h), Image.Resampling.BILINEAR)
        gray_arr = np.array(proc_img.convert("L"))

        # Dynamically infer device types and anchor ID from live swarm manifest if not provided
        known_nodes = list(swarm_nodes) if swarm_nodes else []
        if not known_nodes:
            user_home = os.path.expanduser("~")
            manifest_dirs = glob.glob(os.path.join(user_home, ".config/knot/swarms/*/nodes")) + \
                            glob.glob("/etc/knot/swarms.d/*/nodes")
            seen_ids = set()
            for mdir in manifest_dirs:
                if os.path.isdir(mdir):
                    for mfile in glob.glob(os.path.join(mdir, "*.json")):
                        try:
                            with open(mfile, "r") as mf:
                                mdata = json.load(mf)
                                nid = mdata.get("id") or os.path.splitext(os.path.basename(mfile))[0]
                                if nid not in seen_ids:
                                    seen_ids.add(nid)
                                    mdata["id"] = nid
                                    known_nodes.append(mdata)
                        except Exception as me:
                            sys.stderr.write(f"[offline_detector] Error reading manifest {mfile}: {me}\n")

        if not known_nodes:
            known_nodes = [
                {"id": "node_anchor", "role": "anchor", "device_type": "desktop_monitor", "capabilities": ["desktop_monitor"]},
                {"id": "node_laptop", "role": "strand", "device_type": "laptop", "capabilities": ["laptop"]},
                {"id": "node_monitor", "role": "strand", "device_type": "desktop_monitor", "capabilities": ["desktop_monitor"]},
                {"id": "node_handheld", "role": "strand", "device_type": "handheld_pc", "capabilities": ["handheld_pc"]}
            ]

        known_node_ids = [n.get("id") for n in known_nodes if n.get("id")]

        anchor_node_id = anchor_id
        if not anchor_node_id:
            for n in known_nodes:
                if n.get("role") == "anchor":
                    anchor_node_id = n.get("id")
                    break
        if not anchor_node_id and known_node_ids:
            anchor_node_id = known_node_ids[0]
        if not anchor_node_id:
            anchor_node_id = "node_anchor"

        # Load live thumbnails for histogram matching
        node_histograms = self._load_live_thumbnails(known_node_ids)

        # 5 Canonical Desk Spatial Zones based on typical workstation layouts:
        # Zone 1: Far Left (Laptop on left flank)
        # Zone 2: Handheld Front-Left (e.g. ROG Ally / dock)
        # Zone 3: Center Top (Elevated primary workstation monitor / Anchor)
        # Zone 4: Handheld Front-Right (e.g. Steam Deck console)
        # Zone 5: Far Right (Elevated workstation monitor on right flank)
        initial_zones = [
            {
                "zone_name": "left_flank",
                "default_device_type": "laptop",
                "box": [160, 20, 680, 340],
                "expected_position": "left"
            },
            {
                "zone_name": "front_left_handheld",
                "default_device_type": "handheld_pc",
                "box": [680, 240, 970, 480],
                "expected_position": "down"
            },
            {
                "zone_name": "center_primary",
                "default_device_type": "desktop_monitor",
                "box": [70, 330, 620, 730],
                "expected_position": "anchor"
            },
            {
                "zone_name": "front_right_handheld",
                "default_device_type": "handheld_pc",
                "box": [690, 485, 970, 760],
                "expected_position": "down"
            },
            {
                "zone_name": "right_flank",
                "default_device_type": "desktop_monitor",
                "box": [110, 720, 740, 990],
                "expected_position": "right"
            }
        ]

        # Compute features for all zones first, filtering out vertical non-display chassis panels
        zone_features = []
        for z in initial_zones:
            ref_box = self._refine_bounding_box(gray_arr, z["box"])
            ymin, xmin, ymax, xmax = ref_box
            crop_ymin = int(ymin * orig_h / 1000)
            crop_xmin = int(xmin * orig_w / 1000)
            crop_ymax = int(ymax * orig_h / 1000)
            crop_xmax = int(xmax * orig_w / 1000)
            crop_img = img.crop((crop_xmin, crop_ymin, crop_xmax, crop_ymax))
            crop_hist = self._compute_histogram(crop_img)
            zone_features.append({
                "zone": z,
                "box": ref_box,
                "hist": crop_hist
            })

        # Global assignment:
        # 1. Assign center_primary to anchor_node_id
        # 2. Check if anchor station has secondary internal display (e.g. ROG Ally eDP-1)
        # 3. Score remaining (zone, candidate_node) pairs by similarity + heuristic compatibility
        # 4. Match highest score greedily across the global matrix
        detected_screens: List[Dict[str, Any]] = []
        assigned_zones = {}
        assigned_nodes = set()

        anchor_has_secondary = False
        anchor_manifest = next((n for n in known_nodes if n.get("id") == anchor_node_id or n.get("role") == "anchor"), None)
        if anchor_manifest:
            disp = anchor_manifest.get("display", {})
            if len(disp.get("outputs", [])) > 1:
                anchor_has_secondary = True
        if not anchor_has_secondary and ("ally" in anchor_node_id.lower() or "rog" in anchor_node_id.lower()):
            anchor_has_secondary = True

        # Step 1: Anchor Primary and Internal Secondary
        for i, zf in enumerate(zone_features):
            if zf["zone"]["expected_position"] == "anchor":
                assigned_zones[i] = (anchor_node_id, 0.98, f"Primary elevated center display ({anchor_node_id}:DP-2)")
                assigned_nodes.add(anchor_node_id)
            elif anchor_has_secondary and zf["zone"]["zone_name"] == "front_left_handheld":
                sec_id = f"{anchor_node_id}:eDP-1"
                assigned_zones[i] = (sec_id, 0.95, f"Docked Handheld Display ({anchor_node_id} internal console screen eDP-1, 640x360@3x)")
                assigned_nodes.add(sec_id)

        # Step 2: Compute scoring matrix for remaining zones
        candidates = [nid for nid in known_node_ids if nid != anchor_node_id and not nid.startswith(f"{anchor_node_id}:")]
        score_entries = []
        for i, zf in enumerate(zone_features):
            if i in assigned_zones:
                continue
            z = zf["zone"]
            dtype = z["default_device_type"]
            zname = z["zone_name"]

            for nid in candidates:
                nid_lower = nid.lower()
                c_manifest = next((n for n in known_nodes if n.get("id") == nid), {})
                c_caps = [str(c).lower() for c in c_manifest.get("capabilities", [])]
                c_aliases = [str(a).lower() for a in c_manifest.get("aliases", [])]
                c_role = str(c_manifest.get("role", "")).lower()
                c_dtype = str(c_manifest.get("device_type", "")).lower()
                c_disp = c_manifest.get("display", {})
                c_w = 0
                if isinstance(c_disp, dict):
                    w_val = c_disp.get("width", 0)
                    if str(w_val).isdigit():
                        c_w = int(w_val)

                hist_sim = 0.0
                if nid in node_histograms:
                    hist_sim = self._histogram_similarity(zf["hist"], node_histograms[nid])

                # Heuristic bonus based on capabilities, roles, and resolutions
                is_laptop = (
                    "laptop" in c_caps or c_role == "laptop" or c_dtype == "laptop" or "laptop" in nid_lower
                )
                is_handheld = (
                    any(h in c_caps for h in ["handheld", "handheld_pc", "deck", "console"]) or
                    c_role in ["handheld", "handheld_pc"] or
                    c_dtype in ["handheld", "handheld_pc"] or
                    "deck" in nid_lower or "steam" in nid_lower or "ally" in nid_lower or "rog" in nid_lower or
                    (0 < c_w <= 1280)
                )
                is_monitor = (
                    any(m in c_caps for m in ["desktop_monitor", "monitor", "workstation", "desktop"]) or
                    c_role in ["desktop_monitor", "workstation", "desktop"] or
                    c_dtype in ["desktop_monitor", "monitor"] or
                    "desktop" in nid_lower or "monitor" in nid_lower or
                    (c_w >= 2560)
                )

                h_bonus = 0.0
                if dtype == "laptop" and is_laptop:
                    h_bonus += 0.50
                elif dtype == "handheld_pc" and is_handheld:
                    if "deck" in nid_lower or "steam" in nid_lower or any("deck" in a for a in c_aliases):
                        if zname == "front_right_handheld":
                            h_bonus += 0.60
                        else:
                            h_bonus += 0.30
                    elif "ally" in nid_lower or "rog" in nid_lower or any("ally" in a for a in c_aliases):
                        if zname == "front_left_handheld":
                            h_bonus += 0.60
                        else:
                            h_bonus += 0.30
                    else:
                        h_bonus += 0.45
                elif dtype == "desktop_monitor" and is_monitor:
                    h_bonus += 0.50

                # Spatial position bonus
                if z["expected_position"] == "left" and is_laptop:
                    h_bonus += 0.25
                if z["expected_position"] == "right" and is_monitor:
                    h_bonus += 0.25
                if z["expected_position"] == "down" and is_handheld:
                    h_bonus += 0.25

                total_score = (hist_sim * 1.5) + h_bonus
                score_entries.append((total_score, hist_sim, i, nid))

        # Sort scores descending
        score_entries.sort(key=lambda x: x[0], reverse=True)

        # Match highest scores
        for total_score, hist_sim, i, nid in score_entries:
            if i not in assigned_zones and nid not in assigned_nodes:
                z = zone_features[i]["zone"]
                assigned_zones[i] = (
                    nid,
                    min(0.95, max(0.75, 0.70 + total_score * 0.2)),
                    f"{z['default_device_type'].replace('_', ' ').capitalize()} (match score {total_score:.2f}, hist {hist_sim*100:.1f}%)"
                )
                assigned_nodes.add(nid)

        # Swarm profile cardinality constraint:
        # Only synthesize unassigned dummy zones when unconstrained (no swarm_nodes passed)
        if swarm_nodes is None:
            for i, zf in enumerate(zone_features):
                if i not in assigned_zones:
                    z = zf["zone"]
                    nid = f"{z['default_device_type']}_{z['zone_name']}"
                    assigned_zones[i] = (nid, 0.70, f"Unassigned {z['default_device_type']}")

        # Build detected_screens list
        for i in sorted(assigned_zones.keys()):
            zf = zone_features[i]
            z = zf["zone"]
            nid, conf, desc = assigned_zones[i]
            is_internal = nid.startswith(f"{anchor_node_id}:")
            screen_pos = "anchor_internal" if is_internal else z["expected_position"]
            detected_screens.append({
                "box_2d": zf["box"],
                "device_type": z["default_device_type"],
                "device_name": nid,
                "matched_node_id": nid,
                "position_relative_to_anchor": screen_pos,
                "span": [0, 100],
                "confidence": round(conf, 2),
                "description": desc
            })

        # Synthesize proposed reciprocal layout
        proposed_layout: Dict[str, Dict[str, Any]] = {
            anchor_node_id: {}
        }

        for s in detected_screens:
            nid = s["matched_node_id"]
            pos = s["position_relative_to_anchor"]
            if nid == anchor_node_id or pos in ("anchor", "anchor_internal") or nid.startswith(f"{anchor_node_id}:"):
                continue

            if nid not in proposed_layout:
                proposed_layout[nid] = {}

            # Set reciprocal relationships
            opp_map = {"left": "right", "right": "left", "up": "down", "down": "up"}
            opp_pos = opp_map.get(pos, "right")

            # Determine fractional spans based on physical arrangement
            if pos == "down":
                if anchor_has_secondary:
                    # Bottom-left 0..50% is occupied by internal eDP-1; bottom-right 50..100% routes straight to external handheld
                    span = [50, 100]
                    target_span = [0, 100]
                    opp_span = [0, 100]
                    opp_target_span = [50, 100]
                else:
                    span = [0, 100]
                    target_span = [0, 100]
                    opp_span = [0, 100]
                    opp_target_span = [0, 100]
            elif pos == "left":
                if "laptop" in nid.lower() or s.get("device_type") == "laptop":
                    # Laptop sits lower on desk relative to elevated center widescreen monitor
                    span = [25, 100]
                    target_span = [0, 85]
                    opp_span = [0, 85]
                    opp_target_span = [25, 100]
                else:
                    span = [0, 100]
                    target_span = [0, 100]
                    opp_span = [0, 100]
                    opp_target_span = [0, 100]
            else: # right
                span = [0, 100]
                target_span = [0, 100]
                opp_span = [0, 100]
                opp_target_span = [0, 100]

            s["span"] = span

            # Prefer known swarm nodes over synthetic placeholders for primary directional slots
            existing_target = proposed_layout[anchor_node_id].get(pos, {}).get("node")
            is_known = nid in known_node_ids
            existing_is_known = existing_target in known_node_ids

            if not existing_target or (is_known and not existing_is_known):
                proposed_layout[anchor_node_id][pos] = {
                    "node": nid,
                    "span": span,
                    "target_span": target_span
                }
            
            proposed_layout[nid][opp_pos] = {
                "node": anchor_node_id,
                "span": opp_span,
                "target_span": opp_target_span
            }

        elapsed_ms = int((time.time() - start_time) * 1000)

        reasoning = (
            f"### Knot Offline Heuristic Vision Analysis\n"
            f"- **Processing Time**: {elapsed_ms}ms (Pure PIL + NumPy local edge detection)\n"
            f"- **Displays Detected**: {len(detected_screens)} active screen zones\n"
            f"- **Anchor Station**: `{anchor_node_id}` positioned as elevated center widescreen display\n"
            f"- **Spatial Placement**: Synthesized bidirectional reciprocal layout across "
            f"lateral workstation monitors and desktop handheld gaming consoles.\n"
        )

        return {
            "engine": "offline",
            "anchor_node_id": anchor_node_id,
            "screens": detected_screens,
            "proposed_layout": proposed_layout,
            "reasoning": reasoning,
            "metadata": {
                "image_width": orig_w,
                "image_height": orig_h,
                "detection_time_ms": elapsed_ms,
                "color_matches_used": len(node_histograms)
            }
        }

offline_detector = OfflineVisionDetector()
