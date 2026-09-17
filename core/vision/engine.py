#!/usr/bin/env python3
"""
Knot Swarm Vision & Physical Topology Engine
Unified entry point supporting:
- mode="auto": Swarm AI with graceful fallback to Offline heuristic detector
- mode="swarm": Swarm AI reasoning agent only (raises error on failure)
- mode="offline": Local PIL + numpy detector only
"""

import logging
from typing import Dict, Any, List, Optional
from core.vision.offline_detector import offline_detector
from core.vision.swarm_detector import swarm_detector

logger = logging.getLogger("knot-vision-engine")

def analyze_desk_photo(
    image_input: Any,
    mode: str = "auto",
    swarm_nodes: Optional[List[Dict[str, Any]]] = None,
    anchor_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    Analyze physical desk setup photograph and synthesize topology.json layout.

    Args:
        image_input: File path (str), raw image bytes (bytes), or PIL.Image
        mode: "auto" (default: try swarm AI, fallback to offline), "swarm", or "offline"
        swarm_nodes: Optional list of connected node metadata dicts
        anchor_id: Optional anchor node ID (defaults to 'rog-ally' or center node)

    Returns:
        Structured dictionary conforming to the Knot topology analysis schema.
    """
    mode = mode.lower().strip()

    if mode == "swarm":
        logger.info("Running vision analysis in strict 'swarm' AI mode")
        return swarm_detector.analyze(image_input, swarm_nodes=swarm_nodes, anchor_id=anchor_id)

    elif mode == "offline":
        logger.info("Running vision analysis in local 'offline' heuristic mode")
        return offline_detector.analyze(image_input, swarm_nodes=swarm_nodes, anchor_id=anchor_id)

    elif mode == "auto":
        # Check if agy is available
        if swarm_detector.is_available():
            try:
                logger.info("Attempting vision analysis with Swarm AI agent...")
                return swarm_detector.analyze(image_input, swarm_nodes=swarm_nodes, anchor_id=anchor_id)
            except Exception as e:
                logger.warning(
                    "Swarm AI vision agent failed or timed out (%s). Falling back to offline detector.",
                    e
                )

        logger.info("Executing offline heuristic vision detector fallback...")
        res = offline_detector.analyze(image_input, swarm_nodes=swarm_nodes, anchor_id=anchor_id)
        res["reasoning"] = (
            "*(Auto mode fallback: Swarm AI offline or busy, processed via local computer vision)*\n\n"
            + res.get("reasoning", "")
        )
        return res

    else:
        raise ValueError(f"Unknown vision analysis mode: '{mode}'. Must be 'auto', 'swarm', or 'offline'.")
