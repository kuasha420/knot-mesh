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


---

## 12. Systematic CLI Command & Code Surface Rationalization Audit

**Audit Baseline Commit:** `321e6c3` (`origin/main`)  
**Scope:** Exhaustive evaluation of all 40 root commands/aliases in `bin/knot`, supporting shell modules in `core/modules/`, Python daemons in `core/hub/`, cognitive memory modules in `core/memory/`, vision engines in `core/vision/`, and skill scripts in `runtime/skills/`.  
**Governance Standard:** Universal PSL Gold Standard (`AGENTS.md`) — Zero Error Swallowing, Strict Failure Transparency, Hermetic Verification, and Aggressive Elimination of AI Vibe Slop.

---

### 12.1 Executive Summary & Audit Rationale

Prior to undertaking modular architectural decomposition of `bin/knot` (which currently stands at 2,519 lines), an empirical, line-by-line product utility audit was conducted across every CLI command and backing script. Over multiple waves of AI-assisted feature additions, the codebase accumulated:
1. **Speculative "Vibe Code" Bloat:** Features built around anthropomorphic metaphors (e.g. an 1,822-line "Cognitive Memory Palace" with wings, halls, and drawers; a 297-line "Tournament Referee" tracking cognitive volleys, aces, and power smashes; and computer vision models running 3D RGB color histogram matching on physical desk photographs to infer display positions).
2. **Namespace Pollution & Triplicate Dispatchers:** Root-level aliases (`knot unlock`, `knot lock`, `knot login`, `knot restart`, `knot reboot`, `knot quota`, `knot power`) cluttering the root CLI help alongside their parent commands (`knot screen`, `knot autologin`, `knot kvm`, `knot shutdown`, `knot swarm`, `knot sleep`).
3. **Dead Compatibility Shims & Hollow Stubs:** Leftover SurrealQL shims (`execute_surreal`) and PocketBase replacements in `core/memory/palace.py`, uncalled artifact leases in `core/hub/hub.py`, phantom options in help strings (`knot artifact upload/pull` that were never implemented), and hollow stubs (`knot project sync` which curls `/projects` and does nothing).
4. **Architectural Demarcation:** The core identity of Knot Mesh is a **hardened, hermetic distributed workspace fabric across Arch Linux, KDE Plasma 6 Wayland, and SteamOS** (Deskflow KVM, Wayland virtual monitor extension, OpenSSH ControlMaster multiplexing, KDE Connect clipboard/file fabric, GitOps worktree landing arbiter, and Linda Tuplespace task distribution). Everything outside this boundary is candidate for pruning or consolidation.

---

### 12.2 Exhaustive 40-Command Utility & Redundancy Matrix

The table below catalogs every root command, alias, and subcommand in `bin/knot` evaluated against implementation completeness, product relevance, architectural redundancy, and triage bucket.

