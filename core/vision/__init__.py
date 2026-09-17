"""
Knot Swarm Vision & Physical Topology Reasoning Engine
Provides dual-tier vision:
1. Swarm AI Reasoning Agent (using local multimodal agy runtime)
2. Offline Heuristic Computer Vision (using pure PIL + numpy with thumbnail color matching)
"""

from core.vision.engine import analyze_desk_photo

__all__ = ["analyze_desk_photo"]
