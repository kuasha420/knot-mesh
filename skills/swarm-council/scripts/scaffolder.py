#!/usr/bin/env python3
"""
Swarm Council: Stage 3 Prompt Scaffolder
Calculates 1.5x codebase chunk coverage, injects hardware domain specializations,
and produces tailored prompts for all online swarm nodes.
"""

import os
import sys
import json
import uuid
import argparse
import subprocess
from datetime import datetime

DOMAIN_PROFILES = {
    "desktop": {
        "title": "Mesh Anchor & Coordinator",
        "hardware": "AMD RX 6600 XT, Intel Core i7 16-thread, 32GB RAM, Ultrawide Display",
        "specialization": (
            "- Mesh Anchor & Coordinator role: verify anchor services, deskflow server, and update orchestrations.\n"
            "- Multi-monitor / ultrawide display topology: test display boundaries, resolution scaling, and KVM edges.\n"
            "- Primary compiler & packaging pipelines: test PKGBUILD, makepkg, build artifacts, and systemd units."
        )
    },
    "laptop": {
        "title": "CUDA Compute & Roaming Strand",
        "hardware": "NVIDIA RTX 3050 (4GB GDDR6 CUDA), Intel Core i5, 16GB RAM, Clamshell Display",
        "specialization": (
            "- Roaming strand between 'office' and 'home' swarms: test NetworkManager dispatcher script and roaming guard.\n"
            "- Hardware acceleration: verify NVIDIA CUDA compute, driver bindings, and power management profiles.\n"
            "- Battery & AC state transitions: audit suspend/resume triggers and SSH connectivity."
        )
    },
    "rog-ally": {
        "title": "Dual-Personality Handheld / Anchor",
        "hardware": "AMD Ryzen Z1 Extreme, 16GB LPDDR5, 120Hz Handheld Display, Docked Station",
        "specialization": (
            "- Dual personality: Anchor on 'office' swarm, Strand on 'home' mesh. Test multi-swarm profile switching.\n"
            "- 120Hz display & refresh rates: verify Wayland frame rate, variable refresh (VRR), and KVM cursor smoothness.\n"
            "- Docked vs handheld ergonomics: audit thermal modes, dock USB peripherals, and network reassignments."
        )
    },
    "steamdeck": {
        "title": "Gaming Handheld Strand",
        "hardware": "AMD Van Gogh Zen2/RDNA2 APU, 16GB Unified LPDDR5, Handheld Display + Gamepad",
        "specialization": (
            "- Pure handheld gaming strand: test SteamOS / Arch Linux base integration and read-only root handling.\n"
            "- Non-standard input: test gamepad mode vs desktop mode transitions, virtual keyboard, and Wayland scaling.\n"
            "- Low-power APU & Vulkan/RADV: evaluate lightweight resource footprint and memory constraints."
        )
    }
}

DEFAULT_CHUNKS = [
    {
        "id": "chunk_core_runtime",
        "name": "Core Runtime & Network Resolution",
        "paths": ["bin/knot", "core/lib.sh", "core/resolver.sh", "core/modules/ssh.sh", "core/modules/doctor.sh"]
    },
    {
        "id": "chunk_installer_firewall",
        "name": "Installer Automation & Firewall Security",
        "paths": ["bin/knot-installer", "core/modules/firewall.sh", "core/modules/antigravity.sh", "core/mcp/"]
    },
    {
        "id": "chunk_peripherals_sync",
        "name": "Peripherals, KDE Connect & KVM",
        "paths": ["core/modules/kdeconnect.sh", "core/modules/deskflow.sh", "core/modules/autologin.sh", "core/modules/autounlock.sh", "core/modules/shutdown.sh"]
    },
    {
        "id": "chunk_docs_tests_packaging",
        "name": "Documentation, Test Harnesses & Packaging",
        "paths": ["README.md", "docs/", "PKGBUILD", "tests/"]
    }
]

