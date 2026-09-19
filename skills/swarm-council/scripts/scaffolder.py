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
    if not os.path.isfile(knot_bin) or not os.access(knot_bin, os.X_OK):
        import shutil
        knot_bin = shutil.which("knot") or os.path.expanduser("~/.local/bin/knot")
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
        pass
    if not nodes:
        try:
            local_host = subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip()
        except Exception:
            local_host = "localhost"
        nodes = [local_host]
    return nodes

def resolve_chunks(project_dir=None):
    """
    Dynamically derive codebase chunks. If project_dir is knot-mesh,
    returns DEFAULT_CHUNKS. Otherwise discovers files and creates balanced chunks.
    """
    pdir = project_dir or os.getcwd()
    if os.path.exists(os.path.join(pdir, "bin/knot")) and os.path.exists(os.path.join(pdir, "core/lib.sh")):
        return DEFAULT_CHUNKS

    git_files = []
    try:
        out = subprocess.check_output(["git", "-C", pdir, "ls-files"], text=True, stderr=subprocess.DEVNULL)
        git_files = [line.strip() for line in out.splitlines() if line.strip()]
    except Exception:
        pass

    if not git_files and os.path.isdir(pdir):
        for root, dirs, files in os.walk(pdir):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "target", "build", "dist")]
            for f in files:
                if not f.startswith("."):
                    rel = os.path.relpath(os.path.join(root, f), pdir)
                    git_files.append(rel)

    if not git_files:
        return DEFAULT_CHUNKS

    groups = {}
    for f in git_files:
        parts = f.split(os.sep)
        top = parts[0] if len(parts) > 1 else "root"
        groups.setdefault(top, []).append(f)

    sorted_groups = sorted(groups.items(), key=lambda x: len(x[1]), reverse=True)
    chunks = []
    for name, files in sorted_groups[:3]:
        chunks.append({
            "id": f"chunk_{name.lower()}",
            "name": f"{name.capitalize()} Subsystem",
            "paths": files[:6]
        })

    rest = [name for name, _ in sorted_groups[3:]]
    if rest:
        rest_files = []
        for n in rest:
            rest_files.extend(groups[n][:2])
        chunks.append({
            "id": "chunk_supporting",
            "name": f"Supporting Infrastructure ({', '.join(rest[:4])})",
            "paths": rest_files[:8]
        })

    return chunks if chunks else DEFAULT_CHUNKS

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

try:
    from resolve_node import resolve_local_node_id
except ImportError:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
    try:
        from resolve_node import resolve_local_node_id
    except ImportError:
        def resolve_local_node_id(nodes=None):
            return os.environ.get("KNOT_NODE_ID") or (nodes[0] if nodes else "localhost")

def build_tournament_ring(nodes):
    local_node = resolve_local_node_id(nodes)
    if local_node and local_node in nodes:
        active_ring = [local_node] + [n for n in nodes if n != local_node]
    else:
        active_ring = list(nodes)
    return active_ring if active_ring else ["localhost"]

