#!/usr/bin/env python3
"""
Knot Swarm Decentralized Memory Palace & Cognitive Vault Client
Connects to SurrealDB (:8000) for spatial cognitive graph & vector relations
Connects to PocketBase (:8090) for artifact closet & blob storage
Zero external pip dependencies (pure Python 3 standard library).
"""

import sys
import os
import time
import json
import socket
import base64
import argparse
import urllib.request
import urllib.error
from typing import Any, Optional, Dict, List

# Locate Knot root directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KNOT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))

def get_my_hostname() -> str:
    return socket.gethostname()

def get_swarm_node_dirs() -> List[str]:
    home = os.path.expanduser("~")
    dirs = []
    active_swarm = os.environ.get("KNOT_ACTIVE_SWARM")
    if not active_swarm:
        for p in ["/run/knot/active_swarm", os.path.join(home, ".local/state/knot/active_swarm")]:
            if os.path.isfile(p):
                try:
                    with open(p, "r") as f:
                        s = f.read().strip()
                        if s and s != "none":
                            active_swarm = s
                            break
                except Exception:
                    pass
    if active_swarm:
        for base in [os.path.join(home, f".config/knot/swarms/{active_swarm}/nodes"), f"/etc/knot/swarms.d/{active_swarm}/nodes"]:
            if os.path.isdir(base) and base not in dirs:
                dirs.append(base)
    swarms_base = os.path.join(home, ".config/knot/swarms")
    if os.path.isdir(swarms_base):
        for entry in glob.glob(os.path.join(swarms_base, "*/nodes")):
            if os.path.isdir(entry) and entry not in dirs:
                dirs.append(entry)
    for entry in glob.glob("/etc/knot/swarms.d/*/nodes"):
        if os.path.isdir(entry) and entry not in dirs:
            dirs.append(entry)
    return dirs

def resolve_anchor_host() -> str:
    """
    Resolves the Anchor node address. If running on Anchor itself, uses 127.0.0.1.
    Otherwise, queries resolver or falls back to 127.0.0.1.
    """
    override = os.environ.get("KNOT_ANCHOR_HOST")
    if override:
        return override

    my_host = get_my_hostname()
    for ndir in get_swarm_node_dirs():
        manifest_path = os.path.join(ndir, "desktop.json")
        if os.path.isfile(manifest_path):
            try:
                with open(manifest_path, "r") as f:
                    d = json.load(f)
                    if d.get("hostname") == my_host:
                        return "127.0.0.1"
                    ip_hint = d.get("ip_hint")
                    if ip_hint:
                        return ip_hint
            except Exception:
                pass
    return "127.0.0.1"

