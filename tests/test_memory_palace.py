#!/usr/bin/env python3
"""
Comprehensive Test Suite for Decentralized Memory Palace & Stateless MCP Gateway.
Verifies embedded SQLite storage, CRDT schema, in-process vector cosine similarity,
dual-pool memory architecture, hardware node-role profiles, and MCP gateway integration.
Strict PSL Rule 1 compliance: zero error swallowing, zero || true.
"""

import os
import sys
from pathlib import Path
import json
import tempfile
import struct
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from core.memory.palace import (
    MemoryPalaceClient,
    HybridLogicalClock,
    generate_embedding,
    cosine_similarity_sqlite,
    format_tree,
    POOL_LOCAL,
    POOL_SHARED,
)
from core.memory.profiles import get_profile, list_profiles
from core.mcp.gateway import KnotMCPGateway, MockKnotHubClient


@pytest.fixture
def temp_db_path():
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tf:
        path = tf.name
    yield path
    for suffix in ["", "-wal", "-shm"]:
        p = path + suffix
        if os.path.exists(p):
            os.remove(p)


@pytest.fixture
def memory_client(temp_db_path):
    os.environ["KNOT_NODE_ID"] = "laptop"
    return MemoryPalaceClient(db_path=temp_db_path)


class TestEmbeddedSQLiteInit:
    def test_in_memory_initialization(self):
        client = MemoryPalaceClient(db_path=":memory:")
        assert client.db_path == ":memory:"
        stats = client.get_pool_stats()
        assert "shared" in stats
        assert "local" in stats

    def test_file_persistence_and_wal_mode(self, temp_db_path):
        client1 = MemoryPalaceClient(db_path=temp_db_path)
        m = client1.store(
            wing="architecture",
            hall="mesh_core",
            drawer="decisions",
            title="Embedded SQLite Architecture",
            content="Local persistence without external daemons",
            tags=["sqlite", "crdt"],
            pool=POOL_SHARED,
        )

        client2 = MemoryPalaceClient(db_path=temp_db_path)
        recalled = client2.recall(wing="architecture")
        assert len(recalled) == 1
        assert recalled[0]["id"] == m["id"]
        assert recalled[0]["title"] == "Embedded SQLite Architecture"


class TestInProcessVectorIndexing:
    def test_deterministic_embedding_generation(self):
        v1 = generate_embedding("Decentralized memory palace with vector indexing", dim=128)
        v2 = generate_embedding("Decentralized memory palace with vector indexing", dim=128)
        assert v1 == v2
        assert len(v1) == 128 * 4  # 128 float32 values = 512 bytes

    def test_cosine_similarity_calculation(self):
        v1 = generate_embedding("Machine learning vector similarity search on CUDA GPU", dim=128)
        v2 = generate_embedding("GPU accelerated vector similarity and embedding index", dim=128)
        v3 = generate_embedding("Baking artisan sourdough bread with flour and yeast", dim=128)

        sim_related = cosine_similarity_sqlite(v1, v2)
        sim_unrelated = cosine_similarity_sqlite(v1, v3)

        assert sim_related > 0.4
        assert sim_unrelated < sim_related

    def test_vector_recall_and_ranking(self, memory_client):
        memory_client.store(
            wing="hardware",
            hall="compute",
            drawer="cuda",
            title="NVIDIA RTX 3050 CUDA Acceleration",
            content="High throughput tensor and vector operations executed on worker laptop GPU",
            tags=["cuda", "nvidia", "gpu"],
        )
        memory_client.store(
            wing="recipes",
            hall="kitchen",
            drawer="pastry",
            title="Croissant Lamination Technique",
            content="Butter folding and chilled dough rolling for layered French pastries",
            tags=["baking", "pastry"],
        )

        hits = memory_client.recall(query="CUDA GPU tensor compute", limit=5)
        assert len(hits) >= 1
        assert hits[0]["title"] == "NVIDIA RTX 3050 CUDA Acceleration"
        assert hits[0]["sim"] > 0.3


