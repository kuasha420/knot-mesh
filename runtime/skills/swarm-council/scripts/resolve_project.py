#!/usr/bin/env python3
"""
Swarm Council: Dynamic Project Directory Resolver
Resolves project root paths dynamically using Antigravity primitives
(~/.gemini/config/projects/*.json) with cross-node user path portability.
"""

import os
import sys
import json
import glob
import subprocess


def resolve_project_dir(project_target=None):
    home = os.path.expanduser("~")
    projects_dir = os.path.join(home, ".gemini/config/projects")
    cwd = os.path.realpath(os.getcwd())

    # 1. If explicit project target specified
    if project_target:
        target_clean = project_target.strip()
        is_path_target = target_clean in (".", "./") or target_clean.startswith((".", "/")) or os.path.isdir(target_clean)

        if is_path_target:
            target_dir = os.path.realpath(cwd if target_clean in (".", "./") else target_clean)
            if os.path.isdir(projects_dir):
                for f in glob.glob(os.path.join(projects_dir, "*.json")):
                    try:
                        with open(f, "r", encoding="utf-8") as pf:
                            data = json.load(pf)
                        resources = data.get("projectResources", {}).get("resources", [])
                        for r in resources:
                            uri = r.get("gitFolder", {}).get("folderUri", "")
                            if uri.startswith("file://"):
                                fpath = uri[7:].rstrip("/")
                                rf = os.path.realpath(fpath)
                                if rf == target_dir or target_dir.startswith(rf + "/"):
                                    return target_dir
                    except Exception as _err:
                        sys.stderr.write(f"Notice: [resolve_project] Handled exception: {_err}\n")
            try:
                res = subprocess.run(
                    ["git", "rev-parse", "--show-toplevel"],
                    cwd=target_dir,
                    capture_output=True,
                    text=True
                )
                if res.returncode == 0 and res.stdout.strip():
                    top = res.stdout.strip()
                    if os.path.isdir(top):
                        return top
            except Exception as _err:
                sys.stderr.write(f"Notice: [resolve_project] Handled exception: {_err}\n")
            return target_dir
        else:
            target_clean_lower = target_clean.lower()
            if os.path.isdir(projects_dir):
                for f in glob.glob(os.path.join(projects_dir, "*.json")):
                    try:
                        with open(f, "r", encoding="utf-8") as pf:
                            data = json.load(pf)
                        p_id = data.get("id", "").lower()
                        p_name = data.get("name", "").lower()
                        if target_clean_lower in (p_id, p_name):
                            resources = data.get("projectResources", {}).get("resources", [])
                            for r in resources:
                                uri = r.get("gitFolder", {}).get("folderUri", "")
                                if uri.startswith("file://"):
                                    fpath = uri[7:].rstrip("/")
                                    if os.path.isdir(fpath):
                                        return fpath
                                    # If username differs across fleet nodes (e.g. /home/alice vs /home/bob)
                                    bname = os.path.basename(fpath)
                                    for cand in [
                                        os.path.join(home, "Dev", bname),
                                        os.path.join(home, bname),
                                        os.path.join(home, ".local/share", bname)
                                    ]:
                                        if os.path.isdir(cand):
                                            return cand
                    except Exception as _err:
                        sys.stderr.write(f"Notice: [resolve_project] Handled exception: {_err}\n")

            # Check local candidate paths for project_target (only if not . or ./)
            if target_clean not in (".", "./", ""):
                for cand in [
                    os.path.join(home, "Dev", target_clean),
                    os.path.join(home, target_clean),
                    os.path.join(home, ".local/share", target_clean)
                ]:
                    if os.path.isdir(cand):
                        return cand

    # 2. If no project target or target not found, match against CWD
    if os.path.isdir(projects_dir):
        for f in glob.glob(os.path.join(projects_dir, "*.json")):
            try:
                with open(f, "r", encoding="utf-8") as pf:
                    data = json.load(pf)
                resources = data.get("projectResources", {}).get("resources", [])
                for r in resources:
                    uri = r.get("gitFolder", {}).get("folderUri", "")
                    if uri.startswith("file://"):
                        fpath = uri[7:].rstrip("/")
                        rfpath = os.path.realpath(fpath)
                        if rfpath == cwd or cwd.startswith(rfpath + "/"):
                            return rfpath
            except Exception as _err:
                sys.stderr.write(f"Notice: [resolve_project] Handled exception: {_err}\n")

    # 3. Fallback to git toplevel or CWD
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True
        )
        if res.returncode == 0 and res.stdout.strip():
            top = res.stdout.strip()
            if os.path.isdir(top):
                return top
    except Exception as _err:
        sys.stderr.write(f"Notice: [resolve_project] Handled exception: {_err}\n")

    return cwd


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else None
    print(resolve_project_dir(target))
