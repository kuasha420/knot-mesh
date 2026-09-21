#!/usr/bin/env python3
"""
Knot Swarm Vision & Topology Reasoning Detector
Leverages the authenticated Knot Swarm Agent runtime (via agy) with multimodal models (Gemini Pro/Flash)
to visually inspect physical desk photos, locate display bounding boxes, and synthesize
an optimal Deskflow KVM topology layout.
"""

import os
import io
import re
import json
import time
import shutil
import logging
import tempfile
import subprocess
import sys
import glob
from typing import Dict, Any, List, Optional
from PIL import Image

logger = logging.getLogger("knot-vision-swarm")

class SwarmVisionDetector:
    def __init__(self, timeout_sec: int = 120):
        self.timeout_sec = timeout_sec

    def is_available(self) -> bool:
        """Check if agy CLI is present in PATH."""
        return shutil.which("agy") is not None

    def analyze(
        self,
        image_input: Any,
        swarm_nodes: Optional[List[Dict[str, Any]]] = None,
        anchor_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Execute Swarm AI multimodal vision reasoning on desk photo.
        Returns standard topology and detection dictionary.
        """
        if not self.is_available():
            raise RuntimeError("Swarm AI vision agent ('agy') is not installed or not in PATH")

        start_time = time.time()
        temp_img_path = None

        try:
            # Prepare image file path
            if isinstance(image_input, str) and os.path.isfile(image_input):
                img_path = os.path.abspath(image_input)
                with Image.open(img_path) as im:
                    orig_w, orig_h = im.size
            else:
                # Save bytes or PIL Image to a temporary jpeg file
                fd, temp_img_path = tempfile.mkstemp(suffix=".jpg", prefix="knot_vision_")
                os.close(fd)
                if isinstance(image_input, bytes):
                    with open(temp_img_path, "wb") as f:
                        f.write(image_input)
                elif isinstance(image_input, io.BytesIO):
                    with open(temp_img_path, "wb") as f:
                        f.write(image_input.getvalue())
                elif isinstance(image_input, Image.Image):
                    image_input.save(temp_img_path, format="JPEG")
                else:
                    raise ValueError(f"Unsupported image input type: {type(image_input)}")

                img_path = temp_img_path
                with Image.open(img_path) as im:
                    orig_w, orig_h = im.size

            # Format node context for the agent
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
                                sys.stderr.write(f"[swarm_detector] Error reading manifest {mfile}: {me}\n")

            anchor_node_id = anchor_id
            if not anchor_node_id:
                for n in known_nodes:
                    if n.get("role") == "anchor":
                        anchor_node_id = n.get("id")
                        break
            if not anchor_node_id and known_nodes:
                anchor_node_id = known_nodes[0].get("id")
            if not anchor_node_id:
                anchor_node_id = "node_a"

            node_lines = []
            for n in known_nodes:
                nid = n.get("id", "unknown")
                hname = n.get("hostname", nid)
                role = n.get("role", "strand")
                disp = n.get("display", {})
                w = disp.get("width", 1920) if isinstance(disp, dict) else 1920
                h = disp.get("height", 1080) if isinstance(disp, dict) else 1080
                caps = n.get("capabilities", [])
                caps_str = f", capabilities: {','.join(caps)}" if caps else ""
                node_lines.append(f"- {nid} (hostname: {hname}, role: {role}, resolution: {w}x{h}{caps_str})")

            if not node_lines:
                node_lines = [
                    f"- {anchor_node_id} (role: anchor workstation, resolution: 2560x1440)",
                    "- node_b (role: strand laptop, resolution: 1920x1080)",
                    "- node_c (role: strand desktop monitor, resolution: 2560x1440)",
                    "- node_d (role: strand handheld PC, resolution: 1280x800)"
                ]

            node_context = "\n".join(node_lines)

            prompt = (
                f"You are Knot Swarm's Vision & Topology Reasoning Agent.\n"
                f"Analyze the physical desk photo at: {img_path}\n\n"
                f"Connected Knot Swarm Nodes on this mesh:\n{node_context}\n"
                f"Active Anchor Workstation: {anchor_node_id}\n\n"
                f"Instructions:\n"
                f"1. Use view_file to inspect the desk photo.\n"
                f"2. Locate every computer display, monitor, laptop screen, and handheld screen.\n"
                f"3. For each screen, specify its normalized bounding box [ymin, xmin, ymax, xmax] in 0-1000 scale.\n"
                f"4. Identify device_type ('desktop_monitor', 'laptop', 'handheld_pc').\n"
                f"5. Match each display with the corresponding Knot node ID from the list above.\n"
                f"6. Determine its position relative to the primary center anchor ('left', 'right', 'down', 'up', 'anchor', 'anchor_internal').\n"
                f"7. Multi-Display Geometry & Fractional Spans Rules:\n"
                f"   - If the anchor node ({anchor_node_id}) has an internal secondary screen docked below the center monitor:\n"
                f"     * Label that internal screen position_relative_to_anchor: 'anchor_internal', matched_node_id: '{anchor_node_id}:internal'.\n"
                f"     * The bottom edge left 50% [0, 50] routes locally via OS to the internal screen.\n"
                f"     * Any downward transition to an external handheld device must route from the right half: span [50, 100], target_span [0, 100].\n"
                f"     * External handheld routes up: span [0, 100], target_span [50, 100].\n"
                f"   - Laptops sitting lower on the left flank: span [25, 100], target_span [0, 85]. Reciprocal on right: span [0, 85], target_span [25, 100].\n"
                f"   - Aligned monitors on the right flank: span [0, 100], target_span [0, 100]. Reciprocal on left: span [0, 100], target_span [0, 100].\n"
                f"8. Synthesize a complete bidirectional reciprocal layout dictionary for Deskflow KVM.\n"
                f"9. Provide concise, high-level reasoning.\n\n"
                f"Return ONLY valid JSON formatted inside a ```json code block conforming to this schema:\n"
                f"{{\n"
                f'  "engine": "swarm_ai",\n'
                f'  "anchor_node_id": "{anchor_node_id}",\n'
                f'  "screens": [\n'
                f"    {{\n"
                f'      "box_2d": [ymin, xmin, ymax, xmax],\n'
                f'      "device_type": "laptop",\n'
                f'      "device_name": "node_b",\n'
                f'      "matched_node_id": "node_b",\n'
                f'      "position_relative_to_anchor": "left",\n'
                f'      "span": [25, 100],\n'
                f'      "confidence": 0.95,\n'
                f'      "description": "Secondary workstation laptop screen on left flank"\n'
                f"    }}\n"
                f"  ],\n"
                f'  "proposed_layout": {{\n'
                f'    "{anchor_node_id}": {{\n'
                f'      "left": {{"node": "node_b", "span": [25, 100], "target_span": [0, 85]}},\n'
                f'      "right": {{"node": "node_c", "span": [0, 100], "target_span": [0, 100]}},\n'
                f'      "down": {{"node": "node_d", "span": [50, 100], "target_span": [0, 100]}}\n'
                f"    }},\n"
                f'    "node_b": {{\n'
                f'      "right": {{"node": "{anchor_node_id}", "span": [0, 85], "target_span": [25, 100]}}\n'
                f"    }},\n"
                f'    "node_c": {{\n'
                f'      "left": {{"node": "{anchor_node_id}", "span": [0, 100], "target_span": [0, 100]}}\n'
                f"    }},\n"
                f'    "node_d": {{\n'
                f'      "up": {{"node": "{anchor_node_id}", "span": [0, 100], "target_span": [50, 100]}}\n'
                f"    }}\n"
                f"  }},\n"
                f'  "reasoning": "Spatial reasoning across detected displays"\n'
                f"}}"
            )

            cmd = ["agy", "--dangerously-skip-permissions", "-p", prompt]
            logger.info("Spawning Swarm AI vision agent via agy...")
            res = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.timeout_sec
            )

            if res.returncode != 0:
                raise RuntimeError(f"agy process exited with return code {res.returncode}: {res.stderr.strip()}")

            stdout = res.stdout.strip()
            if not stdout:
                raise ValueError("agy returned empty output")

            # Extract JSON block
            json_text = None
            json_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", stdout, re.DOTALL)
            if json_match:
                json_text = json_match.group(1)
            else:
                # Fallback: search for outermost curly braces
                first_brace = stdout.find("{")
                last_brace = stdout.rfind("}")
                if first_brace != -1 and last_brace > first_brace:
                    json_text = stdout[first_brace:last_brace+1]

            if not json_text:
                raise ValueError(f"Could not parse JSON from agy output: {stdout[:200]}...")

            parsed = json.loads(json_text)
            parsed["engine"] = "swarm_ai"
            parsed.setdefault("anchor_node_id", anchor_node_id)
            parsed.setdefault("screens", [])
            parsed.setdefault("proposed_layout", {})
            parsed.setdefault("reasoning", "Layout generated by Knot Swarm Vision Agent.")

            elapsed_ms = int((time.time() - start_time) * 1000)
            parsed["metadata"] = {
                "image_width": orig_w,
                "image_height": orig_h,
                "detection_time_ms": elapsed_ms,
                "model": "swarm_ai"
            }

            return parsed

        finally:
            if temp_img_path and os.path.exists(temp_img_path):
                try:
                    os.remove(temp_img_path)
                except Exception as exc:
                    logger.warning("Failed to remove temporary image %s: %s", temp_img_path, exc)

swarm_detector = SwarmVisionDetector()
