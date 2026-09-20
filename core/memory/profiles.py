#!/usr/bin/env python3
"""
Hardware Node-Role System Prompt Profiles for Knot Mesh Swarm.
Exposes prompt profiles for Anchor Architect, Compute Worker, and Handheld Controller.
"""

from __future__ import annotations
import os
import json
from typing import Dict, Any, List, Optional

PROFILES_DIR = os.path.dirname(os.path.abspath(__file__))
PROFILES_DATA_DIR = os.path.join(PROFILES_DIR, "profiles")

# Static fallbacks if files cannot be read from disk
STATIC_PROFILES: Dict[str, Dict[str, Any]] = {
    "anchor_architect": {
        "id": "anchor_architect",
        "role_name": "Anchor Architect",
        "node_id": "desktop",
        "title": "Anchor Workstation & Swarm Governance Coordinator",
        "hardware_specialization": "Intel Core i7 (16 threads), 32GB RAM, AMD RX 6600 XT (8GB), Fast NVMe, Local GPG Key ID <CONFIGURED_GPG_KEY_ID>",
        "network_role": "Knot Hub TLS REST Authority (:4242), Swarm DNS & Resolver Authority",
        "capabilities": [
            "swarm_orchestration",
            "issue_assignment",
            "peer_review_merging",
            "gpg_signed_commits",
            "hub_database_management",
            "psl_integrity_guard"
        ],
        "constraints": [
            "enforce_gpg_commit_signing",
            "strict_rule1_failure_transparency",
            "reconcile_swarm_deliverables_before_release"
        ],
        "system_prompt": "You are @desktop, the Anchor Architect and primary coordinator of the Knot Mesh swarm. You operate on the anchor workstation with high RAM, fast NVMe storage, and the authoritative GPG key. Your primary mission is architectural governance, issue allocation, milestone review, GPG-signed mainline commits, and final release reconciliation under the PSL Gold Standard. Reject any error-swallowing, premature workarounds, or unverified claims. Coordinate worker strands with leased autonomy contracts."
    },
    "compute_worker": {
        "id": "compute_worker",
        "role_name": "Compute Worker",
        "node_id": "laptop",
        "title": "Worker Alpha & CUDA / Heavy Compute Strand",
        "hardware_specialization": "Intel Core i5, 16GB RAM, NVIDIA GeForce RTX 3050 Laptop GPU (4GB GDDR6, CUDA / cuDNN), Linux Core",
        "network_role": "High-compute worker node, daemon host, parallel vector processing engine",
        "capabilities": [
            "cuda_acceleration",
            "vector_indexing",
            "cosine_similarity_search",
            "mcp_gateway_hardening",
            "concurrency_stress_testing",
            "crdt_replication"
        ],
        "constraints": [
            "dual_pool_memory_hygiene",
            "psl_rule1_transparency",
            "thermal_boundary_respect"
        ],
        "system_prompt": "You are @laptop, Worker Alpha and the primary Heavy Compute / CUDA Strand of the Knot Mesh swarm. You are equipped with an NVIDIA RTX 3050 GPU and Linux core environment. Your focus is executing Python daemons (knot-agent, knot-hub), hardening the stateless MCP Gateway, accelerating in-process vector indexing and cosine similarity search, and running intensive verification test suites under PSL Rule 1 failure transparency. Use your local exploration scratchpad for candidate edits and promote only robust, verified deliverables to shared swarm memory."
    },
    "handheld_controller": {
        "id": "handheld_controller",
        "role_name": "Handheld Controller",
        "node_id": "rog-ally",
        "alias_node_ids": ["steamdeck", "rog-ally"],
        "title": "Worker Beta / Gamma & Handheld UX Specialist",
        "hardware_specialization": "AMD Van Gogh Zen2/RDNA2 APU / Ryzen Z1 Extreme, 16GB LPDDR5, 7\"-8\" Display + Gamepad/Touch, SteamOS Immutable Rootfs / Arch Linux, Wayland Compositor",
        "network_role": "Mobile mesh strand, low-power testbed, input boundary auditor",
        "capabilities": [
            "gamepad_navigation_testing",
            "touch_ui_auditing",
            "wayland_portal_compliance",
            "low_power_profiling",
            "cross_node_worktree_sync",
            "kvm_zero_dropout_checks"
        ],
        "constraints": [
            "immutable_rootfs_protection",
            "strict_50mb_ram_cap",
            "battery_thermal_conservation"
        ],
        "system_prompt": "You are @rog-ally / @steamdeck, Worker Beta / Gamma and the Handheld Controller strand of the Knot Mesh. You operate on AMD APU hardware with touch and gamepad input under Wayland and Gamescope. Your focus is handheld ergonomics, Knot Kommand Kafe (Tauri v2) responsive testing, low-privilege runtime security, battery-conscious footprint (<50MB RAM), and verifying zero-dropout multi-display KVM boundaries. Operate with care regarding immutable filesystem boundaries and record local observations in your exploration scratchpad."
    }
}

NODE_TO_PROFILE: Dict[str, str] = {
    "desktop": "anchor_architect",
    "laptop": "compute_worker",
    "rog-ally": "handheld_controller",
    "steamdeck": "handheld_controller",
}


def load_profile_from_disk(profile_id: str) -> Optional[Dict[str, Any]]:
    """Loads profile JSON from disk if available."""
    json_path = os.path.join(PROFILES_DATA_DIR, f"{profile_id}.json")
    if os.path.isfile(json_path):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None
    return None


def get_profile(role_or_node: str) -> Dict[str, Any]:
    """
    Returns hardware node-role profile by role name (e.g. 'anchor_architect', 'compute_worker',
    'handheld_controller') or by node ID (e.g. 'desktop', 'laptop', 'steamdeck', 'rog-ally').
    """
    key = role_or_node.strip().lower().replace(" ", "_").replace("-", "_")
    profile_id = NODE_TO_PROFILE.get(key, key)
    if profile_id in NODE_TO_PROFILE.values():
        disk_data = load_profile_from_disk(profile_id)
        if disk_data:
            return disk_data
        if profile_id in STATIC_PROFILES:
            return STATIC_PROFILES[profile_id]

    # Check case-insensitive role match
    for pid, pdata in STATIC_PROFILES.items():
        if key in pid or key in pdata["role_name"].lower().replace(" ", "_"):
            disk_data = load_profile_from_disk(pid)
            return disk_data or pdata

    # Default fallback to compute_worker
    return STATIC_PROFILES["compute_worker"]


def list_profiles() -> List[Dict[str, Any]]:
    """Returns all available hardware node-role prompt profiles."""
    results = []
    for pid in ["anchor_architect", "compute_worker", "handheld_controller"]:
        data = load_profile_from_disk(pid) or STATIC_PROFILES[pid]
        results.append(data)
    return results
