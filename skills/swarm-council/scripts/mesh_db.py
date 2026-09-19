#!/usr/bin/env python3
"""
Swarm Council: Mesh Database Client & Message Board
Provides a distributed SQLite and Knot Hub-backed alternative to GitHub Discussions.
Matches gh_discussion.py CLI interface 1:1 for zero-overhead switching between ghd and mesh.
"""

import argparse
import datetime
import json
import os
import sqlite3
import ssl
import sys
import urllib.error
import urllib.request
import uuid

DEFAULT_DB_PATH = os.path.expanduser("~/.config/knot/council.db")


def get_db_connection(db_path: str = DEFAULT_DB_PATH) -> sqlite3.Connection:
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=30.0)
    conn.execute("PRAGMA journal_mode = WAL;")
    conn.execute("PRAGMA synchronous = NORMAL;")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS council_threads (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            category TEXT DEFAULT 'general',
            url TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_council_threads_run ON council_threads(run_id);")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS council_messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            run_id TEXT NOT NULL,
            node_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'PROGRESS',
            body TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_council_msgs_thread ON council_messages(thread_id);")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_council_msgs_time ON council_messages(created_at);")
    conn.commit()
    return conn


def try_hub_request(method: str, path: str, payload: dict = None, timeout: float = 2.0) -> dict | None:
    hub_url = os.environ.get("KNOT_HUB_URL", "https://127.0.0.1:4242").rstrip("/")
    url = f"{hub_url}{path}"
    data = json.dumps(payload).encode("utf-8") if payload else None
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def create_thread(title: str, body: str, run_id: str = "", category: str = "general", db_path: str = DEFAULT_DB_PATH) -> dict:
    thread_id = run_id if run_id else f"mesh_{datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    url = f"knot://mesh/council/{thread_id}"

    # Try Hub API first
    hub_payload = {
        "id": thread_id,
        "run_id": run_id or thread_id,
        "title": title,
        "body": body,
        "category": category,
        "url": url,
        "created_at": now_iso
    }
    hub_res = try_hub_request("POST", "/council/threads", hub_payload)
    if hub_res and hub_res.get("id"):
        return hub_res

    # Local SQLite fallback
    conn = get_db_connection(db_path)
    with conn:
        conn.execute(
            "INSERT OR REPLACE INTO council_threads (id, run_id, title, body, category, url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (thread_id, run_id or thread_id, title, body, category, url, now_iso)
        )
    conn.close()

    return {
        "id": thread_id,
        "number": 1,
        "url": url,
        "title": title
    }


def post_reply(discussion_id: str, body: str, node_id: str, run_id: str, status: str = "PROGRESS", db_path: str = DEFAULT_DB_PATH) -> dict:
    msg_id = f"msg_{datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    url = f"knot://mesh/council/{discussion_id}#{msg_id}"

    # Try Hub API first
    hub_payload = {
        "id": msg_id,
        "thread_id": discussion_id,
        "run_id": run_id,
        "node_id": node_id,
        "status": status,
        "body": body,
        "created_at": now_iso
    }
    hub_res = try_hub_request("POST", f"/council/threads/{discussion_id}/reply", hub_payload)
    if hub_res and hub_res.get("id"):
        return hub_res

    # Local SQLite fallback
    conn = get_db_connection(db_path)
    with conn:
        conn.execute(
            "INSERT INTO council_messages (id, thread_id, run_id, node_id, status, body, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (msg_id, discussion_id, run_id, node_id, status, body, now_iso)
        )
    conn.close()

    return {
        "id": msg_id,
        "url": url,
        "createdAt": now_iso
    }


def poll_delta(discussion_id: str, last_count: int = 0, db_path: str = DEFAULT_DB_PATH) -> dict:
    # Try Hub API first
    hub_res = try_hub_request("GET", f"/council/threads/{discussion_id}/delta?last_count={last_count}")
    if hub_res and "totalCount" in hub_res:
        return hub_res

    # Local SQLite fallback
    conn = get_db_connection(db_path)
    cur = conn.cursor()
    cur.execute(
        "SELECT id, run_id, node_id, status, body, created_at FROM council_messages WHERE thread_id = ? ORDER BY created_at ASC",
        (discussion_id,)
    )
    rows = cur.fetchall()
    conn.close()

    total = len(rows)
    if total <= last_count:
        return {"totalCount": total, "new_comments": []}

    new_rows = rows[last_count:]
    new_comments = []
    for r in new_rows:
        mid, mrun, mnode, mstat, mbody, mtime = r
        header = f"<!-- KNOT-NODE: {mnode} | RUN: {mrun} | STATUS: {mstat} -->\n"
        full_body = header + mbody if not mbody.startswith("<!-- KNOT-NODE:") else mbody
        new_comments.append({
            "id": mid,
            "createdAt": mtime,
            "author": {"login": mnode},
            "body": full_body
        })

    return {"totalCount": total, "new_comments": new_comments}


