#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 1 Dynamic Project & Source Sync
# Discovers Antigravity project, extracts declared folders, and verifies fleet mirrors

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export SCRIPT_DIR
export KNOT_ROOT="${KNOT_ROOT:-$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)}"

python3 - "$@" << 'PYEOF'
import os, sys, json, glob, subprocess, argparse

parser = argparse.ArgumentParser(description="Swarm Council Project Sync")
parser.add_argument("--pull", action="store_true", help="Pull git mirrors")
parser.add_argument("--project", default=None, help="Target project name or ID")
parser.add_argument("--dir", default=None, help="Explicit directory override")
parser.add_argument("--nodes", default=None, help="Comma-separated nodes to sync")
args, unknown = parser.parse_known_args()

do_pull = args.pull
target_project = args.project
explicit_dir = args.dir
target_nodes = args.nodes

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
    t_clean = target_project.strip()
    is_path_target = t_clean in (".", "./") or t_clean.startswith((".", "/")) or os.path.isdir(t_clean)

    if is_path_target:
        target_dir = os.path.realpath(cwd if t_clean in (".", "./") else t_clean)
        if os.path.isdir(projects_dir):
            for f in glob.glob(os.path.join(projects_dir, "*.json")):
                try:
                    with open(f, "r", encoding="utf-8") as pf:
                        data = json.load(pf)
                    f_list = extract_folders(data)
                    for fpath in f_list:
                        rf = os.path.realpath(fpath)
                        if rf == target_dir or target_dir.startswith(rf + "/"):
                            matched_project = data
                            matched_folders = f_list
                            break
                except Exception as _err:
                    sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")
                if matched_project:
                    break
        if not matched_folders:
            try:
                res = subprocess.run(
                    ["git", "rev-parse", "--show-toplevel"],
                    cwd=target_dir,
                    capture_output=True,
                    text=True
                )
                if res.returncode == 0 and res.stdout.strip():
                    toplevel = res.stdout.strip()
                    if os.path.isdir(toplevel):
                        matched_folders = [toplevel]
                elif res.returncode != 0 and "not a git repository" not in res.stderr.lower():
                    sys.stderr.write(f"Notice: [project_sync] git rev-parse notice: {res.stderr.strip()}\n")
            except Exception as _err:
                sys.stderr.write(f"Notice: [project_sync] git rev-parse exception: {_err}\n")
        if not matched_folders and os.path.isdir(target_dir):
            matched_folders = [target_dir]
    else:
        t_clean_lower = t_clean.lower()
        if os.path.isdir(projects_dir):
            for f in glob.glob(os.path.join(projects_dir, "*.json")):
                try:
                    with open(f, "r", encoding="utf-8") as pf:
                        data = json.load(pf)
                    p_id = data.get("id", "").lower()
                    p_name = data.get("name", "").lower()
                    if t_clean_lower in (p_id, p_name):
                        f_list = extract_folders(data)
                        if f_list:
                            matched_project = data
                            matched_folders = f_list
                            break
                except Exception as _err:
                    sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")
        if not matched_folders:
            for cand in [
                os.path.join(home, "Dev", target_project),
                os.path.join(home, target_project),
                os.path.join(home, ".local/share", target_project)
            ]:
                if os.path.isdir(cand):
                    if os.path.isdir(projects_dir):
                        for f in glob.glob(os.path.join(projects_dir, "*.json")):
                            try:
                                with open(f, "r", encoding="utf-8") as pf:
                                    data = json.load(pf)
                                f_list = extract_folders(data)
                                if any(os.path.realpath(cand) == os.path.realpath(x) for x in f_list):
                                    matched_project = data
                                    matched_folders = f_list
                                    break
                            except Exception as _err:
                                sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")
                            if matched_project:
                                break
                    if not matched_folders:
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
        except Exception as _err:
            sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")
        if matched_project:
            break

# 3. If CWD is inside a git repository, check if it matches a project or treat as standalone repo
if not matched_folders:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True
        )
        if res.returncode == 0 and res.stdout.strip():
            toplevel = res.stdout.strip()
            if os.path.isdir(toplevel):
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
                        except Exception as _err:
                            sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")
                if not matched_folders:
                    matched_folders = [toplevel]
        elif res.returncode != 0 and "not a git repository" not in res.stderr.lower():
            sys.stderr.write(f"Notice: [project_sync] git rev-parse notice in cwd: {res.stderr.strip()}\n")
    except Exception as _err:
        sys.stderr.write(f"Notice: [project_sync] git rev-parse exception in cwd: {_err}\n")

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
            except Exception as _err:
                sys.stderr.write(f"Notice: [project_sync] Failed reading project {f}: {_err}\n")

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
if target_nodes:
    nodes = [n.strip() for n in target_nodes.split(",") if n.strip()]

if not nodes:
    audit_env = os.environ.get("KNOT_AUDIT_NODES")
    if audit_env:
        nodes = [n.strip() for n in audit_env.split(",") if n.strip()]
    else:
        try:
            res = subprocess.run([knot_bin, "status"], capture_output=True, text=True)
            if res.returncode == 0:
                import re
                ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
                clean_out = ansi_escape.sub('', res.stdout)
                for line in clean_out.splitlines():
                    parts = line.split()
                    if len(parts) >= 5 and parts[4] == "ONLINE":
                        nodes.append(parts[0])
            else:
                sys.stderr.write(f"Notice: [project_sync] knot status failed: {res.stderr.strip()}\n")
        except Exception as _err:
            sys.stderr.write(f"Notice: [project_sync] knot status exception: {_err}\n")
            nodes = ["localhost"]