def discover_online_nodes(knot_root):
    knot_bin = os.path.join(knot_root, "bin/knot")
    nodes = []
    try:
        out = subprocess.check_output([knot_bin, "status"], text=True, stderr=subprocess.DEVNULL)
        import re
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        clean = ansi_escape.sub('', out)
        for line in clean.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[4] == "ONLINE":
                nodes.append(parts[0])
    except Exception:
        nodes = ["desktop", "laptop", "rog-ally", "steamdeck"]
    return nodes if nodes else ["desktop"]

def calculate_chunk_distribution(chunks, nodes, target_coverage=1.5):
    """
    Distribute chunks across nodes to achieve target coverage ratio.
    Total assignments = round(len(chunks) * target_coverage)
    """
    num_chunks = len(chunks)
    num_nodes = len(nodes)
    total_assignments = max(num_nodes, int(round(num_chunks * target_coverage)))
    
    node_assignments = {node: [] for node in nodes}
    
    # Round-robin allocation with overlap
    for i in range(total_assignments):
        chunk = chunks[i % num_chunks]
        node = nodes[i % num_nodes]
        if chunk not in node_assignments[node]:
            node_assignments[node].append(chunk)
        else:
            # Shift to next node if already assigned
            for alt_node in nodes:
                if chunk not in node_assignments[alt_node]:
                    node_assignments[alt_node].append(chunk)
                    break

    actual_coverage = sum(len(v) for v in node_assignments.values()) / float(num_chunks)
    return node_assignments, actual_coverage

def scaffold_prompt(node, base_prompt, assigned_chunks, run_id, discussion_url, pack_name, sidequest_pct=30):
    profile = DOMAIN_PROFILES.get(node, {
        "title": "Mesh Node",
        "hardware": "Generic Arch Linux workstation",
        "specialization": "- Standard knot-mesh integration testing and system health."
    })

    chunk_list_md = "\n".join([f"  - **{c['name']}**: `{', '.join(c['paths'])}`" for c in assigned_chunks])

    prompt = f"""# Knot Swarm Council Mission: Node @[{node}]

**Run ID**: `{run_id}`  
**Node Role**: {profile['title']} (`{node}`)  
**Hardware Profile**: {profile['hardware']}  
**Pack**: `{pack_name}`  
**Discussion Registry**: {discussion_url}  

---

## 1. Operational Directives (CRITICAL)
- **Mode**: Autonomous Verification Mode.
- **Execution**: Execute inspection tools (`view_file`, `grep_search`, `run_command`, `find_by_name`) directly.
- **DO NOT** halt to request manual confirmation or artifact review. Complete your assigned audits and tests autonomously.
- **Strict Error Handling**: Adhere strictly to Rule 02 (zero error swallowing, `set -euo pipefail`). Report all unhandled errors.

---

## 2. Overall Mission Objective
{base_prompt}

---

## 3. Assigned Codebase Chunks (Primary Audit Responsibility)
Your node is specifically tasked with in-depth audit and verification of the following chunks:
{chunk_list_md}

*Evaluate syntax (`bash -n`), logic flow, edge cases, error resilience, and parity with private prototype.*

---

## 4. Hardware Domain Specialization
As `{node}`, focus your unique hardware, networking, and operating context on:
{profile['specialization']}

---

## 5. Autonomous Side Quest (~{sidequest_pct}% Capacity)
Dedicate ~{sidequest_pct}% of your mission effort to autonomous deep-dive exploration:
- Choose an area of the codebase, an edge case, or a stress test of your own initiative.
- Dig deep into potential failure modes, concurrency issues, or unverified assumptions.
- Explicitly document your Side Quest objective and discoveries in your final report.

---

## 6. GitHub Discussion Communication Protocol
All progress must be reported to the discussion thread:
`{discussion_url}`

- **Header Requirement**: Every single reply posted MUST start with:
  `<!-- KNOT-NODE: {node} | RUN: {run_id} | STATUS: <25%|50%|75%|ALERT|FINAL> -->`
- **Milestone Checkpoints**: Post updates at your self-assessed 25%, 50%, and 75% milestones.
- **Verified Alerts**: Immediately post an `ALERT` if you discover a critical blocker or regression with high confidence.
- **Peer Callouts**: When addressing a specific peer, use unmistakable markup: `@[node:<node_id>]`.
- **Token Efficiency**: Do NOT fetch the whole discussion repeatedly. Only answer when called out or at checkpoints.
- **Final Deliverable**: Post exactly ONE final reply (`STATUS: FINAL`) with your comprehensive audit findings and release recommendation.
"""
    return prompt

