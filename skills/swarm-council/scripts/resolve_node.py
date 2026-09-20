#!/usr/bin/env python3
"""
Dynamic Node Identifier Resolver
Resolves the Knot mesh node ID dynamically from environment, node_id file,
or swarm topology manifests without hardcoding.
"""
import os
import sys
import glob
import json
import subprocess


def resolve_local_node_id(nodes=None):
    """
    Resolve the local node's mesh identifier.
    Priority:
    1. KNOT_NODE_ID environment variable
    2. ~/.config/knot/node_id file
    3. Swarm topology manifests (~/.config/knot/swarms/*/nodes/*.json)
       matched by hostname, aliases, or node id
    4. Exact match of hostname in supplied nodes list
    5. First node in supplied nodes list (if provided)
    6. System hostname
    """
    # 1. Environment variable
    env_id = os.environ.get("KNOT_NODE_ID")
    if env_id:
        return env_id.strip()

    # 2. Node ID file
    home = os.path.expanduser("~")
    for nid_path in [os.path.join(home, ".config/knot/node_id"), "/etc/knot/node_id"]:
        if os.path.isfile(nid_path):
            try:
                with open(nid_path, "r", encoding="utf-8") as nf:
                    val = nf.read().strip()
                    if val:
                        return val
            except Exception:
                pass

    # 3. System hostname via socket.gethostname() and uname -n
    cur_host = ""
    try:
        import socket
        cur_host = socket.gethostname().strip()
    except Exception:
        cur_host = ""

    if not cur_host:
        try:
            cur_host = os.uname().nodename.strip()
        except Exception:
            pass

    if not cur_host:
        try:
            res = subprocess.run(["uname", "-n"], capture_output=True, text=True, check=False)
            if res.returncode == 0:
                cur_host = res.stdout.strip()
        except Exception:
            pass

    cur_host_short = cur_host.split(".")[0] if cur_host else ""

    # 4. Swarm topology manifests
    detected_nid = None
    manifest_dirs = glob.glob(os.path.join(home, ".config/knot/swarms/*/nodes/*.json")) + \
                    glob.glob("/etc/knot/swarms.d/*/nodes/*.json")
    for manifest_path in manifest_dirs:
        try:
            with open(manifest_path, "r", encoding="utf-8") as mf:
                m = json.load(mf)
            nid = m.get("id", "")
            m_host = m.get("hostname", "")
            aliases = m.get("aliases", [])
            host_matches = {cur_host, cur_host_short} - {""}
            if host_matches and (
                m_host in host_matches or
                any(a in host_matches for a in aliases) or
                nid in host_matches
            ):
                detected_nid = nid
                break
        except Exception:
            pass

    if detected_nid:
        if not nodes or detected_nid in nodes or cur_host in nodes or cur_host_short in nodes:
            return detected_nid

    # 5. Nodes list match
    if nodes:
        if cur_host and cur_host in nodes:
            return cur_host
        if cur_host_short and cur_host_short in nodes:
            return cur_host_short
        return nodes[0]

    return detected_nid or cur_host_short or cur_host or "localhost"


if __name__ == "__main__":
    candidates = sys.argv[1].split(",") if len(sys.argv) > 1 and sys.argv[1] else None
    print(resolve_local_node_id(candidates))
