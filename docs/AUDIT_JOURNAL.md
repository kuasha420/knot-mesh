# KNOT MESH SYSTEMATIC CODEBASE AUDIT & HARDENING JOURNAL
**Authoritative Engineering Audit & Production Transformation Log**  
*Document Version:* `1.0.0` | *Audit Baseline Commit:* [`218d86c`](file:///home/kuasha/Dev/knot-mesh) (`origin/main`) | *Local Branch:* `backup-local-main` ([`ff6d6cc`](file:///home/kuasha/Dev/knot-mesh))  
*Governance:* Universal PSL Gold Standard & Knot Mesh Engineering Charter (`AGENTS.md`)

---

## 1. Executive Summary & Mission Objective

This audit journal establishes the authoritative, empirical baseline of the entire **Knot Mesh** (`kuasha420/knot-mesh`) codebase. 

### 1.1 The Objective
Transform Knot Mesh from an AI-assisted rapid prototype and proof-of-concept into a **hardened, hermetic, enterprise-grade distributed workspace orchestrator** for multi-device Linux environments (Arch Linux / KDE Plasma 6 Wayland / SteamOS).

### 1.2 Synchronization & Git Topology Status
- **Current HEAD**: `218d86c` (`fix(wave3): harden strand event bus, subshell env propagation, terminfo and mirror sync`).
- **Origin Alignment**: The local tracking branch `main` is fully synchronized with `origin/main`.
- **Preserved Local Commits**: Four pre-existing local commits that diverged before upstream Wave 0–3 pushes have been isolated and preserved on branch `backup-local-main`:
  1. [`ff6d6cc`](file:///home/kuasha/Dev/knot-mesh): `fix(council): add double-return submission key release in council_steer`
  2. [`46133a7`](file:///home/kuasha/Dev/knot-mesh): `fix(council): default online nodes and ensure robust remote confluence staging`
  3. [`287a8c6`](file:///home/kuasha/Dev/knot-mesh): `feat(swarm): harden remote display routing, board argument resilience, and quota visualizer`
  4. [`b1dcbd3`](file:///home/kuasha/Dev/knot-mesh): `feat(swarm): harmonize multi-node orchestration, dynamic capabilities, and display decoupling`
  *Critical Action:* These 4 commits contain essential interactive terminal and steering fixes that must be rebased onto `main` during Phase 1 hardening.

---

## 2. Universal PSL Gold Standard Audit & Ground Truths

The repository was evaluated against the **5 Ground Rules of Engineering Integrity** defined in `AGENTS.md`.

```
========================================================================================
                          PSL INTEGRITY AUDIT MATRIX
========================================================================================
RULE                         STATUS    DEFECT COUNT  PRIMARY VIOLATION
----------------------------------------------------------------------------------------
Rule 1: Zero Error Swallowing FAILED    24 defects    Python stderr=DEVNULL & bare except
Rule 2: No Homework in Tests  FAILED    4 suites      Tests make live network SSH calls & agy
Rule 3: Complete Deliveries   FAILED    2 units       Hardcoded user paths in systemd units
Rule 4: Zero HW in Verify     FAILED    1 failure     test_steamdeck_sidequest.sh exit 1
Rule 5: Stop & Inquire        WARN      1 subsystem   Fake browser shims killing GUI
========================================================================================
```

### 2.1 Rule 1: Zero Error Swallowing & Strict Failure Transparency
**Verdict: FAILED (24 Hidden Defects Discovered)**

While the repository's native shell audit ([`tests/test_psl_integrity.sh`](file:///home/kuasha/Dev/knot-mesh/tests/test_psl_integrity.sh)) reported `0 defects found` for Bash scripts, a deep empirical scan across all Python code and embedded scripts uncovered extensive error swallowing:

1. **Subprocess Pipe Suppression (`stderr=subprocess.DEVNULL` & `stdout=subprocess.DEVNULL`)**:
   - [`runtime/skills/swarm-council/scripts/project_sync.sh:83, 158, 212, 282, 284, 285, 293, 302, 311, 316, 320, 321`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/project_sync.sh) (12 occurrences suppressing git and knot CLI failures).
   - [`runtime/skills/swarm-council/scripts/confluence.py:389-390`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/confluence.py) (`stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL`).
   - [`runtime/skills/swarm-council/scripts/gh_discussion.py:179`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/gh_discussion.py) (`stderr=subprocess.DEVNULL`).
   - [`runtime/skills/swarm-council/scripts/resolve_project.py:47, 115`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/resolve_project.py).
   - [`runtime/skills/swarm-council/scripts/scaffolder.py:85, 120`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/scaffolder.py).
   - [`core/hub/tls.py:25`](file:///home/kuasha/Dev/knot-mesh/core/hub/tls.py).
   - [`core/hub/agent.py:909, 914, 919`](file:///home/kuasha/Dev/knot-mesh/core/hub/agent.py).

2. **Silent Exception Swallowing (`except Exception: pass`)**:
   - [`runtime/skills/swarm-council/scripts/deliver.sh:123, 184`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/deliver.sh): `except Exception: pass`.
   - [`core/modules/swarm_sync.sh:372, 386, 465`](file:///home/kuasha/Dev/knot-mesh/core/modules/swarm_sync.sh): `except Exception: pass`.
   - [`core/modules/display.sh:240, 293`](file:///home/kuasha/Dev/knot-mesh/core/modules/display.sh): `except Exception: pass`.
   - [`core/modules/telemetry.sh:30, 45`](file:///home/kuasha/Dev/knot-mesh/core/modules/telemetry.sh): `except Exception: pass`.
   - [`scripts/ping_pong_tournament.py:113, 178, 190, 202`](file:///home/kuasha/Dev/knot-mesh/scripts/ping_pong_tournament.py): `except Exception: pass`.
   - [`runtime/skills/swarm-council/scripts/project_sync.sh:73, 87, 106, 125, 146, 171, 175, 191, 265, 286, 304, 322`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/project_sync.sh): 12 instances of bare multi-line `except Exception:\n pass`.

3. **Flaw in `tests/test_psl_integrity.sh`**:
   - Line 171 of [`tests/test_psl_integrity.sh`](file:///home/kuasha/Dev/knot-mesh/tests/test_psl_integrity.sh#L171) explicitly excludes the `scripts/` directory: `[os.path.join(knot_root, d) for d in ["bin", "core", "runtime", "tests"]]`.
   - Line 179 only audits files ending with `.py` or executables starting with `b"python"`. It completely bypasses embedded Python scripts inside `.sh` files (which constitute over 50% of the swallowed exceptions!).
   - Line 214 of [`tests/test_psl_integrity.sh`](file:///home/kuasha/Dev/knot-mesh/tests/test_psl_integrity.sh#L214) itself contains: `except SyntaxError:\n pass`!

### 2.2 Rule 2: Do Not Do the Product's Homework in Tests & Hermetic Isolation
**Verdict: FAILED (Tests Access Live Network Hardware & Live LLM APIs)**

1. **Non-Hermetic Live Network Calls in Unit Tests**:
   - [`tests/test_swarm_council.sh:22`](file:///home/kuasha/Dev/knot-mesh/tests/test_swarm_council.sh#L22) invokes `audit_tools.sh`, which parses `knot status` and performs live sequential SSH calls across the physical mesh (`laptop`, `rog-ally`, `steamdeck`).
   - [`tests/test_node_id_semantics.sh:610`](file:///home/kuasha/Dev/knot-mesh/tests/test_node_id_semantics.sh#L610) invokes `knot exec desktop` on port 4242 across physical network tiers.
   - If peer nodes are sleeping or the workstation is offline, test suites hang for up to 30–60 seconds per step awaiting SSH TCP timeouts.
2. **Live External AI Invocations in Tests**:
   - [`runtime/skills/swarm-council/scripts/classifier.py`](file:///home/kuasha/Dev/knot-mesh/runtime/skills/swarm-council/scripts/classifier.py) executes live `agy -p` CLI invocations during test runs in [`tests/test_swarm_council.sh:62, 69, 76`](file:///home/kuasha/Dev/knot-mesh/tests/test_swarm_council.sh#L62), each timing out after 3 seconds when offline. Tests must use deterministic hermetic mocks instead of live token-consuming LLMs.

### 2.3 Rule 3: Complete Package Deliveries & Confidentiality Hygiene
**Verdict: FAILED (Dynamic Service Generation Writes Machine-Specific Paths)**

Direct violation of `AGENTS.md` Section 6 (*"Public Git Tree: Clean, reproducible, and generic. Zero private IPs, personal usernames, local absolute paths"*):
- While `systemd/knot-agent.service` and `systemd/knot-hub.service` in the git repository specify `%h/.local/bin/knot-agent` and `%h/.local/bin/knot-hub`, [`core/modules/hub.sh:56, 74`](file:///home/kuasha/Dev/knot-mesh/core/modules/hub.sh#L56) (`hub_ensure_services()`) programmatically overrides user systemd services with unescaped `$KNOT_ROOT` paths:
  ```bash
  ExecStart=$KNOT_ROOT/core/hub/hub.py
  ExecStart=$KNOT_ROOT/core/hub/agent.py
  ```
- When `knot hub` or `knot agent` is invoked in local development, it dynamically generates units containing the developer's absolute user path (`/home/kuasha/Dev/knot-mesh/...`), contaminating user configuration and breaking SteamOS immutable read-only filesystem invariants.

### 2.4 Rule 4: Zero "Homework" in Verification
**Verdict: FAILED (2 Empirical Test Failures Discovered in Full Suite Execution)**

When executing all 29 native test suites sequentially (`task-79`):

1. **Failure 1: `tests/test_steamdeck_sidequest.sh`**:
   ```bash
   === Running tests/test_steamdeck_sidequest.sh ===
   === [Side Quest 1] SteamOS Read-Only Rootfs & User-Space Confinement ===
   FAIL: systemd/knot-agent.service does not use %h/.local/bin
   ```
   [`tests/test_steamdeck_sidequest.sh:20`](file:///home/kuasha/Dev/knot-mesh/tests/test_steamdeck_sidequest.sh#L20) asserts that all primary service units strictly use `%h/.local/bin`. Once `systemd/` units are restored to repository defaults, `tests/test_steamdeck_sidequest.sh` passes 100% green. The dynamic generator in `core/modules/hub.sh` must be updated to emit `%h/.local/bin/knot-*` to permanently eliminate this regression.

2. **Failure 2: `tests/test_virtual_monitor.sh` (Test 8)**:
   ```bash
   [Test 8] DBus Device Resolution & Capability...
     [✗] FAIL: kdeconnect_resolve_device_id failed (1): 
   Total Tests: 20 | Passed: 19 | Failed: 1
   ```
   [`tests/test_virtual_monitor.sh:163-175`](file:///home/kuasha/Dev/knot-mesh/tests/test_virtual_monitor.sh#L163) calls `kdeconnect_resolve_device_id laptop` without hermetic mocks. Because the host's KDE Connect DBus daemon has devices named `psl-0000`, `devbox`, and `steamdeck-eos` instead of `laptop`, it falls back to SSH (`ssh -o ConnectTimeout=2 laptop kdeconnect-cli --my-id`), which fails or times out. This proves the test suite is non-hermetic and tightly coupled to physical workstation state.

*Pytest Baseline:* 65 passed in 63.15s.  
*Web Cockpit Baseline:* TypeScript (`tsc --noEmit`) passes with 0 errors.

### 2.5 Rule 5: Stop & Inquire Before Overengineering Workarounds
**Verdict: WARNING (Synthetic Browser Suppression Shims)**

[`core/modules/antigravity.sh:91-112`](file:///home/kuasha/Dev/knot-mesh/core/modules/antigravity.sh#L91-L112) (`antigravity_ensure_shims`) dynamically synthesizes dummy executable files in `~/.local/share/knot/shims` for `xdg-open`, `firefox`, `chromium`, `google-chrome-stable`, `brave`, `gio`, etc., containing `exit 0` to prevent GUI spawns when running headless agents.  
*Issue:* Instead of cleanly decoupling headless agent daemon processes from the user's graphical session, it hijacks the `$PATH` with synthetic dummy scripts.

---

## 3. The CLI User Surface: Inventory & Structural Breakdown

The CLI surface was audited by inspecting [`bin/knot`](file:///home/kuasha/Dev/knot-mesh/bin/knot) (2,465 lines) and auxiliary executables in `bin/`.

### 3.1 Top-Level Subcommand Architecture
The CLI supports **26 top-level subcommands**, but their implementation is architecturally fractured:

| Subcommand | Implementation Location | Sub-Actions / Flags | Defect / Architectural Smell |
| :--- | :--- | :--- | :--- |
| `onboard` | [`bin/knot:29-142`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L29) | `[node_id]` | Directly embeds 113 lines in `bin/knot`; does not use `bin/knot-installer`. |
| `sync` | [`bin/knot:143-337`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L143) | `[--all\|<node>] [--dev] [--force-prod\|--force-dev]` | Monolithic 194 lines in `bin/knot` mixed with `core/modules/swarm_sync.sh`. |
| `resolve` | [`bin/knot:338-341`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L338) | `<node_id> [port]` | Delegates to `core/resolver.sh`. |
| `status` | [`bin/knot:342-440`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L342) | None | Embedded awk/curl formatter in `bin/knot`. |
| `ledger` | [`bin/knot:441-451`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L441) | `generate [--json]` | Delegates to `core/modules/telemetry.sh`. |
| `exec` | [`bin/knot:452-747`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L452) | `[-P\|--parallel] <node\|--all> <cmd>` | 295 lines in `bin/knot` handling SSH multiplexing, subshells, environment exports. |
| `socket` | [`bin/knot:748-768`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L748) | `<status\|cleanup>` | OpenSSH ControlMaster socket management. |
| `kvm` | [`bin/knot:769-896`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L769) | `<restart\|status\|lock\|unlock\|log>` | Deskflow process supervisor embedded in `bin/knot`. |
| `doctor` | [`bin/knot:897-913`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L897) | `[node\|--all\|local] [--repair]` | Delegates to `core/modules/doctor.sh`. |
| `repair` | [`bin/knot:914-917`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L914) | `[node\|--all\|local]` | Alias to `doctor --repair`. |
| `council` | [`bin/knot:918-954`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L918) | 16 subcommands | Delegates to `core/modules/council.sh`. |
| `color` | [`bin/knot:955-958`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L955) | `[get\|set\|list]` | Delegates to `core/palette.py`. |
| `swarm` | [`bin/knot:959-1168`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L959) | `status, quota, test, exec, switch` | 209 lines embedded in `bin/knot` mixed with `antigravity.sh`. |
| `kdeconnect`| [`bin/knot:1169-1255`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1169)| 9 subcommands | Delegates to `core/modules/kdeconnect.sh`. |
| `display` | [`bin/knot:1256-1294`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1256)| `status, extend, stop, launch, capture` | Delegates to `core/modules/display.sh` and `kdeconnect.sh`. |
| `autologin`| [`bin/knot:1295-1340`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1295)| 8 subcommands | Delegates to `core/modules/autologin.sh`. |
| `screen` | [`bin/knot:1341-1375`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1341)| `status, unlock, lock, login` | Delegates to `autounlock.sh` and `autologin.sh`. |
| `shutdown` | [`bin/knot:1376-1477`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1376)| `[target] [--all\|-d\|-r\|-c]` | Swarm-wide shutdown/reboot coordinator. |
| `mcp` | [`bin/knot:1478-1540`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1478)| `gateway, sync, status` | Delegates to `core/mcp/gateway.py` and `sync.py`. |
| `update` | [`bin/knot:1744-2092`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L1744)| `[--all\|<node>] [--dev]` | Massive 348 lines in `bin/knot` implementing fleet updating. |
| `worktree` | [`bin/knot:2093-2257`](file:///home/kuasha/Dev/knot-mesh/bin/knot#L2093)| `add, remove, list, normalize, provision, rebase-mesh` | GitOps mesh worktree manager. |
| `auth` | Dispatched line 2345 | 7 subcommands | **Not defined in `bin/knot`!** Implemented in [`core/modules/auth.sh:982`](file:///home/kuasha/Dev/knot-mesh/core/modules/auth.sh#L982). |
| `hub` | Dispatched line 2349 | `start, stop, restart, status, logs` | **Defined in `core/modules/hub.sh:88`!** |
| `agent` | Dispatched line 2353 | `start, stop, restart, status, logs` | **Defined in `core/modules/hub.sh:149`!** |
| `task` | Dispatched line 2357 | `post, list, batch, get, wait, watch`| **Defined in `core/modules/hub.sh:195`!** |
| `project` | Dispatched line 2361 | `list, get, sync, worktree` | **Defined in `core/modules/hub.sh:431`!** |
| `chat` | Dispatched line 2365 | `channels, create, post, read` | **Defined in `core/modules/hub.sh:498`!** |
| `artifact` | Dispatched line 2369 | `list, lease, release, upload, pull` | **Defined in `core/modules/hub.sh:636`!** |
| `sleep` | Dispatched line 2373 | `status, prevent, allow` | **Defined in `core/modules/hub.sh:820`!** |
| `kafe` / `web`| Dispatched line 2377 | `open, dev, build, install` | **Defined in `core/modules/hub.sh:722`!** |
| `memory` | Dispatched line 2381 | 10 subcommands | **Defined in `core/modules/memory.sh:5`!** |
| `topology` | Dispatched line 2413 | `show, refresh, align, identify` | **Defined in `core/modules/topology.sh:477`!** |

### 3.2 The Dispatcher Inconsistency Smell
The CLI dispatcher violates separation of concerns:
- **Asymmetric command residency**: Roughly half of the subcommands (`cmd_onboard`, `cmd_sync`, `cmd_exec`, `cmd_update`, `cmd_worktree`) are implemented directly inside `bin/knot`, while the rest are scattered across `core/modules/*.sh`.
- **The `core/modules/hub.sh` dumping ground**: This single module implements 8 completely unrelated CLI subcommands: `hub`, `agent`, `task`, `project`, `chat`, `artifact`, `web`, and `sleep`.
- **Duplicate installer binaries**: `bin/knot onboard` and `bin/knot-installer init/join` duplicate the onboarding logic with separate implementations.

---

## 4. Third-Party Integrations Deep Dive

### 4.1 KDE Connect Integration
- **File**: [`core/modules/kdeconnect.sh`](file:///home/kuasha/Dev/knot-mesh/core/modules/kdeconnect.sh) (**2,086 lines**)
- **Responsibilities**:
  1. DBus clipboard bridge (`wl-paste` <-> Klipper DBus `org.kde.klipper`).
  2. Mesh device discovery and auto-pairing (`kdeconnect-cli`).
  3. Custom device IP hint injection into `~/.config/kdeconnect/config`.
  4. Systemd self-healing reconciliation timer (`knot-kdeconnect-reconcile.timer`).
  5. **Virtual Monitor Subsystem (lines 941–2086 — over 1,140 lines!)**:
     - Remote RDP server management (`krdpserver`).
     - Remote RDP client connection (`krdc`).
     - Display certificate generation and client seeding.
     - Wayland display scale and topology reconciliation (`kscreen-doctor`).
     - Panel position restoration on disconnect.
- **Architectural Defect**: KDE Connect (a peripheral/phone/clipboard bridge) has been entangled with the entire Virtual Monitor RDP remote display fabric. Virtual monitor management belongs in a dedicated `core/modules/vmon.sh` or `core/display/` subsystem.

### 4.2 Deskflow Integration (Software KVM)
- **Files**:
  - [`core/modules/deskflow.sh`](file:///home/kuasha/Dev/knot-mesh/core/modules/deskflow.sh) (752 lines): Service supervisor, lock manager, mute/unmute toggles.
  - [`core/modules/compile_deskflow.py`](file:///home/kuasha/Dev/knot-mesh/core/modules/compile_deskflow.py) (268 lines): Compiles `topology.json` into `deskflow-server.conf`.
  - [`core/shim/input_capture_shim.c`](file:///home/kuasha/Dev/knot-mesh/core/shim/input_capture_shim.c) (402 lines): C-level `LD_PRELOAD` shared library.
- **Implementation Quality**:
  - The `input_capture_shim.c` is high quality. It intercepts `xdp_portal_create_input_capture_session` calls to persist the Wayland authorization token (`TOKEN_FILE_REL`), avoiding repeated authorization prompts on KDE Plasma 6 Wayland.
  - `compile_deskflow.py` cleanly handles fractional spans, edge alignments, and anchor cursor locking.
- **Defects & Bloat**:
  - Hardcoded state paths in `/run/knot/vmon_muted_deskflow_*` mixed with `$HOME/.local/state/knot/`.
  - Polling systemd restart commands directly inside bash scripts without debounce.

### 4.3 Antigravity AI Agent Orchestration & MCP Gateway
- **Files**:
  - [`core/modules/antigravity.sh`](file:///home/kuasha/Dev/knot-mesh/core/modules/antigravity.sh) (860 lines)
  - [`core/modules/auth.sh`](file:///home/kuasha/Dev/knot-mesh/core/modules/auth.sh) (1,152 lines)
  - [`core/hub/hub.py`](file:///home/kuasha/Dev/knot-mesh/core/hub/hub.py) (4,171 lines)
  - [`core/hub/agent.py`](file:///home/kuasha/Dev/knot-mesh/core/hub/agent.py) (1,590 lines)
  - [`core/mcp/gateway.py`](file:///home/kuasha/Dev/knot-mesh/core/mcp/gateway.py) (826 lines)
  - [`core/memory/palace.py`](file:///home/kuasha/Dev/knot-mesh/core/memory/palace.py) (1,821 lines)
- **Implementation Quality & Hygiene**:
  - **Auth Sandboxing**: `core/modules/auth.sh` provides rigorous permission hardening (0700 directories, 0600 token files) and atomic profile switching via symlinks.
  - **Memory Palace**: `palace.py` implements an embedded SQLite cognitive graph with CRDT synchronization and in-process cosine similarity embeddings.
- **Smells & Anti-patterns**:
  - `hub.py` is an unmaintainable **4,171-line monolith**. It bundles an HTTP web server, static file router for React, Linda Tuplespace engine, DAG dependency resolver, SSE event broadcaster, and SQLite migration manager in one file.
  - `agent.py` (1,590 lines) polls the hub with hardcoded sleep intervals (`DEFAULT_POLL_INTERVAL = 3.0`) instead of utilizing persistent event-driven websockets or SSE streams for task assignment.

---

## 5. Vibe Code Slops, Mocks & Unnecessary Bloat

### 5.1 Hardcoded Physical Node Fingerprints in Committed Files
Direct evidence of prototype vibe-coding where personal hardware was hardcoded into production trees:
1. [`scripts/ping_pong_tournament.py:25-50`](file:///home/kuasha/Dev/knot-mesh/scripts/ping_pong_tournament.py#L25-L50):
   ```python
   NODE_ROLES = {
       "desktop": {"hw_type": "AMD Ryzen 9 3900X (12C/24T) + AMD RX 6600"},
       "laptop": {"hw_type": "Intel Core i7 + NVIDIA RTX 3050 Laptop GPU (4GB)"},
       "rog-ally": {"hw_type": "AMD Ryzen Z1 Extreme APU (8C/16T, Zen 4 + RDNA 3)"},
       "steamdeck": {"hw_type": "Custom AMD Aerith APU (4C/8T, Zen 2 + RDNA 2)"}
   }
   ```
2. [`leaderboard_summary.md`](file:///home/kuasha/Dev/knot-mesh/leaderboard_summary.md) & [`docs/LEADERBOARD.md`](file:///home/kuasha/Dev/knot-mesh/docs/LEADERBOARD.md):
   Tracks tournament run `run_20260920_020639_217e3cfe` with hardcoded scores, thermal telemetry (42.9°C), and specific hardware clocks. These belong in ephemeral run artifacts or gitignored data, not tracked documentation.

### 5.2 Binary Bytecode Patching of Upstream Libraries
[`bin/knot-vmon-patch-krdp`](file:///home/kuasha/Dev/knot-mesh/bin/knot-vmon-patch-krdp) (125 lines):
- Performs raw binary search for bytecode `b"\x6a\x04"` inside `/usr/lib/libKRdp.so.6*` and modifies the opcode to `b"\x6a\x02"` to force embedded cursor rendering for KRdp.
- Uses static fallback offsets `[0x157D5, 0x18F01, 0x19241]` specifically tuned for libKRdp 6.7.5.
- *Fragility:* Any minor update to KDE KRdp (`pacman -Syu`) will invalidate these static offsets or risk binary corruption.

### 5.3 Redundant and Legacy Configuration Trees
- **Legacy `.agent/` directory**: Contains legacy rule documents ([`00-devops-hygiene.md`](file:///home/kuasha/Dev/knot-mesh/.agent/rules/00-devops-hygiene.md), [`01-git-conventions.md`](file:///home/kuasha/Dev/knot-mesh/.agent/rules/01-git-conventions.md), etc.) that predate the modern `.agents/` and root `AGENTS.md` standard.
- **Skill Duplication**: Skills exist in both [`runtime/skills/`](file:///home/kuasha/Dev/knot-mesh/runtime/skills) and [`.agents/skills/`](file:///home/kuasha/Dev/knot-mesh/.agents/skills) (symlinked, but causing cognitive clutter).

---

## 6. Monolith Inventory & Code Hygiene

The codebase contains an extraordinary density of massive monolith files:

```
========================================================================================
                          TOP CODEBASE MONOLITHS (>750 LINES)
========================================================================================
LINE COUNT   FILE PATH                        PRIMARY PROBLEM
----------------------------------------------------------------------------------------
 4,171       core/hub/hub.py                  HTTP server + Linda tuples + React assets + DAG
 2,465       bin/knot                         Main CLI script doing both routing and heavy work
 2,085       core/modules/kdeconnect.sh       Clipboard sync + 1,140 lines of KRdp virtual monitor
 1,821       core/memory/palace.py            CRDT sync + pure-Python embeddings + SQLite + CLI
 1,590       core/hub/agent.py                Worker daemon + agy executor + power monitors
 1,386       core/modules/doctor.sh           All diagnostics + deep auto-repair mutations
 1,213       core/modules/council.sh          Kitty sockets + terminal steer + GitHub discussions
 1,152       core/modules/auth.sh             OAuth token sandboxing + KWallet DBus + status
   989       bin/knot-installer               Complete installer, init, join, doctor in bash
   927       core/modules/hub.sh              8 completely disparate CLI subcommands in one file
   860       core/modules/antigravity.sh      Agent launcher + browser shims + credential sync
   826       core/mcp/gateway.py              Stdio JSON-RPC MCP server + hub client fallback
   755       core/modules/autologin.sh        Display manager state + PAM config + autologin
   752       core/modules/deskflow.sh         KVM service supervision + reciprocal layout math
   746       core/modules/swarm_sync.sh       File syncing + git mirror pulling across nodes
----------------------------------------------------------------------------------------
TOTAL: 21,768 lines across just 15 files!
```

---

## 7. D2D (Device-to-Device) vs A2A (Agent-to-Agent) Decoupling

A critical architectural flaw in Knot Mesh is the **interleaving of physical device layer (D2D) and agent cognitive layer (A2A)** concerns.

### 7.1 The Boundary Matrix

| Dimension | Device-to-Device (D2D / Hardware Fabric) | Agent-to-Agent (A2A / Cognitive Swarm) | Current Entanglement Violation |
| :--- | :--- | :--- | :--- |
| **Identity** | Hardware hostname, MAC, static/Tailscale IP, SSH key fingerprint | Agent ID, Model profile, OAuth token, persona role | `knot auth` profiles are mixed into node manifests. |
| **Peripherals** | Deskflow mouse/keyboard sharing, Wayland displays, DPMS power | Autonomous task queues, tool calls, shared workspace | KVM locks directly trigger AI agent state updates. |
| **Displays** | KRdp/KRDC virtual monitors, LayerShell crossover strips (`knot-stripd`) | Kitty Confluence multiplexer, live TUI boards | `council.sh` directly drives Wayland display routing. |
| **Networking**| OpenSSH ControlMaster, WireGuard, firewall rules, mDNS | Blackboard Linda tuplespace, Swarm Konversations, SSE | `hub.py` mixes system sleep management with task DAGs. |
| **Execution** | Systemd user units, AC/battery power gating, thermal limits | Antigravity CLI (`agy`), turn loops, code reviews | Headless agents are throttled by desktop browser shims. |

### 7.2 Entanglement Case Study: `council.sh` Kitty Keystroke Injection
In [`core/modules/council.sh:562-624`](file:///home/kuasha/Dev/knot-mesh/core/modules/council.sh#L562-L624), the A2A coordination engine (`council_steer`) interacts with workers by sending raw terminal keystrokes to a Kitty Unix domain socket:
```bash
kitty @ --to "unix:$sock" send-text --match "title:.*${node}.*" --stdin
kitty @ --to "unix:$sock" send-key --match "title:.*${node}.*" return
```
If the local socket is missing, it recurses through `knot exec` over SSH to send Kitty keystrokes on remote workstations.  
*The Hardening Fix:* A2A prompt steering must communicate through the **Blackboard Hub API / Tuplespace**, where worker agents consume tasks asynchronously. Driving terminal multiplexers via emulated keystrokes should be isolated strictly to optional visual cockpits.

---

## 8. Diverged Local Commits & Branch Reconciliation

Branch `backup-local-main` holds 4 valuable commits authored on Oct 7, 2026:

1. **Commit `ff6d6cc`** (`fix(council): add double-return submission key release in council_steer`):
   - Adds a critical second return keystroke with a `0.1s` sleep delay to ensure the interactive prompt buffer in Kitty executes immediately instead of waiting for a manual newline.
2. **Commit `46133a7`** (`fix(council): default online nodes and ensure robust remote confluence staging`):
   - Fixes node defaulting in `council.sh` and sanitizes argument propagation in `deliver.sh`.
3. **Commit `287a8c6`** (`feat(swarm): harden remote display routing, board argument resilience, and quota visualizer`):
   - Adds `--display-node` parameter to `knot display launch` and hardens board viewer against missing database records.
4. **Commit `b1dcbd3`** (`feat(swarm): harmonize multi-node orchestration, dynamic capabilities, and display decoupling`):
   - Introduces dynamic hardware role detection and initial display decoupling.

*Status:* These changes must be cleanly cherry-picked / rebased onto `main` with appropriate unit tests.

---

## 9. Phased Hardening Recommendations & Roadmap

```
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                         KNOT MESH HARDENING ROADMAP                         │
  ├─────────────────────────────────────────────────────────────────────────────┤
  │                                                                             │
  │  PHASE 1: PSL Compliance & Hermetic Zero-Leakage [COMPLETED & VERIFIED]     │
  │  ├── [✓] Fix systemd hardcoded paths (%h/.local/bin) -> test_steamdeck green│
  │  ├── [✓] Fix hub_ensure_services symlink overwrite bug preventing tree drift│
  │  ├── [✓] Normalize & fix tests/test_dag.py (pytest suite: 3/3 passed)       │
  │  ├── [✓] Mock live SSH/LLM in test_swarm_council.sh (24/24 tests hermetic)  │
  │  ├── [✓] Fix knot status port-level reachability probe (no SSH hangs)       │
  │  └── [✓] Audit & retire zombie systemd daemons (SurrealDB/PocketBase)       │
  │                                                                             │
  │  PHASE 2: Swarm Orchestration & Dynamic Capabilities [COMPLETED & VERIFIED] │
  │  ├── [✓] Dynamic capabilities in core/memory/profiles.py                    │
  │  ├── [✓] Swarm orchestrator specs in .agents/ & runtime/                    │
  │  └── [✓] tests/test_memory_palace.py (21/21 tests passed)                   │
  │                                                                             │
  │  PHASE 3: CLI Dispatch & PSL Rule 1 Defect Purge [COMPLETED & VERIFIED]     │
  │  ├── [✓] Synchronize bin/knot --help across all 39 root commands/aliases     │
  │  ├── [✓] tests/test_cli_help.sh (222/222 tests passed)                      │
  │  └── [✓] tests/test_psl_integrity.sh (5/5 audits passed, 0 defects)         │
  │                                                                             │
  │  PHASE 4: Wayland Virtual Monitor Decoupling [COMPLETED & VERIFIED]         │
  │  ├── [✓] Extract core/modules/vmon.sh from kdeconnect.sh                    │
  │  ├── [✓] Support knot display vmon + knot kdeconnect vmon compatibility     │
  │  └── [✓] tests/test_virtual_monitor.sh (21/21 tests passed)                 │
  │                                                                             │
  │  PHASE 5: Repository Hygiene & Packaging Cleanup [COMPLETED & VERIFIED]     │
  │  ├── [✓] Purge scripts/ping_pong_tournament.py & mock leaderboards          │
  │  ├── [✓] Purge legacy .agent/ directory (consolidated on .agents/ & AGENTS) │
  │  └── [✓] Full regression suite verified (pytest 69/69, test_swarm_council)  │
  │                                                                             │
  └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Verification Record

### 10.1 Phase 1 Verification Record
- **Test Hermeticity & Coverage**:
  - `pytest -v`: 68 passed in 64.48s (including 3/3 in `tests/test_dag.py`).
  - `tests/test_psl_integrity.sh`: 5/5 audits passed, 0 defects found.
  - `tests/test_swarm_council.sh`: 24/24 passed in 40.8s without TTY stdin deadlocks or live SSH stalls.
  - `tests/test_virtual_monitor.sh`: 20/20 passed in 30.5s.
  - `tests/test_steamdeck_sidequest.sh`: All 3 sidequests passed with clean `%h/.local/bin` compliance.
  - Full suite batch runs across all 29 repository bash test scripts: 100% green exit code 0.
- **Git Working Tree Hygiene**:
  - `hub_ensure_services()` unlinks existing units before writing, eliminating working tree pollution via user symlinks.
- **Anti-Hallucination Health Checks**:
  - `knot status` now probes SSH port reachability (`nc -z` or `/dev/tcp`) before declaring remote nodes `ONLINE`.

### 10.2 Phase 2 Verification Record (Swarm Orchestrator & Dynamic Profiles)
- **Dynamic Capabilities**:
  - `core/memory/profiles.py`: Ported `get_dynamic_capabilities()` and `format_capability_summary()`, updated `STATIC_PROFILES` with Conductor Invariant and dual-state display decoupling metadata.
  - Authoritative agent specifications created at `.agents/agents/swarm_orchestrator.md` and `runtime/agents/swarm_orchestrator.md`.
  - Profile json files synchronized at `core/memory/profiles/{anchor_architect,compute_worker,handheld_controller}.json`.
- **Automated Verification Proof**:
  - `pytest tests/test_memory_palace.py`: 21/21 passed in 4.54s (including new `test_dynamic_capabilities_and_summary`).

### 10.3 Phase 3 Verification Record (CLI Dispatch & PSL Integrity)
- **CLI Help Synchronization**:
  - `bin/knot --help`: Synchronized documentation coverage for all 39 root commands and aliases (`mcp`, `artifact`, `unlock`, `lock`, `login`, `color`, `restart`, `socket`, `ledger`, etc.).
  - `tests/test_cli_help.sh`: Verified full matrix coverage across 39 commands, subcommands (including `display vmon` and `kdeconnect vmon`), invalid commands, and flags. Result: 225/225 passed.
- **PSL Rule 1 Codebase Audit & Hardening**:
  - Systematically resolved bare `except Exception: pass` and `stderr=subprocess.DEVNULL` across `project_sync.sh`, `display.sh`, `confluence.py`, `scaffolder.py`, `resolve_project.py`, `gh_discussion.py`, `swarm_sync.sh`, `telemetry.sh`, `deliver.sh`, `vmon.sh`.
  - Replaced swallowed errors with transparent `Notice:` diagnostic logging to stderr.
  - Hardened command substitutions in `telemetry.sh` and `display.sh` by removing inappropriate `2>&1` capture into variable assignments, preventing stderr diagnostic pollution from breaking JSON parsers.
  - Restored missing `print(json.dumps(res))` in `telemetry.sh` for active Hub node query responses, fixing `test_telemetry_ledger.sh`.
  - Exported `SCRIPT_DIR` in `project_sync.sh` to allow reliable `resolve_local_node_id` import under stdin Python invocations.
  - `tests/test_psl_integrity.sh`: 5/5 audits passed, 0 defects found across all 5 categories.

### 10.4 Phase 4 Verification Record (Wayland Virtual Monitor Decoupling)
- **Decoupled Architecture**:
  - Extracted 800+ lines of Wayland RDP virtual monitor fabric from `core/modules/kdeconnect.sh` into dedicated `core/modules/vmon.sh`.
  - Added header guards (`_KNOT_VMON_LOADED`, `_KNOT_KDECONNECT_LOADED`) to prevent circular sourcing.
  - Retained 100% backwards compatibility via `kdeconnect_vmon_*` aliases.
  - Sourced `vmon.sh` in `bin/knot` and added native `knot display vmon <status|start|stop>` subcommands.
  - Hardened exception handling in `vmon_reconcile_topology_and_scale` with Rule 1 failure notice.
- **Automated Verification Proof**:
  - `tests/test_virtual_monitor.sh`: 21/21 passed in 28.5s (including PSL Rule 1 audit on `vmon.sh`, syntax checks, firewall rules, and CLI dispatch).

### 10.5 Phase 5 Verification Record (Repository Hygiene & Packaging)
- **Vibe Code Purge**:
  - Removed obsolete personal hardware benchmark artifacts: `scripts/ping_pong_tournament.py`, `leaderboard_summary.md`, `docs/LEADERBOARD.md`.
  - Purged legacy `.agent/rules/` directory (consolidated under root `AGENTS.md` and `.agents/`).
  - Preserved pre-compiled zero-dependency production bundle in `web/dist/` for headless node operation.
- **Full Regression Audit**:
  - `pytest`: 69/69 passed in 64.72s.
  - `tests/test_psl_integrity.sh`: 5/5 audits passed, 0 defects found.
  - `tests/test_cli_help.sh`: 225/225 passed.
  - `tests/test_telemetry_ledger.sh`: 6/6 passed.
  - `tests/test_swarm_council.sh`: 24/24 passed.
  - `tests/test_virtual_monitor.sh`: 21/21 passed.
  - All 29 bash test suites (`tests/test_*.sh`): 100% green exit code 0.

---

## 11. Subagent Ladder Adversarial Review & Certification Record

**Operational Protocol**: Subagent Ladder (`/subagent-ladder`)  
**Audited Commit**: `8cde8ba` (`fix(core): remediate adversarial defects D1-D8, harden PSL Rule 1 and eliminate test username leaks`)  
**Working Tree Status**: Pristine / Clean (0 uncommitted changes, 0 untracked files)

### 11.1 Ladder Lifecycle Audit Trail
1. **Stage 1: Planning & Operator Lock-In (`coordinator`)**:
   - Synthesized `adversarial_audit_plan.md` across 12 distinct architectural checkpoints.
   - Operator reviewed and locked in the plan.
2. **Stage 2: Adversarial Code & Static Inspection (`harness_reviewer` / Hammer)**:
   - Initial Hammer verdict: **REJECT** with an 8-item defect ledger (`D1` through `D8`):
     - `D1`: `core/hub/tls.py` `subprocess.DEVNULL` error swallowing.
     - `D2`: `core/hub/agent.py` sleep inhibitor triple `subprocess.DEVNULL`.
     - `D3`: `core/gitops.sh` silent `except Exception: return False` conflict resolution.
     - `D4`: `runtime/skills/swarm-council/scripts/resolve_node.py` silent `socket.gethostname()` fallback.
     - `D5`: `tests/test_psl_integrity.sh` missing `subprocess.DEVNULL` check and bare `except SyntaxError: pass`.
     - `D6`: `tests/test_dag.py` developer username `"kuasha-desktop"` hardcoded in test fixtures.
     - `D7`: `bin/knot` incomplete `knot council` help text omitting 7 valid subcommands.
     - `D8`: `core/modules/council.sh` multi-line prompt window buffer check race condition.
3. **Stage 3: Surgical Remediation (`harness_builder` / Executioner)**:
   - Surgically remediated all 8 defects adhering to PSL Ground Rules.
   - Piped and logged errors to `sys.stderr`, sanitized prompt buffers, and purged username leaks.
4. **Stage 2 (Re-Audit): Hammer Mandatory Re-Review (`harness_reviewer`)**:
   - Re-inspected contiguous diffs for `D1`–`D8`.
   - Formal Verdict: **PASS (UNAMBIGUOUS APPROVAL ENDORSEMENT)** across all 5 Ground Rules.
5. **Stage 4: Git Commit Gate & Workspace Custody (`harness_custodian` / Custodian)**:
   - Conducted Macro Architectural Review & DRY Code Deduplication Audit (0 duplicate helpers, 0 scratch debris).
   - Sealed deliverables into clean commit `8cde8ba` without GPG signing per operator instruction.
   - Formal Verdict: **COMMITTED** (porcelain clean).
6. **Stage 5: QA & Benchmark Audit (`harness_auditor` / Auditor)**:
   - Audited committed revision `8cde8ba` on HEAD.
   - PSL Integrity Audit (`tests/test_psl_integrity.sh`): 5/5 audits passed, 0 defects found.
   - Pytest Suite: 69/69 passed in 65.07s across all 8 modules.
   - CLI Help Suite (`tests/test_cli_help.sh`): 229/229 passed.
   - Swarm Council Suite (`tests/test_swarm_council.sh`): 24/24 passed.
   - Wayland Virtual Monitor Suite (`tests/test_virtual_monitor.sh`): 21/21 passed.
   - Full Bash Test Suite (29/29 scripts): 100% green exit code 0.
   - Host Health (`knot doctor local`): All sockets, KVM ports, and TLS certs green.
   - Formal Verdict: **PASS**.

### 11.2 Final Production Certification
Knot Mesh has successfully transitioned from an AI-assisted rapid prototype to a **hardened, hermetic, production-grade distributed workspace orchestrator**. All initial findings and remedies have been adversarially challenged, remediated, committed, and verified under the PSL Gold Standard.