def main():
    parser = argparse.ArgumentParser(description="Swarm Council Prompt Scaffolder")
    parser.add_argument("--prompt", help="Base mission prompt text")
    parser.add_argument("--prompt-file", help="Path to file containing base mission prompt")
    parser.add_argument("--pack", default="audit-parity", help="Template pack name")
    parser.add_argument("--run-id", default="", help="Optional run identifier")
    parser.add_argument("--discussion-url", default="https://github.com/kuasha420/knot-mesh/discussions", help="Discussion thread URL")
    parser.add_argument("--nodes", default="", help="Comma-separated list of nodes (auto-discovered if empty)")
    parser.add_argument("--coverage", type=float, default=1.5, help="Target codebase coverage ratio")
    parser.add_argument("--out-dir", default="", help="Output directory for generated prompt files")
    parser.add_argument("--dry-run", action="store_true", help="Print summary without writing files")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    knot_root = os.path.abspath(os.path.join(script_dir, "../../.."))

    # Load prompt
    if args.prompt_file:
        with open(args.prompt_file) as f:
            base_prompt = f.read().strip()
    elif args.prompt:
        base_prompt = args.prompt.strip()
    else:
        base_prompt = "Audit private prototype to public transition across all nodes."

    # Load pack hints if exists
    packs_file = os.path.join(script_dir, "../templates/packs.json")
    sidequest_pct = 30
    coverage_ratio = args.coverage
    if os.path.exists(packs_file):
        try:
            with open(packs_file) as pf:
                pdata = json.load(pf).get("packs", {}).get(args.pack, {})
                hints = pdata.get("hints", {})
                coverage_ratio = hints.get("divide:coverage", coverage_ratio)
                sidequest_pct = hints.get("sidequest:capacity", sidequest_pct)
        except Exception:
            pass

    # Determine nodes
    if args.nodes:
        nodes = [n.strip() for n in args.nodes.split(",") if n.strip()]
    else:
        nodes = discover_online_nodes(knot_root)

    run_id = args.run_id or f"run_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    out_dir = args.out_dir or os.path.expanduser(f"~/.config/knot/missions/{run_id}")

    # Chunk allocation
    assignments, actual_coverage = calculate_chunk_distribution(DEFAULT_CHUNKS, nodes, coverage_ratio)

    summary = {
        "run_id": run_id,
        "pack": args.pack,
        "nodes": nodes,
        "target_coverage": coverage_ratio,
        "actual_coverage": round(actual_coverage, 2),
        "chunk_count": len(DEFAULT_CHUNKS),
        "prompts_generated": {}
    }

    if not args.dry_run:
        os.makedirs(out_dir, exist_ok=True)

    for node in nodes:
        node_chunks = assignments.get(node, [])
        prompt_content = scaffold_prompt(
            node=node,
            base_prompt=base_prompt,
            assigned_chunks=node_chunks,
            run_id=run_id,
            discussion_url=args.discussion_url,
            pack_name=args.pack,
            sidequest_pct=sidequest_pct
        )

        out_path = os.path.join(out_dir, f"{node}_prompt.md")
        if not args.dry_run:
            with open(out_path, "w") as out_f:
                out_f.write(prompt_content)
            summary["prompts_generated"][node] = {
                "file": out_path,
                "chunks": [c["name"] for c in node_chunks]
            }
        else:
            summary["prompts_generated"][node] = {
                "preview_len": len(prompt_content),
                "chunks": [c["name"] for c in node_chunks]
            }

    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
