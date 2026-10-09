#!/usr/bin/env python3
"""
Hardware Node-Role System Prompt Profiles for Knot Mesh Swarm.
Exposes prompt profiles for Anchor Architect, Compute Worker, and Handheld Controller.
"""

from __future__ import annotations
import os
import sys
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
        "title": "Anchor Workstation & Swarm Governance Lead",
        "hardware_specialization": "High-thread CPU, High RAM, Fast NVMe, Local GPG Key ID <CONFIGURED_GPG_KEY_ID>, Ultrawide Wayland Display",
        "network_role": "Knot Hub TLS Authority (:4242), Swarm Governance, Anchor Node",
        "capabilities": [
            "swarm_orchestration",
            "conductor_invariant_enforcement",
            "issue_assignment",
            "peer_review_merging",
            "gpg_signed_commits",
            "hub_database_management",
            "psl_integrity_guard"
        ],
        "constraints": [
            "conductor_invariant_zero_lone_ranger",
            "anti_phantom_ledger_enforced",
            "strict_rule1_failure_transparency",
            "enforce_gpg_commit_signing"
        ],
        "system_prompt": "You are @desktop, operating as an Anchor node in the Knot Mesh swarm. When acting as Swarm Orchestrator during a multi-node campaign, you strictly enforce the Conductor Invariant: never write implementation code or execute local unit tests directly on this node while worker strands have capacity. Allocate tasks across the homogeneous cluster, provision isolated git worktrees, and conduct ruthless delta reviews before GPG-signed mainline merges. Reject any error-swallowing or synthetic ledger allocations."
    },
    "compute_worker": {
        "id": "compute_worker",
        "role_name": "Compute Worker",
        "node_id": "laptop",
        "title": "Worker Strand & Dynamic Acceleration Node",
        "hardware_specialization": "Multi-core CPU, 16GB+ RAM, NVIDIA RTX 3050 CUDA Acceleration / Linux Core",
        "network_role": "High-compute worker strand in homogeneous mesh cluster",
        "capabilities": [
            "full_swe_execution",
            "cuda_acceleration",
            "vector_indexing",
            "cosine_similarity_search",
            "mcp_gateway_hardening",
            "concurrency_stress_testing",
            "crdt_replication"
        ],
        "constraints": [
            "dual_state_decoupling_enforced",
            "dual_pool_memory_hygiene",
            "psl_rule1_transparency",
            "thermal_boundary_respect"
        ],
        "system_prompt": "You are a first-class compute worker in the homogeneous Knot Mesh cluster (@laptop). You are equipped with CUDA hardware acceleration and full Linux development toolchains. Your mission is executing autonomous engineering workstreams in isolated git worktrees, running test suites, accelerating vector operations, and providing decoupled display cockpits (Kitty Confluence) under PSL Rule 1 failure transparency."
    },
    "handheld_controller": {
        "id": "handheld_controller",
        "role_name": "Handheld Controller",
        "node_id": "rog-ally",
        "alias_node_ids": ["steamdeck", "rog-ally"],
        "title": "Worker Strand & Dynamic Handheld Node",
        "hardware_specialization": "AMD Van Gogh Zen2/RDNA2 APU / Ryzen Z1 Extreme, 16GB LPDDR5, 7\"-8\" Display + Gamepad/Touch, SteamOS / Arch Linux, Wayland Compositor",
        "network_role": "First-class computational worker strand in homogeneous mesh cluster",
        "capabilities": [
            "full_swe_execution",
            "background_worktree_tasks",
            "gamepad_navigation_testing",
            "touch_ui_auditing",
            "wayland_portal_compliance",
            "cross_node_worktree_sync",
            "kvm_zero_dropout_checks"
        ],
        "constraints": [
            "dual_state_decoupling_enforced",
            "immutable_rootfs_protection",
            "battery_thermal_conservation"
        ],
        "system_prompt": "You are a first-class compute worker in the homogeneous Knot Mesh cluster (@steamdeck / @rog-ally). While your hardware features an AMD APU and handheld display surface, you possess full 16GB computational capacity to compile code, run test suites, and execute SWE workstreams inside isolated git worktrees. Strict Dual-State Decoupling Invariant: If a telemetry HUD (knot quota live) or Message Board (knot council board) is active on your physical display, your background compute capacity remains 100% available for autonomous task execution."
    }
}

NODE_TO_PROFILE: Dict[str, str] = {
    "desktop": "anchor_architect",
    "laptop": "compute_worker",
    "rog-ally": "handheld_controller",
    "rog_ally": "handheld_controller",
    "steamdeck": "handheld_controller",
    "steam_deck": "handheld_controller",
}


def load_profile_from_disk(profile_id: str) -> Optional[Dict[str, Any]]:
    """Loads profile JSON from disk if available."""
    json_path = os.path.join(PROFILES_DATA_DIR, f"{profile_id}.json")
    if os.path.isfile(json_path):
        try:
            with open(json_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as _err:
            sys.stderr.write(f"Notice: [profiles] Failed to load profile from {json_path}: {_err}\n")
            return None
    return None


def get_profile(role_or_node: str) -> Dict[str, Any]:
    """
    Returns hardware node-role profile by role name (e.g. 'anchor_architect', 'compute_worker',
    'handheld_controller') or by node ID (e.g. 'desktop', 'laptop', 'steamdeck', 'rog-ally').
    """
    raw = role_or_node.strip().lower()
    key = raw.replace(" ", "_").replace("-", "_")
    profile_id = NODE_TO_PROFILE.get(key, NODE_TO_PROFILE.get(raw, key))
    if profile_id in STATIC_PROFILES:
        disk_data = load_profile_from_disk(profile_id)
        if disk_data:
            return disk_data
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


def get_dynamic_capabilities(node_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Probes dynamic capabilities of a target node or the active cluster.
    Reads node topology and specifications from Knot manifests or live probes.
    """
    node = (node_id or "localhost").strip().lower()
    profile = get_profile(node)

    capabilities = {
        "node_id": node,
        "is_homogeneous_worker": True,
        "d2d_surface_decoupled": True,
        "role_name": profile.get("role_name", "Compute Worker"),
        "hardware_specialization": profile.get("hardware_specialization", "Standard x86_64 Core"),
        "capabilities": profile.get("capabilities", []),
        "constraints": profile.get("constraints", []),
    }
    return capabilities


def format_capability_summary(node_id: str) -> str:
    """Returns a concise prompt string summarizing a node's dynamic compute capabilities."""
    caps = get_dynamic_capabilities(node_id)
    return (
        f"Node @[{node_id}] (Homogeneous Worker): {caps['hardware_specialization']} | "
        f"Capabilities: {', '.join(caps['capabilities'][:4])} | "
        f"D2D/A2A Decoupled: True"
    )

