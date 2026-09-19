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
    node_id_file = os.path.join(home, ".config/knot/node_id")
    if os.path.isfile(node_id_file):
        try:
            with open(node_id_file, "r", encoding="utf-8") as nf:
                val = nf.read().strip()
                if val:
                    return val
        except Exception:
            pass

    # 3. System hostname
    try:
        cur_host = subprocess.run(["hostname", "-s"], capture_output=True, text=True).stdout.strip()
    except Exception:
        cur_host = ""

    # 4. Swarm topology manifests
    for manifest_path in glob.glob(os.path.join(home, ".config/knot/swarms/*/nodes/*.json")):
        try:
            with open(manifest_path, "r", encoding="utf-8") as mf:
                m = json.load(mf)
            nid = m.get("id", "")
            m_host = m.get("hostname", "")
            aliases = m.get("aliases", [])
            if cur_host and (cur_host == m_host or cur_host in aliases or cur_host == nid):
                return nid
        except Exception:
            pass

    # 5. Nodes list match
    if nodes:
        if cur_host and cur_host in nodes:
            return cur_host
        return nodes[0]

    return cur_host or "localhost"


if __name__ == "__main__":
    candidates = sys.argv[1].split(",") if len(sys.argv) > 1 and sys.argv[1] else None
    print(resolve_local_node_id(candidates))
