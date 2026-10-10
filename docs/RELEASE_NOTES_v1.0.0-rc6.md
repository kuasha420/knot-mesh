# Knot Mesh v1.0.0-rc6 Release Notes

> **Release Version**: `v1.0.0-rc6`  
> **Release Name**: Open-Source Hardening, Wayland Virtual Monitor Fabric & Fleet Rationalization  
> **Date**: 2026-10-10  
> **Repository**: `kuasha420/knot-mesh`  
> **Governance Charter**: PSL Gold Standard (`AGENTS.md`)  

---

## 1. Executive Overview

**Knot Mesh `v1.0.0-rc6`** represents the culmination of extensive stabilization, architectural refactoring across Waves 0 through 3, and radical codebase slop excision following `v1.0.0-rc5`. 

Over the course of 54 commits (+18,452 insertions, -16,295 deletions), the repository underwent a disciplined transformation: transitioning from prototype-heavy exploration to an enterprise-grade, lean distributed workspace fabric. More than **13,750 lines of dead code, speculative AI castle metaphors, and hollow stubs were excised**, leaving a hardened core backed by turnkey Wayland Virtual Monitor display extension (Epic #63), multi-tenant credential sandboxing (Epic #60), OpenSSH ControlMaster connection multiplexing, and automated verification suites enforcing the PSL Gold Standard.

---

## 2. Major Architectural Highlights

### 2.1 Wayland Virtual Monitor Fabric (Epic #63)
Knot Mesh now features turnkey virtual display extension for multi-device setups running KDE Plasma 6 Wayland:
- **Zero-Touch TLS Generation & FreeRDP Pre-Trust**: Automatically issues host certificates (`krdp.crt`) and pre-trusts client thumbprints across the mesh over secure SSH, removing manual interactive certificate prompts (`456ecc7`).
- **Dynamic Port Allocation**: Supports dynamic KRdp port ranges (`5900..5920/tcp`) with automated subnet firewall management.
- **Spatial Alignment & HiDPI Scaling**: Automatically aligns virtual monitors with physical displays, provides bottom-aligned positioning, and embeds local mouse cursors to eliminate input lag.
- **Deskflow KVM Boundary Muting**: Automatically suppresses boundary indicators and mutes KVM transitions across screens active in virtual monitor mode (`ef4aebe`, `b7cdc6b`).

### 2.2 Multi-Tenant Local Profile Sandboxing (Epic #60)
Comprehensive credential isolation and identity management:
- **Hermetic Token Storage**: User sessions isolated under `~/.config/knot/auth/<profile>/` with strict POSIX `0700` directory and `0600` file permissions (`ec78af6`).
- **Atomic Symlink Profile Switching**: Seamless switching between multiple accounts without cross-profile token contamination (`knot auth switch <profile>`).
- **Non-Blocking SecretService & KWallet Inspection**: Prioritizes FreeDesktop Secret Service with graceful fallback, preventing UI freeze when system keyrings are locked on autologin nodes (`6b6a9d5`).
- **Remote GUI & Headless Authentication**: Supports persistent Konsole wrappers (`--gui`) and raw PTY preservation (`-tt`) for headless/remote OAuth completions (`bac54bf`, `aec330e`).

### 2.3 Cluster-Wide Fleet Operations & SSH Multiplexing (Wave 2)
Streamlined operations across multi-node swarms:
- **SSH ControlMaster Multiplexing (`knot socket`)**: Persistent master socket management (`knot socket start`, `status`, `stop`) yielding zero-token, near-instant remote execution (`a5665a1`).
- **Parallel Command Execution (`knot exec -P`)**: Executes arbitrary shell commands across all registered strands in parallel, collecting formatted stdout/stderr summaries.
- **Telemetry & Fleet Ledger (`knot ledger`)**: Aggregates node status, network latency, active roles, and quota allocations into structured machine-readable ledgers.

### 2.4 Decoupled SWE Coordination: Subagent Ladder & Swarm Council
Architectural separation of physical device management (D2D) and multi-agent AI collaboration (A2A):
- **User-Invoked Subagent Ladder**: Formalized four-phase SWE ladder (`Executioner` → `Hammer` → `Custodian` → `Auditor`) in `.agents/skills/subagent-ladder/SKILL.md` (`ac2e0eb`).
- **Swarm Orchestrator & Council Steer**: Kitty Confluence multiplexing (`knot council steer`) for direct out-of-band operator steering across physical devices without polling loops (`5ba558d`).

### 2.5 Radical Codebase Slop Pruning (-13,750+ Lines)
Systematic excision of speculative prototypes and unused subsystems:
- **Memory Palace Prune**: Removed 1,822 lines of complex cognitive castle metaphors, dead SurrealQL shims, and write-only transcripts.
- **Tournament Referee Prune**: Removed 297 lines of synthetic esports tournament scoring algorithms.
- **Photo Vision Prune**: Purged over 1,000 lines of experimental desk photo computer vision algorithms (`core/vision/`).
- **Frontend & CLI Prune**: Pruned 3,395 unused lines from web package lockfiles, deleted dead React chat components, and removed hollow CLI stubs (`knot chat`, `knot artifact`, `knot memory`).

### 2.6 PSL Gold Standard Verification & Shell Hygiene
All codebase modules rigorously audited against the PSL Gold Standard:
- **PSL Rule 1**: Strict ban on `2>/dev/null`, `&>/dev/null`, and bare error suppression; all background commands and probes handle errors transparently (`tests/test_psl_integrity.sh`).
- **CLI Help Normalization**: Complete coverage across all 39 root commands and nested subcommands, ensuring `--help` and `-h` return exit code 0, while invalid commands and flags consistently return exit code 1 (`tests/test_cli_help.sh`).

---

## 3. Component-by-Component Changelog

### Core CLI & Dispatcher (`bin/knot`)
- Normalized argument parsing across all commands (`c8ac77f`).
- Added `knot display vmon` subcommand for Wayland Virtual Monitor lifecycle.
- Added `knot socket` subcommand for OpenSSH ControlMaster lifecycle.
- Added `knot ledger` command for fleet-wide telemetry aggregation.
- Added `-P` flag to `knot exec` for parallel multi-strand execution.
- Added strict unknown-flag rejection returning exit code 1.

### Virtual Monitor Subsystem (`core/modules/vmon.sh`)
- Implemented `vmon_start`, `vmon_stop`, and `vmon_status` routines.
- Integrated automated TLS certificate generation and remote client certificate injection.
- Added automatic firewall port opening for FreeRDP/KRdp sessions.
- Added display geometry synchronization with `kscreen-doctor`.

### Deskflow KVM & Input Capture Shim (`core/modules/deskflow.sh`, `core/shim/`)
- Ordered `xdg-desktop-portal` activation after KDE backend to fix Wayland Input Capture API 2 handshake (`70b9875`).
- Added graceful fallback to Input Capture API 1 when API 2 is unavailable (`6aa44e4`).
- Prevented spurious Deskflow service restarts when device role remains unchanged (`013851a`).
- Embedded cursor rendering in virtual display streams (`6624b42`).

### Authentication & Sandboxing (`core/modules/auth.sh`)
- Built multi-tenant account directories under `~/.config/knot/auth/`.
- Implemented atomic profile switching via symlink swapping.
- Added non-blocking FreeDesktop SecretService checks with fallback to avoid D-Bus freezes (`6b6a9d5`).
- Supported remote OAuth completion with Konsole wrappers (`bac54bf`).

### Blackboard Hub & Event Bus (`core/hub/`)
- Introduced `/strand/events` event bus endpoint for real-time fleet event distribution (`875fd0f`, `218d86c`).
- Fixed headless `HOME` environment crash during dual-direction background reconciliation (`b18c61c`).
- Supported Antigravity weekly telemetry updates and prevented cross-account quota caching leaks (`1f7e9db`).

### Packaging & Systemd Confinement (`PKGBUILD`, `systemd/`)
- Updated systemd unit templates to enforce user-space execution via `%h/.local/bin/`.
- Verified `knot-installer` and `PKGBUILD` user-space confinement compliance.
- Removed machine-specific usernames and paths across all unit configurations.

---

## 4. Breaking Changes & Command Consolidations

In accordance with Wave 0-3 CLI rationalization, several deprecated prototype commands were removed or consolidated:

| Old / Deprecated Command | New / Canonical Command | Rationale |
|---|---|---|
| `knot chat` | *Removed* | Purged hollow AI chat stub. |
| `knot artifact` | *Removed* | Purged dead prototype artifact subsystem. |
| `knot memory` | *Removed* | Purged speculative Memory Palace castle subsystem. |
| `knot unlock` / `knot lock` / `knot login` | `knot screen {unlock\|lock\|login}` | Grouped under unified screen namespace. |
| `knot restart` | `knot kvm restart` | Explicit KVM service restart targeting. |
| `knot reboot` | `knot shutdown --reboot` | Consolidated under shutdown command. |

---

## 5. Upgrade & Migration Guide

### 5.1 Upgrading from `v1.0.0-rc5` to `v1.0.0-rc6`

1. **Pull and Install Latest Release Candidate**:
   ```bash
   git fetch --tags
   git checkout v1.0.0-rc6
   bin/knot-installer
   ```

2. **Verify CLI Version**:
   ```bash
   knot --version
   # Expected output: knot-mesh version 1.0.0-rc6
   ```

3. **Run Local Diagnostics & Repair**:
   ```bash
   knot doctor local --repair
   ```

4. **Verify Systemd Units**:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart knot-hub knot-guard knot-stripd
   knot status
   ```

5. **Authenticate / Verify Sandboxed Profiles**:
   ```bash
   knot auth status
   knot auth list
   ```

---

## 6. Empirical Verification Certification

This release candidate has undergone full automated test execution and integrity auditing:

| Test Suite | Command | Result | Details |
|---|---|:---:|---|
| **Functional & Unit Tests** | `pytest` | **44 / 44 PASS** | Deskflow compilation, DAG dependency, live TUI viewers, magic onboarding, color palette, strand event bus. |
| **Universal PSL Integrity** | `tests/test_psl_integrity.sh` | **0 DEFECTS** | 5 comprehensive audits: zero error swallowing, strict `set -euo pipefail`, shell syntax (`bash -n`), python syntax, executable permissions. |
| **CLI Help Normalization** | `tests/test_cli_help.sh` | **191 / 191 PASS** | Validated root and subcommand `-h`/`--help` exit codes (0), undocumented command rejection, invalid subcommands (1), and invalid flags (1). |
