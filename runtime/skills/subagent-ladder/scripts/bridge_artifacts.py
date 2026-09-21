#!/usr/bin/env python3
"""
Knot Mesh Subagent Ladder - Workspace Artifacts Bridge Helper
Manages deterministic symlinks between the Antigravity session brain directory
and the local workspace (.agents/artifacts) to ensure zero discovery burn.
"""

import argparse
import os
import sys
from pathlib import Path


def find_workspace_root(start_dir: Path | None = None) -> Path:
    current = (start_dir or Path.cwd()).resolve()
    while current != current.parent:
        if (current / ".git").exists() or (current / "bin" / "knot").exists():
            return current
        current = current.parent
    return Path.cwd().resolve()


def check_gitignore(root: Path) -> bool:
    gitignore = root / ".gitignore"
    if not gitignore.exists():
        return False
    content = gitignore.read_text(encoding="utf-8")
    for line in content.splitlines():
        stripped = line.strip()
        if stripped in (".agents/artifacts", ".agents/artifacts/", "artifacts/"):
            return True
    return False


def setup_bridge(brain_path_str: str, root: Path) -> int:
    brain_path = Path(brain_path_str).resolve()
    if not brain_path.is_dir():
        print(f"Error: Specified brain directory does not exist or is not a directory: {brain_path}", file=sys.stderr)
        return 1

    agents_dir = root / ".agents"
    agents_dir.mkdir(parents=True, exist_ok=True)
    symlink_target = agents_dir / "artifacts"

    # Remove existing if present
    if symlink_target.is_symlink() or symlink_target.exists():
        try:
            symlink_target.unlink()
        except OSError as e:
            print(f"Error removing existing symlink {symlink_target}: {e}", file=sys.stderr)
            return 1

    try:
        symlink_target.symlink_to(brain_path, target_is_directory=True)
    except OSError as e:
        print(f"Error creating symlink {symlink_target} -> {brain_path}: {e}", file=sys.stderr)
        return 1

    in_gitignore = check_gitignore(root)
    print(f"[✓] Artifact bridge established: {symlink_target} -> {brain_path}")
    if in_gitignore:
        print("  -> Confirmed: .agents/artifacts is present in .gitignore.")
    else:
        print("  -> Warning: .agents/artifacts is NOT explicitly listed in .gitignore!", file=sys.stderr)

    return 0


def check_bridge(root: Path) -> int:
    symlink_target = root / ".agents" / "artifacts"
    if not symlink_target.is_symlink():
        print(f"[-] No active artifact bridge symlink at {symlink_target}")
        return 1

    target = symlink_target.resolve()
    if not target.is_dir():
        print(f"[-] Broken artifact bridge symlink: {symlink_target} -> {target} (Target does not exist)", file=sys.stderr)
        return 1

    print(f"[✓] Active artifact bridge verified: {symlink_target} -> {target}")
    # List sample artifacts
    artifacts = sorted([f.name for f in target.glob("*.md")])
    print(f"  -> Found {len(artifacts)} markdown artifacts:")
    for art in artifacts[:8]:
        print(f"     • .agents/artifacts/{art}")
    if len(artifacts) > 8:
        print(f"     • ... and {len(artifacts) - 8} more")
    return 0


def clean_bridge(root: Path) -> int:
    symlink_target = root / ".agents" / "artifacts"
    if symlink_target.is_symlink() or symlink_target.exists():
        try:
            symlink_target.unlink()
            print(f"[✓] Artifact bridge removed: {symlink_target}")
            return 0
        except OSError as e:
            print(f"Error removing symlink {symlink_target}: {e}", file=sys.stderr)
            return 1
    print("[✓] No artifact bridge to remove.")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Knot Mesh Artifact Bridge Manager")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--setup", metavar="BRAIN_DIR", help="Create .agents/artifacts symlink to specified brain directory")
    group.add_argument("--check", action="store_true", help="Check status of active artifact bridge")
    group.add_argument("--clean", action="store_true", help="Safely remove active artifact bridge symlink")
    parser.add_argument("--root", metavar="WORKSPACE_ROOT", help="Override workspace root directory")

    args = parser.parse_args()
    root = Path(args.root).resolve() if args.root else find_workspace_root()

    if args.setup:
        sys.exit(setup_bridge(args.setup, root))
    elif args.check:
        sys.exit(check_bridge(root))
    elif args.clean:
        sys.exit(clean_bridge(root))


if __name__ == "__main__":
    main()
