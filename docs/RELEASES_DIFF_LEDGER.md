# Knot Mesh: Inter-Release Milestone Diff Ledger

> **Document Classification**: Authoritative Engineering Architecture Ledger  
> **Repository**: `kuasha420/knot-mesh`  
> **Governance Standard**: PSL Gold Standard & Engineering Integrity (`AGENTS.md`)  
> **Baseline Range**: `v1.0.0-rc1` (`08d7764`) → `HEAD` (`b97d11e`)  
> **Total Lifecycle Metrics**: 170 Commits | 275 Unique Files | +40,315 Insertions | -12,095 Deletions | Net +28,220 Lines  

---

## 1. Executive Summary & Macro Evolution

This ledger chronicles the quantitative and architectural evolution of Knot Mesh across its six historical milestone boundaries, spanning from the initial pre-release candidate (`v1.0.0-rc1`) on 2026-09-16 through the pending candidate release (`v1.0.0-rc6`) on 2026-10-10.

Over these six milestone boundaries, Knot Mesh transformed from a single-machine Deskflow KVM configuration helper into a robust, multi-device Wayland workspace fabric and distributed agent coordination platform:

1. **Boundary 1 (`rc1` → `rc2`)**: Greenfield migration purge, cryptographic GPG history re-signing, and dynamic LayerShell neon boundary indicators (`knot-stripd`).
2. **Boundary 2 (`rc2` → `rc3`)**: Hardening daemon lifecycles (`bin/knot-hub`), multi-target topology rendering, and strict variable initialization under `set -u`.
3. **Boundary 3 (`rc3` → `rc4`)**: Transition from single-node execution to fleet-wide management via `knot sync`, `knot update`, and modular system documentation.
4. **Boundary 4 (`rc4` → `rc5` via premature `v1.0.0` tag)**: Emergence of the multi-agent cognitive layer (Swarm Council, Kitty Confluence multiplexing, CRDT Memory Palace, and Kafe Tauri v2 shell). *(Note: A `v1.0.0` GA tag was prematurely published at commit `d5f9964` during this development arc, but was formally retracted and deleted; the repository remains strictly on the RC track).*
5. **Boundary 5 (`rc4/premature-v1.0.0` → `rc5`)**: First major audit and privacy purge: strict user-space confinement (`%h/.local/bin`), MCP dead code pruning, and version reset to `1.0.0-rc5` to restore open-source release engineering rigor.
6. **Boundary 6 (`rc5` → `HEAD`)**: Horizon 2 maturity: Wayland Virtual Monitor fabric (Epic #63), multi-tenant profile sandboxing (Epic #60), Wave 0–3 closures, and radical AI slop pruning (-13,750+ lines excised).

---

## 2. Master Quantitative Milestone Ledger

The following empirical matrix summarizes all git diff metrics across consecutive milestone boundaries:

| # | Milestone Boundary | Date Interval | Commits | Changed Files | Insertions (+) | Deletions (-) | Net Churn | Primary Architectural Focus |
|---|---|---|:---:|:---:|:---:|:---:|:---:|---|
| **1** | `v1.0.0-rc1` → `v1.0.0-rc2` | 2026-09-16 → 2026-09-18 | 20* | 54 | 7,044 | 1,942 | +5,102 | Re-signed GPG history, Magic URL onboarding, LayerShell `knot-stripd`, KWin barrier sync, purged legacy migration engine |
| **2** | `v1.0.0-rc2` → `v1.0.0-rc3` | 2026-09-18 → 2026-09-18 | 4 | 10 | 112 | 50 | +62 | Persistent neon crossover glow, KVM lock initialization under `set -u`, `bin/knot-hub` wrapper, topology multi-target list |
| **3** | `v1.0.0-rc3` → `v1.0.0-rc4` | 2026-09-18 → 2026-09-19 | 16 | 29 | 3,173 | 386 | +2,787 | Fleet update/sync distribution, live roaming swarm switching, `knot-guard` systemd unit, modular docs suite |
| **4** | `v1.0.0-rc4` → `v1.0.0` GA | 2026-09-19 → 2026-09-20 | 46 | 96 | 19,023 | 1,340 | +17,683 | Swarm Council CLI & Kitty Confluence cockpit, CRDT Memory Palace, Kafe Tauri v2 shell, Cross-node GitOps worktrees, Root `AGENTS.md` |
| **5** | `v1.0.0` GA → `v1.0.0-rc5` | 2026-09-20 → 2026-09-21 | 13 | 81 | 2,138 | 1,709 | +429 | Phase 2 private data purge, dead MCP code prune, `%h/.local/bin` systemd hygiene, live curses/kitty viewers, version reset to `rc5` |
| **6** | `v1.0.0-rc5` → `HEAD` (`main`) | 2026-09-21 → 2026-10-10 | 54 | 239 | 18,452 | 16,295 | +2,157 | Wayland Virtual Monitor fabric (Epic #63), Multi-tenant auth sandboxing (Epic #60), Waves 0-3 closures, Subagent Ladder, AI slop pruning |
| **TOTAL** | **`v1.0.0-rc1` → `HEAD`** | **2026-09-16 → 2026-10-10** | **170** | **275** | **40,315** | **12,095** | **+28,220** | **Comprehensive Full-Mesh Evolution** |

*\*Note on Boundary 1 Lineage:* Between `rc1` and `rc2`, the initial 17 commits were rebased to enforce GPG commit signing (`bca2b93`..`5288d3c`). Commit `5288d3c` is the cryptographic equivalent of `08d7764`. Exactly 20 commits were introduced from `5288d3c` to `v1.0.0-rc2` (totaling 37 commits in rc2).

---

## 3. In-Depth Milestone Boundary Breakdown

### 3.1 Boundary 1: `v1.0.0-rc1` → `v1.0.0-rc2`

#### Git & Tag Metadata
- **Start Reference**: Tag `v1.0.0-rc1`
  - Target Commit SHA: `08d7764ff7eee42d71a52a7384d60b8513f88d62`
  - Date: `2026-09-16 17:05:13 +0600`
  - Tag Message: Lightweight tag (`fix(guard,deskflow): strict zero-error-swallowing, dynamic strand client & multi-ap swarm fencing`)
- **End Reference**: Tag `v1.0.0-rc2`
  - Tag Object SHA: `28b896503cd49bd18fd91745da97a816f619ebf8`
  - Target Commit SHA: `cdb7b5f5a33df13aa2b83f5954f9d837ef63c55d`
  - Date: `2026-09-18 16:46:32 +0600`
  - Tag Message: `Release Candidate 2: Verified GPG history & greenfield installer without migration baggage` (PGP Signed)
- **Lineage & Ancestry**:
  - `git merge-base --is-ancestor v1.0.0-rc1 v1.0.0-rc2`: False (history re-signed with verified GPG signatures).
  - Equivalent re-signed base commit: `5288d3c`.
  - Commits from base to `v1.0.0-rc2`: 20 commits (37 total commits from root).
- **Empirical Metrics**:
  - `git diff --shortstat v1.0.0-rc1 v1.0.0-rc2`: **54 files changed, 7,044 insertions(+), 1,942 deletions(-)**
  - Net Line Churn: **+5,102 lines**

#### Key Feature Introductions
1. **Magic URL Zero-Setup Strand Onboarding**: Tokenized one-line onboarding delivery via Knot Hub (`cffaca3`, `core/modules/hub.py`, `tests/test_magic_onboarding.py`).
2. **LayerShell Dynamic Boundary Indicators (`knot-stripd`)**: Replaced static screen borders with dynamic Wayland LayerShell neon indicators and cursor crossover impulse flares (`84e9736`, `bin/knot-stripd`, `core/shim/input_capture_shim.c`, `systemd/knot-stripd.service`).
3. **Multi-Display Internal Topology & Wayland KWin Barrier Synchronizer**: Support for internal laptop/handheld displays alongside multi-monitor desktop grids (`a5624cf`, `core/modules/topology.sh`).
4. **Web Cockpit Radar**: Interactive display calibration overlay, photo topology modal, and SVG canvas (`PhotoTopologyModal.tsx`, `DisplayCalibrationOverlay.tsx`, `TopologyCanvas.tsx`).
5. **Roaming Dynamic Swarm Profiles**: Dual-role Anchor/Strand orchestration enabling portable devices to switch between home and office swarms (`cd2becb`).
6. **Authoritative Deskflow TLS Distribution**: Knot Hub acting as authoritative CA distributing pinned TLS certificates (`26de825`).

#### Critical Defect Remediations
1. **Fork-Bomb Prevention in Guard**: Fixed recursive fork-bomb in `knot-guard` autologin check (`04864f6`).
2. **TTY Stdin Hijacking Freeze**: Prevented curl-piped onboarding from freezing due to background TTY stdin consumption (`03d48c5`).
3. **SSH Proxy Packet Corruption**: Isolated stdin during port probes in `core/resolver.sh` (`d606284`).
4. **Firewalld Port 4242 Support**: Automatically opened port 4242 in firewalld and integrated diagnostics into `knot doctor` (`7c21d43`).
5. **Non-Root Execution Guarantee**: Ensured fully non-root execution in autounlock and installer (`6083417`).

#### Architectural Pivots
- **Purge of Legacy Migration Engine**: Deleted `core/installer/migrate.sh` (-335 lines) and `tests/test_migrate.sh` (-153 lines), establishing Knot Mesh as a pure greenfield standalone installer (`bin/knot-installer`).
- **Cryptographic Commit Signing**: Standardized mandatory GPG signing across repository commits.

#### Complete Commit Log (`5288d3c..v1.0.0-rc2`)
```
cdb7b5f 2026-09-18 chore(release): bump version to 1.0.0-rc2
a67d521 2026-09-18 chore(installer): strip legacy migration engine and gitops compatibility shims
c05f849 2026-09-18 fix(topology,stripd): support multi-screen edge layout and robust resolver
6334868 2026-09-18 feat(topology): add DPMS wake and session unlock to identify overlay
764a424 2026-09-18 fix(hub): define anchor_id in /topology/identify to trigger remote overlays
04864f6 2026-09-18 fix(guard): prevent recursive fork-bomb in knot-guard autologin check
a5624cf 2026-09-18 feat(topology): multi-display internal topology, vision calibration & wayland KWin barrier synchronizer
84e9736 2026-09-18 feat(stripd): port dynamic LayerShell boundary strips, web cockpit, and protocol harmonization
d606284 2026-09-18 fix(resolver): isolate stdin during port probes to prevent SSH proxy packet corruption
03d48c5 2026-09-18 fix(bootstrap): prevent tty stdin hijacking freeze during curl piped onboarding
d831472 2026-09-18 feat(onboarding,doctor): e2e automagic strand setup with interactive tty sudo escalation, multi-port resolver diagnostics and zero-error-swallowing healing
26de825 2026-09-18 feat(deskflow): distribute authoritative deskflow TLS cert via Knot Hub
6083417 2026-09-18 fix(autounlock,install): ensure fully non-root execution in autounlock and installer
dadc4a4 2026-09-18 fix(cli,kvm): add knot swarm switch command, fix strand kvm restart, and save ip_hint
f06313d 2026-09-18 feat(onboarding): automagic mutual SSH key exchange, active swarm activation and automated KVM client launch
d6aa280 2026-09-18 fix(onboarding,kvm): auto-configure swarm active state, deskflow topology and remove root unit from user systemd
7c21d43 2026-09-18 fix(firewall,doctor): allow port 4242 in firewalld and add port diagnostics to doctor
cffaca3 2026-09-18 feat(hub): add magic url zero-setup strand onboarding and lan bundle delivery
298bdea 2026-09-18 core(doctor): adapt role diagnostics to active swarm and eliminate error swallowing
cd2becb 2026-09-18 core(roaming): add dual-role anchor/strand dynamic orchestration and office swarm profile
```

---

### 3.2 Boundary 2: `v1.0.0-rc2` → `v1.0.0-rc3`

#### Git & Tag Metadata
- **Start Reference**: Tag `v1.0.0-rc2` (`cdb7b5f`, Date: `2026-09-18 16:46:32 +0600`)
- **End Reference**: Tag `v1.0.0-rc3`
  - Tag Object SHA: `4ffa9b09f504755724f94b76ef1c21a369a44570`
  - Target Commit SHA: `a5216f5f13dc0c29878aa00bbe7dca0398d53799`
  - Date: `2026-09-18 17:16:36 +0600`
  - Tag Message: `Release v1.0.0-rc3` (PGP Signed)
- **Lineage & Ancestry**: Direct sequential descendant (`cdb7b5f` is parent of `333406d`).
- **Empirical Metrics**:
  - `git diff --shortstat v1.0.0-rc2 v1.0.0-rc3`: **10 files changed, 112 insertions(+), 50 deletions(-)**
  - Commit Count: **4 commits**
  - Net Line Churn: **+62 lines**

#### Key Feature Introductions
1. **Dedicated `bin/knot-hub` Executable Wrapper**: Added standalone wrapper script configuring dynamic `PYTHONPATH` resolution to resolve daemon startup hurdles and updated `systemd/knot-hub.service` (`333406d`).

#### Critical Defect Remediations
1. **Multi-Target Rendering in Topology Show**: Fixed `core/modules/topology.sh` to correctly render complex multi-screen mesh arrangements without truncating adjacent nodes (`1e7e793`).
2. **KVM Unbound Variable & Lock State Under `set -u`**: Initialized `kvm_lock` state in `deskflow_configure` and resolved unbound `cmd_kvm` error (`57d8fa6`).
3. **Stripd Ambient Glow & Impulse Flaring**: Restored 0.45 idle ambient neon glow on active edges while preserving 0.90 crossover impulse flares.

#### Architectural Pivots
- Encapsulated python daemon invocation into binary entrypoints (`bin/knot-hub`) rather than direct python execution from systemd user units.

#### Complete Commit Log (`v1.0.0-rc2..v1.0.0-rc3`)
```
a5216f5 2026-09-18 chore(release): bump version to v1.0.0-rc3
57d8fa6 2026-09-18 fix(kvm): initialize kvm_lock state and resolve cmd_kvm unbound variable
1e7e793 2026-09-18 fix(topology): support multi-target list rendering in topology show
333406d 2026-09-18 feat(hub): add bin/knot-hub wrapper with dynamic PYTHONPATH and update systemd unit
```

---

### 3.3 Boundary 3: `v1.0.0-rc3` → `v1.0.0-rc4`

#### Git & Tag Metadata
- **Start Reference**: Tag `v1.0.0-rc3` (`a5216f5`, Date: `2026-09-18 17:16:36 +0600`)
- **End Reference**: Tag `v1.0.0-rc4`
  - Tag Object SHA: `f1eda978c6069058a357af13a2ba83bae1716896`
  - Target Commit SHA: `a8b4ea68defd92b39143d893b013b810e003b364`
  - Date: `2026-09-19 06:05:08 +0600`
  - Tag Message: `Release v1.0.0-rc4` (PGP Signed)
- **Lineage & Ancestry**: Direct sequential descendant (`a5216f5` is parent of `0bb91db`).
- **Empirical Metrics**:
  - `git diff --shortstat v1.0.0-rc3 v1.0.0-rc4`: **29 files changed, 3,173 insertions(+), 386 deletions(-)**
  - Commit Count: **16 commits**
  - Net Line Churn: **+2,787 lines**

#### Key Feature Introductions
1. **Fleet Binary Distribution (`knot update`)**: Added cluster-wide software update distribution mechanism supporting rsync and streaming tar fallback when rsync is absent (#39, `0bb91db`, `2169833`).
2. **Multi-Node Swarm Configuration Distribution (`knot sync`)**: Introduced multi-node configuration sync engine for SSH keys, client configs, and pairing state (#38, `9514171`, `core/modules/swarm_sync.sh`).
3. **Live Roaming Swarm Switching & Guard Supervision**: Dynamic swarm roaming and automatic deployment of `systemd/knot-guard.service` (#45, `90d043b`).
4. **Modular Documentation Architecture**: Established structured markdown documentation suite: `docs/CLI_REFERENCE.md`, `docs/FIREWALL.md`, `docs/GETTING_STARTED.md`, and `docs/SWARM_OPERATIONS.md` (#47, `976c88a`).
5. **Automated Firewall Configuration**: Automated subnet rules and Antigravity onboarding (#44, #46, `97094f9`).

#### Critical Defect Remediations
1. **Locked KWallet Handling on Autologin Nodes**: Gracefully handle locked KWallet without failing agent execution (#37, `953f777`).
2. **Prevent Updater Self-Delegation**: Added `knot_is_anchor` helper preventing updater from issuing recursive loops (`c98322d`).
3. **KDE Connect Legacy Registry Purge**: Purged obsolete registry paths and resolved swarm `customDevices` (#48, #49, `96248d6`).
4. **Offline Topology PC Chassis Rejection**: Improved vision detector to filter out computer chassis false positives (#40, `24d77a1`).
5. **Test State Isolation**: Isolated `test_swarm_sync.sh` from host workstation configuration (`1fa71af`).

#### Architectural Pivots
- Paradigm shift from local node configuration to cluster-wide fleet operations (`sync`, `update`).
- Separation of documentation into dedicated operational guides in `docs/`.

#### Complete Commit Log (`v1.0.0-rc3..v1.0.0-rc4`)
```
a8b4ea6 2026-09-19 chore(release): bump version to v1.0.0-rc4
976c88a 2026-09-19 docs: modular documentation suite with CLI reference and guides (#47)
24d77a1 2026-09-19 feat(vision): improve offline topology detector with PC chassis rejection and swarm constraints (#40)
97094f9 2026-09-19 feat(installer): automate firewall rules and Antigravity onboarding (#44, #46)
1fa71af 2026-09-19 test(swarm): isolate test_swarm_sync from host system state
c98322d 2026-09-19 fix(core,cli): add knot_is_anchor and prevent self-delegation in updater
96248d6 2026-09-19 fix(core,kdeconnect): purge legacy registry paths and resolve swarm customDevices (#48, #49)
2169833 2026-09-18 fix(cli): add streaming tar fallback to knot update when rsync is missing
0c8acb1 2026-09-18 merge: feat(cli): implement knot update fleet distribution (#39)
b9865a7 2026-09-18 merge: feat(roaming): live swarm switching and knot-guard deployment (#45)
20e915d 2026-09-18 merge: feat(cli): implement knot sync multi-node distribution (#38)
f27994c 2026-09-18 merge: fix(agent): handle locked KWallet gracefully on autologin nodes (#37)
9514171 2026-09-18 feat(cli): implement knot sync multi-node distribution (#38)
953f777 2026-09-18 fix(agent): handle locked KWallet gracefully on autologin nodes (#37)
90d043b 2026-09-18 feat(roaming): live swarm switching and knot-guard deployment (#45)
0bb91db 2026-09-18 feat(cli): implement knot update fleet distribution (#39)
```

---

### 3.4 Boundary 4: `v1.0.0-rc4` → Commit `d5f9964` (Premature GA Arc, Retracted)

#### Git & Tag Metadata
- **Start Reference**: Tag `v1.0.0-rc4` (`a8b4ea6`, Date: `2026-09-19 06:05:08 +0600`)
- **End Reference**: Commit `d5f9964` (`chore(release): lock canonical KNOT_VERSION to 1.0.0`)
  - Target Commit SHA: `d5f99649730f95fc24a71199744aa5912f8de26f`
  - Date: `2026-09-20 06:12:36 +0600`
  - *Retraction Status*: A `v1.0.0` GA tag was briefly published here, but was premature as the project remains in Release Candidate phase. The tag and GitHub release have been formally deleted/retracted.
- **Lineage & Ancestry**: Direct sequential descendant (`a8b4ea6` is parent of `f5f447e`).
- **Empirical Metrics**:
  - `git diff --shortstat v1.0.0-rc4 d5f9964`: **96 files changed, 19,023 insertions(+), 1,340 deletions(-)**
  - Commit Count: **46 commits**
  - Net Line Churn: **+17,683 lines**

#### Key Feature Introductions
1. **Swarm Council Multi-Agent Coordination**: Out-of-band collaboration protocol using GitHub Discussions, Kitty Confluence 2x2 grid layout, and terminal multiplexing (`f5f447e`, `3e84d9a`, `core/modules/council.sh`).
2. **Cockpit Remote Bridge (`knot council steer`)**: Direct prompt injection into active Kitty panes (`2f0d01c`).
3. **Decentralized SQLite CRDT Memory Palace**: Embedded SQLite cognitive graph with vector cosine similarity and MCP gateway (#41, `4e5d705`, `core/memory/palace.py`).
4. **Knot Kommand Kafe (Tauri v2 Shell)**: Rust Tauri v2 desktop shell, Blackboard Kanban, and handheld gamepad navigation (#42, `f39798a`, `kafe/`).
5. **Cross-Node GitOps Worktrees**: Cross-node worktree manager, home path translation, and canonical node ID semantics (#54, #43, `ed646af`, `bin/knot:cmd_worktree`).
6. **PSL Gold Standard Governance**: Introduced root `AGENTS.md` and living `ROADMAP.md` establishing engineering integrity rules (`8e0d21f`).
7. **Autonomous Leased Autonomy (`goal-with-lease`)**: Leased autonomy runtime skill (`a0a3ab4`).
8. **Universal Color Palette Engine**: Mathematical WCAG-compliant color derivation based on the Golden Angle (`614abe1`, `core/palette.py`).

#### Critical Defect Remediations
1. **Enforce PSL Rule 1**: Systematically eliminated error swallowing (`2>/dev/null`) across council and hub (`4749d86`).
2. **Cross-Distro Portability**: Fixed random hex generation, float comparisons, and hermetic database paths (`a443f85`).
3. **Atomic Subshell Safety**: Replaced unsafe `$$` with `${BASHPID:-$$}` for concurrency-safe temporary file generation (`7027f31`).
4. **PreInvocation Hooks & Session Resumption**: Preserved turn state and prevented prompt buffer truncation (`a85dd8c`).

#### Architectural Pivots
- Emergence of the multi-agent cognitive layer (A2A) alongside the hardware workspace fabric (D2D).
- Formalization of the PSL Gold Standard and repository governance.

#### Complete Commit Log (`v1.0.0-rc4..v1.0.0`)
```
d5f9964 2026-09-20 chore(release): lock canonical KNOT_VERSION to 1.0.0
a443f85 2026-09-20 fix(council): cross-distro portability for random hex, float comparison, and hermetic db path
d64d35b 2026-09-20 chore(release): bump knot-mesh version to 1.0.0 GA
4749d86 2026-09-20 refactor(core): eliminate error swallowing and enforce PSL Rule 1 across council and hub
fd662a3 2026-09-20 feat(worktree): merge Issues #54 and #43 cross-node worktrees and canonical node id semantics
ed646af 2026-09-20 feat(worktree): cross-node worktree management, portable paths, and node id semantics (Issues #54, #43)
2f1bfe4 2026-09-20 feat(kafe): merge Issue #42 tauri v2 shell, blackboard kanban, and handheld mode
f39798a 2026-09-20 feat(kafe): tauri v2 shell, blackboard kanban, and handheld gamepad navigation
a0a3ab4 2026-09-20 feat(governance): add goal-with-lease skill and ignore target directories
8182f75 2026-09-20 feat(memory): merge Issue #41 decentralized memory palace and mcp hardening
43108bd 2026-09-20 feat(council): implement Issue #55 harness hardening and direct mesh db inspection
4e5d705 2026-09-20 feat(memory): decentralized embedded sqlite crdt palace and mcp hardening
8e0d21f 2026-09-20 docs(governance): add root AGENTS.md and living ROADMAP.md per PSL standard
b0f9b61 2026-09-20 docs(leaderboard): record flawless 4-node swarm crypto tournament results
20599f4 2026-09-20 feat(swarm-council): dynamic node resolution, zero hardcoding, and active server delivery
b302795 2026-09-20 fix(council): preserve scaffolder opening_node and ring in meta.json merge
db59124 2026-09-20 feat(swarm-council): dynamic ring routing, zero hardcoding, and deterministic tournament exit
83124c1 2026-09-20 fix(deliver): remove bash local keyword outside function scope
8a01676 2026-09-20 refactor(council): eliminate language prescription in tournament prompts, enforcing targeted anti-patterns only
2bc11bb 2026-09-20 fix(council): zero-token standby, remote steer relay, anti-meta directives for tournament
4597cd2 2026-09-20 docs(tournament): record 80 proofs milestone and 5.0x swarm streak multiplier
f27491d 2026-09-20 docs(tournament): update final leaderboard with 76 proofs (4.8x streak multiplier)
91e2288 2026-09-20 docs(tournament): update final leaderboard with 73 proofs (4.6x streak multiplier)
a110d88 2026-09-20 fix(council): add steer anchor proxy fallback and fix referee message id tracking
e6932b0 2026-09-20 docs(tournament): record final 4-node swarm crypto tournament leaderboard (68 proofs, 4.4x multiplier)
2f0d01c 2026-09-20 feat(council): add Cockpit Bridge Remote (knot council steer) and tournament pack
95d4172 2026-09-20 feat(tournament): add 4-node swarm crypto ping-pong tournament orchestrator
6319148 2026-09-20 docs: update swarm ping-pong tournament leaderboard (5-min timed rally)
c2797de 2026-09-20 fix(test): clean KNOT_COUNCIL_RUN_ID in global hook arena isolation test
4965412 2026-09-20 fix(council): harden project sync and eliminate stderr pollution in jq pipeline
38dfd51 2026-09-19 feat(ops): implement --dev mode for sync and update with bidirectional safety lockouts
f4e8be0 2026-09-19 fix(council): multi-project portability, symlink resolution & dynamic chunking
a85dd8c 2026-09-19 feat(council): zero-token interactive cockpit, PreInvocation hook & session resumption
6e838c4 2026-09-19 fix(mcp, memory): import glob in palace.py, add MockMemoryPalaceClient for hermetic self-test, and steamdeck sidequest test
a1d633b 2026-09-19 feat(council): add --db mesh message board, --interactive cockpit, and --tiling layout engine
614abe1 2026-09-19 feat(core): dynamic universal palette engine with topological collision avoidance and dynamic display scaling
7027f31 2026-09-19 fix(concurrency): replace $$ with ${BASHPID:-$$} for atomic temp files
bc5c787 2026-09-19 fix(packaging): package skills and hub/unlock symlinks, import glob in palace, and test anchor sidequest
4ec710c 2026-09-19 fix(council): dynamically constrain confluence cockpit panes to active nodes
b7e70d5 2026-09-19 fix(hub): canonical node identity, strip theme seeds, quota matrix and compact checkpoints
3e84d9a 2026-09-19 fix(council): overhaul confluence 2x2 grid layout, project navigation, and fleet trust automation
00ff4c3 2026-09-19 fix(council): fix newlines in gh discussions, add -t to knot exec, and auto-sync tokens
c83a054 2026-09-19 fix(council): enforce exact single quote SIGHUP trap in confluence generator
9112f4f 2026-09-19 fix(council): safely stage and load remote prompt files in confluence mode
ca6265b 2026-09-19 fix(council): fix git pull command formatting in project_sync
f5f447e 2026-09-19 feat(council): implement Swarm Council multi-agent coordination skill and CLI
```

---

### 3.5 Boundary 5: Commit `d5f9964` → `v1.0.0-rc5` (Phase 2 Refactor & Version Reset)

#### Git & Tag Metadata
- **Start Reference**: Commit `d5f9964` (`2026-09-20 06:12:36 +0600`)
- **End Reference**: Tag `v1.0.0-rc5`
  - Tag Object SHA: `8829774c87d9c4785a5e5225b2f69c58252938d7`
  - Target Commit SHA: `8b915a5e37d085f377818740c46b8fb814caedc1`
  - Date: `2026-09-21 13:11:06 +0600`
  - Tag Message: `Release v1.0.0-rc5` (PGP Signed)
- **Lineage & Ancestry**: Direct sequential descendant (`d5f9964` is parent of `5832167`).
- **Empirical Metrics**:
  - `git diff --shortstat d5f9964 v1.0.0-rc5`: **81 files changed, 2,138 insertions(+), 1,709 deletions(-)**
  - Commit Count: **13 commits**
  - Net Line Churn: **+429 lines**

#### Key Feature Introductions
1. **Live Model Limit Visualizer (`knot quota live`)**: Standalone curses visualizer rendering 5-hour and weekly Antigravity quota matrices (`core/hub/limit_visualizer.py`).
2. **Curses Mesh Board Viewer (`knot council board`)**: Live TUI board visualizer for mesh tasks without external browser dependencies (`skills/swarm-council/scripts/board_viewer.py`).
3. **Automated Live Viewers Test Suite**: Added `tests/test_live_viewers.py` (360 lines) testing TUI visualizer components hermetically.
4. **Cockpit Self-Healing & Topology Guard**: Added automatic topology guard and cockpit recovery (#57, `cb5497a`).
5. **Gamepad Navigation Hook in Kafe**: Added touch/gamepad navigation (`useGamepadNavigation.ts`, `tests/test_tauri_kafe.sh`).

#### Critical Defect Remediations & Confidentiality Purge
1. **Phase 2 Private Data Purge**: Excluded machine-specific hardware assumptions, local paths, and private usernames across git tracking.
2. **MCP Gateway Dead Code Excision**: Stripped 1,331 lines of legacy MCP gateway code down to a clean, robust 4-tool gateway (`core/mcp/gateway.py`).
3. **Systemd User-Space Confinement (%h/.local/bin)**: Fixed systemd unit templates to use `%h/.local/bin` wrappers, eliminating absolute `/home/<user>` paths (`b643219`).
4. **Purged Deprecated Skills**: Deleted obsolete skill directories (`skills/channels`, `skills/storage`, `skills/remote-control`, `skills/vision`).
5. **Agent SSL Context Fix**: Passed explicit SSL context to `get_swarm_activity` restoring sleep inhibition (`1243ff2`).
6. **Dynamic Hub Re-Resolution**: Supported dynamic URL re-resolution and dual D-Bus/systemd power inhibition (`8c501af`).

#### Architectural Pivots
- **Version Reset**: Reset versioning from premature `1.0.0` GA back to `v1.0.0-rc5` to restore disciplined open-source release engineering and establish pre-release stability fences.

#### Complete Commit Log (`v1.0.0..v1.0.0-rc5`)
```
8b915a5 2026-09-21 refactor: complete Phase 2 private data purge, dead code elimination & version reset to v1.0.0-rc5
25845eb 2026-09-21 docs: add historical inception acknowledgment to README
387e649 2026-09-21 fix(kvm): dynamically refresh controller IPs from leases in knot-stripd
b643219 2026-09-21 fix(systemd): use generic %h/.local/bin wrappers to comply with Rule 4 OSS boundary
1243ff2 2026-09-21 fix(agent): pass SSL context to get_swarm_activity to restore sleep inhibition
8c501af 2026-09-21 fix(hub): add dynamic Hub URL re-resolution and dual D-Bus/systemd power inhibition
cb5497a 2026-09-21 feat(council): implement cockpit self-healing and topology guard (closes #57)
35744fd 2026-09-21 feat(ui): merge PR #58 Curses Mesh Board Viewer and Live Limit Visualizer
34df09e 2026-09-21 feat(kafe): merge PR #56 Knot Kommand Kafe - Tauri v2 Desktop Container & Handheld Mode (#42)
455aa26 2026-09-20 fix(ui): address PR review comments for mesh live viewers
f442a03 2026-09-20 fix(kafe): address PR #56 review comments
eb8ea1d 2026-09-20 feat(ui): zero-token kitty-based mesh board viewer and live limit visualizer
5832167 2026-09-20 feat(kafe): packaging integration, desktop container launcher, and test suite
```

---

### 3.6 Boundary 6: `v1.0.0-rc5` → Current `main` (`HEAD`)

#### Git & Tag Metadata
- **Start Reference**: Tag `v1.0.0-rc5` (`8b915a5`, Date: `2026-09-21 13:11:06 +0600`)
- **End Reference**: Current `main` (`HEAD: b97d11e`)
  - Commit SHA: `b97d11e04db18de997b22ab64d1c7e884e91808d`
  - Date: `2026-10-10 02:36:13 +0600`
  - Commit Message: `docs(audit): record Subagent Ladder certification of slop pruning in AUDIT_JOURNAL.md`
- **Lineage & Ancestry**: Direct sequential descendant (`8b915a5` is parent of `e85ee30`).
- **Empirical Metrics**:
  - `git diff --shortstat v1.0.0-rc5 HEAD`: **239 files changed, 18,452 insertions(+), 16,295 deletions(-)**
  - Commit Count: **54 commits**
  - Net Line Churn: **+2,157 lines**

#### Key Feature Introductions
1. **Wayland Virtual Monitor Fabric (Epic #63)**: Turnkey multi-device display extension via KDE Plasma 6 KWin virtual displays, KRdp headless server, and KRDC client (`60a6d71`, `456ecc7`, `ef4aebe`, `core/modules/vmon.sh`, `tests/test_virtual_monitor.sh`):
   - Zero-touch host TLS certificate creation (`krdp.crt`).
   - Automated FreeRDP pre-trust over SSH across dynamic port range `5900..5920`.
   - Subnet firewall management (ports 5900-5910/tcp).
   - Spatial HiDPI alignment and Deskflow KVM boundary muting.
2. **Multi-Tenant Local Profile Sandboxing (Epic #60)**: Isolated account management under `~/.config/knot/auth/` (`ec78af6`, `core/modules/auth.sh`, `tests/test_knot_auth.sh`):
   - Strict 0700/0600 permissions on token storage.
   - Atomic symlink switching between active profiles.
   - Non-blocking SecretService / KWallet lock inspection.
3. **Wave 0 & 1 Operational Closures (`c8ac77f`)**:
   - Universal CLI help normalization across all 39 root commands and subcommands (`tests/test_cli_help.sh`).
   - Hardened council session staging, gitops worktrees, and authentication.
4. **Wave 2 Fleet Capabilities (`a5665a1`)**:
   - OpenSSH ControlMaster multiplexing socket manager (`knot socket`).
   - Parallel command execution across strands (`knot exec -P`).
   - Telemetry ledger generation (`knot ledger`).
5. **Wave 3 Closures (`875fd0f`, `218d86c`)**:
   - Strand event bus (`/strand/events`), heartbeat workers, fleet mirror syncing, terminfo propagation.
6. **Subagent Ladder & Operational Skills**:
   - Formalized user-invoked `subagent-ladder` operational protocol (`ac2e0eb`).
   - Formalized `swarm-orchestrator` skill (`5ba558d`).

#### Critical Defect Remediations & Slop Excision
1. **Systematic AI Slop Excision (`cd48c82`, `b97d11e`)**:
   - Purged 1,822 lines of speculative "Memory Palace" castle metaphors, dead SurrealQL shims, and write-only transcripts.
   - Purged 297 lines of esports "tournament referee" scoring algorithms.
   - Purged 1,000+ lines of desk photo computer vision algorithms (`core/vision/`).
   - Purged hollow stubs (`chat`, `artifact`, `project sync`).
   - Pruned 3,395 unused lines in web lockfile (`pnpm-lock.yaml`) and retired dead React chat components.
2. **Wayland Input Capture API 2 Ordering**: Ordered `xdg-desktop-portal` after KDE backend for input capture API 2 (`70b9875`, `6aa44e4`).
3. **Deskflow Spurious Restart Suppression**: Prevented periodic restarts when role has not changed (`013851a`).
4. **Autologin Background Crash Fix**: Resolved crash in headless `HOME` environment during dual-direction reconciliation (`b18c61c`).
5. **Universal PSL Rule 1 & 2 Audit**: Passed 100% green with 0 defects across 5 audits in `tests/test_psl_integrity.sh`.

#### Architectural Pivots
- **D2D vs A2A Decoupling**: Physical device fabric (KVM, Virtual Monitor, OpenSSH multiplexing) strictly separated from AI cognitive workflows (Tuplespace, Subagent Ladder).
- **Radical Slop Pruning**: Reduced codebase bloat by over 13,750 lines, transforming Knot Mesh into a lean, enterprise-grade distributed workspace fabric.

#### Complete Commit Log (`v1.0.0-rc5..HEAD`)
```
b97d11e 2026-10-10 docs(audit): record Subagent Ladder certification of slop pruning in AUDIT_JOURNAL.md
cd48c82 2026-10-10 refactor(core): purge dead code, slop subsystems and rationalize CLI surface across sweeps 1-2
321e6c3 2026-10-09 feat(core): harden knot-mesh production architecture across phases 1-5
218d86c 2026-10-09 fix(wave3): harden strand event bus, subshell env propagation, terminfo and mirror sync
875fd0f 2026-10-09 feat(hub,sync,orchestrator): complete Wave 3 event bus, fleet sync, quality ladder & rematch closures
a5665a1 2026-10-09 feat(fleet): implement Wave 2 fleet capabilities, SSH ControlMaster multiplexing, parallel exec, display module, landing arbiter & telemetry
c8ac77f 2026-10-08 feat(core): complete Wave 0 & Wave 1 closures, normalize CLI help, harden council, gitops & auth
b18c61c 2026-10-06 fix(autologin): add dual-direction background reconciliation and fix headless HOME crash
013851a 2026-10-02 fix(guard): prevent periodic deskflow restarts when role has not changed
70b9875 2026-10-02 fix(deskflow): order xdg-desktop-portal after KDE backend for input capture API 2
6aa44e4 2026-10-02 fix(deskflow): add input capture fallback to API 1 and enforce Restart=always
f2a2f45 2026-10-02 fix(mesh): restore generic systemd units, dynamic hub resolution, and fleet symlink healing
5ba558d 2026-10-02 feat(skills): introduce swarm-orchestrator skill and harden council steer across physical mesh
6624b42 2026-09-29 fix(vmon): embed mouse cursor into virtual monitor stream and fix keepalive pkill collision
5c2e506 2026-09-29 fix(stripd): pin indicator strip to primary physical display and ensure user state path fallback
4682dcf 2026-09-29 chore: extract JimHa game into standalone repository kuasha420/jimha
78b44e4 2026-09-29 feat(apps): introduce JimHa's interactive key smash game and knot-jimheart launcher
512487e 2026-09-26 fix(vmon): enable showLocalCursor and cleanup stale KRDC sessions
e30e951 2026-09-26 fix(vmon): guard kdeconnect reconcile to prevent virtual monitor teardown
b7cdc6b 2026-09-26 fix(vmon): resolve strand lockouts, bottom-align displays, and suppress muted KVM strips
ef4aebe 2026-09-26 feat(vmon): harmonize spatial topology, hidpi scaling, deskflow muting, and persistent panels
c3cdb70 2026-09-26 docs(vmon): document zero-touch virtual monitor architecture, cli, and rules
947d2df 2026-09-26 fix(doctor): initialize local is_anchor in doctor_repair_local
4f076f6 2026-09-26 fix(doctor): route --repair to doctor_repair and invoke knot repair local on strands
456ecc7 2026-09-26 feat(vmon): automate zero-touch TLS certificates, client pre-trust, and viewer lifecycle
60a6d71 2026-09-26 feat(vmon): integrate Wayland Virtual Monitor fabric via KDE Connect and KRDP (Epic #63)
9e9a281 2026-09-26 feat(kdeconnect): add Tier 1 D2D continuous self-healing, timer supervision, and turnkey onboarding
f0c1834 2026-09-26 docs(roadmap): refine Epics #61 and #62 with verified Kitty A2A steering and KDE Connect clipboard stances
5593164 2026-09-26 docs(roadmap): link Epic #61 (handheld HUDs) and Epic #62 (KDE Connect audit)
1f7e9db 2026-09-26 fix(hub): support Antigravity Starter Quota weekly telemetry and prevent cross-account cache pollution
bac54bf 2026-09-26 feat(auth): add persistent Konsole wrapper for remote GUI login
aec330e 2026-09-26 fix(auth): preserve -tt raw PTY and export TERM for remote logins, add --gui support
d60404b 2026-09-26 fix(auth): stash SecretService and pause knot-agent during login to guarantee fresh OAuth prompt
d8d1040 2026-09-26 feat(auth): add top-level node dispatch, fleet sweeps, and isolated multi-profile login
7bbc5c0 2026-09-26 fix(council): resolve repository root accurately in confluence and sync scripts
ec78af6 2026-09-26 feat(auth): implement multi-tenant local profile sandboxing and live viewer autodiscovery (fixes #60)
4fd3c21 2026-09-25 feat(core): resolve Horizon 2 bug-bash defects (BUG-014 through BUG-017)
2b2424b 2026-09-25 fix(agent): propagate initial account resolution in heartbeat worker
6b6a9d5 2026-09-25 fix(auth): prioritize FreeDesktop Secret Service in is_kwallet_unlocked
1b98f99 2026-09-25 fix(agent): extend quota probe timeout to 150s for upstream network delays
46c22b2 2026-09-25 fix(agent): increase headless quota probe subprocess timeout from 15s to 35s
1c412d4 2026-09-25 refactor(resolver): clean up fallback return in resolve_node.py
16ba55b 2026-09-25 feat(hardware): support string targets in deskflow compiler and add rog ally hardware domain test
4495391 2026-09-25 fix(council): resolve local node accurately in cockpit and fix deliver runner escaping
54355b5 2026-09-25 fix(resolver): replace socat inactivity timeout with connection timeout to prevent SYN hangs
7393294 2026-09-25 fix(telemetry): permit headless quota probes with token file and preserve reset timestamps
5a2d1fc 2026-09-25 fix(resolver): prioritize dynamic mDNS, evict stale leases, and fix doctor 255 issue arithmetic
57bf8f8 2026-09-21 refactor(orchestration): eliminate prompt overfit, negative prompts, and rule drift
d31816e 2026-09-21 feat(skills): wire all runtime skills into .agents/skills and swarm_sync
ac2e0eb 2026-09-21 feat(skills): formalize strictly user-invoked subagent-ladder operational skill
0f1b082 2026-09-21 chore(agents): ignore .agents/artifacts workspace bridge symlink
32fdca2 2026-09-21 docs(phase-5): holistic documentation overhaul, swarm verification & final audit
bee900c 2026-09-21 refactor(phase-4): PSL Rule 1 & 2 system-wide audit, zero error swallowing & universal integrity suite
e85ee30 2026-09-21 refactor(phase-3): D2D/A2A layering, governance decoupling & clean feature redesigns
```

---

## 4. Cumulative Codebase Growth & Velocity Analysis

### 4.1 Churn Ratio & Expansion Profile
Across the repository lifecycle, additions outpaced deletions until Boundary 6, where refactoring and pruning actively counterbalanced growth:

```
Milestone 1 (rc1 -> rc2):  +7,044 /  -1,942   (Net:  +5,102)  Ratio: 3.63:1
Milestone 2 (rc2 -> rc3):  +  112 /  -   50   (Net:  +   62)  Ratio: 2.24:1
Milestone 3 (rc3 -> rc4):  +3,173 /  -  386   (Net:  +2,787)  Ratio: 8.22:1
Milestone 4 (rc4 -> GA):   +19,023 /  -1,340   (Net: +17,683)  Ratio: 14.20:1  [Peak expansion]
Milestone 5 (GA -> rc5):   +2,138 /  -1,709   (Net:  +  429)  Ratio: 1.25:1  [Data purge]
Milestone 6 (rc5 -> HEAD): +18,452 / -16,295   (Net:  +2,157)  Ratio: 1.13:1  [Massive pruning]
-----------------------------------------------------------------------------
Total Evolution:           +40,315 / -12,095   (Net: +28,220)  Ratio: 3.33:1
```

### 4.2 Subsystem Footprint Evolution
- **CLI Dispatcher (`bin/knot`)**: Expanded from ~200 lines to ~1,200 lines, implementing 39 root commands and subcommands with strict argument validation and non-zero exit codes for unknown flags.
- **Core Library (`core/lib.sh`)**: Standardized environment resolution, logging utilities (`knot_info`, `knot_warn`, `knot_err`), and lockfile helpers (`knot_acquire_lock`).
- **Core Subsystems (`core/modules/`)**: Modular decomposition into dedicated domain files:
  - `deskflow.sh`: KVM configuration, TLS cert distribution, and barrier sync.
  - `vmon.sh`: Wayland Virtual Monitor lifecycle, FreeRDP pre-trust, and KRdp server control.
  - `auth.sh`: Sandboxed multi-profile token management and KWallet non-blocking inspection.
  - `swarm_sync.sh` & `council.sh`: Fleet config distribution and out-of-band council coordination.
- **Packaging & Daemon Units**: Confinement under `%h/.local/bin`, dynamic user-space fallback, and unified systemd user unit management.

---

## 5. Verification & Quality Standard Evolution

The verification strategy of Knot Mesh matured concurrently with the codebase:

1. **`v1.0.0-rc1`**: Initial verification relied on basic shell syntax checks and two manual integration scripts.
2. **`v1.0.0-rc2`..`rc3`**: Introduction of `test_magic_onboarding.py` and structured resolver diagnostics.
3. **`v1.0.0-rc4`**: Expansion of automated test isolation (`test_swarm_sync.sh`) and cross-distro portability tests.
4. **`v1.0.0` GA**: Formalization of `AGENTS.md` and the PSL Gold Standard:
   - Mandatory ban on `2>/dev/null` error swallowing (Rule 1).
   - Mandatory ban on synthetic test passes (Rule 2).
5. **`v1.0.0-rc5`**: Hermetic curses visualizer testing (`tests/test_live_viewers.py`) and user-space systemd validation.
6. **`v1.0.0-rc6` (`HEAD`)**: Complete multi-tier test harness:
   - **Unit & Functional Tests**: `pytest` running 44/44 green tests.
   - **CLI Interface Completeness**: `tests/test_cli_help.sh` validating 191/191 command/flag combinations and exit codes.
   - **PSL Gold Standard Integrity**: `tests/test_psl_integrity.sh` executing 5 comprehensive sweeps across shell and Python files with 0 defects detected.
