# Knot Swarm & Memory Palace MCP Server Instructions

The `knot` MCP server provides bidirectional coordination across the physical Knot mesh, DAG task orchestration, 3-state atomic artifact versioning, Swarm Konversations channel messaging, and long-term decentralized memory.

## Canonical Tool Groups (19 Tools):

### 1. Swarm Orchestration & DAG Task Matrix (10 Tools)
- `knot_swarm_topology`: Consolidated single-turn snapshot of the entire swarm (online nodes, IPs, assigned LLM models, GPU backends, active activity, and 5h/weekly quotas).
- `knot_exec_command`: Execute shell commands directly across the mesh (`desktop`, `laptop`, `steamdeck`, or `--all`) via fast SSH transport with **zero LLM token consumption on the target node**. Ideal for remote inspection, environment checks, and commands without burning AI tokens.
- `knot_node_status`: Inspect mesh health, hardware architecture, and capability tags across all registered nodes (`desktop`, `laptop`, `steamdeck`).
- `knot_quota_matrix`: Inspect remaining 5-hour and weekly budgets across all nodes to select high-capacity nodes.
- `knot_gpu_status`: Query NVIDIA CUDA and AMD ROCm VRAM and GPU compute metrics (e.g. `laptop` RTX 3050).
- `knot_task_post`: Submit tasks to the Linda blackboard tuplespace. Use `target_plane` to route to specific hardware (`steamdeck`, `laptop`, `gpu_cuda`, `high_memory`).
- `knot_task_wait`: Wait for a posted task ID to finish execution and retrieve full response text and token metrics.
- `knot_task_list`: Query active, claimed, queued, or completed tasks on the swarm blackboard (supports `batch_id` and `status` filters).
- `knot_task_fanout`: Divide-and-Conquer: Atomically post a batch of parallel subtasks across hardware planes with an optional barrier reducer task held in `BLOCKED_ON_DEPS`.
- `knot_task_batch_status`: Query batch progress, completion percentage, and individual subtask statuses.

### 2. 3-State Shared Artifacts & Vault (4 Tools)
- `knot_artifact_lock`: Acquire or renew an atomic lease on an artifact to perform safe surgical edits (`LOCKED_SURGERY`).
- `knot_artifact_commit`: Commit an artifact version into PocketBase and index into SurrealDB Cognitive Palace, transitioning state to `VERIFIED_COMMITTED` and releasing leases.
- `knot_closet_store`: Store raw diffs, logs, code files, and binary artifacts in the embedded SQLite vault.
- `knot_closet_get`: Retrieve full artifacts and metadata by record ID.

### 3. Swarm Konversations Group Chat (2 Tools)
- `knot_chat_post`: Post messages to the shared Swarm Konversations channel (`#knot-core`) with `@mentions` (`@swarm`, `@desktop`, `@laptop`, `@steamdeck`).
- `knot_chat_read`: Read recent conversation messages and agent turns from the channel ledger.

### 4. Cognitive Memory Palace (SurrealDB v3.2.4) (5 Tools)
- `knot_memory_store`: Store thoughts into hierarchical spatial memory (`wing -> hall -> drawer`). Assign `importance` (0.0–1.0) and `tags`.
- `knot_memory_recall`: Query memories by semantic search, spatial location (`wing`/`hall`/`drawer`), or tags with decay-weighted ranking.
- `knot_memory_palace_map`: View the hierarchical mental map of wings, halls, and drawers.
- `knot_memory_promote`: Boost cognitive weight of a memory and reset its temporal decay.
- `knot_memory_relate`: Create associative graph edges (`relates_to`) connecting memories.
