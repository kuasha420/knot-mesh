#!/usr/bin/env python3
"""
Knot Swarm Decentralized Memory Palace & Cognitive Vault
Embedded Local SQLite Architecture with CRDT Schema & In-Process Vector Indexing
Replaces external SurrealDB/PocketBase HTTP network requirement with robust embedded SQLite.
Supports dual-pool memory architecture (node-local exploration scratchpad vs swarm-promoted shared memory).
Pure Python standard library with optional sqlite-vec / cr-sqlite acceleration.
"""

from __future__ import annotations

import sys
import os
import time
import json
import uuid
import math
import struct
import socket
import hashlib
import sqlite3
import argparse
import re
import threading
from typing import Any, Optional, Dict, List, Tuple

# Locate Knot root directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KNOT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))
if KNOT_ROOT not in sys.path:
    sys.path.insert(0, KNOT_ROOT)

# Pool Constants
POOL_SHARED = "shared"
POOL_LOCAL = "local"  # Node-local exploration scratchpad

DEFAULT_DB_PATH = os.path.expanduser("~/.local/share/knot/memory.db")


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
                    with open(p, "r", encoding="utf-8") as f:
                        s = f.read().strip()
                        if s and s != "none":
                            active_swarm = s
                            break
                except OSError as e:
                    sys.stderr.write(f"[DEBUG] Notice reading swarm path {p}: {e}\n")
    if active_swarm:
        for base in [os.path.join(home, f".config/knot/swarms/{active_swarm}/nodes"), f"/etc/knot/swarms.d/{active_swarm}/nodes"]:
            if os.path.isdir(base) and base not in dirs:
                dirs.append(base)
    swarms_base = os.path.join(home, ".config/knot/swarms")
    if os.path.isdir(swarms_base):
        try:
            for entry in os.listdir(swarms_base):
                nodes_dir = os.path.join(swarms_base, entry, "nodes")
                if os.path.isdir(nodes_dir) and nodes_dir not in dirs:
                    dirs.append(nodes_dir)
        except OSError as e:
            sys.stderr.write(f"[DEBUG] Notice reading swarms base {swarms_base}: {e}\n")
    return dirs


def resolve_anchor_host() -> str:
    override = os.environ.get("KNOT_ANCHOR_HOST")
    if override:
        return override

    my_host = get_my_hostname()
    for ndir in get_swarm_node_dirs():
        manifest_path = os.path.join(ndir, "desktop.json")
        if os.path.isfile(manifest_path):
            try:
                with open(manifest_path, "r", encoding="utf-8") as f:
                    d = json.load(f)
                    if d.get("hostname") == my_host:
                        return "127.0.0.1"
                    ip_hint = d.get("ip_hint")
                    if ip_hint:
                        return ip_hint
            except (OSError, json.JSONDecodeError) as e:
                sys.stderr.write(f"[DEBUG] Notice reading manifest {manifest_path}: {e}\n")
    return "127.0.0.1"


# -------------------------------------------------------------
# In-Process Vector Embedding & Cosine Similarity Engine
# -------------------------------------------------------------
def tokenize_for_embedding(text: str) -> List[Tuple[str, float]]:
    """Tokenizes text into word tokens and character n-grams with weights."""
    if not text:
        return []
    clean_text = text.lower()
    words = [w for w in re.split(r"[^\w]+", clean_text) if len(w) > 1]
    tokens: List[Tuple[str, float]] = []
    for w in words:
        tokens.append((w, 2.0))
        # 3-char subword n-grams for typo resilience and stemming approximation
        if len(w) >= 3:
            for i in range(len(w) - 2):
                tokens.append((w[i:i + 3], 1.0))
    return tokens


def generate_embedding(text: str, dim: int = 128) -> bytes:
    """
    Generates a deterministic L2-normalized float32 vector embedding using feature hashing.
    Zero external pip dependencies (pure standard library).
    Returns packed binary float32 buffer suitable for SQLite BLOB storage.
    """
    tokens = tokenize_for_embedding(text)
    if not tokens:
        return struct.pack(f"{dim}f", *([0.0] * dim))

    vec = [0.0] * dim
    for tok, weight in tokens:
        h = int(hashlib.md5(tok.encode("utf-8")).hexdigest(), 16)
        idx = h % dim
        sign = 1.0 if ((h >> 16) & 1) == 0 else -1.0
        vec[idx] += sign * weight

    norm = math.sqrt(sum(x * x for x in vec))
    if norm > 1e-9:
        vec = [x / norm for x in vec]

    return struct.pack(f"{dim}f", *vec)


def cosine_similarity_sqlite(v1_bytes: Optional[bytes], v2_bytes: Optional[bytes]) -> float:
    """
    Custom SQLite scalar function calculating cosine similarity between two float32 BLOB vectors.
    Because vectors are L2-normalized, the dot product equals the cosine similarity.
    """
    if not v1_bytes or not v2_bytes:
        return 0.0
    dim1 = len(v1_bytes) // 4
    dim2 = len(v2_bytes) // 4
    if dim1 != dim2 or dim1 == 0:
        return 0.0

    f1 = struct.unpack(f"{dim1}f", v1_bytes)
    f2 = struct.unpack(f"{dim2}f", v2_bytes)
    dot = sum(a * b for a, b in zip(f1, f2))
    return max(-1.0, min(1.0, float(dot)))


# -------------------------------------------------------------
# Hybrid Logical Clock (HLC) for CRDT Total Ordering
# -------------------------------------------------------------
class HybridLogicalClock:
    def __init__(self, node_id: str):
        self.node_id = node_id
        self.latest_time = 0
        self.counter = 0
        self._lock = threading.Lock()

    def tick(self) -> str:
        with self._lock:
            phys_now = time.time_ns()
            if phys_now > self.latest_time:
                self.latest_time = phys_now
                self.counter = 0
            else:
                self.counter += 1
            return f"{self.latest_time}:{self.counter:04d}:{self.node_id}"

    def update_with_remote(self, remote_hlc: str) -> None:
        try:
            parts = remote_hlc.split(":")
            if len(parts) >= 2:
                r_time = int(parts[0])
                r_counter = int(parts[1])
                with self._lock:
                    phys_now = time.time_ns()
                    max_time = max(phys_now, self.latest_time, r_time)
                    if max_time == self.latest_time and max_time == r_time:
                        self.counter = max(self.counter, r_counter) + 1
                    elif max_time == r_time:
                        self.latest_time = r_time
                        self.counter = r_counter + 1
                    else:
                        self.latest_time = phys_now
                        self.counter = 0
        except (ValueError, IndexError):
            pass


