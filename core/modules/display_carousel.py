# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Arafat Zahan (@kuasha420)
# Corporate Stewardship & Infrastructure: Purrfect Software Limited (PSL)
# Governed by: ICARO-42/b Ordinance (Company-Supported Personal IP Framework)

"""
PSL Remote Subsystem: Headless Fleet Screen Capture Artifact Bridge.

Captures, decodes, and organizes multi-node fleet screen captures into persistent
artifacts and generates interactive carousel markdown documents.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import re
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# Minimal valid 1x1 PNG bytes for dummy / placeholder screen frames
MINIMAL_PNG_BYTES: bytes = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
    b"\x00\x00\x00\x1f\x15c4\x00\x00\x00\rIDATx\x9cc`\x00\x00\x00\x02\x00\x01H\xaf"
    b"\xa4q\x00\x00\x00\x00IEND\xaeB`\x82"
)


def _sanitize_filename(name: str) -> str:
    """Sanitize node name or identifier for safe filesystem usage."""
    return re.sub(r"[^a-zA-Z0-9_\-]", "_", name.strip().lower())


def _normalize_screens_data(raw_data: Optional[Dict[str, Any] | List[Any]]) -> List[Dict[str, Any]]:
    """Normalize various dictionary and list formats into a structured screens list."""
    if raw_data is None:
        # Default knot mesh fleet placeholders
        now_iso = datetime.now(timezone.utc).isoformat()
        return [
            {
                "node": "desktop",
                "title": "Desktop Anchor (Main Display)",
                "status": "active",
                "window_title": "Kitty - Subagent Ladder Confluence",
                "timestamp": now_iso,
                "image_bytes": MINIMAL_PNG_BYTES,
            },
            {
                "node": "laptop",
                "title": "CUDA Laptop (Worker Cockpit)",
                "status": "active",
                "window_title": "Antigravity Worker Executioner",
                "timestamp": now_iso,
                "image_bytes": MINIMAL_PNG_BYTES,
            },
            {
                "node": "steamdeck",
                "title": "Handheld Controller (Steam Deck)",
                "status": "idle",
                "window_title": "KDE Wayland Session",
                "timestamp": now_iso,
                "image_bytes": MINIMAL_PNG_BYTES,
            },
        ]

    screens: List[Dict[str, Any]] = []

    if isinstance(raw_data, list):
        items = raw_data
    elif isinstance(raw_data, dict):
        if "screens" in raw_data and isinstance(raw_data["screens"], list):
            items = raw_data["screens"]
        elif "nodes" in raw_data and isinstance(raw_data["nodes"], list):
            items = raw_data["nodes"]
        else:
            # Key-value map: {"desktop": {...}, "laptop": {...}}
            items = []
            for k, v in raw_data.items():
                if isinstance(v, dict):
                    entry = dict(v)
                    if "node" not in entry and "name" not in entry:
                        entry["node"] = k
                    items.append(entry)
                elif isinstance(v, (str, bytes)):
                    items.append({"node": k, "image_base64": v})

    for item in items:
        if not isinstance(item, dict):
            continue
        node = str(item.get("node") or item.get("name") or "unknown")
        title = str(item.get("title") or f"{node.capitalize()} Screen")
        status = str(item.get("status") or "active")
        window_title = str(item.get("window_title") or item.get("window") or "Terminal")
        timestamp = str(item.get("timestamp") or datetime.now(timezone.utc).isoformat())

        img_bytes = MINIMAL_PNG_BYTES
        if "image_bytes" in item and isinstance(item["image_bytes"], bytes):
            img_bytes = item["image_bytes"]
        elif "image_base64" in item and item["image_base64"]:
            raw_b64 = str(item["image_base64"]).strip()
            if "," in raw_b64:
                raw_b64 = raw_b64.split(",", 1)[1]
            try:
                img_bytes = base64.b64decode(raw_b64)
            except Exception as e:
                logger.warning("Failed to decode base64 screenshot for node '%s': %s", node, e)
                img_bytes = MINIMAL_PNG_BYTES
        elif "image_path" in item and item["image_path"]:
            p = Path(item["image_path"])
            if p.is_file():
                try:
                    img_bytes = p.read_bytes()
                except OSError:
                    img_bytes = MINIMAL_PNG_BYTES

        screens.append({
            "node": node,
            "title": title,
            "status": status,
            "window_title": window_title,
            "timestamp": timestamp,
            "image_bytes": img_bytes,
        })

    return screens


def capture_fleet_screens(
    brain_dir: Optional[Path] = None,
    json_data: Optional[Dict[str, Any] | List[Any]] = None,
) -> Path:
    """
    Ingests and decodes multi-node screen captures into <brain_dir>/artifacts/fleet_screens/
    and generates an interactive carousel markdown artifact at <brain_dir>/artifacts/fleet_screens.md.

    Args:
        brain_dir: Optional brain directory. Defaults to environment or ~/.gemini/antigravity/brain.
        json_data: Optional dictionary or list of node captures containing base64 images or paths.

    Returns:
        Path to the generated fleet_screens.md artifact.
    """
    b_dir = brain_dir or Path(
        os.environ.get(
            "ANTIGRAVITY_BRAIN_DIR",
            os.environ.get(
                "GEMINI_BRAIN_DIR", Path.home() / ".gemini" / "antigravity" / "brain"
            ),
        )
    )

    artifacts_dir = b_dir / "artifacts"
    screens_dir = artifacts_dir / "fleet_screens"
    screens_dir.mkdir(parents=True, exist_ok=True)

    normalized_screens = _normalize_screens_data(json_data)
    slides_md: List[str] = []

    for sc in normalized_screens:
        node_clean = _sanitize_filename(sc["node"])
        img_filename = f"{node_clean}.png"
        img_path = screens_dir / img_filename
        img_path.write_bytes(sc["image_bytes"])

        abs_img_path = img_path.resolve()
        slide = (
            f"### {sc['title']} (`{sc['node']}`)\n"
            f"**Captured**: {sc['timestamp']}  \n"
            f"**Status**: `{sc['status']}` | **Active Window**: {sc['window_title']}\n\n"
            f"![{sc['title']}]({abs_img_path})\n"
        )
        slides_md.append(slide.strip())

    carousel_body = "\n\n<!-- slide -->\n\n".join(slides_md)

    content = (
        "# Knot Mesh Fleet Screen Cockpit\n\n"
        f"Consolidated visual telemetry captured across {len(normalized_screens)} mesh strand node(s).\n\n"
        "````carousel\n"
        f"{carousel_body}\n"
        "````\n"
    )

    artifact_file = artifacts_dir / "fleet_screens.md"
    artifact_file.write_text(content, encoding="utf-8")

    return artifact_file


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Knot Mesh Fleet Screen Carousel Generator")
    parser.add_argument("--brain-dir", type=Path, default=None)
    parser.add_argument("--data", type=str, default=None)
    args = parser.parse_args()
    data = None
    if args.data:
        p_data = Path(args.data)
        if p_data.is_file():
            data = json.loads(p_data.read_text(encoding="utf-8"))
        else:
            data = json.loads(args.data)
    art = capture_fleet_screens(brain_dir=args.brain_dir, json_data=data)
    print(f"Artifact created: {art}")