class TestDualPoolMemoryArchitecture:
    def test_dual_pool_separation(self, temp_db_path):
        os.environ["KNOT_NODE_ID"] = "laptop"
        c_laptop = MemoryPalaceClient(db_path=temp_db_path)

        shared_mem = c_laptop.store(
            wing="swarm",
            hall="consensus",
            drawer="decisions",
            title="Mesh Release Protocol v2",
            content="Verified release criteria signed by Anchor",
            pool=POOL_SHARED,
        )

        scratch_mem = c_laptop.store_scratchpad(
            wing="scratchpad",
            hall="laptop_experiments",
            drawer="local_drafts",
            title="Candidate SQLite Pruning Strategy",
            content="Experimental idea to test under heavy writes",
        )

        # Laptop queries
        lap_shared = c_laptop.recall(pool="shared")
        assert any(m["id"] == shared_mem["id"] for m in lap_shared)
        assert not any(m["id"] == scratch_mem["id"] for m in lap_shared)

        lap_local = c_laptop.recall(pool="local")
        assert any(m["id"] == scratch_mem["id"] for m in lap_local)
        assert not any(m["id"] == shared_mem["id"] for m in lap_local)

        # Peer node (desktop) connects to same database
        os.environ["KNOT_NODE_ID"] = "desktop"
        c_desktop = MemoryPalaceClient(db_path=temp_db_path)

        # Desktop should see shared memory but NOT laptop's private scratchpad
        desk_default = c_desktop.recall()
        assert any(m["id"] == shared_mem["id"] for m in desk_default)
        assert not any(m["id"] == scratch_mem["id"] for m in desk_default)

        desk_local = c_desktop.recall(pool="local")
        assert len(desk_local) == 0  # Desktop has no local scratchpads

    def test_scratchpad_promotion_to_shared(self, memory_client):
        scratch = memory_client.store_scratchpad(
            wing="investigation",
            hall="mcp",
            drawer="hardening",
            title="Stateless Gateway Session Pinning",
            content="Discovered solution for persistent session resumption",
            importance=1.0,
        )
        assert scratch["pool"] == POOL_LOCAL

        # Promote to swarm shared memory
        prom_res = memory_client.promote(scratch["id"], boost=1.5, to_shared=True)
        assert prom_res["status"] == "PROMOTED"
        assert prom_res["pool"] == POOL_SHARED
        assert prom_res["importance"] == 2.5

        # Query shared pool
        shared_mems = memory_client.recall(pool="shared")
        promoted = next(m for m in shared_mems if m["id"] == scratch["id"])
        assert promoted["pool"] == POOL_SHARED
        assert promoted["importance"] == 2.5

    def test_scratchpad_pruning(self, memory_client):
        scratch = memory_client.store_scratchpad(
            wing="scratchpad",
            hall="test",
            drawer="temp",
            title="Ephemeral Observation",
            content="Old observation to be pruned",
        )
        # Pruning items older than 0 seconds prunes this item
        pruned = memory_client.prune_scratchpad(older_than_seconds=0.0)
        assert pruned >= 1

        # Should not be returned in recall
        recalled = memory_client.recall(pool="local")
        assert not any(m["id"] == scratch["id"] for m in recalled)