class MemoryPalaceClient:
    def __init__(
        self,
        surreal_url: Optional[str] = None,
        pocketbase_url: Optional[str] = None,
        user: str = "root",
        password: str = "knotmemory",
        namespace: str = "knot",
        database: str = "swarm",
    ):
        anchor_host = resolve_anchor_host()
        self.surreal_url = surreal_url or os.environ.get("KNOT_SURREAL_URL") or f"http://{anchor_host}:8000"
        self.pocketbase_url = pocketbase_url or os.environ.get("KNOT_POCKETBASE_URL") or f"http://{anchor_host}:8090"
        self.user = user
        self.password = password
        self.namespace = namespace
        self.database = database
        self.my_node = self._detect_node_id()

    def _detect_node_id(self) -> str:
        my_host = get_my_hostname()
        for ndir in get_swarm_node_dirs():
            if os.path.isdir(ndir):
                for fn in os.listdir(ndir):
                    if fn.endswith(".json"):
                        fp = os.path.join(ndir, fn)
                        try:
                            with open(fp, "r") as f:
                                d = json.load(f)
                                if d.get("hostname") == my_host:
                                    return d.get("id", my_host)
                        except Exception:
                            pass
        return my_host

    def execute_surreal(self, sql: str) -> List[Dict[str, Any]]:
        """
        Executes SurrealQL statement(s) against SurrealDB HTTP /sql endpoint.
        Returns the parsed JSON response list.
        """
        url = f"{self.surreal_url.rstrip('/')}/sql"
        # Prefix with USE NS ... DB ... to ensure session context
        full_sql = f"USE NS {self.namespace} DB {self.database};\n{sql}"
        data = full_sql.encode("utf-8")

        req = urllib.request.Request(url, data=data, method="POST")
        auth_str = f"{self.user}:{self.password}"
        auth_b64 = base64.b64encode(auth_str.encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {auth_b64}")
        req.add_header("Accept", "application/json")
        req.add_header("Content-Type", "text/plain; charset=utf-8")

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw = resp.read().decode("utf-8")
                res = json.loads(raw)
                # Filter out the USE statement result
                if isinstance(res, list) and len(res) > 1:
                    return res[1:]
                return res
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"SurrealDB HTTP {e.code}: {err_body}")
        except Exception as e:
            raise RuntimeError(f"SurrealDB connection error to {url}: {e}")

    # -------------------------------------------------------------
    # PocketBase Artifact Closet
    # -------------------------------------------------------------
    def store_artifact(
        self,
        name: str,
        content: str,
        artifact_type: str = "text",
        meta: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Stores an artifact blob into PocketBase collection 'artifacts'.
        Returns the record ID.
        """
        url = f"{self.pocketbase_url.rstrip('/')}/api/collections/artifacts/records"
        payload = {
            "name": name,
            "artifact_type": artifact_type,
            "content": content,
            "meta": meta or {}
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Accept", "application/json")

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                return res.get("id", "")
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"PocketBase store_artifact HTTP {e.code}: {err}")
        except Exception as e:
            raise RuntimeError(f"PocketBase store_artifact error to {url}: {e}")

    def get_artifact(self, artifact_id: str) -> Dict[str, Any]:
        """
        Retrieves an artifact record from PocketBase by record ID.
        """
        url = f"{self.pocketbase_url.rstrip('/')}/api/collections/artifacts/records/{artifact_id}"
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/json")

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="ignore")
            raise RuntimeError(f"PocketBase get_artifact HTTP {e.code}: {err}")
        except Exception as e:
            raise RuntimeError(f"PocketBase get_artifact error to {url}: {e}")

    def store_artifact_version(
        self,
        name: str,
        content: str,
        state: str = "VERIFIED_COMMITTED",
        author_node: str = "desktop",
        meta: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        Stores versioned artifact record with 3-state metadata in PocketBase
        and indexes it into SurrealDB cognitive palace under wing:artifacts.
        """
        full_meta = meta.copy() if meta else {}
        full_meta.update({
            "state": state,
            "author_node": author_node,
            "timestamp": int(time.time()),
            "version": full_meta.get("version", 1)
        })
        aid = self.store_artifact(
            name=name,
            content=content,
            artifact_type=full_meta.get("artifact_type", "document"),
            meta=full_meta
        )
        try:
            self.store(
                wing="artifacts",
                hall="shared_space",
                drawer=self._sanitize_key(name),
                title=f"Artifact: {name} ({state})",
                content=f"Artifact '{name}' state={state} author=@{author_node}. Length: {len(content)} bytes.\\nPreview:\\n{content[:300]}",
                tags=["artifact", state.lower(), author_node],
                importance=2.0,
                artifact_id=aid,
                meta=full_meta
            )
        except Exception:
            pass
        return aid

    def get_artifact_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Queries PocketBase for the latest artifact matching name.
        """
        encoded_filter = urllib.parse.quote(f'name="{name}"')
        url = f"{self.pocketbase_url.rstrip('/')}/api/collections/artifacts/records?filter={encoded_filter}&sort=-created&limit=1"
        req = urllib.request.Request(url, method="GET")
        req.add_header("Accept", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                items = res.get("items", [])
                return items[0] if items else None
        except Exception:
            return None

    def ingest_antigravity_transcript(self, transcript_path: str, session_id: str, node_id: str = "desktop") -> Dict[str, Any]:
        """
        Parses JSONL transcript generated by Antigravity CLI session steps,
        extracts decisions, tool executions, and resolutions, and stores them in SurrealDB.
        """
        if not os.path.isfile(transcript_path):
            return {"error": f"Transcript file not found: {transcript_path}", "ingested": 0}

        decisions = []
        tools_called = []
        errors_resolved = []
        step_count = 0

        with open(transcript_path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    step = json.loads(line)
                    step_count += 1
                    t_type = step.get("type", "")
                    content = step.get("content", "")
                    thinking = step.get("thinking", "")
                    t_calls = step.get("tool_calls", [])

                    for tc in t_calls:
                        tname = tc.get("name", "")
                        if tname:
                            tools_called.append(tname)

                    if t_type == "PLANNER_RESPONSE" and ("decision" in thinking.lower() or "decided" in thinking.lower()):
                        decisions.append(thinking[:400])

                    if step.get("status") == "ERROR":
                        errors_resolved.append(content[:300])
                except Exception:
                    continue

        summary_content = (
            f"Session {session_id} on @{node_id}: {step_count} steps.\\n"
            f"Tools used: {list(set(tools_called))}\\n"
            f"Decisions captured: {len(decisions)}\\n"
            f"Errors logged: {len(errors_resolved)}"
        )

        m = self.store(
            wing="swarm_sessions",
            hall=node_id,
            drawer="transcripts",
            title=f"Session Transcript: {session_id[:8]}",
            content=summary_content,
            tags=["session", node_id, "transcript"],
            importance=1.5,
            meta={"session_id": session_id, "step_count": step_count, "tools": list(set(tools_called))}
        )
        return {"session_id": session_id, "step_count": step_count, "memory_id": m.get("id")}

    # -------------------------------------------------------------
    # Spatial Cognitive Memory Palace (SurrealDB Graph)
    # -------------------------------------------------------------
    def _sanitize_key(self, text: str) -> str:
        s = text.strip().lower()
        for ch in [" ", "-", "/", "\\", ":", "."]:
            s = s.replace(ch, "_")
        return "".join(c for c in s if c.isalnum() or c == "_")

    def store(
        self,
        wing: str,
        hall: str,
        drawer: str,
        title: str,
        content: str,
        tags: Optional[List[str]] = None,
        importance: float = 1.0,
        artifact_id: Optional[str] = None,
        meta: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Stores a memory into the Cognitive Palace hierarchy:
        wing -> contains -> hall -> contains -> drawer -> contains -> memory
        """
        w_id = f"wing:{self._sanitize_key(wing)}"
        h_id = f"hall:{self._sanitize_key(hall)}"
        d_id = f"drawer:{self._sanitize_key(drawer)}"

        meta_json = json.dumps(meta or {})
        tags_json = json.dumps(tags or [])

        sql = f"""
        UPSERT {w_id} SET name = '{wing}', updated_at = time::now();
        UPSERT {h_id} SET name = '{hall}', updated_at = time::now();
        UPSERT {d_id} SET name = '{drawer}', updated_at = time::now();

        LET $e1 = (SELECT id FROM contains WHERE in = {w_id} AND out = {h_id});
        IF array::len($e1) == 0 THEN RELATE {w_id}->contains->{h_id} END;

        LET $e2 = (SELECT id FROM contains WHERE in = {h_id} AND out = {d_id});
        IF array::len($e2) == 0 THEN RELATE {h_id}->contains->{d_id} END;

        LET $mem = CREATE ONLY memory CONTENT {{
            title: {json.dumps(title)},
            content: {json.dumps(content)},
            tags: {tags_json},
            importance: {importance},
            recall_count: 0,
            decay_factor: 0.95,
            artifact_id: {json.dumps(artifact_id)},
            node: '{self.my_node}',
            created_at: time::now(),
            updated_at: time::now(),
            meta: {meta_json}
        }};

        RELATE {d_id}->contains->$mem.id;
        RETURN $mem;
        """

        results = self.execute_surreal(sql)
        mem_data = None
        for res in reversed(results):
            if res.get("status") == "OK" and res.get("result"):
                r = res.get("result")
                if isinstance(r, dict) and "title" in r:
                    mem_data = r
                    break
                elif isinstance(r, list) and len(r) > 0 and isinstance(r[0], dict) and "title" in r[0]:
                    mem_data = r[0]
                    break
        return mem_data or {"status": "STORED", "wing": wing, "hall": hall, "drawer": drawer, "title": title}

    def recall(
        self,
        query: Optional[str] = None,
        wing: Optional[str] = None,
        hall: Optional[str] = None,
        drawer: Optional[str] = None,
        tags: Optional[List[str]] = None,
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Recalls memories matching query, tags, or spatial path (wing/hall/drawer).
        Increments recall_count on accessed memories.
        """
        where_clauses = []
        if query:
            q_esc = json.dumps(query)
            where_clauses.append(f"(string::lowercase(title ?? '') CONTAINS string::lowercase({q_esc}) OR string::lowercase(content ?? '') CONTAINS string::lowercase({q_esc}))")

        if tags:
            for t in tags:
                where_clauses.append(f"tags CONTAINS {json.dumps(t)}")

        # Spatial constraint filtering via reverse graph traversal
        if drawer:
            d_id = f"drawer:{self._sanitize_key(drawer)}"
            where_clauses.append(f"<-contains<-drawer CONTAINS {d_id}")
        elif hall:
            h_id = f"hall:{self._sanitize_key(hall)}"
            where_clauses.append(f"<-contains<-drawer<-contains<-hall CONTAINS {h_id}")
        elif wing:
            w_id = f"wing:{self._sanitize_key(wing)}"
            where_clauses.append(f"<-contains<-drawer<-contains<-hall<-contains<-wing CONTAINS {w_id}")

        filter_str = ""
        if where_clauses:
            filter_str = "WHERE " + " AND ".join(where_clauses)

        sql = f"""
        SELECT * FROM memory {filter_str} ORDER BY importance DESC, created_at DESC LIMIT {limit};
        """
        results = self.execute_surreal(sql)
        items = []
        if results and results[0].get("status") == "OK":
            items = results[0].get("result") or []

        # Bump recall_count in background
        if items:
            id_list = [item["id"] for item in items if "id" in item]
            if id_list:
                bump_sql = "; ".join([f"UPDATE {mid} SET recall_count += 1, updated_at = time::now()" for mid in id_list])
                try:
                    self.execute_surreal(bump_sql)
                except Exception:
                    pass

        return items

    def relate(self, memory_id_1: str, memory_id_2: str, relation_type: str = "relates_to", weight: float = 1.0) -> Dict[str, Any]:
        """
        Establishes an associative cognitive edge between two memories.
        """
        sql = f"""
        RELATE {memory_id_1}->relates_to->{memory_id_2} SET relation_type = '{relation_type}', weight = {weight};
        """
        res = self.execute_surreal(sql)
        return {"status": "RELATED", "source": memory_id_1, "target": memory_id_2, "weight": weight}

    def promote(self, memory_id: str, boost: float = 1.0) -> Dict[str, Any]:
        """
        Promotes memory importance and refreshes its cognitive decay.
        """
        sql = f"""
        UPDATE {memory_id} SET importance += {boost}, updated_at = time::now();
        """
        res = self.execute_surreal(sql)
        return {"status": "PROMOTED", "id": memory_id, "boost": boost}

    def palace_map(self) -> List[Dict[str, Any]]:
        """
        Returns the entire spatial hierarchy of Wings, Halls, Drawers, and Memory titles.
        """
        sql = """
        SELECT *, ->contains->hall.* AS halls FROM wing;
        SELECT *, ->contains->drawer.* AS drawers FROM hall;
        SELECT *, ->contains->memory.{id, title, importance, recall_count, tags} AS memories FROM drawer;
        """
        results = self.execute_surreal(sql)
        wings = []
        halls_by_id = {}
        drawers_by_id = {}

        if len(results) >= 1 and results[0].get("status") == "OK":
            wings = results[0].get("result") or []
        if len(results) >= 2 and results[1].get("status") == "OK":
            for h in results[1].get("result") or []:
                halls_by_id[h["id"]] = h
        if len(results) >= 3 and results[2].get("status") == "OK":
            for d in results[2].get("result") or []:
                drawers_by_id[d["id"]] = d

        # Link drawers into halls
        for hid, h in halls_by_id.items():
            seen_drawers = set()
            full_drawers = []
            for d_stub in h.get("drawers") or []:
                did = d_stub.get("id") if isinstance(d_stub, dict) else d_stub
                if did in seen_drawers:
                    continue
                seen_drawers.add(did)
                if did in drawers_by_id:
                    d_obj = dict(drawers_by_id[did])
                    d_obj["memories"] = [m for m in (d_obj.get("memories") or []) if isinstance(m, dict)]
                    full_drawers.append(d_obj)
                elif isinstance(d_stub, dict):
                    d_obj = dict(d_stub)
                    d_obj["memories"] = [m for m in (d_obj.get("memories") or []) if isinstance(m, dict)]
                    full_drawers.append(d_obj)
            h["drawers"] = full_drawers

        # Link halls into wings
        for w in wings:
            seen_halls = set()
            full_halls = []
            for h_stub in w.get("halls") or []:
                hid = h_stub.get("id") if isinstance(h_stub, dict) else h_stub
                if hid in seen_halls:
                    continue
                seen_halls.add(hid)
                if hid in halls_by_id:
                    full_halls.append(halls_by_id[hid])
                elif isinstance(h_stub, dict):
                    full_halls.append(h_stub)
            w["halls"] = full_halls

        return wings

def format_tree(wings: List[Dict[str, Any]]) -> str:
    lines = []
    lines.append("🏰 Knot Swarm Cognitive Memory Palace")
    lines.append("=====================================")
    if not wings:
        lines.append("  (Palace is currently empty)")
        return "\n".join(lines)

    for w in wings:
        if not isinstance(w, dict):
            continue
        w_name = w.get("name", w.get("id"))
        lines.append(f"🏛️  Wing: {w_name} ({w.get('id')})")
        halls = w.get("halls") or []
        for h in halls:
            if not isinstance(h, dict):
                continue
            h_name = h.get("name", h.get("id"))
            lines.append(f"  🏢 Hall: {h_name} ({h.get('id')})")
            drawers = h.get("drawers") or []
            for d in drawers:
                if not isinstance(d, dict):
                    continue
                d_name = d.get("name", d.get("id"))
                lines.append(f"    📂 Drawer: {d_name} ({d.get('id')})")
                memories = d.get("memories") or []
                for m in memories:
                    if not isinstance(m, dict):
                        continue
                    m_title = m.get("title", "Untitled")
                    m_id = m.get("id")
                    m_imp = m.get("importance", 1.0)
                    m_rec = m.get("recall_count", 0)
                    lines.append(f"      💡 [{m_id}] {m_title} (⭐ {m_imp}, recalled: {m_rec})")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Knot Swarm Decentralized Memory Palace & Vault")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # store
    p_store = subparsers.add_parser("store", help="Store memory into spatial palace")
    p_store.add_argument("--wing", "-w", required=True, help="Wing name (e.g. 'architecture', 'bugfixes')")
    p_store.add_argument("--hall", "-H", required=True, help="Hall name (e.g. 'auth', 'quota')")
    p_store.add_argument("--drawer", "-d", required=True, help="Drawer name (e.g. 'decisions', 'incidents')")
    p_store.add_argument("--title", "-t", required=True, help="Memory title")
    p_store.add_argument("--content", "-c", required=True, help="Memory content / insight")
    p_store.add_argument("--tags", nargs="*", default=[], help="Categorical tags")
    p_store.add_argument("--importance", type=float, default=1.0, help="Initial importance rating")
    p_store.add_argument("--artifact-file", help="Path to file to archive into PocketBase closet")

    # recall
    p_recall = subparsers.add_parser("recall", help="Recall memories by keyword or path")
    p_recall.add_argument("query", nargs="?", default="", help="Search query string")
    p_recall.add_argument("--wing", "-w", help="Filter by wing")
    p_recall.add_argument("--hall", "-H", help="Filter by hall")
    p_recall.add_argument("--drawer", "-d", help="Filter by drawer")
    p_recall.add_argument("--tags", nargs="*", help="Filter by tags")
    p_recall.add_argument("--limit", "-n", type=int, default=5, help="Max results")

    # map
    subparsers.add_parser("map", help="Display full palace spatial hierarchy tree")

    # promote
    p_prom = subparsers.add_parser("promote", help="Boost importance of a memory")
    p_prom.add_argument("memory_id", help="Memory ID (e.g. memory:abc)")
    p_prom.add_argument("--boost", type=float, default=1.0, help="Importance increment")

    # relate
    p_rel = subparsers.add_parser("relate", help="Connect two memories associatively")
    p_rel.add_argument("source", help="Source memory ID")
    p_rel.add_argument("target", help="Target memory ID")
    p_rel.add_argument("--type", default="relates_to", help="Relation type")
    p_rel.add_argument("--weight", type=float, default=1.0, help="Connection weight")

    # artifact-put
    p_aput = subparsers.add_parser("artifact-put", help="Upload artifact to PocketBase vault")
    p_aput.add_argument("--name", required=True, help="Artifact name")
    p_aput.add_argument("--type", default="text", help="Artifact type (diff, code, log, binary)")
    p_aput.add_argument("--content", help="Text content")
    p_aput.add_argument("--file", help="Path to file to upload")

    # artifact-get
    p_aget = subparsers.add_parser("artifact-get", help="Retrieve artifact from PocketBase vault")
    p_aget.add_argument("id", help="Artifact ID")

    # test
    subparsers.add_parser("test", help="Run comprehensive Memory Palace & Vault self-test")

    args = parser.parse_args()
    client = MemoryPalaceClient()

    if args.subcommand == "store":
        art_id = None
        if args.artifact_file and os.path.exists(args.artifact_file):
            with open(args.artifact_file, "r", errors="ignore") as f:
                c = f.read()
            art_id = client.store_artifact(
                name=os.path.basename(args.artifact_file),
                content=c,
                artifact_type="file",
                meta={"source_path": args.artifact_file}
            )
            print(f"[*] Stored artifact in PocketBase vault: ID={art_id}")

        res = client.store(
            wing=args.wing,
            hall=args.hall,
            drawer=args.drawer,
            title=args.title,
            content=args.content,
            tags=args.tags,
            importance=args.importance,
            artifact_id=art_id
        )
        print(f"[+] Memory stored in Palace: {res.get('id', 'OK')}")
        print(json.dumps(res, indent=2))

    elif args.subcommand == "recall":
        mems = client.recall(
            query=args.query if args.query else None,
            wing=args.wing,
            hall=args.hall,
            drawer=args.drawer,
            tags=args.tags,
            limit=args.limit
        )
        if not mems:
            print("[*] No matching memories found in Palace.")
            return

        print(f"[+] Recalled {len(mems)} memory item(s):")
        for m in mems:
            mid = m.get("id", "?")
            title = m.get("title", "Untitled")
            imp = m.get("importance", 1.0)
            rec = m.get("recall_count", 0)
            print(f"\n💡 [{mid}] {title} (Importance: {imp}, Recalls: {rec})")
            print(f"   Content: {m.get('content')}")
            if m.get("tags"):
                print(f"   Tags: {', '.join(m.get('tags'))}")
            if m.get("artifact_id"):
                print(f"   Artifact Vault ID: {m.get('artifact_id')}")

    elif args.subcommand == "map":
        tree = client.palace_map()
        print(format_tree(tree))

    elif args.subcommand == "promote":
        res = client.promote(args.memory_id, args.boost)
        print(f"[+] Promoted {args.memory_id}: {res}")

    elif args.subcommand == "relate":
        res = client.relate(args.source, args.target, args.type, args.weight)
        print(f"[+] Linked {args.source} -> {args.target} ({args.type}): {res}")

    elif args.subcommand == "artifact-put":
        content = args.content or ""
        if args.file and os.path.exists(args.file):
            with open(args.file, "r", errors="ignore") as f:
                content = f.read()
        aid = client.store_artifact(args.name, content, args.type)
        print(f"[+] Uploaded artifact: ID={aid}")

    elif args.subcommand == "artifact-get":
        rec = client.get_artifact(args.id)
        print(json.dumps(rec, indent=2))

    elif args.subcommand == "test":
        print("=== Running Memory Palace & Vault Self-Test ===")
        t0 = time.time()
        # 1. PocketBase
        print("[1/5] Testing PocketBase artifact vault...")
        aid = client.store_artifact(
            name="selftest.diff",
            content="--- a/test\n+++ b/test\n+knot_memory_test",
            artifact_type="diff",
            meta={"test_run": True}
        )
        assert aid, "Failed to get artifact ID"
        art = client.get_artifact(aid)
        assert art.get("name") == "selftest.diff", "Artifact name mismatch"
        print(f"  -> PocketBase artifact verified (ID={aid})")

        # 2. SurrealDB Store
        print("[2/5] Testing Cognitive Palace store & graph indexing...")
        m1 = client.store(
            wing="architecture",
            hall="mesh_core",
            drawer="decisions",
            title="Adopt SurrealDB and PocketBase for Zero-Git Swarm Memory",
            content="SurrealDB provides graph traversal and semantic vector memory. PocketBase serves as artifact closet.",
            tags=["architecture", "memory", "storage"],
            importance=2.5,
            artifact_id=aid
        )
        assert m1 and "id" in m1, f"Failed storing m1: {m1}"
        m1_id = m1["id"]
        print(f"  -> Memory 1 created: {m1_id}")

        m2 = client.store(
            wing="architecture",
            hall="security",
            drawer="auth",
            title="Antigravity CLI Interactive OAuth Flow",
            content="When tokens expire, background headless processes suppress browser tabs with BROWSER=/bin/true while knot auth provides TTY.",
            tags=["auth", "antigravity", "security"],
            importance=2.0
        )
        assert m2 and "id" in m2, f"Failed storing m2: {m2}"
        m2_id = m2["id"]
        print(f"  -> Memory 2 created: {m2_id}")

        # 3. Associate Memories
        print("[3/5] Testing cognitive associative graph edge...")
        rel = client.relate(m1_id, m2_id, "influences", weight=1.5)
        print(f"  -> Associated {m1_id} -> {m2_id}")

        # 4. Recall
        print("[4/5] Testing spatial and keyword recall...")
        recalled = client.recall(query="SurrealDB")
        assert any(r.get("id") == m1_id for r in recalled), "Failed to recall m1 by keyword"
        print(f"  -> Successfully recalled memory by keyword 'SurrealDB' (found {len(recalled)})")

        recalled_spatial = client.recall(wing="architecture", hall="mesh_core")
        assert any(r.get("id") == m1_id for r in recalled_spatial), "Failed spatial recall"
        print(f"  -> Successfully recalled memory by spatial path wing='architecture', hall='mesh_core'")

        # 5. Palace Map
        print("[5/5] Testing full spatial hierarchy map...")
        pmap = client.palace_map()
        assert len(pmap) > 0, "Palace map returned empty"
        print(format_tree(pmap))

        total_ms = (time.time() - t0) * 1000
        print(f"\n[+] ALL TESTS PASSED! Total duration: {total_ms:.2f}ms")

if __name__ == "__main__":
    main()