def scaffold_tournament_prompt(node, nodes, run_id, discussion_url, db="mesh", target_rounds=5):
    active_ring = build_tournament_ring(nodes)
    idx = active_ring.index(node) if node in active_ring else 0
    next_node = active_ring[(idx + 1) % len(active_ring)]
    prev_node = active_ring[(idx - 1) % len(active_ring)]

    # Dynamic Ring Routing Table
    routing_entries = [f"@{active_ring[i]} passes to @{active_ring[(i+1)%len(active_ring)]}" for i in range(len(active_ring))]
    routing_table_str = "\n".join(f"  - {entry}" for entry in routing_entries)
    ring_chain_str = " -> ".join(f"@{n}" for n in active_ring) + f" -> @{active_ring[0]}"

    profile = DOMAIN_PROFILES.get(node, {
        "title": "Tournament Player",
        "hardware": "Generic Arch Linux workstation",
        "specialization": "- Cryptographic solver."
    })

    if node == active_ring[0]:
        role_header = f"🏆 TOURNAMENT MASTER & OPENING SERVER (@[{node}])"
        task_directive = f"""You are the **Opening Server & Tournament Master** for this {target_rounds}-round Cryptographic Agent Rally!
The rally ring topology is: `{ring_chain_str}`.

### DYNAMIC RING ROUTING TABLE:
{routing_table_str}

### TOURNAMENT PARAMETERS & EXIT CONDITION:
- **Total Rounds**: {target_rounds} complete ring laps ({target_rounds * len(active_ring)} total peer volleys).
- **Your Peer Successor**: `@{next_node}`
- **Your Peer Predecessor**: `@{prev_node}`

### YOUR ACTIONS (ROUND 1 SERVE):
1. Immediately generate the Opening Cryptographic Challenge for your peer `@{next_node}`.
2. Adhere strictly to the **Anti-Cheating Contract**:
   - Give ONLY one-way constraints, input generators, or algebraic invariants.
   - **NEVER** include the answer, solution witness, or pre-computed plain hash in the prompt!
   - Challenge Format (embed these exact solve and routing directives in your payload):
     `🏓 [ROUND 1/{target_rounds} SERVE from @{node}] Target: Find a string starting with "KNOT-SET1-" such that SHA256(string) has at least 4 leading zeros ("0000") and contains the word "RALLY". Return: (1) discovered string, (2) verified hash, (3) solve compute time in ms. ⚠️ DIRECTIVE: Solve immediately using local tools, post telemetry to Mesh DB (knot council reply {run_id} --node <your_node> --status PROGRESS --body "🏓 Volley Returned | Nonce: <val> | Solve Time: <ms>ms | HW: <hw>"), and pass next challenge to your successor according to the Ring Routing Table: {ring_chain_str}. Table: {'; '.join(routing_entries)}. Find your node in the table and steer your successor: knot council steer <successor> '<next_payload>'.`
3. Deliver the challenge visibly into `@{next_node}`'s terminal using the Cockpit Bridge:
   `knot council steer {next_node} '<challenge_payload>'`
4. Broadcast opening serve to Mesh DB:
   `knot council reply {run_id} --node {node} --status PROGRESS --body "🏓 [OPENING SERVE] Served Set 1 Challenge to @[{next_node}]"`

### RALLY MONITORING & EXIT PROTOCOL:
5. Stand by for the return volley from `@{prev_node}`! When it arrives:
   - Verify the proof constraint and solution witness.
   - Log the verified volley to Mesh DB.
   - If round < {target_rounds}:
     Increment the round count (e.g. Round 2 of {target_rounds}), generate the next challenge with increased difficulty, and steer `@{next_node}`!
   - If round >= {target_rounds}:
     🏁 **TERMINATION CONDITION MET**: Log final completion to Mesh DB:
     `knot council reply {run_id} --node {node} --status COMPLETE --body "🏁 [TOURNAMENT CONCLUDED] All {target_rounds} rounds completed across {len(active_ring)} nodes!"`
     Print `🏁 Tournament Master concluded. Standing down.` and STAND DOWN! DO NOT serve any further challenges.
"""
    else:
        role_header = f"⚡ TOURNAMENT RALLY PLAYER & INDEPENDENT VERIFIER (@[{node}])"
        is_anchor = (node == active_ring[-1])
        return_role = f"return the final volley of the round to Tournament Master `@{active_ring[0]}`" if is_anchor else f"pass the next challenge to your successor `@{next_node}`"
        task_directive = f"""You are an active **Rally Player & Verifier** in the {len(active_ring)}-node Cryptographic Agent Rally!
The rally ring topology is: `{ring_chain_str}`.
Your predecessor is `@{prev_node}`. Your successor is `@{next_node}`.

### DYNAMIC RING ROUTING TABLE:
{routing_table_str}

### YOUR OPERATIONAL DIRECTIVES:
1. You are running in your dedicated pane in the Kitty Confluence cockpit.
2. When a challenge is steered into your session by `@{prev_node}`:
   - **Reason**: Analyze the mathematical / cryptographic constraints.
   - **Solve**: Compute the verified solution witness using your preferred local tools or scripts.
   - **Extract**: Obtain the verified witness and calculate your cognitive solve latency (dt).
   - **Telemetry**: Post your solve telemetry to the Mesh DB:
     `knot council reply {run_id} --node {node} --status PROGRESS --body "🏓 Volley Returned | Nonce: <val> | Solve Time: <ms>ms | HW: <hw>"`
   - **Pass**: Synthesize the next dynamic one-way challenge and {return_role}:
     `knot council steer {next_node} '<new_challenge_payload>'`
     Include the round counter and the Ring Routing Table in your payload so your successor knows who to steer.
   - **Anti-Cheating Contract**: Never give `@{next_node}` the solution! Provide only one-way constraints.
3. **Exit Condition**: If the challenge you received was marked as the final round (Round {target_rounds}/{target_rounds}), after steering `@{next_node}`, print `🏁 Final round complete. Standing down.` and stand down without waiting for further challenges!
"""

    return f"""# Knot Swarm Council Mission: {role_header}

**Run ID**: `{run_id}`  
**Node**: `@{node}`  
**Hardware Profile**: {profile['hardware']}  
**Pack**: `tournament`  
**Ring Topology**: `{' -> '.join(active_ring)}`  
**Registry**: {discussion_url}  

---

## 1. Operational Directives
- **Mode**: Autonomous Multi-Agent Tournament.
- **Focus**: Pure Cryptographic & Non-Deterministic Agent Benchmark.
- **Targeted Anti-Patterns (MANDATORY)**:
  1. DO NOT audit or inspect the Knot codebase, SKILL.md, or git history. Workspace tools and paths are pre-verified.
  2. DO NOT run background polling loops or shell status checks without solving.
  3. Focus 100% of cognitive effort on generating and solving cryptographic challenges.
- **Observability**: Every action you take is visible to the operator in your cockpit pane.
- **Anti-Cheating Contract**: Provide only one-way verifiable constraints to peers. Zero leaked plain solutions.

---

## 2. Mission Assignment
{task_directive}

---

## 3. Communication Protocol
- **Steer Peer Pane**: `knot council steer <target_node> '<payload>'`
- **Broadcast Telemetry**: `knot council reply {run_id} --node {node} --status PROGRESS --body '<compact update>'`
- **Inspect Ledger**: `knot council status {run_id}`
"""