def get_full_thread(discussion_id: str, db_path: str = DEFAULT_DB_PATH) -> dict:
    # Try Hub API first
    hub_res = try_hub_request("GET", f"/council/threads/{discussion_id}")
    if hub_res and "comments" in hub_res:
        return hub_res

    # Local SQLite fallback
    conn = get_db_connection(db_path)
    cur = conn.cursor()
    cur.execute(
        "SELECT id, run_id, title, body, url, created_at FROM council_threads WHERE id = ? OR run_id = ?",
        (discussion_id, discussion_id)
    )
    t_row = cur.fetchone()

    if not t_row:
        tid = discussion_id
        trun = discussion_id
        ttitle = f"Mesh Council Mission: {discussion_id}"
        tbody = "Mesh registry mission thread"
        turl = f"knot://mesh/council/{discussion_id}"
        ttime = datetime.datetime.now(datetime.timezone.utc).isoformat()
    else:
        tid, trun, ttitle, tbody, turl, ttime = t_row

    cur.execute(
        "SELECT id, run_id, node_id, status, body, created_at FROM council_messages WHERE thread_id = ? OR run_id = ? ORDER BY created_at ASC",
        (tid, tid)
    )
    m_rows = cur.fetchall()
    conn.close()

    comments_nodes = []
    for r in m_rows:
        mid, mrun, mnode, mstat, mbody, mtime = r
        header = f"<!-- KNOT-NODE: {mnode} | RUN: {mrun} | STATUS: {mstat} -->\n"
        full_body = header + mbody if not mbody.startswith("<!-- KNOT-NODE:") else mbody
        comments_nodes.append({
            "id": mid,
            "createdAt": mtime,
            "author": {"login": mnode},
            "body": full_body
        })

    return {
        "id": tid,
        "number": 1,
        "title": ttitle,
        "url": turl,
        "body": tbody,
        "createdAt": ttime,
        "comments": {
            "totalCount": len(comments_nodes),
            "nodes": comments_nodes
        }
    }


def list_threads(db_path: str = DEFAULT_DB_PATH) -> list:
    conn = get_db_connection(db_path)
    cur = conn.cursor()
    cur.execute(
        "SELECT id, run_id, title, url, created_at, (SELECT COUNT(*) FROM council_messages WHERE thread_id = council_threads.id) as msg_count FROM council_threads ORDER BY created_at DESC"
    )
    rows = cur.fetchall()
    conn.close()

    threads = []
    for r in rows:
        threads.append({
            "id": r[0],
            "run_id": r[1],
            "title": r[2],
            "url": r[3],
            "created_at": r[4],
            "messages": r[5]
        })
    return threads


def main():
    parser = argparse.ArgumentParser(description="Swarm Council Mesh Database Helper")
    parser.add_argument("--db-path", default=DEFAULT_DB_PATH, help="Path to SQLite database file")
    subparsers = parser.add_subparsers(dest="cmd")

    create_p = subparsers.add_parser("create")
    create_p.add_argument("--title", required=True)
    create_p.add_argument("--body", required=True)
    create_p.add_argument("--run-id", default="")
    create_p.add_argument("--category", default="general")
    create_p.add_argument("--owner", default="")
    create_p.add_argument("--repo", default="")

    reply_p = subparsers.add_parser("reply")
    reply_p.add_argument("--discussion-id", required=True)
    reply_p.add_argument("--body", required=True)
    reply_p.add_argument("--node-id", required=True)
    reply_p.add_argument("--run-id", required=True)
    reply_p.add_argument("--status", default="PROGRESS")

    poll_p = subparsers.add_parser("poll_delta")
    poll_p.add_argument("--discussion-id", required=True)
    poll_p.add_argument("--last-count", type=int, default=0)

    thread_p = subparsers.add_parser("get_thread")
    thread_p.add_argument("--discussion-id", required=True)

    list_p = subparsers.add_parser("list")

    args = parser.parse_args()

    if args.cmd == "create":
        body = args.body.replace('\\n', '\n')
        res = create_thread(args.title, body, run_id=args.run_id, category=args.category, db_path=args.db_path)
        print(json.dumps(res, indent=2))
    elif args.cmd == "reply":
        body = args.body.replace('\\n', '\n')
        res = post_reply(args.discussion_id, body, args.node_id, args.run_id, args.status, db_path=args.db_path)
        print(json.dumps(res, indent=2))
    elif args.cmd == "poll_delta":
        res = poll_delta(args.discussion_id, args.last_count, db_path=args.db_path)
        print(json.dumps(res, indent=2))
    elif args.cmd == "get_thread":
        res = get_full_thread(args.discussion_id, db_path=args.db_path)
        print(json.dumps(res, indent=2))
    elif args.cmd == "list":
        res = list_threads(db_path=args.db_path)
        print(json.dumps(res, indent=2))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
