#!/usr/bin/env python3
"""
Knot Swarm MCP Sync & Permission Pre-Approval Utility
Ensures all 3 kinds of Antigravity (CLI, 2.0 Desktop App, IDE) on the local host
have the Knot MCP server configured, all 13 tool schemas deployed, and global
pre-approval grants injected across all projects with zero prompts.
Zero external dependencies (uses standard library Python 3).
"""

import json
import os
import shutil
import sys

KNOT_TOOLS = [
    "knot_task_post",
    "knot_task_wait",
    "knot_task_list",
    "knot_node_status",
    "knot_quota_matrix",
    "knot_gpu_status",
    "knot_memory_store",
    "knot_memory_recall",
    "knot_memory_palace_map",
    "knot_memory_promote",
    "knot_memory_relate",
    "knot_closet_store",
    "knot_closet_get",
    "knot_task_fanout",
    "knot_task_batch_status",
    "knot_artifact_lock",
    "knot_artifact_commit",
    "knot_chat_post",
    "knot_chat_read",
    "knot_project_list",
    "knot_chat_list_conversations",
    "knot_chat_create_conversation",
    "knot_exec_command",
    "knot_swarm_topology",
]

def sync_mcp():
    knot_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    schemas_dir = os.path.join(knot_root, "core", "mcp", "schemas")
    gateway_script = os.path.join(knot_root, "core", "mcp", "gateway.py")

    home = os.path.expanduser("~")
    gemini_dir = os.path.join(home, ".gemini")
    config_dir = os.path.join(gemini_dir, "config")
    os.makedirs(config_dir, exist_ok=True)

    print(f"[*] Knot MCP Sync starting on {os.uname().nodename}...")
    print(f"    Knot Root: {knot_root}")
    print(f"    Schemas:   {schemas_dir}")

    # 1. Update ~/.gemini/config/mcp_config.json
    mcp_config_path = os.path.join(config_dir, "mcp_config.json")
    mcp_cfg = {"mcpServers": {}}
    if os.path.exists(mcp_config_path):
        try:
            with open(mcp_config_path, "r") as f:
                mcp_cfg = json.load(f)
        except Exception:
            mcp_cfg = {"mcpServers": {}}

    if "mcpServers" not in mcp_cfg:
        mcp_cfg["mcpServers"] = {}

    mcp_cfg["mcpServers"]["knot"] = {
        "command": sys.executable,
        "args": [gateway_script],
        "disabled": False
    }

    with open(mcp_config_path, "w") as f:
        json.dump(mcp_cfg, f, indent=2)
    print(f"[+] Updated global MCP config: {mcp_config_path}")

    # 2. Symlink mcp_config.json for Antigravity (2.0) and Antigravity IDE
    for app_dir_name in ["antigravity", "antigravity-ide", "antigravity-cli"]:
        app_dir = os.path.join(gemini_dir, app_dir_name)
        if not os.path.exists(app_dir):
            os.makedirs(app_dir, exist_ok=True)

        target_link = os.path.join(app_dir, "mcp_config.json")
        if os.path.islink(target_link):
            os.unlink(target_link)
        elif os.path.exists(target_link):
            os.remove(target_link)
        try:
            os.symlink(mcp_config_path, target_link)
            print(f"[+] Symlinked {target_link} -> {mcp_config_path}")
        except Exception as e:
            print(f"[!] Could not symlink {target_link}: {e}")

    # 3. Deploy schemas to all 3 Antigravity directories
    for app_dir_name in ["antigravity", "antigravity-cli", "antigravity-ide"]:
        app_knot_mcp = os.path.join(gemini_dir, app_dir_name, "mcp", "knot")
        os.makedirs(app_knot_mcp, exist_ok=True)
        if os.path.exists(schemas_dir):
            for fname in os.listdir(schemas_dir):
                src = os.path.join(schemas_dir, fname)
                dst = os.path.join(app_knot_mcp, fname)
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
            print(f"[+] Deployed {len(os.listdir(schemas_dir))} files (schemas + instructions) to: {app_knot_mcp}")

    # 4. Global Permission Pre-Approval in ~/.gemini/config/config.json
    main_cfg_path = os.path.join(config_dir, "config.json")
    main_cfg = {}
    if os.path.exists(main_cfg_path):
        try:
            with open(main_cfg_path, "r") as f:
                main_cfg = json.load(f)
        except Exception:
            main_cfg = {}

    if "userSettings" not in main_cfg:
        main_cfg["userSettings"] = {}
    user_settings = main_cfg["userSettings"]

    if "globalPermissionGrants" not in user_settings:
        user_settings["globalPermissionGrants"] = {"allow": []}
    grants = user_settings["globalPermissionGrants"]
    if "allow" not in grants:
        grants["allow"] = []

    allow_list = grants["allow"]
    required_grants = ["mcp(knot/*)"] + [f"mcp(knot/{t})" for t in KNOT_TOOLS]
    added = 0
    for rg in required_grants:
        if rg not in allow_list:
            allow_list.append(rg)
            added += 1

    with open(main_cfg_path, "w") as f:
        json.dump(main_cfg, f, indent=2)
    print(f"[+] Pre-approved {len(required_grants)} Knot MCP permission grants in {main_cfg_path}")

    # 5. Pre-approve in VS Code / Antigravity IDE settings
    vscode_dirs = [
        os.path.join(home, ".config", "Antigravity", "User"),
        os.path.join(home, ".config", "Antigravity IDE", "User"),
        os.path.join(home, ".config", "Code", "User")
    ]
    for vdir in vscode_dirs:
        if os.path.exists(vdir):
            vsettings_path = os.path.join(vdir, "settings.json")
            vcfg = {}
            if os.path.exists(vsettings_path):
                try:
                    with open(vsettings_path, "r") as f:
                        vcfg = json.load(f)
                except Exception:
                    vcfg = {}
            vcfg["antigravity.mcp.alwaysAllow"] = ["knot"]
            vcfg["antigravity.mcp.autoApprove"] = True
            vcfg["mcp.alwaysAllow"] = ["knot"]
            with open(vsettings_path, "w") as f:
                json.dump(vcfg, f, indent=4)
            print(f"[+] Injected IDE auto-approvals into {vsettings_path}")

    print("[✓] Knot MCP Suite is fully synchronized and pre-approved on this node!\n")

if __name__ == "__main__":
    sync_mcp()