def scaffold_prompt(node, base_prompt, assigned_chunks, run_id, discussion_url, pack_name, sidequest_pct=30, db="ghd"):
    profile = DOMAIN_PROFILES.get(node, {
        "title": "Mesh Node",
        "hardware": "Generic Arch Linux workstation",
        "specialization": "- Standard knot-mesh integration testing and system health."
    })

    chunk_list_md = "\n".join([f"  - **{c['name']}**: `{', '.join(c['paths'])}`" for c in assigned_chunks])

    comm_title = "Mesh Council Communication Protocol" if db == "mesh" else "GitHub Discussion Communication Protocol"
    cli_reply_hint = ""
    if db == "mesh":
        cli_reply_hint = f"""- **Posting Updates via CLI**:
  You can post your checkpoints and reports directly from bash:
  `knot council reply {run_id} --node {node} --status <25%|50%|75%|ALERT|FINAL> --body '<message>'`
  or pipe markdown:
  `knot council reply {run_id} --node {node} --status FINAL < report.md`

"""

    prompt = f"""# Knot Swarm Council Mission: Node @[{node}]

**Run ID**: `{run_id}`  
**Node Role**: {profile['title']} (`{node}`)  
**Hardware Profile**: {profile['hardware']}  
**Pack**: `{pack_name}`  
**Registry**: {discussion_url}  

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

## 6. {comm_title}
All progress must be reported to the mission registry:
`{discussion_url}`

- **Header Requirement & Visual Self-Identification**: Every single reply posted MUST begin with:
  ```markdown
  <!-- KNOT-NODE: {node} | RUN: {run_id} | STATUS: <25%|50%|75%|ALERT|FINAL> -->
  ### 🛰️ `@{node}` — {profile['title']}
  **Assigned Chunks**: {', '.join([c['name'] for c in assigned_chunks])}
  ```

{cli_reply_hint}- **Compact Milestone Checkpoints (25%, 50%, 75%)**:
  - **MANDATORY CONCISENESS RULE**: Keep interim checkpoints strictly under 15-20 lines.
  - **DO NOT** output the full audit discoveries, large code dumps, or exhaustive file listings in checkpoints!
  - **STRICT FOCUS FOR CHECKPOINTS**:
    1. **Liveness & Active Task**: Exactly what file or test you are actively inspecting right now.
    2. **Velocity & ETA**: Current progress percentage and estimated time to completion.
    3. **Curious Cases & Red Flags**: Anomalies, strange edge cases, or potential breaking bugs that the swarm must be aware of early.
  - **Reserve Exhaustive Deliverables for `STATUS: FINAL`**: Comprehensive findings, validation matrices, tables, and release verdicts belong exclusively in your final completion reply.

- **Verified Alerts**: Immediately post an `ALERT` if you discover a critical blocker or regression with high confidence.
- **Peer Callouts**: When addressing a specific peer, use unmistakable markup: `@[node:<node_id>]`.
- **Token Efficiency**: Do NOT fetch the whole discussion repeatedly. Only answer when called out or at checkpoints.
- **Final Deliverable**: Post exactly ONE final reply (`STATUS: FINAL`) with your complete, exhaustive findings and release sign-off.
"""
    return prompt

