#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 1 Dynamic Project & Source Sync
# Discovers Antigravity project, extracts declared folders, and verifies fleet mirrors

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export KNOT_ROOT="${KNOT_ROOT:-$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)}"

python3 - "$@" << 'PYEOF'
import os, sys, json, glob, subprocess, argparse

parser = argparse.ArgumentParser(description="Swarm Council Project Sync")
parser.add_argument("--pull", action="store_true", help="Pull git mirrors")
parser.add_argument("--project", default=None, help="Target project name or ID")
parser.add_argument("--dir", default=None, help="Explicit directory override")
args, unknown = parser.parse_known_args()

do_pull = args.pull
target_project = args.project
explicit_dir = args.dir

home = os.path.expanduser("~")
cwd = os.path.realpath(explicit_dir) if explicit_dir else os.path.realpath(os.getcwd())
projects_dir = os.path.join(home, ".gemini/config/projects")
knot_root = os.path.realpath(os.environ.get("KNOT_ROOT", os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../.."))))

matched_project = None
matched_folders = []

def extract_folders(data):
    resources = data.get("projectResources", {}).get("resources", [])
    folders = []
    for r in resources:
        uri = r.get("gitFolder", {}).get("folderUri", "")
        if uri.startswith("file://"):
            p = uri[7:].rstrip("/")
            if os.path.isdir(p):
                folders.append(p)
            else:
                bname = os.path.basename(p)
                for cand in [
                    os.path.join(home, "Dev", bname),
                    os.path.join(home, bname),
                    os.path.join(home, ".local/share", bname)
                ]:
                    if os.path.isdir(cand):
                        folders.append(cand)
                        break
    return folders

# 1. Target project specified explicitly
if target_project:
    t_clean = target_project.strip().lower()
    if os.path.isdir(projects_dir):
        for f in glob.glob(os.path.join(projects_dir, "*.json")):
            try:
                with open(f, "r", encoding="utf-8") as pf:
                    data = json.load(pf)
                p_id = data.get("id", "").lower()
                p_name = data.get("name", "").lower()
                if t_clean in (p_id, p_name):
                    f_list = extract_folders(data)
                    if f_list:
                        matched_project = data
                        matched_folders = f_list
                        break
            except Exception:
                pass
    if not matched_folders:
        for cand in [
            os.path.join(home, "Dev", target_project),
            os.path.join(home, target_project),
            os.path.join(home, ".local/share", target_project)
        ]:
            if os.path.isdir(cand):
                matched_folders = [cand]
                break

# 2. Try matching CWD against Antigravity project workspaces
if not matched_folders and os.path.isdir(projects_dir):
    for f in glob.glob(os.path.join(projects_dir, "*.json")):
        try:
            with open(f, "r", encoding="utf-8") as pf:
                data = json.load(pf)
            f_list = extract_folders(data)
            for fpath in f_list:
                rf = os.path.realpath(fpath)
                if rf == cwd or cwd.startswith(rf + "/"):
                    matched_project = data
                    matched_folders = f_list
                    break
        except Exception:
            pass
        if matched_project:
            break

# 3. If CWD is inside a git repository, check if it matches a project or treat as standalone repo
if not matched_folders:
    try:
        toplevel = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            text=True,
            stderr=subprocess.DEVNULL
        ).strip()
        if toplevel and os.path.isdir(toplevel):
            if os.path.isdir(projects_dir):
                for f in glob.glob(os.path.join(projects_dir, "*.json")):
                    try:
                        with open(f, "r", encoding="utf-8") as pf:
                            data = json.load(pf)
                        f_list = extract_folders(data)
                        if toplevel in [os.path.realpath(x) for x in f_list]:
                            matched_project = data
                            matched_folders = f_list
                            break
                    except Exception:
                        pass
            if not matched_folders:
                matched_folders = [toplevel]
    except Exception:
        pass

# 4. Fallback: Default to "knot-mesh" project if available, or knot_root
if not matched_folders:
    if os.path.isdir(projects_dir):
        for f in glob.glob(os.path.join(projects_dir, "*.json")):
            try:
                with open(f, "r", encoding="utf-8") as pf:
                    data = json.load(pf)
                if data.get("name", "").lower() == "knot-mesh":
                    f_list = extract_folders(data)
                    if f_list:
                        matched_project = data
                        matched_folders = f_list
                        break
            except Exception:
                pass

if not matched_folders:
    if os.path.isdir(knot_root):
        matched_folders = [knot_root]
    else:
        matched_folders = [cwd]

# Discover online nodes via knot status
knot_bin = os.path.join(knot_root, "bin/knot")
if not os.path.isfile(knot_bin) or not os.access(knot_bin, os.X_OK):
    import shutil
    knot_bin = shutil.which("knot") or os.path.expanduser("~/.local/bin/knot")

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

project_name = (
    matched_project.get("name")
    if matched_project
    else (target_project if target_project else os.path.basename(matched_folders[0]))
)
project_id = (
    matched_project.get("id")
    if matched_project
    else "single-repo"
)

results = {
    "project_id": project_id,
    "project_name": project_name,
    "folders": matched_folders,
    "nodes": {}
}

# Determine local node identifiers
try:
    from resolve_node import resolve_local_node_id
    detected_local = resolve_local_node_id()
except Exception:
    detected_local = ""

local_node_ids = {"localhost", "127.0.0.1", os.uname().nodename.split(".")[0]}
if detected_local:
    local_node_ids.add(detected_local)
env_node = os.environ.get("KNOT_NODE_ID")
if env_node:
    local_node_ids.add(env_node)
node_id_file = os.path.join(home, ".config/knot/node_id")
if os.path.isfile(node_id_file):
    try:
        with open(node_id_file) as nf:
            local_node_ids.add(nf.read().strip())
    except Exception:
        pass

# Verify folders on each node
for node in nodes:
    is_local = (node in local_node_ids)
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
            # Probe remote node across candidate directory roots
            pull_subcmd = "git pull -q --ff-only && " if do_pull else ""
            remote_cmd = f'TARGET=""; for c in ~/Dev/{folder_name} ~/{folder_name} ~/.local/share/{folder_name}; do if [ -d "$c" ]; then TARGET="$c"; break; fi; done; if [ -n "$TARGET" ]; then (cd "$TARGET" && {pull_subcmd}git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD && echo "$TARGET"); else echo "MISSING"; fi'
            try:
                rout = subprocess.check_output([knot_bin, "exec", node, remote_cmd], text=True, stderr=subprocess.DEVNULL).strip().splitlines()
                if rout and rout[0] != "MISSING":
                    r_branch = rout[0] if len(rout) > 0 else "unknown"
                    r_commit = rout[1] if len(rout) > 1 else "unknown"
                    r_path = rout[2] if len(rout) > 2 else f"~/Dev/{folder_name}"
                    node_res["folders"][folder_name] = {"path": r_path, "exists": True, "branch": r_branch, "commit": r_commit}
                else:
                    node_res["folders"][folder_name] = {"path": f"~/Dev/{folder_name}", "exists": False, "branch": "", "commit": ""}
                    node_res["status"] = "MISSING_FOLDER"
            except Exception as e:
                node_res["folders"][folder_name] = {"exists": False, "error": str(e)}
                node_res["status"] = "UNREACHABLE"
    
    results["nodes"][node] = node_res

print(json.dumps(results, indent=2))
PYEOF