class TestCRDTSynchronization:
    def test_hlc_monotonicity(self):
        clock = HybridLogicalClock("laptop")
        t1 = clock.tick()
        t2 = clock.tick()
        assert t1 < t2
        assert t1.endswith(":laptop")

    def test_crdt_cross_node_export_and_merge(self):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f1, tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f2:
            db_laptop = f1.name
            db_desktop = f2.name

        try:
            os.environ["KNOT_NODE_ID"] = "laptop"
            c_lap = MemoryPalaceClient(db_path=db_laptop)

            os.environ["KNOT_NODE_ID"] = "desktop"
            c_desk = MemoryPalaceClient(db_path=db_desktop)

            # Laptop creates memory and artifact
            m = c_lap.store(
                wing="cuda",
                hall="profiling",
                drawer="benchmarks",
                title="Llama-bench CUDA Latency",
                content="35 tokens/sec on RTX 3050 Laptop GPU",
                pool=POOL_SHARED,
            )
            aid = c_lap.store_artifact("benchmark.csv", "batch,tps\n1,35.2\n4,68.1")

            # Export changes from laptop
            changeset = c_lap.export_crdt_changes(since_version=0)
            assert len(changeset["changes"]["memories"]) >= 1
            assert len(changeset["changes"]["artifacts"]) >= 1

            # Merge into desktop
            merge_summary = c_desk.merge_crdt_changes(changeset)
            assert merge_summary["memories_merged"] >= 1
            assert merge_summary["artifacts_merged"] >= 1

            # Verify desktop has merged items
            desk_mem = c_desk.recall(query="Llama-bench")
            assert any(item["id"] == m["id"] for item in desk_mem)

            desk_art = c_desk.get_artifact(aid)
            assert "batch,tps" in desk_art["content"]

            # Test LWW Conflict Resolution: Laptop updates with newer HLC
            c_lap.store(
                wing="cuda",
                hall="profiling",
                drawer="benchmarks",
                title="Llama-bench CUDA Latency",
                content="Updated: 38 tokens/sec on RTX 3050 Laptop GPU",
                memory_id=m["id"],
                pool=POOL_SHARED,
            )
            changeset_v2 = c_lap.export_crdt_changes(since_version=changeset["current_version"])
            c_desk.merge_crdt_changes(changeset_v2)

            desk_mem_updated = c_desk.recall(query="Llama-bench")
            target = next(item for item in desk_mem_updated if item["id"] == m["id"])
            assert "38 tokens/sec" in target["content"]
        finally:
            for p in [db_laptop, db_desktop]:
                for s in ["", "-wal", "-shm"]:
                    fp = p + s
                    if os.path.exists(fp):
                        os.remove(fp)


class TestEmbeddedArtifactCloset:
    def test_store_and_get_artifact(self, memory_client):
        aid = memory_client.store_artifact(
            name="patch.diff",
            content="--- a/main.py\n+++ b/main.py\n+print('hello')",
            artifact_type="diff",
            meta={"module": "core"},
        )
        assert aid.startswith("art_")

        art = memory_client.get_artifact(aid)
        assert art["name"] == "patch.diff"
        assert art["artifact_type"] == "diff"
        assert "print('hello')" in art["content"]
        assert art["meta"]["module"] == "core"

    def test_versioned_artifact_storage(self, memory_client):
        aid1 = memory_client.store_artifact_version(
            name="config.yaml",
            content="version: 1",
            state="DRAFT",
            author_node="laptop",
        )
        aid2 = memory_client.store_artifact_version(
            name="config.yaml",
            content="version: 2",
            state="VERIFIED_COMMITTED",
            author_node="desktop",
        )

        assert aid1 != aid2
        latest = memory_client.get_artifact_by_name("config.yaml")
        assert latest is not None
        assert latest["id"] == aid2
        assert latest["version"] == 2
        assert latest["state"] == "VERIFIED_COMMITTED"
        assert latest["author_node"] == "desktop"

    def test_nonexistent_artifact_raises_key_error(self, memory_client):
        with pytest.raises(KeyError):
            memory_client.get_artifact("art_nonexistent123")


class TestHardwareNodeRoleProfiles:
    def test_profiles_module_retrieval(self):
        anchor = get_profile("anchor_architect")
        assert anchor["node_id"] == "desktop"
        assert "GPG" in anchor["hardware_specialization"]

        worker = get_profile("compute_worker")
        assert worker["node_id"] == "laptop"
        assert "CUDA" in worker["hardware_specialization"]

        handheld = get_profile("handheld_controller")
        assert handheld["node_id"] in ("rog-ally", "steamdeck")
        assert "AMD" in handheld["hardware_specialization"]

    def test_profiles_alias_lookup(self):
        prof_deck = get_profile("steamdeck")
        assert prof_deck["role_name"] == "Handheld Controller"

        prof_desk = get_profile("desktop")
        assert prof_desk["role_name"] == "Anchor Architect"

        prof_lap = get_profile("laptop")
        assert prof_lap["role_name"] == "Compute Worker"

    def test_palace_client_profile_query(self, memory_client):
        prof = memory_client.get_profile("compute_worker")
        assert prof["role_name"] == "Compute Worker"
        assert "RTX 3050" in prof["hardware_specialization"]
        assert len(prof["capabilities"]) > 0
        assert len(prof["constraints"]) > 0


