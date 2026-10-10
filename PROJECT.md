# Project: Knot Mesh Release Synchronization & Hardening

## Architecture
- **Knot Mesh Runtime**: Distributed multi-device orchestration system (`bin/knot`, `core/lib.sh`, daemons, systemd user units).
- **Packaging & Confinement**: User-space confined packaging via `%h/.local/bin` (`PKGBUILD`, `bin/knot-installer`, `systemd/knot-*.service`).
- **Documentation & Ledgers**: Exhaustive release diff metrics, architectural lineage, changelogs (`docs/RELEASES_DIFF_LEDGER.md`, `docs/RELEASE_NOTES_v1.0.0-rc6.md`, `docs/ROADMAP.md`).
- **Release Automation**: GitHub Releases API (`gh release`), GPG-signed git tags, Conventional Commits.
- **CI / GitHub Infrastructure**: Hermetic test execution (`.github/workflows/ci.yml`, issue templates).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Reconcile missing pre-releases | Publish GitHub Pre-releases for tags `v1.0.0-rc1` and `v1.0.0-rc4` with curated markdown notes | M1 | ORIGINAL_REQUEST § R1 |
| 2 | Normalize `rc3` and `rc2` releases | Edit GitHub releases for `v1.0.0-rc3` and `v1.0.0-rc2` to be Pre-release, stripping erroneous `Latest` flag | M1 | ORIGINAL_REQUEST § R1 |
| 3 | Publish `v1.0.0` GA release notes | Publish official GitHub GA release notes for tag `v1.0.0` flagged as `Latest` | M1 | ORIGINAL_REQUEST § R1 |
| 4 | Preserve authentic metadata | Link releases to authentic tag timestamps and commit SHAs without rewriting git history | M1 | ORIGINAL_REQUEST § R1, R5 |
| 5 | Milestone Diff Ledger | Generate `docs/RELEASES_DIFF_LEDGER.md` with commit counts, line churn, features, fixes, pivots across all 6 boundaries | M2 | ORIGINAL_REQUEST § R2 |
| 6 | Draft rc6 release notes | Create `docs/RELEASE_NOTES_v1.0.0-rc6.md` documenting stabilization, slop pruning, and packaging readiness | M2 | ORIGINAL_REQUEST § R4 |
| 7 | Systemd user-space confinement | Update `systemd/knot-guard.service` to support user-space `%h/.local/bin` confinement fallback | M3 | ORIGINAL_REQUEST § R3 |
| 8 | Repository hygiene & sanitization | Sanitize personal hostnames (`devbox`), mesh IPs (`192.168.68.145`), and local paths (`file:///home/kuasha/`) across docs, tests, and UI | M3 | ORIGINAL_REQUEST § R3 |
| 9 | Web UI bundle rebuild | Rebuild `web/` assets so `web/dist/` reflects sanitized generic hostnames | M3 | ORIGINAL_REQUEST § R3 |
| 10 | GitHub CI & templates | Scaffold `.github/workflows/ci.yml` and issue templates for open-source repository governance | M3 | ORIGINAL_REQUEST § R3 |
| 11 | Synchronized version bump | Atomically bump version from `1.0.0-rc5` to `1.0.0-rc6` across all 11 mapped files | M4 | ORIGINAL_REQUEST § R4 |
| 12 | Test suite & CLI verification | Verify 100% green execution across `pytest` (44/44), `test_psl_integrity.sh` (0 defects), and `test_cli_help.sh` (191+ checks) | M4 | Acceptance Criteria |
| 13 | Atomic Conventional Commits | Stage and commit validated changes with GPG signature and clean git tree | M4 | ORIGINAL_REQUEST § R5 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | GitHub Release Reconciliation & Normalization | Create rc1, rc4 pre-releases; normalize rc2, rc3 to pre-release; publish v1.0.0 GA as Latest | none | DONE |
| M2 | Inter-Release Milestone Diff Analysis | Author `docs/RELEASES_DIFF_LEDGER.md` (6 boundaries) and `docs/RELEASE_NOTES_v1.0.0-rc6.md` | none | DONE |
| M3 | Repository Hygiene, Confinement & GitHub Infra | Sanitize hostnames/IPs/paths, fix `knot-guard.service`, rebuild web UI, add `.github/` workflows | none | DONE |
| M4 | Version Bump, Packaging Sync & Full Certification | Bump 11 files to 1.0.0-rc6, run full test suite (pytest, psl integrity, cli help, installer), commit | M2, M3 | DONE |

## Interface Contracts
### GitHub Releases API ↔ Local Repository
- Releases mapped to pre-existing remote tags (`refs/tags/*`) on `kuasha420/knot-mesh`.
- No forced tag rewriting on remote.
- Output format: markdown release notes adhering to Conventional Commits categories.

### Systemd User Units ↔ Packaging
- All units in `systemd/knot-*.service` must execute `%h/.local/bin/<executable>`.
- `bin/knot-installer` creates symlinks in `${HOME}/.local/bin/`.

### Core Version ↔ Packaging & Tests
- `bin/knot` (`KNOT_VERSION="1.0.0-rc6"`)
- `core/lib.sh` (`export KNOT_VERSION="1.0.0-rc6"`)
- `bin/knot-installer` (`echo "knot-mesh version ${KNOT_VERSION:-1.0.0-rc6}"`)
- `PKGBUILD` (`pkgver=1.0.0.rc6`, source tarball `v1.0.0-rc6.tar.gz`)
- `tests/test_knot_installer.sh` & `tests/test_bootstrap_installer.sh` assert `1.0.0-rc6`.

## Code Layout
- `bin/`: CLI executables (`knot`, `knot-installer`, `knot-agent`, `knot-hub`, etc.)
- `core/`: Core runtime shell libraries (`core/lib.sh`) and python services (`core/mcp/`)
- `systemd/`: Systemd user service units (`knot-*.service`, `knot-*.timer`)
- `docs/`: Documentation, ledgers, and release notes
- `tests/`: Automated test suites (`pytest`, bash integration and verification scripts)
- `web/`: Radar web interface (React / TypeScript / Vite)
- `.github/`: CI workflows and community templates
