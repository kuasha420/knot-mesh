#!/usr/bin/env python3
"""
Swarm Council: Stage 6 Discussion Reconciler
Parses node checkpoints and final verdicts from GitHub Discussions
and generates a consolidated audit report.
"""

import re
import os
import sys
import json
import argparse
import subprocess

def fetch_thread_data(discussion_id, backend="auto", run_id="", db_path=""):
    script_dir = os.path.dirname(os.path.realpath(__file__))
    
    if backend == "auto":
        # Check meta.json if run_id is known
        if run_id:
            meta_path = os.path.expanduser(f"~/.config/knot/missions/{run_id}/meta.json")
            if os.path.exists(meta_path):
                try:
                    with open(meta_path) as mf:
                        mdata = json.load(mf)
                        if mdata.get("db") == "mesh":
                            backend = "mesh"
                        elif mdata.get("db") == "ghd":
                            backend = "ghd"
                except Exception as _err:
                    sys.stderr.write(f"Notice: [reconcile] Handled exception: {_err}\n")
        if backend == "auto":
            if discussion_id.startswith("mesh_") or discussion_id.startswith("run_") or not discussion_id.startswith("D_"):
                backend = "mesh"
            else:
                backend = "ghd"

    if backend == "mesh":
        helper = os.path.join(script_dir, "mesh_db.py")
    else:
        helper = os.path.join(script_dir, "gh_discussion.py")

    cmd = [helper]
    if db_path and backend == "mesh":
        cmd.extend(["--db-path", db_path])
    cmd.extend(["get_thread", "--discussion-id", discussion_id])
    out = subprocess.check_output(cmd, text=True)
    return json.loads(out)

def parse_comments(thread_data, target_run_id):
    comments = thread_data.get("comments", {}).get("nodes", [])
    node_reports = {}

    header_regex = re.compile(
        r'<!--\s*KNOT-NODE:\s*([^\s|]+)\s*\|\s*RUN:\s*([^\s|]+)\s*\|\s*STATUS:\s*([^\s|]+)\s*-->',
        re.IGNORECASE
    )

    for c in comments:
        body = c.get("body", "")
        match = header_regex.search(body)
        if match:
            node_id, run_id, status = match.groups()
            if target_run_id and run_id != target_run_id:
                continue

            content = header_regex.sub('', body).strip()
            node_reports.setdefault(node_id, []).append({
                "run_id": run_id,
                "status": status.upper(),
                "created_at": c.get("createdAt"),
                "author": c.get("author", {}).get("login"),
                "content": content
            })

    return node_reports

def generate_reconciled_report(thread_data, node_reports, target_run_id):
    lines = [
        f"# Swarm Council Consolidated Audit Report",
        f"",
        f"**Run ID**: `{target_run_id or 'all'}`  ",
        f"**Discussion Thread**: [{thread_data.get('title')}]({thread_data.get('url')})  ",
        f"**Total Discussion Comments**: {thread_data.get('comments', {}).get('totalCount', 0)}  ",
        f"",
        "---",
        "",
        "## 1. Executive Summary & Fleet Status Matrix",
        "",
        "| Node ID | Milestones Passed | Final Verdict | Key Findings / Side Quest |",
        "| :--- | :---: | :---: | :--- |"
    ]

    all_verdicts = []

    for node_id, updates in node_reports.items():
        statuses = [u["status"] for u in updates]
        final_update = next((u for u in reversed(updates) if u["status"] == "FINAL"), updates[-1] if updates else None)
        
        milestones = ", ".join([s for s in statuses if s in ["25%", "50%", "75%"]]) or "Direct"
        verdict = "IN_PROGRESS"
        findings_summary = "Awaiting final deliverable."

        if final_update:
            text = final_update["content"]
            if "READY FOR GA" in text.upper():
                verdict = "✅ READY FOR GA"
            elif "NOT READY" in text.upper():
                verdict = "❌ NOT READY (Blocking Issues)"
            else:
                verdict = final_update["status"]

            # Extract first summary paragraph or header
            for p in text.split("\n\n"):
                clean = p.strip().replace("\n", " ")
                if len(clean) > 20 and not clean.startswith("#"):
                    findings_summary = clean[:120] + "..."
                    break

        all_verdicts.append(verdict)
        lines.append(f"| **`{node_id}`** | {milestones} | {verdict} | {findings_summary} |")

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 2. Reconciled Findings by Workstation")
    lines.append("")

    for node_id, updates in node_reports.items():
        lines.append(f"### Workstation: `@{node_id}`")
        for u in updates:
            lines.append(f"#### Status: `{u['status']}` ({u['created_at']})")
            lines.append(u["content"])
            lines.append("")

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Swarm Council Discussion Reconciler")
    parser.add_argument("--discussion-id", required=True, help="Discussion node ID or Mesh thread ID")
    parser.add_argument("--run-id", default="", help="Specific run ID to reconcile")
    parser.add_argument("--db-backend", default="auto", choices=["auto", "ghd", "mesh"], help="Backend: auto (default), ghd, or mesh")
    parser.add_argument("--db-path", default="", help="Custom SQLite database path for mesh backend")
    parser.add_argument("--out-file", default="", help="Output markdown report path")

    args = parser.parse_args()

    thread_data = fetch_thread_data(args.discussion_id, backend=args.db_backend, run_id=args.run_id, db_path=args.db_path)
    node_reports = parse_comments(thread_data, args.run_id)
    report_md = generate_reconciled_report(thread_data, node_reports, args.run_id)

    if args.out_file:
        with open(args.out_file, "w") as f:
            f.write(report_md)
        print(f"Reconciled report written to: {args.out_file}")
    else:
        print(report_md)

if __name__ == "__main__":
    main()