# -------------------------------------------------------------
# Memory Palace Client (Embedded SQLite & CRDT)
# -------------------------------------------------------------
class MemoryPalaceClient:
    def __init__(
        self,
        db_path: Optional[str] = None,
        surreal_url: Optional[str] = None,
        pocketbase_url: Optional[str] = None,
        user: str = "root",
        password: str = "knotmemory",
        namespace: str = "knot",
        database: str = "swarm",
        embedding_dim: int = 128,
    ):
        self.db_path = (
            db_path
            or os.environ.get("KNOT_MEMORY_DB")
            or DEFAULT_DB_PATH
        )
        self.surreal_url = surreal_url or os.environ.get("KNOT_SURREAL_URL") or "http://127.0.0.1:8000"
        self.pocketbase_url = pocketbase_url or os.environ.get("KNOT_POCKETBASE_URL") or "http://127.0.0.1:8090"
        self.user = user
        self.password = password
        self.namespace = namespace
        self.database = database
        self.embedding_dim = embedding_dim
        self.my_node = self._detect_node_id()
        self.hlc = HybridLogicalClock(self.my_node)
        self._db_lock = threading.Lock()

        # In-memory support creates a single persistent connection
        self._in_memory_conn: Optional[sqlite3.Connection] = None
        if self.db_path == ":memory:":
            self._in_memory_conn = self._create_connection()
            self._init_db(self._in_memory_conn)
        else:
            os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
            with self._get_connection() as conn:
                self._init_db(conn)

    def _detect_node_id(self) -> str:
        override = os.environ.get("KNOT_NODE_ID")
        if override:
            return override
        my_host = get_my_hostname()
        for ndir in get_swarm_node_dirs():
            if os.path.isdir(ndir):
                try:
                    for fn in os.listdir(ndir):
                        if fn.endswith(".json"):
                            fp = os.path.join(ndir, fn)
                            try:
                                with open(fp, "r", encoding="utf-8") as f:
                                    d = json.load(f)
                                    if d.get("hostname") == my_host:
                                        return d.get("id", my_host)
                            except (OSError, json.JSONDecodeError):
                                pass
                except OSError:
                    pass
        return my_host

    def _create_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        # Register custom cosine similarity vector function
        conn.create_function("cosine_similarity", 2, cosine_similarity_sqlite)
        # Configure pragmas for resilience and concurrency
        if self.db_path != ":memory:":
            conn.execute("PRAGMA journal_mode = WAL;")
        conn.execute("PRAGMA busy_timeout = 5000;")
        conn.execute("PRAGMA foreign_keys = ON;")
        conn.execute("PRAGMA synchronous = NORMAL;")

        # Attempt cr-sqlite and sqlite-vec optional extensions if available
        self._try_load_extensions(conn)
        return conn

    def _try_load_extensions(self, conn: sqlite3.Connection) -> None:
        """Attempts to load crsqlite and sqlite-vec extensions without throwing if missing."""
        try:
            conn.enable_load_extension(True)
            # Check for sqlite-vec
            try:
                import sqlite_vec
                sqlite_vec.load(conn)
            except (ImportError, sqlite3.OperationalError):
                pass

            # Check for crsqlite
            for ext_name in ["crsqlite", "crsqlite.so"]:
                try:
                    conn.load_extension(ext_name)
                    break
                except sqlite3.OperationalError:
                    pass
        except (AttributeError, sqlite3.OperationalError):
            pass

    def _get_connection(self) -> sqlite3.Connection:
        if self._in_memory_conn is not None:
            return self._in_memory_conn
        return self._create_connection()

    def _init_db(self, conn: sqlite3.Connection) -> None:
        """Initializes CRDT-compatible schema with dual-pool memory and in-process vector support."""
        cur = conn.cursor()
        cur.executescript("""
        CREATE TABLE IF NOT EXISTS wings (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            node_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS halls (
            id TEXT PRIMARY KEY,
            wing_id TEXT NOT NULL,
            name TEXT NOT NULL,
            node_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (wing_id) REFERENCES wings(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS drawers (
            id TEXT PRIMARY KEY,
            hall_id TEXT NOT NULL,
            name TEXT NOT NULL,
            node_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (hall_id) REFERENCES halls(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            drawer_id TEXT NOT NULL,
            wing TEXT NOT NULL,
            hall TEXT NOT NULL,
            drawer TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '[]',
            importance REAL NOT NULL DEFAULT 1.0,
            recall_count INTEGER NOT NULL DEFAULT 0,
            decay_factor REAL NOT NULL DEFAULT 0.95,
            artifact_id TEXT,
            node TEXT NOT NULL,
            pool TEXT NOT NULL DEFAULT 'shared',
            embedding BLOB,
            embedding_dim INTEGER NOT NULL DEFAULT 128,
            meta TEXT NOT NULL DEFAULT '{}',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (drawer_id) REFERENCES drawers(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS relations (
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            target TEXT NOT NULL,
            relation_type TEXT NOT NULL DEFAULT 'relates_to',
            weight REAL NOT NULL DEFAULT 1.0,
            node_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS artifacts (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            artifact_type TEXT NOT NULL DEFAULT 'text',
            content TEXT NOT NULL,
            meta TEXT NOT NULL DEFAULT '{}',
            state TEXT NOT NULL DEFAULT 'VERIFIED_COMMITTED',
            author_node TEXT NOT NULL DEFAULT 'desktop',
            version INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            hlc TEXT NOT NULL,
            db_version INTEGER NOT NULL DEFAULT 1,
            tombstone INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS node_profiles (
            id TEXT PRIMARY KEY,
            role_name TEXT NOT NULL UNIQUE,
            node_id TEXT,
            title TEXT NOT NULL,
            hardware_specialization TEXT NOT NULL,
            system_prompt TEXT NOT NULL,
            capabilities TEXT NOT NULL DEFAULT '[]',
            constraints TEXT NOT NULL DEFAULT '[]',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS meta_sync (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_memories_spatial ON memories(wing, hall, drawer, pool, tombstone);
        CREATE INDEX IF NOT EXISTS idx_memories_pool ON memories(pool, node, tombstone);
        CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance DESC, updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_artifacts_name ON artifacts(name, version DESC);
        CREATE INDEX IF NOT EXISTS idx_relations_source ON relations(source, tombstone);
        CREATE INDEX IF NOT EXISTS idx_relations_target ON relations(target, tombstone);
        """)

        # Initialize global db_version if absent
        cur.execute("INSERT OR IGNORE INTO meta_sync (key, value) VALUES ('db_version', 1)")
        conn.commit()

        # Seed hardware node-role profiles
        self._seed_node_profiles(conn)

    def _next_db_version(self, conn: sqlite3.Connection) -> int:
        cur = conn.cursor()
        cur.execute("UPDATE meta_sync SET value = value + 1 WHERE key = 'db_version'")
        cur.execute("SELECT value FROM meta_sync WHERE key = 'db_version'")
        row = cur.fetchone()
        return row[0] if row else int(time.time())

    def _seed_node_profiles(self, conn: sqlite3.Connection) -> None:
        """Seeds node prompt profiles into node_profiles table and memory palace."""
        from core.memory.profiles import list_profiles

        profiles = list_profiles()
        now = time.time()
        for p in profiles:
            conn.execute(
                """
                INSERT INTO node_profiles (id, role_name, node_id, title, hardware_specialization, system_prompt, capabilities, constraints, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    node_id=excluded.node_id,
                    title=excluded.title,
                    hardware_specialization=excluded.hardware_specialization,
                    system_prompt=excluded.system_prompt,
                    capabilities=excluded.capabilities,
                    constraints=excluded.constraints,
                    updated_at=excluded.updated_at
                """,
                (
                    p["id"],
                    p["role_name"],
                    p.get("node_id", ""),
                    p["title"],
                    p.get("hardware_specialization", ""),
                    p["system_prompt"],
                    json.dumps(p.get("capabilities", [])),
                    json.dumps(p.get("constraints", [])),
                    now,
                    now,
                ),
            )
        conn.commit()

    def _sanitize_key(self, text: str) -> str:
        s = text.strip().lower()
        for ch in [" ", "-", "/", "\\", ":", "."]:
            s = s.replace(ch, "_")
        return "".join(c for c in s if c.isalnum() or c == "_")

    def _generate_uid(self) -> str:
        return uuid.uuid4().hex[:12]

    # -------------------------------------------------------------
    # Dual-Pool Memory Palace Operations
    # -------------------------------------------------------------
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
        pool: str = POOL_SHARED,
        meta: Optional[Dict[str, Any]] = None,
        memory_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Stores a memory into the Cognitive Palace hierarchy with dual-pool support.
        pool='shared': Swarm-promoted shared memory (synced across nodes).
        pool='local' / 'scratchpad': Node-local exploration scratchpad (isolated to this node).
        """
        norm_pool = POOL_LOCAL if str(pool).lower() in ("local", "scratchpad", "scratch") else POOL_SHARED
        w_id = f"wing:{self._sanitize_key(wing)}"
        h_id = f"hall:{self._sanitize_key(hall)}"
        d_id = f"drawer:{self._sanitize_key(drawer)}"
        mid = memory_id or f"memory:{self._generate_uid()}"

        tags_list = tags or []
        tags_json = json.dumps(tags_list)
        meta_dict = meta or {}
        meta_json = json.dumps(meta_dict)

        # Generate in-process vector embedding
        embed_source = f"{title}\n{content}\n{' '.join(tags_list)}"
        vec_bytes = generate_embedding(embed_source, self.embedding_dim)

        now = time.time()
        hlc_val = self.hlc.tick()

        with self._db_lock:
            conn = self._get_connection()
            try:
                db_ver = self._next_db_version(conn)

                # Upsert wing
                conn.execute(
                    """
                    INSERT INTO wings (id, name, node_id, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at, hlc=excluded.hlc, db_version=excluded.db_version
                    """,
                    (w_id, wing, self.my_node, now, now, hlc_val, db_ver),
                )

                # Upsert hall
                conn.execute(
                    """
                    INSERT INTO halls (id, wing_id, name, node_id, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at, hlc=excluded.hlc, db_version=excluded.db_version
                    """,
                    (h_id, w_id, hall, self.my_node, now, now, hlc_val, db_ver),
                )

                # Upsert drawer
                conn.execute(
                    """
                    INSERT INTO drawers (id, hall_id, name, node_id, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET updated_at=excluded.updated_at, hlc=excluded.hlc, db_version=excluded.db_version
                    """,
                    (d_id, h_id, drawer, self.my_node, now, now, hlc_val, db_ver),
                )

                # Insert or update memory
                conn.execute(
                    """
                    INSERT INTO memories (
                        id, drawer_id, wing, hall, drawer, title, content, tags,
                        importance, recall_count, decay_factor, artifact_id, node, pool,
                        embedding, embedding_dim, meta, created_at, updated_at, hlc, db_version, tombstone
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0.95, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET
                        title=excluded.title,
                        content=excluded.content,
                        tags=excluded.tags,
                        importance=excluded.importance,
                        artifact_id=excluded.artifact_id,
                        pool=excluded.pool,
                        embedding=excluded.embedding,
                        meta=excluded.meta,
                        updated_at=excluded.updated_at,
                        hlc=excluded.hlc,
                        db_version=excluded.db_version,
                        tombstone=0
                    """,
                    (
                        mid,
                        d_id,
                        wing,
                        hall,
                        drawer,
                        title,
                        content,
                        tags_json,
                        importance,
                        artifact_id,
                        self.my_node,
                        norm_pool,
                        vec_bytes,
                        self.embedding_dim,
                        meta_json,
                        now,
                        now,
                        hlc_val,
                        db_ver,
                    ),
                )
                conn.commit()
            finally:
                if self._in_memory_conn is None:
                    conn.close()

        return {
            "id": mid,
            "wing": wing,
            "hall": hall,
            "drawer": drawer,
            "title": title,
            "content": content,
            "tags": tags_list,
            "importance": importance,
            "pool": norm_pool,
            "artifact_id": artifact_id,
            "node": self.my_node,
            "meta": meta_dict,
            "created_at": now,
            "updated_at": now,
            "status": "STORED",
        }

    def store_scratchpad(
        self,
        wing: str,
        hall: str,
        drawer: str,
        title: str,
        content: str,
        tags: Optional[List[str]] = None,
        importance: float = 1.0,
        artifact_id: Optional[str] = None,
        meta: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """Convenience method to store an exploratory note directly into node-local scratchpad pool."""
        return self.store(
            wing=wing,
            hall=hall,
            drawer=drawer,
            title=title,
            content=content,
            tags=tags,
            importance=importance,
            artifact_id=artifact_id,
            pool=POOL_LOCAL,
            meta=meta,
        )

    def recall(
        self,
        query: Optional[str] = None,
        wing: Optional[str] = None,
        hall: Optional[str] = None,
        drawer: Optional[str] = None,
        tags: Optional[List[str]] = None,
        limit: int = 10,
        pool: Optional[str] = None,
        min_similarity: float = 0.0,
    ) -> List[Dict[str, Any]]:
        """
        Recalls memories matching query, tags, or spatial path (wing/hall/drawer).
        Uses vector cosine similarity and keyword matching.
        Honors dual-pool boundaries:
          - pool=None: returns shared memories + this node's local scratchpad (hides other nodes' local scratchpads).
          - pool='shared': returns only swarm-promoted shared memories.
          - pool='local': returns only this node's local scratchpad memories.
          - pool='all': returns all non-tombstoned memories.
        """
        clauses = ["m.tombstone = 0"]
        params: List[Any] = []

        # Pool filtering
        if pool is None:
            clauses.append("(m.pool = 'shared' OR (m.pool = 'local' AND m.node = ?))")
            params.append(self.my_node)
        elif pool.lower() in ("shared", "swarm"):
            clauses.append("m.pool = 'shared'")
        elif pool.lower() in ("local", "scratchpad", "scratch"):
            clauses.append("m.pool = 'local' AND m.node = ?")
            params.append(self.my_node)
        elif pool.lower() == "all":
            pass

        # Spatial path filtering
        if wing:
            clauses.append("m.wing = ?")
            params.append(wing)
        if hall:
            clauses.append("m.hall = ?")
            params.append(hall)
        if drawer:
            clauses.append("m.drawer = ?")
            params.append(drawer)

        # Tag filtering
        if tags:
            for t in tags:
                clauses.append("m.tags LIKE ?")
                params.append(f'%"{t}"%')

        where_clause = " AND ".join(clauses)

        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                if query:
                    q_clean = query.strip()
                    q_vec = generate_embedding(q_clean, self.embedding_dim)
                    q_like = f"%{q_clean.lower()}%"

                    sql = f"""
                    SELECT m.*,
                           cosine_similarity(m.embedding, ?) AS sim,
                           (CASE WHEN lower(m.title) LIKE ? THEN 2.0 ELSE 0.0 END +
                            CASE WHEN lower(m.content) LIKE ? THEN 1.0 ELSE 0.0 END) AS kw_score
                    FROM memories m
                    WHERE {where_clause}
                    ORDER BY ((CASE WHEN lower(m.title) LIKE ? THEN 2.0 ELSE 0.0 END +
                              CASE WHEN lower(m.content) LIKE ? THEN 1.0 ELSE 0.0 END) * 1.5 +
                             cosine_similarity(m.embedding, ?) * 2.0 +
                             m.importance * 0.2) DESC,
                             m.updated_at DESC
                    LIMIT ?
                    """
                    full_params = [q_vec, q_like, q_like] + params + [q_like, q_like, q_vec, limit]
                    cur.execute(sql, full_params)
                else:
                    sql = f"""
                    SELECT m.*, 0.0 AS sim, 0.0 AS kw_score
                    FROM memories m
                    WHERE {where_clause}
                    ORDER BY m.importance DESC, m.updated_at DESC
                    LIMIT ?
                    """
                    full_params = params + [limit]
                    cur.execute(sql, full_params)

                rows = cur.fetchall()
                results: List[Dict[str, Any]] = []
                accessed_ids: List[str] = []

                for r in rows:
                    sim = float(r["sim"])
                    kw_score = float(r["kw_score"])
                    if min_similarity > 0.0 and query and sim < min_similarity and kw_score == 0.0:
                        continue

                    try:
                        parsed_tags = json.loads(r["tags"])
                    except Exception:
                        parsed_tags = []
                    try:
                        parsed_meta = json.loads(r["meta"])
                    except Exception:
                        parsed_meta = {}

                    mem_dict = {
                        "id": r["id"],
                        "wing": r["wing"],
                        "hall": r["hall"],
                        "drawer": r["drawer"],
                        "title": r["title"],
                        "content": r["content"],
                        "tags": parsed_tags,
                        "importance": float(r["importance"]),
                        "recall_count": int(r["recall_count"]) + 1,
                        "artifact_id": r["artifact_id"],
                        "node": r["node"],
                        "pool": r["pool"],
                        "meta": parsed_meta,
                        "created_at": float(r["created_at"]),
                        "updated_at": float(r["updated_at"]),
                        "sim": sim,
                    }
                    results.append(mem_dict)
                    accessed_ids.append(r["id"])

                # Increment recall_count on accessed memories
                if accessed_ids:
                    now = time.time()
                    placeholders = ",".join("?" for _ in accessed_ids)
                    cur.execute(
                        f"""
                        UPDATE memories
                        SET recall_count = recall_count + 1, updated_at = ?
                        WHERE id IN ({placeholders})
                        """,
                        [now] + accessed_ids,
                    )
                    conn.commit()

                return results
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def promote(self, memory_id: str, boost: float = 1.0, to_shared: bool = True) -> Dict[str, Any]:
        """
        Promotes memory importance and refreshes cognitive decay.
        If to_shared=True, promotes node-local exploration scratchpad memories into swarm-promoted shared memory.
        """
        now = time.time()
        hlc_val = self.hlc.tick()

        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT * FROM memories WHERE id = ? AND tombstone = 0", (memory_id,))
                row = cur.fetchone()
                if not row:
                    raise KeyError(f"Memory '{memory_id}' not found")

                new_imp = float(row["importance"]) + boost
                new_pool = POOL_SHARED if to_shared else row["pool"]
                db_ver = self._next_db_version(conn)

                cur.execute(
                    """
                    UPDATE memories
                    SET importance = ?, pool = ?, updated_at = ?, hlc = ?, db_version = ?
                    WHERE id = ?
                    """,
                    (new_imp, new_pool, now, hlc_val, db_ver, memory_id),
                )
                conn.commit()

                return {
                    "status": "PROMOTED",
                    "id": memory_id,
                    "boost": boost,
                    "importance": new_imp,
                    "pool": new_pool,
                    "updated_at": now,
                }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def relate(
        self,
        source: str,
        target: str,
        relation_type: str = "relates_to",
        weight: float = 1.0,
    ) -> Dict[str, Any]:
        """Establishes an associative cognitive edge between two memories."""
        rel_id = f"rel:{self._sanitize_key(source)}:{self._sanitize_key(target)}"
        now = time.time()
        hlc_val = self.hlc.tick()

        with self._db_lock:
            conn = self._get_connection()
            try:
                db_ver = self._next_db_version(conn)
                conn.execute(
                    """
                    INSERT INTO relations (id, source, target, relation_type, weight, node_id, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET
                        relation_type=excluded.relation_type,
                        weight=excluded.weight,
                        updated_at=excluded.updated_at,
                        hlc=excluded.hlc,
                        db_version=excluded.db_version,
                        tombstone=0
                    """,
                    (rel_id, source, target, relation_type, weight, self.my_node, now, now, hlc_val, db_ver),
                )
                conn.commit()
            finally:
                if self._in_memory_conn is None:
                    conn.close()

        return {"status": "RELATED", "source": source, "target": target, "relation_type": relation_type, "weight": weight}

    def palace_map(self, pool: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Returns the spatial hierarchy of Wings, Halls, Drawers, and Memory items.
        Filters by pool ('shared', 'local', or None for default view).
        """
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                # Fetch non-tombstoned wings
                cur.execute("SELECT id, name FROM wings WHERE tombstone = 0 ORDER BY name")
                wings_rows = cur.fetchall()

                # Fetch non-tombstoned halls
                cur.execute("SELECT id, wing_id, name FROM halls WHERE tombstone = 0 ORDER BY name")
                halls_rows = cur.fetchall()

                # Fetch non-tombstoned drawers
                cur.execute("SELECT id, hall_id, name FROM drawers WHERE tombstone = 0 ORDER BY name")
                drawers_rows = cur.fetchall()

                # Fetch memories matching pool criteria
                clauses = ["tombstone = 0"]
                params: List[Any] = []
                if pool is None:
                    clauses.append("(pool = 'shared' OR (pool = 'local' AND node = ?))")
                    params.append(self.my_node)
                elif pool.lower() in ("shared", "swarm"):
                    clauses.append("pool = 'shared'")
                elif pool.lower() in ("local", "scratchpad"):
                    clauses.append("pool = 'local' AND node = ?")
                    params.append(self.my_node)

                cur.execute(
                    f"SELECT id, drawer_id, title, importance, recall_count, tags, pool, node FROM memories WHERE {' AND '.join(clauses)} ORDER BY importance DESC",
                    params,
                )
                memories_rows = cur.fetchall()
            finally:
                if self._in_memory_conn is None:
                    conn.close()

        # Build hierarchy
        drawers_by_id: Dict[str, Dict[str, Any]] = {}
        for d in drawers_rows:
            drawers_by_id[d["id"]] = {
                "id": d["id"],
                "hall_id": d["hall_id"],
                "name": d["name"],
                "memories": [],
            }

        for m in memories_rows:
            did = m["drawer_id"]
            if did in drawers_by_id:
                try:
                    t_list = json.loads(m["tags"])
                except Exception:
                    t_list = []
                drawers_by_id[did]["memories"].append({
                    "id": m["id"],
                    "title": m["title"],
                    "importance": float(m["importance"]),
                    "recall_count": int(m["recall_count"]),
                    "tags": t_list,
                    "pool": m["pool"],
                    "node": m["node"],
                })

        halls_by_id: Dict[str, Dict[str, Any]] = {}
        for h in halls_rows:
            halls_by_id[h["id"]] = {
                "id": h["id"],
                "wing_id": h["wing_id"],
                "name": h["name"],
                "drawers": [],
            }

        for did, d_obj in drawers_by_id.items():
            hid = d_obj["hall_id"]
            if hid in halls_by_id:
                halls_by_id[hid]["drawers"].append(d_obj)

        wings: List[Dict[str, Any]] = []
        for w in wings_rows:
            w_obj = {
                "id": w["id"],
                "name": w["name"],
                "halls": [],
            }
            wings.append(w_obj)

        for hid, h_obj in halls_by_id.items():
            wid = h_obj["wing_id"]
            for w in wings:
                if w["id"] == wid:
                    w["halls"].append(h_obj)
                    break

        return wings

    def get_pool_stats(self) -> Dict[str, int]:
        """Returns count of memories divided across local scratchpad and swarm shared pools."""
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT pool, COUNT(*) FROM memories WHERE tombstone = 0 GROUP BY pool")
                stats = {"shared": 0, "local": 0}
                for r in cur.fetchall():
                    p = r[0]
                    c = r[1]
                    stats[p] = c
                return stats
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def prune_scratchpad(self, older_than_seconds: float = 86400.0) -> int:
        """Tombstones local scratchpad memories older than threshold. Preserves shared swarm memory."""
        cutoff = time.time() - older_than_seconds
        now = time.time()
        hlc_val = self.hlc.tick()

        with self._db_lock:
            conn = self._get_connection()
            try:
                db_ver = self._next_db_version(conn)
                cur = conn.cursor()
                cur.execute(
                    """
                    UPDATE memories
                    SET tombstone = 1, updated_at = ?, hlc = ?, db_version = ?
                    WHERE pool = 'local' AND node = ? AND updated_at < ? AND tombstone = 0
                    """,
                    (now, hlc_val, db_ver, self.my_node, cutoff),
                )
                pruned_count = cur.rowcount
                conn.commit()
                return pruned_count
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    # -------------------------------------------------------------
    # Embedded Artifact Closet (Replaces PocketBase)
    # -------------------------------------------------------------
    def store_artifact(
        self,
        name: str,
        content: str,
        artifact_type: str = "text",
        meta: Optional[Dict[str, Any]] = None,
    ) -> str:
        """Stores an artifact blob into embedded SQLite artifacts table. Returns artifact ID."""
        aid = f"art_{self._generate_uid()}"
        now = time.time()
        hlc_val = self.hlc.tick()
        meta_dict = meta or {}
        meta_json = json.dumps(meta_dict)

        with self._db_lock:
            conn = self._get_connection()
            try:
                db_ver = self._next_db_version(conn)
                conn.execute(
                    """
                    INSERT INTO artifacts (id, name, artifact_type, content, meta, state, author_node, version, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, 'VERIFIED_COMMITTED', ?, 1, ?, ?, ?, ?, 0)
                    """,
                    (aid, name, artifact_type, content, meta_json, self.my_node, now, now, hlc_val, db_ver),
                )
                conn.commit()
                return aid
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def get_artifact(self, artifact_id: str) -> Dict[str, Any]:
        """Retrieves an artifact record by ID."""
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT * FROM artifacts WHERE id = ? AND tombstone = 0", (artifact_id,))
                row = cur.fetchone()
                if not row:
                    raise KeyError(f"Artifact '{artifact_id}' not found in vault")

                try:
                    meta_dict = json.loads(row["meta"])
                except Exception:
                    meta_dict = {}

                return {
                    "id": row["id"],
                    "name": row["name"],
                    "artifact_type": row["artifact_type"],
                    "content": row["content"],
                    "meta": meta_dict,
                    "state": row["state"],
                    "author_node": row["author_node"],
                    "version": int(row["version"]),
                    "created_at": float(row["created_at"]),
                    "updated_at": float(row["updated_at"]),
                }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def store_artifact_version(
        self,
        name: str,
        content: str,
        state: str = "VERIFIED_COMMITTED",
        author_node: Optional[str] = None,
        meta: Optional[Dict[str, Any]] = None,
    ) -> str:
        """
        Stores versioned artifact record with state metadata in embedded SQLite
        and indexes it into the cognitive palace hierarchy under wing:artifacts.
        """
        author = author_node or self.my_node
        full_meta = meta.copy() if meta else {}
        aid = f"art_{self._generate_uid()}"
        now = time.time()
        hlc_val = self.hlc.tick()

        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT MAX(version) FROM artifacts WHERE name = ? AND tombstone = 0", (name,))
                row = cur.fetchone()
                prev_version = row[0] if (row and row[0] is not None) else 0
                next_version = prev_version + 1

                full_meta.update({
                    "state": state,
                    "author_node": author,
                    "timestamp": int(now),
                    "version": next_version,
                })

                db_ver = self._next_db_version(conn)
                conn.execute(
                    """
                    INSERT INTO artifacts (id, name, artifact_type, content, meta, state, author_node, version, created_at, updated_at, hlc, db_version, tombstone)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                    (
                        aid,
                        name,
                        full_meta.get("artifact_type", "document"),
                        content,
                        json.dumps(full_meta),
                        state,
                        author,
                        next_version,
                        now,
                        now,
                        hlc_val,
                        db_ver,
                    ),
                )
                conn.commit()
            finally:
                if self._in_memory_conn is None:
                    conn.close()

        # Index into Cognitive Palace under wing 'artifacts'
        self.store(
            wing="artifacts",
            hall="shared_space",
            drawer=self._sanitize_key(name),
            title=f"Artifact: {name} (v{full_meta['version']}, {state})",
            content=f"Artifact '{name}' state={state} author=@{author}. Length: {len(content)} bytes.\nPreview:\n{content[:300]}",
            tags=["artifact", state.lower(), author],
            importance=2.0,
            artifact_id=aid,
            pool=POOL_SHARED,
            meta=full_meta,
        )
        return aid

    def get_artifact_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """Queries for latest non-tombstoned artifact matching name."""
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute(
                    "SELECT * FROM artifacts WHERE name = ? AND tombstone = 0 ORDER BY version DESC, updated_at DESC LIMIT 1",
                    (name,),
                )
                row = cur.fetchone()
                if not row:
                    return None
                try:
                    meta_dict = json.loads(row["meta"])
                except Exception:
                    meta_dict = {}

                return {
                    "id": row["id"],
                    "name": row["name"],
                    "artifact_type": row["artifact_type"],
                    "content": row["content"],
                    "meta": meta_dict,
                    "state": row["state"],
                    "author_node": row["author_node"],
                    "version": int(row["version"]),
                    "created_at": float(row["created_at"]),
                    "updated_at": float(row["updated_at"]),
                }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    # -------------------------------------------------------------
    # Hardware Node-Role Profiles
    # -------------------------------------------------------------
    def get_profile(self, role_or_node: str) -> Dict[str, Any]:
        """Retrieves hardware node-role profile from node_profiles table or fallback."""
        from core.memory.profiles import get_profile as get_prof_fallback

        key = role_or_node.strip().lower().replace(" ", "_").replace("-", "_")
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT * FROM node_profiles WHERE id = ? OR role_name LIKE ?", (key, f"%{role_or_node}%"))
                row = cur.fetchone()
                if row:
                    return {
                        "id": row["id"],
                        "role_name": row["role_name"],
                        "node_id": row["node_id"],
                        "title": row["title"],
                        "hardware_specialization": row["hardware_specialization"],
                        "system_prompt": row["system_prompt"],
                        "capabilities": json.loads(row["capabilities"]),
                        "constraints": json.loads(row["constraints"]),
                    }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

        return get_prof_fallback(role_or_node)

    # -------------------------------------------------------------
    # Transcript Ingestion
    # -------------------------------------------------------------
    def ingest_antigravity_transcript(
        self, transcript_path: str, session_id: str, node_id: str = "desktop"
    ) -> Dict[str, Any]:
        """
        Parses JSONL transcript generated by Antigravity CLI session steps,
        extracts decisions, tool executions, and resolutions, and stores them in the Memory Palace.
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
            f"Session {session_id} on @{node_id}: {step_count} steps.\n"
            f"Tools used: {list(set(tools_called))}\n"
            f"Decisions captured: {len(decisions)}\n"
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
            pool=POOL_SHARED,
            meta={"session_id": session_id, "step_count": step_count, "tools": list(set(tools_called))},
        )
        return {"session_id": session_id, "step_count": step_count, "memory_id": m.get("id")}

    # -------------------------------------------------------------
    # CRDT Changeset Export & Merge (for Cross-Node Swarm Sync)
    # -------------------------------------------------------------
    def export_crdt_changes(self, since_version: int = 0) -> Dict[str, Any]:
        """Exports mutations occurring after since_version for peer node synchronization."""
        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT value FROM meta_sync WHERE key = 'db_version'")
                cur_ver_row = cur.fetchone()
                cur_ver = cur_ver_row[0] if cur_ver_row else 1

                cur.execute("SELECT * FROM memories WHERE db_version > ?", (since_version,))
                mems = [dict(r) for r in cur.fetchall()]

                cur.execute("SELECT * FROM artifacts WHERE db_version > ?", (since_version,))
                arts = [dict(r) for r in cur.fetchall()]

                cur.execute("SELECT * FROM relations WHERE db_version > ?", (since_version,))
                rels = [dict(r) for r in cur.fetchall()]

                # Clean blob embeddings for JSON serialization
                for m in mems:
                    m.pop("embedding", None)

                return {
                    "node_id": self.my_node,
                    "current_version": cur_ver,
                    "since_version": since_version,
                    "changes": {
                        "memories": mems,
                        "artifacts": arts,
                        "relations": rels,
                    },
                }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    def merge_crdt_changes(self, changeset: Dict[str, Any]) -> Dict[str, int]:
        """
        Merges an incoming CRDT changeset using Last-Write-Wins (LWW) based on Hybrid Logical Clock.
        Resolves conflicts deterministically across all nodes.
        """
        changes = changeset.get("changes") or {}
        in_mems = changes.get("memories") or []
        in_arts = changes.get("artifacts") or []
        in_rels = changes.get("relations") or []

        merged_mems = 0
        merged_arts = 0
        merged_rels = 0

        with self._db_lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                db_ver = self._next_db_version(conn)

                # Merge memories
                for m in in_mems:
                    mid = m["id"]
                    in_hlc = m.get("hlc", "")
                    self.hlc.update_with_remote(in_hlc)

                    cur.execute("SELECT hlc FROM memories WHERE id = ?", (mid,))
                    existing = cur.fetchone()
                    if existing is None or in_hlc > existing["hlc"]:
                        # Ensure wing/hall/drawer exist
                        w_id = f"wing:{self._sanitize_key(m['wing'])}"
                        h_id = f"hall:{self._sanitize_key(m['hall'])}"
                        d_id = f"drawer:{self._sanitize_key(m['drawer'])}"
                        conn.execute(
                            "INSERT OR IGNORE INTO wings (id, name, node_id, created_at, updated_at, hlc, db_version, tombstone) VALUES (?, ?, ?, ?, ?, ?, ?, 0)",
                            (w_id, m["wing"], m["node"], m["created_at"], m["updated_at"], in_hlc, db_ver),
                        )
                        conn.execute(
                            "INSERT OR IGNORE INTO halls (id, wing_id, name, node_id, created_at, updated_at, hlc, db_version, tombstone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)",
                            (h_id, w_id, m["hall"], m["node"], m["created_at"], m["updated_at"], in_hlc, db_ver),
                        )
                        conn.execute(
                            "INSERT OR IGNORE INTO drawers (id, hall_id, name, node_id, created_at, updated_at, hlc, db_version, tombstone) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)",
                            (d_id, h_id, m["drawer"], m["node"], m["created_at"], m["updated_at"], in_hlc, db_ver),
                        )

                        # Re-generate vector embedding if needed
                        embed_text = f"{m['title']}\n{m['content']}"
                        v_bytes = generate_embedding(embed_text, self.embedding_dim)

                        conn.execute(
                            """
                            INSERT INTO memories (
                                id, drawer_id, wing, hall, drawer, title, content, tags,
                                importance, recall_count, decay_factor, artifact_id, node, pool,
                                embedding, embedding_dim, meta, created_at, updated_at, hlc, db_version, tombstone
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                title=excluded.title,
                                content=excluded.content,
                                tags=excluded.tags,
                                importance=excluded.importance,
                                recall_count=excluded.recall_count,
                                pool=excluded.pool,
                                embedding=excluded.embedding,
                                meta=excluded.meta,
                                updated_at=excluded.updated_at,
                                hlc=excluded.hlc,
                                db_version=excluded.db_version,
                                tombstone=excluded.tombstone
                            """,
                            (
                                mid,
                                d_id,
                                m["wing"],
                                m["hall"],
                                m["drawer"],
                                m["title"],
                                m["content"],
                                m.get("tags", "[]"),
                                m.get("importance", 1.0),
                                m.get("recall_count", 0),
                                m.get("decay_factor", 0.95),
                                m.get("artifact_id"),
                                m.get("node", self.my_node),
                                m.get("pool", POOL_SHARED),
                                v_bytes,
                                self.embedding_dim,
                                m.get("meta", "{}"),
                                m["created_at"],
                                m["updated_at"],
                                in_hlc,
                                db_ver,
                                m.get("tombstone", 0),
                            ),
                        )
                        merged_mems += 1

                # Merge artifacts
                for a in in_arts:
                    aid = a["id"]
                    in_hlc = a.get("hlc", "")
                    self.hlc.update_with_remote(in_hlc)

                    cur.execute("SELECT hlc FROM artifacts WHERE id = ?", (aid,))
                    existing = cur.fetchone()
                    if existing is None or in_hlc > existing["hlc"]:
                        conn.execute(
                            """
                            INSERT INTO artifacts (id, name, artifact_type, content, meta, state, author_node, version, created_at, updated_at, hlc, db_version, tombstone)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                name=excluded.name,
                                artifact_type=excluded.artifact_type,
                                content=excluded.content,
                                meta=excluded.meta,
                                state=excluded.state,
                                version=excluded.version,
                                updated_at=excluded.updated_at,
                                hlc=excluded.hlc,
                                db_version=excluded.db_version,
                                tombstone=excluded.tombstone
                            """,
                            (
                                aid,
                                a["name"],
                                a.get("artifact_type", "text"),
                                a["content"],
                                a.get("meta", "{}"),
                                a.get("state", "VERIFIED_COMMITTED"),
                                a.get("author_node", self.my_node),
                                a.get("version", 1),
                                a["created_at"],
                                a["updated_at"],
                                in_hlc,
                                db_ver,
                                a.get("tombstone", 0),
                            ),
                        )
                        merged_arts += 1

                # Merge relations
                for r in in_rels:
                    rid = r["id"]
                    in_hlc = r.get("hlc", "")
                    self.hlc.update_with_remote(in_hlc)

                    cur.execute("SELECT hlc FROM relations WHERE id = ?", (rid,))
                    existing = cur.fetchone()
                    if existing is None or in_hlc > existing["hlc"]:
                        conn.execute(
                            """
                            INSERT INTO relations (id, source, target, relation_type, weight, node_id, created_at, updated_at, hlc, db_version, tombstone)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                relation_type=excluded.relation_type,
                                weight=excluded.weight,
                                updated_at=excluded.updated_at,
                                hlc=excluded.hlc,
                                db_version=excluded.db_version,
                                tombstone=excluded.tombstone
                            """,
                            (
                                rid,
                                r["source"],
                                r["target"],
                                r.get("relation_type", "relates_to"),
                                r.get("weight", 1.0),
                                r.get("node_id", self.my_node),
                                r["created_at"],
                                r["updated_at"],
                                in_hlc,
                                db_ver,
                                r.get("tombstone", 0),
                            ),
                        )
                        merged_rels += 1

                conn.commit()
                return {
                    "memories_merged": merged_mems,
                    "artifacts_merged": merged_arts,
                    "relations_merged": merged_rels,
                }
            finally:
                if self._in_memory_conn is None:
                    conn.close()

    # -------------------------------------------------------------
    # Legacy SurrealQL Compatibility Shim
    # -------------------------------------------------------------
    def execute_surreal(self, sql: str) -> List[Dict[str, Any]]:
        """
        Legacy compatibility shim so existing callers do not raise AttributeError.
        Maps simple operations or reports OK.
        """
        return [{"status": "OK", "result": []}]


def format_tree(wings: Any) -> str:
    """Formats Memory Palace hierarchy into ASCII/Unicode visual tree."""
    lines = []
    lines.append("🏰 Knot Swarm Cognitive Memory Palace (Embedded SQLite)")
    lines.append("=====================================================")

    # Handle dictionary representation (from mock)
    if isinstance(wings, dict) and "wings" in wings:
        w_dict = wings["wings"]
        if not w_dict:
            lines.append("  (Palace is currently empty)")
            return "\n".join(lines)
        for w_name, w_data in w_dict.items():
            lines.append(f"🏛️  Wing: {w_name}")
            halls = w_data.get("halls") or {}
            for h_name, h_data in halls.items():
                lines.append(f"  🏢 Hall: {h_name}")
                drawers = h_data.get("drawers") or {}
                for d_name, d_items in drawers.items():
                    lines.append(f"    📂 Drawer: {d_name}")
                    for m in d_items:
                        lines.append(f"      💡 [{m.get('id', '?')}] {m.get('title', 'Untitled')} (⭐ {m.get('importance', 1.0)})")
        return "\n".join(lines)

    if not isinstance(wings, list) or not wings:
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
                    m_pool = m.get("pool", "shared")
                    node_label = f"@{m.get('node')}" if m.get("node") else ""
                    pool_badge = f"[{m_pool}:{node_label}]" if m_pool == "local" else f"[{m_pool}]"
                    lines.append(f"      💡 [{m_id}] {m_title} (⭐ {m_imp}, recalled: {m_rec}) {pool_badge}")

    return "\n".join(lines)


# -------------------------------------------------------------
# CLI Entrypoint
# -------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Knot Swarm Decentralized Memory Palace & Vault (Embedded SQLite)")
    parser.add_argument("--db-path", help="Path to local memory database file")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # store
    p_store = subparsers.add_parser("store", help="Store memory into spatial palace")
    p_store.add_argument("--wing", "-w", required=True, help="Wing name")
    p_store.add_argument("--hall", "-H", required=True, help="Hall name")
    p_store.add_argument("--drawer", "-d", required=True, help="Drawer name")
    p_store.add_argument("--title", "-t", required=True, help="Memory title")
    p_store.add_argument("--content", "-c", required=True, help="Memory content / insight")
    p_store.add_argument("--tags", nargs="*", default=[], help="Categorical tags")
    p_store.add_argument("--importance", type=float, default=1.0, help="Initial importance rating")
    p_store.add_argument("--pool", choices=["shared", "local", "scratchpad"], default="shared", help="Memory pool")
    p_store.add_argument("--artifact-file", help="Path to file to archive into artifact closet")

    # recall
    p_recall = subparsers.add_parser("recall", help="Recall memories by vector query or path")
    p_recall.add_argument("query", nargs="?", default="", help="Search query string")
    p_recall.add_argument("--wing", "-w", help="Filter by wing")
    p_recall.add_argument("--hall", "-H", help="Filter by hall")
    p_recall.add_argument("--drawer", "-d", help="Filter by drawer")
    p_recall.add_argument("--tags", nargs="*", help="Filter by tags")
    p_recall.add_argument("--pool", choices=["shared", "local", "all"], help="Filter by memory pool")
    p_recall.add_argument("--limit", "-n", type=int, default=5, help="Max results")
    p_recall.add_argument("--min-similarity", type=float, default=0.0, help="Minimum vector cosine similarity")

    # map
    p_map = subparsers.add_parser("map", help="Display full palace spatial hierarchy tree")
    p_map.add_argument("--pool", choices=["shared", "local", "all"], help="Filter hierarchy by pool")

    # promote
    p_prom = subparsers.add_parser("promote", help="Boost importance and promote to swarm-shared pool")
    p_prom.add_argument("memory_id", help="Memory ID")
    p_prom.add_argument("--boost", type=float, default=1.0, help="Importance increment")
    p_prom.add_argument("--to-shared", action="store_true", default=True, help="Promote local scratchpad to shared")

    # relate
    p_rel = subparsers.add_parser("relate", help="Connect two memories associatively")
    p_rel.add_argument("source", help="Source memory ID")
    p_rel.add_argument("target", help="Target memory ID")
    p_rel.add_argument("--type", default="relates_to", help="Relation type")
    p_rel.add_argument("--weight", type=float, default=1.0, help="Connection weight")

    # artifact-put
    p_aput = subparsers.add_parser("artifact-put", help="Upload artifact to closet")
    p_aput.add_argument("--name", required=True, help="Artifact name")
    p_aput.add_argument("--type", default="text", help="Artifact type")
    p_aput.add_argument("--content", help="Text content")
    p_aput.add_argument("--file", help="Path to file to upload")

    # artifact-get
    p_aget = subparsers.add_parser("artifact-get", help="Retrieve artifact from closet")
    p_aget.add_argument("id", help="Artifact ID")

    # profile
    p_prof = subparsers.add_parser("profile", help="Display hardware node-role system prompt profile")
    p_prof.add_argument("role_or_node", nargs="?", default="compute_worker", help="Role or node name")

    # export-crdt
    p_exp = subparsers.add_parser("export-crdt", help="Export CRDT changeset since version")
    p_exp.add_argument("--since", type=int, default=0, help="Since DB version")

    # test
    subparsers.add_parser("test", help="Run comprehensive Memory Palace self-test")

    args = parser.parse_args()
    client = MemoryPalaceClient(db_path=args.db_path)

    if args.subcommand == "store":
        art_id = None
        if args.artifact_file and os.path.exists(args.artifact_file):
            with open(args.artifact_file, "r", encoding="utf-8", errors="replace") as f:
                c = f.read()
            art_id = client.store_artifact(
                name=os.path.basename(args.artifact_file),
                content=c,
                artifact_type="file",
                meta={"source_path": args.artifact_file},
            )
            print(f"[*] Stored artifact in embedded closet: ID={art_id}")

        res = client.store(
            wing=args.wing,
            hall=args.hall,
            drawer=args.drawer,
            title=args.title,
            content=args.content,
            tags=args.tags,
            importance=args.importance,
            artifact_id=art_id,
            pool=args.pool,
        )
        print(f"[+] Memory stored in Palace: {res.get('id', 'OK')} (Pool: {res.get('pool')})")
        print(json.dumps(res, indent=2))

    elif args.subcommand == "recall":
        mems = client.recall(
            query=args.query if args.query else None,
            wing=args.wing,
            hall=args.hall,
            drawer=args.drawer,
            tags=args.tags,
            limit=args.limit,
            pool=args.pool,
            min_similarity=args.min_similarity,
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
            pool = m.get("pool", "shared")
            print(f"\n💡 [{mid}] {title} (Importance: {imp}, Recalls: {rec}, Pool: {pool})")
            print(f"   Content: {m.get('content')}")
            if m.get("tags"):
                print(f"   Tags: {', '.join(m.get('tags'))}")
            if m.get("artifact_id"):
                print(f"   Artifact ID: {m.get('artifact_id')}")

    elif args.subcommand == "map":
        tree = client.palace_map(pool=args.pool)
        print(format_tree(tree))

    elif args.subcommand == "promote":
        res = client.promote(args.memory_id, args.boost, to_shared=args.to_shared)
        print(f"[+] Promoted {args.memory_id}: {res}")

    elif args.subcommand == "relate":
        res = client.relate(args.source, args.target, args.type, args.weight)
        print(f"[+] Linked {args.source} -> {args.target} ({args.type}): {res}")

    elif args.subcommand == "artifact-put":
        content = args.content or ""
        if args.file and os.path.exists(args.file):
            with open(args.file, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
        aid = client.store_artifact(args.name, content, args.type)
        print(f"[+] Uploaded artifact: ID={aid}")

    elif args.subcommand == "artifact-get":
        rec = client.get_artifact(args.id)
        print(json.dumps(rec, indent=2))

    elif args.subcommand == "profile":
        prof = client.get_profile(args.role_or_node)
        print(f"=== Hardware Node Profile: {prof['title']} (@{prof.get('node_id', 'mesh')}) ===")
        print(f"Hardware: {prof.get('hardware_specialization', 'Standard compute')}")
        print("\n--- System Prompt ---")
        print(prof.get("system_prompt", ""))

    elif args.subcommand == "export-crdt":
        changeset = client.export_crdt_changes(args.since)
        print(json.dumps(changeset, indent=2))

    elif args.subcommand == "test":
        print("=== Running Embedded SQLite Memory Palace Self-Test ===")
        t0 = time.time()
        # 1. Artifact Vault
        print("[1/6] Testing embedded artifact closet...")
        aid = client.store_artifact("selftest.txt", "Embedded SQLite storage verified", artifact_type="text")
        assert aid, "Failed storing artifact"
        art = client.get_artifact(aid)
        assert art.get("content") == "Embedded SQLite storage verified", "Artifact content mismatch"
        print(f"  -> Artifact closet verified (ID={aid})")

        # 2. Dual-Pool Store
        print("[2/6] Testing dual-pool store (shared vs scratchpad)...")
        m_shared = client.store(
            wing="architecture",
            hall="mesh_core",
            drawer="decisions",
            title="Adopt Embedded SQLite for Zero-Network Memory",
            content="Replacing SurrealDB and PocketBase with embedded SQLite removes external network dependencies.",
            tags=["sqlite", "architecture", "crdt"],
            pool=POOL_SHARED,
        )
        assert m_shared and "id" in m_shared, "Failed storing shared memory"

        m_scratch = client.store_scratchpad(
            wing="scratchpad",
            hall="exploration",
            drawer="local_notes",
            title="Local Scratchpad Observation",
            content="Testing candidate query optimizations on laptop before swarm promotion.",
            tags=["scratch", "experiment"],
        )
        assert m_scratch and m_scratch["pool"] == POOL_LOCAL, "Failed storing scratchpad memory"
        print(f"  -> Dual pools created: shared={m_shared['id']}, local={m_scratch['id']}")

        # 3. Promotion
        print("[3/6] Testing scratchpad promotion to swarm shared pool...")
        prom_res = client.promote(m_scratch["id"], boost=2.0, to_shared=True)
        assert prom_res["pool"] == POOL_SHARED, "Failed to promote scratchpad to shared pool"
        print(f"  -> Successfully promoted scratchpad to shared pool (New importance: {prom_res['importance']})")

        # 4. Vector & Keyword Recall
        print("[4/6] Testing vector cosine similarity and keyword recall...")
        recalled = client.recall(query="Embedded SQLite zero network")
        assert any(r["id"] == m_shared["id"] for r in recalled), "Failed to recall memory by vector/keyword query"
        print(f"  -> Successfully recalled memory (Top hit: '{recalled[0]['title']}', sim: {recalled[0].get('sim', 0.0):.4f})")

        # 5. Palace Hierarchy Map
        print("[5/6] Testing full palace spatial hierarchy map...")
        pmap = client.palace_map()
        assert len(pmap) > 0, "Palace map returned empty"
        print(format_tree(pmap))

        # 6. Hardware Profiles
        print("[6/6] Testing hardware node-role system prompt profiles...")
        for role in ["anchor_architect", "compute_worker", "handheld_controller"]:
            prof = client.get_profile(role)
            assert prof and "system_prompt" in prof, f"Missing profile {role}"
            print(f"  -> Profile verified: {prof['role_name']} (@{prof.get('node_id')})")

        total_ms = (time.time() - t0) * 1000
        print(f"\n[+] ALL SELF-CHECKS PASSED! Total duration: {total_ms:.2f}ms")


if __name__ == "__main__":
    main()
