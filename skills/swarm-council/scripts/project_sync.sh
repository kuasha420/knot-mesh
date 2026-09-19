#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 1 Dynamic Project & Source Sync
# Discovers Antigravity project from CWD, extracts declared folders, and verifies fleet mirrors

DO_PULL=0
if [ "${1:-}" = "--pull" ]; then
  DO_PULL=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CWD="$(pwd)"

python3 - "$DO_PULL" <<PYEOF
import os, sys, json, glob, subprocess

do_pull = (sys.argv[1] == "1")
cwd = os.path.realpath("$CWD")
home = os.path.expanduser("~")
projects_dir = os.path.join(home, ".gemini/config/projects")

matched_project = None
matched_folders = []

# 1. Search for matching Antigravity project
if os.path.isdir(projects_dir):
    for f in glob.glob(os.path.join(projects_dir, "*.json")):
        try:
            with open(f) as pf:
                data = json.load(pf)
                resources = data.get("projectResources", {}).get("resources", [])
                folders = []
                for r in resources:
                    uri = r.get("gitFolder", {}).get("folderUri", "")
                    if uri.startswith("file://"):
                        path = uri[7:].rstrip("/")
                        folders.append(path)
                
                # Check if current directory is inside any of these folders
                for fpath in folders:
                    if os.path.realpath(fpath) == cwd or cwd.startswith(os.path.realpath(fpath) + "/"):
                        matched_project = data
                        matched_folders = folders
                        break
            if matched_project:
                break
        except Exception:
            pass

# Fallback: single repo root
if not matched_folders:
    try:
        toplevel = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
        matched_folders = [toplevel]
    except Exception:
        matched_folders = [cwd]

# 2. Discover online nodes via knot status
knot_bin = os.path.join("$KNOT_ROOT", "bin/knot")
nodes = []
try:
    status_out = subprocess.check_output([knot_bin, "status"], text=True, stderr=subprocess.DEVNULL)
    import re
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    clean_out = ansi_escape.sub('', status_out)
    for line in clean_out.splitlines():
        parts = line.split()
        if len(parts) >= 5 and parts[4] == "ONLINE":
            nodes.append(parts[0])
except Exception:
    nodes = ["localhost"]

if not nodes:
    nodes = ["localhost"]

results = {
    "project_id": matched_project.get("id") if matched_project else "single-repo",
    "project_name": matched_project.get("name") if matched_project else os.path.basename(matched_folders[0]),
    "folders": matched_folders,
    "nodes": {}
}

# 3. Verify folders on each node
for node in nodes:
    is_local = (node in ["desktop", "localhost", os.uname().nodename.split(".")[0]])
    node_res = {"status": "SYNCED", "folders": {}}
    
    for folder in matched_folders:
        folder_name = os.path.basename(folder)
        
        if is_local:
            exists = os.path.isdir(folder)
            branch = ""
            commit = ""
            if exists:
                if do_pull:
                    subprocess.run(["git", "-C", folder, "pull", "--ff-only"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    branch = subprocess.check_output(["git", "-C", folder, "rev-parse", "--abbrev-ref", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
                    commit = subprocess.check_output(["git", "-C", folder, "rev-parse", "--short", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
                except Exception:
                    pass
            node_res["folders"][folder_name] = {"path": folder, "exists": exists, "branch": branch, "commit": commit}
        else:
            # Probe remote node
            pull_subcmd = "git pull --ff-only >/dev/null 2>&1 && " if do_pull else ""
            remote_cmd = f"test -d ~/Dev/{folder_name} && (cd ~/Dev/{folder_name} && {pull_subcmd}git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD) || echo 'MISSING'"
            try:
                rout = subprocess.check_output([knot_bin, "exec", node, remote_cmd], text=True, stderr=subprocess.DEVNULL).strip().splitlines()
                if rout and rout[0] != "MISSING":
                    r_branch = rout[0] if len(rout) > 0 else "unknown"
                    r_commit = rout[1] if len(rout) > 1 else "unknown"
                    node_res["folders"][folder_name] = {"path": f"~/Dev/{folder_name}", "exists": True, "branch": r_branch, "commit": r_commit}
                else:
                    node_res["folders"][folder_name] = {"path": f"~/Dev/{folder_name}", "exists": False, "branch": "", "commit": ""}
                    node_res["status"] = "MISSING_FOLDER"
            except Exception as e:
                node_res["folders"][folder_name] = {"exists": False, "error": str(e)}
                node_res["status"] = "UNREACHABLE"
    
    results["nodes"][node] = node_res

print(json.dumps(results, indent=2))
PYEOF