| # | Command / Alias | Subcommands / Flags | Backing File(s) | Implementation State | Core Mission Relevance | Redundancy & Overlap | Triage Classification |
|---|---|---|---|---|---|---|---|
| **1** | `update` | `--all`, `<node_id>`, `--dev`, `--force-prod`, `--force-dev`, `-f` | `bin/knot:cmd_update`, `cmd_update_dev` | **Complete**: Production GitHub release downloading, fast-forward git pulls across fleet, symlink healing, and safe service restarts. | **CORE**: Essential software update distribution mechanism across heterogeneous nodes. | None. Canonical updater. | **[KEEP - CORE]** |
| **2** | `topology` | `show`, `align-internal`, `identify`, `refresh` (`--photo`), `guide` | `core/modules/topology.sh`, `core/vision/engine.py` | **Mixed**: `show` (ASCII map) and `align-internal` (ROG Ally layout) are robust. `refresh --photo` calls complex CV heuristic / Swarm AI. | **PARTIAL**: 2D ASCII spatial map and output alignment are core to KVM; photo-based computer vision is speculative vibe bloat. | `topology refresh --photo` overlaps nothing but introduces large PIL/numpy dependency footprint. | **[CONSOLIDATE]** / **[HARDEN]**<br>*(Keep show/align; prune photo CV)* |
| **3** | `onboard` | `[node_id]` | `bin/knot:cmd_onboard`, `core/modules/ssh.sh`, `core/modules/firewall.sh`, etc. | **Complete**: Automated SSH key generation, firewall rules, passwordless sudo, systemd guard, mDNS, autologin DM, manifest creation. | **CORE**: Single-command turnkey node enrollment into the active mesh. | None. Primary node enrollment path. | **[KEEP - CORE]** |
| **4** | `sync` | `--all`, `<node_id>`, `--dev`, `--mirrors`, `--terminfo`, `--force-prod` | `bin/knot:cmd_sync`, `core/modules/swarm_sync.sh` | **Complete**: Synchronizes SSH keys, client configs, Deskflow configs, KDE Connect pairings, pacman mirrors, terminfo definitions. | **CORE**: Foundational cluster-wide configuration and key synchronization engine. | Minor overlap with `council sync` (which runs `project_sync.sh`). | **[KEEP - CORE]** |
| **5** | `resolve` | `<node_id> [port]` | `core/resolver.sh` | **Complete**: Multi-tiered IP resolution engine (Tailscale 100.x -> Local Subnet ARP -> mDNS .local -> cached IP hint). | **CORE**: Universal inter-node address resolution primitive used by every remote command. | None. Foundation for all networking. | **[KEEP - CORE]** |
| **6** | `status` | *(none)* | `bin/knot:cmd_status` | **Complete**: Probes all registered nodes, detects online state, measures ping latency, probes SSH reachability, checks KVM port :24800. | **CORE**: Indispensable live cluster observability and health dashboard. | None. Primary status view. | **[KEEP - CORE]** |
| **7** | `exec` | `[-P]`, `[--timeout]`, `[-t]`, `<target\|--all>`, `<command>` | `bin/knot:cmd_exec` | **Complete**: Sequential and parallel (`-P`) remote execution with environment propagation (terminfo, PATH, node ID, hub URL). | **CORE**: Fundamental remote command execution primitive across the mesh. | `knot swarm exec` wraps this command redundantly. | **[KEEP - CORE]** |
| **8** | `kvm` | `restart`, `status`, `lock`, `unlock`, `lock-toggle` | `bin/knot:cmd_kvm`, `core/modules/deskflow.sh` | **Complete**: Full Deskflow server/client daemon management, boundary cursor lock toggling, and socket connection auditing. | **CORE**: Primary software KVM mouse/keyboard sharing capability. | Top-level `knot restart` is a redundant wrapper around `knot kvm restart`. | **[KEEP - CORE]** |
| **9** | `screen` | `status`, `status-raw`, `unlock`, `lock`, `login` | `bin/knot:cmd_screen`, `core/modules/autounlock.sh` | **Complete**: Queries and controls graphical session lock/unlock via loginctl, kscreenlocker, and qdbus. | **CORE**: Essential for remote display wake and unlock across headless Wayland nodes. | Shadowed by top-level aliases `unlock`, `lock`, `login`. | **[CONSOLIDATE]**<br>*(Make canonical home for screen state)* |
| **10** | `unlock` | `[node\|--all\|local]` | `core/modules/autounlock.sh:screen_unlock` | **Complete**: Directly forwards to `screen_unlock`. | **REDUNDANT**: Convenience shortcut that pollutes the root CLI namespace. | 100% duplicate of `knot screen unlock`. | **[CONSOLIDATE]**<br>*(Merge into `knot screen unlock`)* |
| **11** | `lock` | `[node\|--all\|local]` | `core/modules/autounlock.sh:screen_lock` | **Complete**: Directly forwards to `screen_lock`. | **REDUNDANT**: Convenience shortcut that pollutes the root CLI namespace. | 100% duplicate of `knot screen lock`. | **[CONSOLIDATE]**<br>*(Merge into `knot screen lock`)* |
| **12** | `login` | `[node\|--all\|local]` | `core/modules/autounlock.sh:screen_login` | **Complete**: Directly forwards to `screen_login` -> `autologin_execute_local`. | **REDUNDANT**: Convenience shortcut duplicating display manager autologin. | Triplicate of `knot screen login` and `knot autologin local`. | **[CONSOLIDATE]**<br>*(Merge into `knot autologin local`)* |
| **13** | `autologin` | `status`, `check`, `doctor`, `migrate-dm`, `local`, `reconcile`, `purge-stale`, `configure-timer`, `fix-kwallet` | `bin/knot:cmd_autologin`, `core/modules/autologin.sh` | **Complete**: Display manager setup (SDDM, LightDM, GDM), PAM kwallet integration, and systemd reconciler. | **CORE**: Crucial for handheld and headless nodes rebooting directly into Wayland sessions without passwords. | Duplicated by `knot login` and `knot screen login`. | **[KEEP - CORE]**<br>*(Canonical home for DM login)* |
| **14** | `kdeconnect` | `status`, `sync`, `pair`, `reconcile`, `vmon`, `share`, `sync-clipboard`, `test-clipboard`, `prune-stale` | `bin/knot:cmd_kdeconnect`, `core/modules/kdeconnect.sh` | **Complete**: Inter-device pairing, cross-node clipboard synchronization, and file sharing. | **CORE**: Primary peer-to-peer data and clipboard sharing mechanism. | `knot kdeconnect vmon` is a 100% duplicate alias of `knot display vmon`. | **[CONSOLIDATE]**<br>*(Retain KDE Connect; move vmon to display)* |
| **15** | `display` | `status`, `extend`, `stop`, `vmon`, `toggle-kvm`, `launch`, `capture-fleet` | `bin/knot:cmd_display`, `core/modules/display.sh`, `core/modules/vmon.sh` | **Complete**: Virtual monitor scaling, KRDP headless Wayland session lifecycle, application launching, and screen captures. | **CORE**: Enables using portable nodes (ROG Ally, Steam Deck, Laptop) as secondary Wayland monitors. | `display vmon` duplicates `kdeconnect vmon`; `display toggle-kvm` duplicates `kvm lock-toggle`. | **[HARDEN]**<br>*(Canonical home for virtual display routing)* |
| **16** | `council` | `start`, `resume`, `status`, `reply`, `list`, `attach`, `reconcile`, `copy`, `clean`, `kill`, `steer`, `challenge`, `db`, `board`, `heal`, `audit`, `sync` | `core/modules/council.sh`, `runtime/skills/swarm-council/scripts/` | **Complete**: Out-of-band multi-agent coordination via GitHub Discussions, Kitty Confluence spatial multiplexer, curses board. | **CORE / SPECIALIZED**: Essential out-of-band collaboration mechanism for autonomous SWE campaigns. | Contains `tournament_referee.py` (vibe slop); `council sync` overlaps `project_sync.sh`. | **[HARDEN]**<br>*(Purge esports referee; harden council core)* |
| **17** | `swarm` | `status`, `quota`, `auth`, `color`, `test`, `exec`, `wave`, `switch` | `bin/knot:cmd_swarm`, `core/modules/antigravity.sh` | **Bloated Umbrella**: Hub for Antigravity AI agents, active swarm switching, and multi-node sweeps. | **HIGH CONFUSION**: Acted as a catch-all dumping ground for commands that already exist at root level. | `swarm quota` -> `knot quota`; `swarm auth` -> `knot auth`; `swarm color` -> `knot color`; `swarm exec` -> `knot exec`. | **[CONSOLIDATE]**<br>*(Strip redundant switches; keep switch/use)* |
| **18** | `color` / `palette` | `[get\|set\|list]` | `bin/knot:cmd_color`, `core/palette.py` | **Complete**: Mathematical node color derivation based on Golden Angle and WCAG contrast against dark terminal canvas. | **UTILITY**: Visual terminal identification across multiplexed Kitty strands. | Exact duplicate in `knot swarm color`. | **[KEEP - CORE]**<br>*(Canonical command; drop swarm color)* |
| **19** | `quota` | `[node\|--all]`, `watch`, `live` | `core/modules/antigravity.sh:antigravity_swarm_quota`, `core/hub/limit_visualizer.py` | **Complete**: Live curses TUI and tabular visualizer for Antigravity 5h and weekly model quota limits across nodes. | **UTILITY**: Essential operational tool for preventing LLM quota exhaustion during distributed campaigns. | Top-level alias delegating to `knot swarm quota`. | **[KEEP - CORE]**<br>*(Promote to canonical command)* |
| **20** | `auth` | `login`, `import`, `list`, `status`, `switch`, `remove`, `test-lock`, `sync`, `token` | `core/modules/auth.sh` (1,153 lines) | **Complete**: Multi-tenant profile sandboxing, D-Bus SecretService probing, OAuth token linking, headless terminal flows (Issue #60). | **CORE**: Hardened production security module for multi-account management across headless Linux devices. | `knot swarm auth` is a redundant wrapper. | **[KEEP - CORE]**<br>*(Canonical authentication tool)* |
| **21** | `hub` | `start`, `stop`, `restart`, `status`, `logs` | `bin/knot:cmd_hub`, `core/modules/hub.sh`, `core/hub/hub.py` | **Complete**: Systemd user daemon management for Blackboard Hub HTTP/SSE server (:4242). | **CORE**: Central cluster coordination and state broadcast authority. | None. Daemon controller. | **[KEEP - CORE]** |
| **22** | `agent` | `start`, `stop`, `restart`, `status`, `logs` | `bin/knot:cmd_agent`, `core/modules/hub.sh`, `core/hub/agent.py` | **Complete**: Systemd user daemon management for Worker Agent background process. | **CORE**: Distributed task executor claiming and executing Tuplespace tasks across strands. | None. Daemon controller. | **[KEEP - CORE]** |
| **23** | `task` | `post`, `list`, `batch`, `get`, `wait`, `watch` | `bin/knot:cmd_task`, `core/modules/hub.sh` | **Complete**: Linda Tuplespace client interacting with `hub.py` (posting prompts, claiming tasks, polling, SSE streaming). | **CORE**: Core distributed task distribution engine for autonomous agent swarms. | None. Client interface to Hub. | **[KEEP - CORE]** |
| **24** | `project` | `list`, `get`, `sync`, `worktree` | `bin/knot:cmd_project`, `core/modules/hub.sh` | **Incomplete / Stub**: `list`/`get` query `~/.gemini/config/projects`. `sync` is a dummy stub (counts items, does no sync). `worktree` forwards to `knot worktree`. | **LOW**: Minimal utility; `project worktree` is redundant; `project sync` is hollow. Real sync is in `runtime/skills/swarm-council/scripts/project_sync.sh`. | Directly duplicates `knot worktree`. | **[CONSOLIDATE]**<br>*(Merge into `knot worktree`; purge stubs)* |
| **25** | `worktree` | `add`, `remove`, `list`, `normalize`, `provision`, `rebase-mesh` | `bin/knot:cmd_worktree`, `core/gitops.sh` | **Complete**: Parallel git worktree lifecycle manager, path normalization across home directories, mesh provisioning, and rebasing. | **CORE**: Foundational parallel GitOps workspace engine for multi-node SWE development. | Duplicated by `knot project worktree`. | **[KEEP - CORE]** |
| **26** | `chat` | `channels`, `create`, `post`, `read` | `bin/knot:cmd_chat`, `core/modules/hub.sh`, `core/hub/hub.py` | **Speculative Prototype**: "Swarm Konversations" IRC-style message posting to `hub.py`. | **DEAD / VIBE SLOP**: Disconnected from actual development workflows (which use GitHub Discussions via `knot council` or stdio). Zero functional tests. | Competes with `knot council` without providing GitHub persistence or terminal multiplexing. | **[PURGE - DEAD/SLOP]**<br>*(Immediate deletion)* |
| **27** | `artifact` | `list`, `lock`, `release` *(help claims `upload/pull` which do not exist)* | `bin/knot:cmd_artifact`, `core/modules/hub.sh`, `core/hub/hub.py` | **Abandoned Prototype**: In-memory string lease manager. Help text advertises phantom `upload` and `pull` options. | **DEAD / VIBE SLOP**: Unused POC. Git worktrees (`knot worktree`) already provide actual filesystem isolation. Zero functional tests. | Duplicated by `palace.py`'s embedded "artifact closet" (`artifact-put`/`get`). | **[PURGE - DEAD/SLOP]**<br>*(Immediate deletion)* |
| **28** | `sleep` | `status`, `prevent [mins]`, `allow` | `bin/knot:cmd_sleep`, `core/modules/hub.sh`, `core/hub/hub.py` | **Complete**: Swarm-wide power state monitoring and AC sleep prevention enforcement (`/swarm/wake`, `/swarm/sleep-allow`). | **CORE**: Prevents laptops and handheld consoles from sleeping during long compilation/testing sweeps. | Aliased by `knot power`. | **[KEEP - CORE]** |
| **29** | `power` | `status`, `prevent [mins]`, `allow` | `core/modules/hub.sh:cmd_sleep` | **Complete**: Exact alias of `knot sleep`. | **REDUNDANT**: Duplicate root dispatcher entry. | 100% duplicate of `knot sleep`. | **[CONSOLIDATE]**<br>*(Retain as alias or document under `sleep`)* |
| **30** | `kafe` | `open`, `desktop`, `build-desktop`, `dev`, `build`, `install`, `typecheck` | `bin/knot:cmd_web`, `core/modules/hub.sh`, `web/` | **Complete**: Launcher and build orchestrator for React 19 + Vite + Tailwind + `@assistant-ui` cockpit. | **UTILITY**: Web-based operational cockpit and Blackboard visualization UI. | Triplicate aliases: `knot kafe`, `knot web`, `knot cockpit`. | **[CONSOLIDATE]**<br>*(Consolidate under single canonical name)* |
| **31** | `web` | `dev`, `build`, `install` | `bin/knot:cmd_web` | **Complete**: Build and dev tooling for `web/`. | **UTILITY**: Web build interface. | Triplicate alias of `knot kafe`. | **[CONSOLIDATE]**<br>*(Merge with `knot kafe`)* |
| **32** | `memory` | `store`, `recall`, `map`, `promote`, `relate`, `artifact-put`, `artifact-get`, `profile`, `test` | `bin/knot:cmd_memory`, `core/modules/memory.sh`, `core/memory/palace.py` (1,822 lines), `core/memory/profiles.py` | **Vibe Code Overhaul**: "Cognitive Memory Palace" graph with wings, halls, drawers, pure-Python cosine similarity, and legacy SurrealDB shims. | **VIBE BLOAT**: Knot is a distributed Linux workspace fabric, not a cognitive mind graph. MCP gateway pruned memory tools in Issue #41. | Contains dead `execute_surreal` shims, duplicate artifact closet, and duplicate node profiles. | **[PURGE - DEAD/SLOP]**<br>*(Eliminate palace bloat & dead shims)* |
| **33** | `doctor` | `local`, `<node_id>`, `--all`, `--json` | `bin/knot:cmd_doctor`, `core/modules/doctor.sh` (1,500+ lines) | **Complete**: Comprehensive diagnostic suite checking SSH keys, permissions, firewall ports, systemd units, KVM, Wayland, TLS certs. | **CORE**: Indispensable cluster diagnostic and pre-flight verification tool. | None. Essential diagnostic suite. | **[KEEP - CORE]** |
| **34** | `repair` | `[node\|--all]` | `bin/knot:cmd_repair`, `core/modules/doctor.sh:doctor_repair` | **Complete**: Auto-repair engine: re-establishes dropped KVM links, cleans stale sockets, restarts failed services. | **CORE**: Indispensable automated self-healing and recovery mechanism. | None. Essential repair command. | **[KEEP - CORE]** |
| **35** | `restart` | `[kvm]` | `bin/knot:2437` | **Incomplete Wrapper**: Root command that only accepts `kvm` and forwards to `cmd_kvm restart`. | **REDUNDANT**: Pointless single-purpose root command. | 100% duplicate of `knot kvm restart`. | **[CONSOLIDATE]**<br>*(Remove root command; use `knot kvm restart`)* |
| **36** | `shutdown` | `[target]`, `-d`, `-r`, `-c`, `-s`, `-m`, `-f` | `bin/knot:cmd_shutdown`, `core/modules/shutdown.sh` | **Complete**: Graceful swarm-wide poweroff/reboot engine with delay timers, cancellation, broadcast wall messages, confirmation gates. | **CORE**: Essential cluster-wide physical power management. | Aliased by `knot reboot`. | **[KEEP - CORE]** |
| **37** | `reboot` | `[target]`, `-d`, `-c`, `-m`, `-f` | `bin/knot:cmd_shutdown --reboot` | **Complete**: Convenience alias for `knot shutdown --reboot`. | **REDUNDANT**: Duplicate root dispatcher entry. | 100% duplicate of `knot shutdown --reboot`. | **[CONSOLIDATE]**<br>*(Consolidate into `knot shutdown --reboot`)* |
| **38** | `mcp` | `gateway`, `sync`, `status`, `test`, `list` | `bin/knot:cmd_mcp`, `core/mcp/gateway.py`, `core/mcp/sync.py` | **Complete**: Zero-dependency stdio Model Context Protocol (MCP) server exposing 4 canonical tools to LLM coding agents. | **CORE**: Primary standard interface allowing AI coding agents to control Knot Mesh safely without shell escape hazards. | None. Core agent interface. | **[KEEP - CORE]** |
| **39** | `socket` | `status`, `cleanup` | `bin/knot:cmd_socket`, `core/modules/ssh.sh` | **Complete**: OpenSSH ControlMaster multiplexing socket manager (inspects `~/.ssh/sockets/`, purges stale/orphaned sockets). | **CORE**: Infrastructure foundation ensuring zero-latency sub-second SSH execution across nodes. | None. Essential SSH socket management. | **[KEEP - CORE]** |
| **40** | `ledger` | `generate`, `[--json]`, `[--swarm]` | `bin/knot:cmd_ledger`, `core/modules/telemetry.sh` | **Complete**: Generates deterministic machine-readable JSON/text cluster health, socket, and node state telemetry. | **CORE**: Critical for autonomous agent auditability and telemetry synchronization. | None. Telemetry generator. | **[KEEP - CORE]** |

---

### 12.3 Triage Classification Summary & Breakdown

Based on empirical audit, all 40 commands and sub-dispatchers break down into 4 clear buckets:

```
========================================================================================
                       KNOT CLI RATIONALIZATION TRIAGE MATRIX
========================================================================================
BUCKET                 COUNT  COMMANDS / SUBSYSTEMS
----------------------------------------------------------------------------------------
[KEEP - CORE]          20     update, onboard, sync, resolve, status, exec, kvm, 
                              autologin, color, quota, auth, hub, agent, task, 
                              worktree, sleep, doctor, repair, shutdown, mcp, 
                              socket, ledger
[CONSOLIDATE]          12     screen (merge unlock/lock/login), unlock, lock, login,
                              kdeconnect (consolidate vmon), swarm (strip auth/quota/color),
                              power (merge sleep), kafe/web (merge cockpit), 
                              restart (merge kvm), reboot (merge shutdown),
                              project (merge worktree)
[HARDEN]               3      display (canonical vmon & headless routing), 
                              council (purge tournament slop; streamline discussion),
                              topology (retain ASCII 2D spatial layout; purge photo CV)
[PURGE - DEAD/SLOP]    5      chat (Swarm Konversations), artifact (abandoned leases),
                              memory (Cognitive Memory Palace & SurrealQL shims),
                              tournament_referee (esports ping pong scoring),
                              core/vision (heuristic desk photo detector)
========================================================================================
TOTAL AUDITED:         40 root dispatchers and subsystem backings
========================================================================================
```

---

### 12.4 Backing Architecture & Dead Code Deep Dive

Beyond the root CLI dispatcher, every supporting file in `core/modules/`, `core/hub/`, `core/memory/`, `core/vision/`, `web/`, and `runtime/skills/` was audited line-by-line to uncover hidden couplings, dead code, unused endpoints, and test suite dependencies.

#### 12.4.1 The Esports Ping Pong Slop (`tournament_referee.py` & `scaffolder.py`)
- **File:** `runtime/skills/swarm-council/scripts/tournament_referee.py` (297 lines)
- **Evidence:** While Phase 5 purged personal benchmark scripts (`scripts/ping_pong_tournament.py`), `tournament_referee.py` was left behind in the council skill. It contains functions like `calculate_volley_points()` (evaluating "aces", "power smashes", "elegance bonuses", "faults", and "streak multipliers") and models like `NodeScore` and `TournamentState`.
- **Cross-References & Test Coupling:**
  1. `runtime/skills/swarm-council/scripts/scaffolder.py`: line 211 (`build_tournament_ring`), line 219 (`scaffold_tournament_prompt`), line 303 (`Pack: tournament`).
  2. `tests/test_council_steer.sh`:
     - Step 3 (lines 45–58): Executes `scaffolder.py --pack tournament --dry-run` and asserts pack name is `"tournament"`.
     - Step 4 (lines 60–80): Imports and asserts `calculate_volley_points` and `verify_proof` from `tournament_referee.py`.
- **Verdict & Impact:** Pure AI vibe slop. Deleting `tournament_referee.py` and removing `--pack tournament` from `scaffolder.py` requires atomically refactoring **both Step 3 and Step 4** of `tests/test_council_steer.sh` to maintain a green test suite.

#### 12.4.2 The Cognitive Memory Palace Bloat, Dead Shims & Pytest Coupling (`palace.py` & `profiles.py`)
- **Files:** `core/memory/palace.py` (1,822 lines), `core/memory/profiles.py` (177 lines), `core/modules/memory.sh` (8 lines)
- **Evidence:** 
  1. `core/memory/palace.py` line 1523 contains `execute_surreal(self, sql: str)`, an empty dead shim returning `[{"status": "OK", "result": []}]` from a legacy SurrealDB migration.
  2. Line 1023 defines an "Embedded Artifact Closet (Replaces PocketBase)", duplicating file storage.
  3. The entire "Memory Palace" structure (organizing data into "wings", "halls", and "drawers" formatted with castle emojis 🏰 🏛️ 🏢 📂) is speculative vibe architecture.
  4. In Issue #41, `core/mcp/gateway.py` was explicitly pruned to 4 lean tools, eliminating memory tools. However, **`core/mcp/gateway.py` lines 28–33 and line 111 still import and instantiate `MemoryPalaceClient`** (`self.memory = memory_client or MemoryPalaceClient()`). While `self.memory` is dead and uncalled, deleting `palace.py` without cleaning up `gateway.py` will cause an unhandled `ImportError` on `knot mcp gateway`!
  5. `core/memory/profiles.py` duplicates `.agents/skills/hardware-profiles/SKILL.md` verbatim.
  6. **Write-Only Sink in `agent.py`:** `core/hub/agent.py` lines 1404 and 1492 spawn background daemon threads calling `palace.ingest_antigravity_transcript()`, storing records into "wing: swarm_sessions". An exhaustive audit confirms that **zero readers or query callers exist anywhere in Knot Mesh** for this data. It is a 100% write-only sink.
- **Pytest Coupling Hazard:**
  - `tests/test_memory_palace.py` contains **21 pytest tests** across 494 lines (testing SQLite init, CRDT schema, in-process cosine similarity, dual-pool memory, and hardware profiles).
  - These 21 tests constitute **30.4% of the entire 69-assertion pytest test suite**.
- **Verdict & Safe Migration:** Anthropomorphic palace bloat and dead shims must be excised. `core/mcp/gateway.py` must be cleaned up to drop the dead import. The 21 tests in `tests/test_memory_palace.py` must be adapted to verify the lean storage model or retired in sync with the module.

#### 12.4.3 Speculative Desk Photo Computer Vision & Web Radar Modal (`core/vision/`)
- **Files:** `core/vision/engine.py` (67 lines), `core/vision/offline_detector.py` (510 lines), `core/vision/swarm_detector.py` (280 lines), `core/vision/display_overlay.py` (170 lines)
- **Evidence:** Implements heuristic computer vision algorithms (PIL edge detection, bounding box normalization, 3D RGB color histogram matching against `/tmp/knot_screens/`) to deduce physical screen positions from photographs. `display_overlay.py` introduces a heavyweight PyQt6 GUI dependency.
- **Cross-References & Web Coupling:**
  1. Tested only by synthetic unit tests in `tests/test_vision_engine.py` (4 tests using synthetic PIL rectangles).
  2. `web/src/components/radar/PhotoTopologyModal.tsx` is an active 668-line React component in the web cockpit (`knot kafe`) calling `/topology/analyze-photo` (line 116) and `/topology/identify` (line 89).
  3. Real users configure spatial topology deterministically via `knot topology align-internal` or declarative `topology.json`.
- **Verdict:** Speculative AI vibe feature. Adds substantial maintenance surface, cognitive overhead, and heavy dependencies (PIL, numpy, PyQt6). Purging requires removing `core/vision/`, updating `core/modules/topology.sh`, retiring `tests/test_vision_engine.py`, and removing the modal from `web/`.

#### 12.4.4 Chat & Artifact Subsystems: Agent Daemon & Web Cockpit Couplings
- **Files:** `core/modules/hub.sh` (`cmd_chat: lines 501-637`, `cmd_artifact: lines 639-723`, `cmd_project sync: lines 479-486`), `core/hub/hub.py`, `core/hub/agent.py`, `web/`
- **Evidence & Hidden Couplings:**
  1. `knot chat` ("Swarm Konversations"): 137 lines of shell code managing IRC-like chat channels (`/chat/conversations`, `/chat/messages`).
     - **CRITICAL DAEMON COUPLING:** `core/hub/agent.py` lines 1228–1433 runs an active background daemon thread `chat_mention_worker(self)` (`chat_thread = threading.Thread(target=self.chat_mention_worker, daemon=True)` started at line 1432). Every 4 seconds (line 1236: `self.stop_event.wait(4.0)`), it issues an HTTP request to `f"{self.hub.hub_url}/chat/messages?conv_id=all&limit=20"`!
     - **Failure Mode:** If `/chat/*` is deleted from `hub.py` without stopping `chat_mention_worker` in `agent.py`, the worker will throw continuous HTTP 404 errors every 4 seconds and flood stderr in an infinite loop.
     - **Web Cockpit Usage:** `web/src/components/chat/SwarmChat.tsx` and `web/src/hooks/useKnotChatRuntime.ts` provide a full chat interface in the web cockpit.
  2. `knot artifact`: 85 lines of shell code managing in-memory string locks (`/artifacts/leases`, `/artifacts/lock`, `/artifacts/release`).
     - Help text advertises phantom `upload` and `pull` options that do not exist.
     - `web/src/components/artifacts/ArtifactVault.tsx` provides a "3-State Atomic Artifact Lease Vault" UI calling `/artifacts/*` via `web/src/hooks/useKnotSSE.ts`.
  3. `knot project sync`: 8 lines of shell code that curls `/projects`, prints item count, and does zero actual synchronization.
- **Verdict & Safe Migration:** While the CLI entrypoints (`knot chat`, `knot artifact`) and hollow stubs (`knot project sync`) can be immediately pruned from `bin/knot`, removing backend `/chat/*` and `/artifacts/*` from `hub.py` requires **atomically excising `chat_mention_worker` from `agent.py` and retiring the corresponding tabs from `web/`**.

#### 12.4.5 Namespace Pollution & Legacy Script Delegation
- **Files:** `bin/knot` (lines 2349–2364, 2381–2388, 2417–2424, 2437–2456), `core/modules/antigravity.sh`
- **Evidence:** 
  1. Root convenience aliases cluttering the CLI: `unlock`, `lock`, `login`, `restart`, `reboot`, `power`, `quota`.
  2. `knot swarm auth` vs `knot auth`: `knot auth` dispatches to `core/modules/auth.sh` (1,153 lines, hardened multi-tenant architecture), while `knot swarm auth` dispatches directly to `antigravity_swarm_auth` in `core/modules/antigravity.sh` (124 lines, legacy procedural SSH script).
  3. `tests/test_cli_help.sh` tests all 39 root subcommands and 18 nested commands across 229 assertions.
- **Verdict:** Consolidate aliases into canonical commands (`knot screen`, `knot autologin`, `knot kvm`, `knot shutdown`, `knot sleep`, `knot quota`, `knot auth`). Update `tests/test_cli_help.sh` to match the canonical palette.

---

### 12.5 Atomic Pruning & Consolidation Action Plan

To execute this pruning safely and deterministically without breaking mesh invariants or test suites, the work is organized into 4 atomic phases:

#### Phase 1: Dead Code & Vibe Slop Elimination (Immediate Excision)
1. **Purge Esports Referee & Scaffolder Tournament Packs:**
   - Delete `runtime/skills/swarm-council/scripts/tournament_referee.py`.
   - In `runtime/skills/swarm-council/scripts/scaffolder.py`: remove `build_tournament_ring`, `scaffold_tournament_prompt`, and `--pack tournament`.
   - In `tests/test_council_steer.sh`: refactor Step 3 (replace tournament pack check) and Step 4 (replace points calculation with core council challenge/steering verification).
2. **Purge Desk Photo CV Engine:**
   - Delete `core/vision/` directory (`engine.py`, `offline_detector.py`, `swarm_detector.py`, `display_overlay.py`).
   - In `core/modules/topology.sh`: remove `topology_refresh` photo handling and `topology_identify` overlay execution. Retain `show`, `align-internal`, and `guide`.
   - In `core/hub/hub.py`: remove `/topology/analyze-photo` and `/topology/identify` routes.
   - Remove `tests/test_vision_engine.py` (4 tests).
   - In `web/`: remove `PhotoTopologyModal.tsx` and decouple radar trigger.
3. **Purge Cognitive Memory Palace & Clean Up MCP Gateway:**
   - In `core/mcp/gateway.py`: remove dead `from core.memory.palace import MemoryPalaceClient` (lines 28–33) and unused `self.memory` attribute (line 111).
   - In `core/hub/agent.py`: remove dead background transcript harvesting (`_bg_chat_ingest`, `_bg_ingest`).
   - Remove `execute_surreal`, embedded artifact closet, and castle metaphors from `core/memory/palace.py` (or replace with lean, unopinionated SQLite store <100 lines).
   - Deduplicate `core/memory/profiles.py` to point to `runtime/skills/hardware-profiles/`.
   - Adapt `tests/test_memory_palace.py` to maintain 100% green test assertions.
4. **Purge CLI Stubs & Abandoned Prototypes:**
   - Remove `cmd_chat` and `cmd_artifact` from `core/modules/hub.sh`.
   - Remove `chat` and `artifact` cases from `bin/knot` dispatcher.
   - In `core/hub/agent.py`: remove `chat_mention_worker` daemon thread (lines 1228–1433) before dropping `/chat/*` hub endpoints.
   - In `core/hub/hub.py`: remove `/chat/*` and `/artifacts/*` routes and in-memory stores.
   - In `web/`: retire `SwarmChat.tsx` and `ArtifactVault.tsx`.
   - Update `tests/test_cli_help.sh` to remove `chat` and `artifact`.

#### Phase 2: CLI Namespace Consolidation
1. **Consolidate Screen & Login Commands:**
   - Canonicalize `knot screen <status|unlock|lock>`.
   - Canonicalize `knot autologin <local|status|reconcile|...>`.
   - Remove redundant top-level `knot unlock`, `knot lock`, and `knot login` entries from `bin/knot` (or retain hidden backwards-compatible shims while removing from primary help).
2. **Consolidate Power & System Operations:**
   - Canonicalize `knot kvm restart`; retire standalone `knot restart`.
   - Canonicalize `knot shutdown [--reboot]`; consolidate `knot reboot` into `knot shutdown --reboot`.
   - Canonicalize `knot sleep`; consolidate `knot power` into `knot sleep`.
3. **Consolidate Display & Virtual Monitor:**
   - Standardize virtual monitor commands exclusively under `knot display vmon <status|start|stop>`.
   - Deprecate duplicate `knot kdeconnect vmon` alias.
4. **Consolidate Swarm Umbrella:**
   - Canonicalize `knot quota` as the top-level command for model quotas.
   - Make `knot auth` the sole canonical authentication tool; remove redundant `knot swarm auth`.
   - Retain `knot swarm switch <id>`, `knot swarm status`, and `knot swarm wave` as genuine swarm commands.

#### Phase 3: Hub Route Compaction
- In `core/hub/hub.py`: streamline route table down to verified production routes:
  - Cluster Health: `/health`, `/nodes`, `/nodes/activity`
  - Task Blackboard: `/tasks/*`, `/stream`, `/events`, `/strand/events`
  - Model Quotas: `/quota`, `/swarm/models`
  - Power Coordination: `/power/status`, `/swarm/wake`, `/swarm/sleep-allow`
  - Mesh Remote Action: `/mesh/action`, `/mesh/exec`
  - Enrollment & Distribution: `/dist/*`, `/join/*`, `/swarm/enroll/*`

#### Phase 4: Test Suite & Documentation Harmonization
- Update `tests/test_cli_help.sh` (all 229 assertions) to reflect the pruned canonical command dictionary.
- Verify `tests/test_tauri_kafe.sh` (ensuring `pnpm typecheck` and `pnpm build` pass with 0 errors).
- Verify `tests/test_psl_integrity.sh` (asserting 0 defects under Rule 1).
- Verify `pytest` (asserting 100% green across remaining test modules).
- Update `docs/CLI_REFERENCE.md` and `README.md` to document the streamlined command palette.

---

### 12.6 Safety & Non-Breaking Verification Analysis

The pruning plan is specifically engineered to guarantee that **zero core workspace capabilities are broken**:

1. **KVM & Input Capture Invariant:**
   - Deskflow configuration compilation (`core/modules/compile_deskflow.py`), service unit management (`knot-deskflow.service`), and the C-level Wayland token persistence shim (`core/shim/input_capture_shim.c`) are 100% untouched.
2. **Virtual Monitor Invariant:**
   - Virtual monitor scaling (`core/modules/vmon.sh`), `knot-vmon-keepalive`, and KRDP Wayland headless virtual display creation remain 100% intact under canonical `knot display vmon`.
3. **GitOps Worktrees & Landing Arbiter Invariant:**
   - Cross-node worktree provisioning, home path normalization, and rebase verification (`core/gitops.sh`, `tests/test_gitops.sh`, `tests/test_worktree_rebase_mesh.sh`) remain 100% untouched.
4. **Hub & Linda Tuplespace Task Engine Invariant:**
   - Task queuing, batch fanouts, node claims, heartbeats, results, and SSE event streaming (`core/hub/hub.py`, `core/hub/agent.py`, `tests/test_strand_event_bus.py`, `tests/test_dag.py`) remain 100% untouched.
5. **OpenSSH ControlMaster Multiplexing Invariant:**
   - Socket creation, status inspection, and cleanup (`core/modules/ssh.sh`, `core/resolver.sh`, `bin/knot:cmd_socket`) remain 100% untouched.

By executing this rationalization, Knot Mesh eliminated over 13,750 lines of dead code and speculative vibe bloat across 127 files, resolved hidden daemon crash risks, dramatically reduced maintenance overhead, and established a hardened, coherent, enterprise-grade CLI interface.

---

### 12.7 Subagent Ladder Audit & Final Certification Record
- **Review Cycle**: Subagent Ladder (`/subagent-ladder`)
- **Sealed Commit**: `4ceeb7b` (`refactor(core): purge dead code, slop subsystems and rationalize CLI surface across sweeps 1-2`)
- **Impact**: 127 files changed, 1,138 insertions(+), 13,758 deletions(-)
- **Ladder Pipeline**:
  1. *Stage 1 (Planning)*: Interactive `/grill-me` alignment, implementation plan locked in.
  2. *Stage 2 (Execution)*: DeepCoder executed Sweeps 1 & 2 slop purging, file migrations, and daemon decoupling.
  3. *Stage 3 (Hammer Review)*: Hammer identified 2 defects in `web/` (`useKnotSSE.ts` unlogged catches, dead npm packages). Executioner remediated; Hammer issued formal **PASS**.
  4. *Stage 4 (Custodian Commit Gate)*: Custodian conducted Macro Architectural Review & DRY deduplication audit, confirmed clean porcelain tree, and sealed commit `4ceeb7b`.
  5. *Stage 5 (Auditor Certification)*: Auditor independently tested HEAD on `4ceeb7b`: 44/44 pytest passed, 191/191 CLI help passed, 21/21 virtual monitor passed, 22/22 council passed, 10/10 bugbash passed, 5/5 council steer passed, PSL integrity passed (0 defects). Verdict: **PASS**.
- **Certification Status**: Verified, sealed, and archived.

