# Knot GitOps Conventions & Workflow

Knot manages infrastructure state as code through git. Follow these conventions strictly.

## 1. Branching Strategy
- **`main`**: The single source of truth for active mesh topology and tooling. Every commit on `main` is production-ready and safe for immediate reconcile via `knot sync`.
- **`node/<strand-id>`**: Working branch used when onboarding or reconfiguring a strand. Merged into `main` after local validation.
- **`feat/<feature>` / `fix/<component>`**: For developing new CLI tools, resolver improvements, or skills.

## 2. Semantic Commit Taxonomy
All commits must follow conventional semantic types:
- `node(onboard): enroll <strand-id> into knot mesh`
- `node(update): update mac/ip hints for <strand-id>`
- `node(retire): decommission <strand-id> from mesh`
- `mesh(topo): update spatial screen layout in topology.json`
- `mesh(keys): reconcile public keys across strands`
- `sec(firewall): configure subnet rules for <engine>`
- `sec(sshd): update key-only hardening drop-in`
- `sec(guard): update network-gating guard criteria`
- `skill(<name>): update agent capability definition`
- `core(<tool>): update resolver / cli logic`
- `docs: update mesh documentation or architecture`

## 3. Automated Git Operations
- Commands like `knot onboard` and `knot sync` should use `core/gitops.sh` to construct proper branch names and semantic commit messages automatically.