class TestSpatialHierarchyAndMap:
    def test_palace_map_and_tree_formatting(self, memory_client):
        memory_client.store(
            wing="security",
            hall="auth",
            drawer="oauth",
            title="Antigravity TTY Auth Fallback",
            content="Headless OAuth suppression when BROWSER=/bin/true",
            pool=POOL_SHARED,
        )

        pmap = memory_client.palace_map()
        assert len(pmap) >= 1
        sec_wing = next(w for w in pmap if "security" in w["id"])
        assert len(sec_wing["halls"]) >= 1

        formatted = format_tree(pmap)
        assert "Knot Swarm Cognitive Memory Palace" in formatted
        assert "Wing: security" in formatted
        assert "Hall: auth" in formatted
        assert "Antigravity TTY Auth Fallback" in formatted

    def test_relate_associative_graph(self, memory_client):
        m1 = memory_client.store("w1", "h1", "d1", "Idea 1", "Initial concept")
        m2 = memory_client.store("w1", "h1", "d1", "Idea 2", "Refined concept")

        res = memory_client.relate(m1["id"], m2["id"], relation_type="evolved_into", weight=2.0)
        assert res["status"] == "RELATED"
        assert res["source"] == m1["id"]
        assert res["target"] == m2["id"]
        assert res["relation_type"] == "evolved_into"
        assert res["weight"] == 2.0


class TestTranscriptIngestion:
    def test_transcript_ingestion(self, memory_client):
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False, mode="w", encoding="utf-8") as tf:
            steps = [
                {"type": "USER_INPUT", "content": "Optimize SQLite memory palace", "status": "DONE"},
                {"type": "PLANNER_RESPONSE", "thinking": "I have decided to use embedded SQLite with CRDT schema.", "tool_calls": [{"name": "write_to_file"}], "status": "DONE"},
                {"type": "TOOL_RESULT", "content": "File created", "status": "DONE"},
                {"type": "PLANNER_RESPONSE", "thinking": "Resolution reached and verified.", "status": "DONE"},
            ]
            for s in steps:
                tf.write(json.dumps(s) + "\n")
            transcript_file = tf.name

        try:
            res = memory_client.ingest_antigravity_transcript(transcript_file, "session_test_99", node_id="laptop")
            assert res["step_count"] == 4
            assert res["memory_id"] is not None

            # Verify memory in palace
            recalled = memory_client.recall(query="session_test_99")
            assert len(recalled) >= 1
            assert "Session session_test_99 on @laptop" in recalled[0]["content"]
        finally:
            if os.path.exists(transcript_file):
                os.remove(transcript_file)


class TestMCPGatewayLiveIntegration:
    def test_mcp_tools_with_real_embedded_palace(self, memory_client):
        mock_hub = MockKnotHubClient()
        gateway = KnotMCPGateway(hub_client=mock_hub, memory_client=memory_client)

        # 1. Test tools/list
        list_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {},
        }
        list_resp = gateway.handle_request(list_req)
        assert list_resp is not None
        tools = list_resp["result"]["tools"]
        tool_names = {t["name"] for t in tools}
        assert tool_names == {
            "knot_node_status",
            "knot_quota_matrix",
            "knot_exec_command",
            "knot_swarm_topology",
        }

        def call_tool(tname: str, targs: dict) -> tuple[str, bool]:
            req = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {"name": tname, "arguments": targs},
            }
            resp = gateway.handle_request(req)
            assert resp is not None, f"Null response for {tname}"
            result = resp.get("result", {})
            text = result["content"][0]["text"]
            is_err = result.get("isError", False)
            return text, is_err

        # 2. Test knot_node_status
        res_status, err_status = call_tool("knot_node_status", {})
        assert not err_status
        assert len(res_status) > 0

        # 3. Test knot_quota_matrix
        res_quota, err_quota = call_tool("knot_quota_matrix", {"target": "all"})
        assert not err_quota
        assert len(res_quota) > 0

        # 4. Test knot_swarm_topology
        res_topo, err_topo = call_tool("knot_swarm_topology", {})
        assert not err_topo
        assert len(res_topo) > 0

        # 5. Test knot_exec_command
        res_exec, err_exec = call_tool("knot_exec_command", {"target": "desktop", "command": "uname -a"})
        assert not err_exec
        assert len(res_exec) > 0