def main():
    parser = argparse.ArgumentParser(description="Swarm Council Prompt Scaffolder")
    parser.add_argument("--prompt", help="Base mission prompt text")
    parser.add_argument("--prompt-file", help="Path to file containing base mission prompt")
    parser.add_argument("--project-dir", default="", help="Target project root directory")
    parser.add_argument("--pack", default="audit-parity", help="Template pack name")
    parser.add_argument("--run-id", default="", help="Optional run identifier")
    parser.add_argument("--discussion-url", default="https://github.com/kuasha420/knot-mesh/discussions", help="Discussion thread URL")
    parser.add_argument("--db", default="ghd", choices=["ghd", "mesh"], help="Registry backend: ghd (default) or mesh")
    parser.add_argument("--nodes", default="", help="Comma-separated list of nodes (auto-discovered if empty)")
    parser.add_argument("--coverage", type=float, default=1.5, help="Target codebase coverage ratio")
    parser.add_argument("--rounds", type=int, default=5, help="Target tournament rounds (default: 5)")
    parser.add_argument("--out-dir", default="", help="Output directory for generated prompt files")
    parser.add_argument("--dry-run", action="store_true", help="Print summary without writing files")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.realpath(__file__))
    knot_root = os.path.realpath(os.path.join(script_dir, "../../.."))
    project_dir = args.project_dir or os.getcwd()

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

    # Dynamic chunk allocation
    chunks = resolve_chunks(project_dir)
    assignments, actual_coverage = calculate_chunk_distribution(chunks, nodes, coverage_ratio)

    active_ring = build_tournament_ring(nodes)

    summary = {
        "run_id": run_id,
        "pack": args.pack,
        "opening_node": active_ring[0],
        "ring": active_ring,
        "target_rounds": args.rounds,
        "nodes": nodes,
        "target_coverage": coverage_ratio,
        "actual_coverage": round(actual_coverage, 2),
        "chunk_count": len(chunks),
        "prompts_generated": {}
    }

    if not args.dry_run:
        os.makedirs(out_dir, exist_ok=True)
        meta_file = os.path.join(out_dir, "meta.json")
        meta_data = {}
        if os.path.exists(meta_file):
            try:
                with open(meta_file) as mf:
                    meta_data = json.load(mf)
            except Exception:
                pass
        meta_data.update({
            "run_id": run_id,
            "pack": args.pack,
            "opening_node": active_ring[0],
            "ring": active_ring,
            "target_rounds": args.rounds,
            "nodes": nodes
        })
        with open(meta_file, "w") as mf:
            json.dump(meta_data, mf, indent=2)

    for node in nodes:
        node_chunks = assignments.get(node, [])
        if args.pack == "tournament":
            prompt_content = scaffold_tournament_prompt(
                node=node,
                nodes=nodes,
                run_id=run_id,
                discussion_url=args.discussion_url,
                db=args.db,
                target_rounds=args.rounds
            )
        else:
            prompt_content = scaffold_prompt(
                node=node,
                base_prompt=base_prompt,
                assigned_chunks=node_chunks,
                run_id=run_id,
                discussion_url=args.discussion_url,
                pack_name=args.pack,
                sidequest_pct=sidequest_pct,
                db=args.db
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