if not nodes:
    nodes = ["localhost"]

project_name = (
    matched_project.get("name")
    if matched_project
    else (target_project if (target_project and target_project not in (".", "./") and not os.path.isdir(target_project)) else os.path.basename(matched_folders[0]))
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
    _sdir = os.environ.get("SCRIPT_DIR") or os.path.join(knot_root, "runtime/skills/swarm-council/scripts")
    if _sdir and _sdir not in sys.path:
        sys.path.insert(0, _sdir)
    from resolve_node import resolve_local_node_id
    detected_local = resolve_local_node_id()
except Exception as _err:
    sys.stderr.write(f"Notice: [project_sync] resolve_local_node_id exception: {_err}\n")
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
    except Exception as _err:
        sys.stderr.write(f"Notice: [project_sync] Failed reading node_id_file: {_err}\n")

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
                    p_res = subprocess.run(["git", "-C", folder, "pull", "--ff-only"], capture_output=True, text=True)
                    if p_res.returncode != 0:
                        sys.stderr.write(f"Notice: [project_sync] git pull failed for {folder}: {p_res.stderr.strip()}\n")
                try:
                    b_res = subprocess.run(["git", "-C", folder, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True)
                    branch = b_res.stdout.strip() if b_res.returncode == 0 else ""
                    c_res = subprocess.run(["git", "-C", folder, "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
                    commit = c_res.stdout.strip() if c_res.returncode == 0 else ""
                except Exception as _err:
                    sys.stderr.write(f"Notice: [project_sync] git rev-parse exception for {folder}: {_err}\n")
            node_res["folders"][folder_name] = {"path": folder, "exists": exists, "branch": branch, "commit": commit}
        else:
            # Sync Antigravity project JSON if matched
            if matched_project:
                try:
                    h_res = subprocess.run([knot_bin, "exec", node, 'echo "$HOME"'], capture_output=True, text=True)
                    remote_home = h_res.stdout.strip() if h_res.returncode == 0 else ""
                    if remote_home:
                        adapted_data = json.loads(json.dumps(matched_project))
                        for res in adapted_data.get("projectResources", {}).get("resources", []):
                            u = res.get("gitFolder", {}).get("folderUri", "")
                            if u.startswith(f"file://{home}/"):
                                res["gitFolder"]["folderUri"] = f"file://{remote_home}/{u[len(f'file://{home}/'):]}"
                        p_json_str = json.dumps(adapted_data, indent=2)
                        sync_proj_cmd = f"mkdir -p ~/.gemini/config/projects && cat > ~/.gemini/config/projects/{project_id}.json"
                        p = subprocess.Popen([knot_bin, "exec", node, sync_proj_cmd], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                        p_out, p_err = p.communicate(input=p_json_str)
                        if p.returncode != 0:
                            sys.stderr.write(f"Notice: [project_sync] Failed syncing project to {node}: {p_err.strip()}\n")
                except Exception as _err:
                    sys.stderr.write(f"Notice: [project_sync] Remote project adaptation exception on {node}: {_err}\n")

            # Probe remote node across candidate directory roots
            pull_subcmd = "git pull -q --ff-only && " if do_pull else ""
            remote_cmd = f'TARGET=""; for c in ~/Dev/{folder_name} ~/{folder_name} ~/.local/share/{folder_name}; do if [ -d "$c" ]; then TARGET="$c"; break; fi; done; if [ -n "$TARGET" ]; then (cd "$TARGET" && {pull_subcmd}git rev-parse --abbrev-ref HEAD && git rev-parse --short HEAD && echo "$TARGET"); else echo "MISSING"; fi'
            try:
                r_res = subprocess.run([knot_bin, "exec", node, remote_cmd], capture_output=True, text=True)
                rout = r_res.stdout.strip().splitlines() if r_res.returncode == 0 else []
                if (not rout or rout[0] == "MISSING") and do_pull:
                    try:
                        u_res = subprocess.run(
                            ["git", "-C", folder, "config", "--get", "remote.origin.url"],
                            capture_output=True, text=True
                        )
                        remote_url = u_res.stdout.strip() if u_res.returncode == 0 else ""
                        if remote_url:
                            clone_cmd = f'mkdir -p ~/Dev && git clone -q "{remote_url}" ~/Dev/{folder_name}'
                            cl_res = subprocess.run([knot_bin, "exec", node, clone_cmd], capture_output=True, text=True)
                            if cl_res.returncode != 0:
                                sys.stderr.write(f"Notice: [project_sync] Remote clone failed on {node}: {cl_res.stderr.strip()}\n")
                            r_res2 = subprocess.run([knot_bin, "exec", node, remote_cmd], capture_output=True, text=True)
                            rout = r_res2.stdout.strip().splitlines() if r_res2.returncode == 0 else []
                    except Exception as _err:
                        sys.stderr.write(f"Notice: [project_sync] Remote clone exception on {node}: {_err}\n")

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
