# Knot Swarm: Prior Arts, Architectural Patterns & Ecosystem Survey 🪢🤖

## Executive Summary

Before transitioning from Phase 0 (mesh authentication & CLI verification) to Phase 1 (coordination hub & agent workers), this document conducts a rigorous audit of prior art, open-source frameworks, academic literature, and protocol standards across five foundational pillars:
1. **Multi-Agent Coordination & Swarm Orchestration** (Blackboard systems, Tuplespaces, Actor models, and leasing).
2. **Decentralized & Resilient Memory Palaces** (Method of Loci, dual-pool memory, CRDT-replicated SQLite, and embedded vector search).
3. **Stateless Model Context Protocol (MCP) & Distributed Tool Fabrics** (2026 stateless MCP spec, proxy/routing gateways, and hardware-plane tool federation).
4. **Skills, Rules, and System Prompt Architecture** (Progressive disclosure, hierarchical rule sets, and node specialization).
5. **Interactive Swarm Cockpits & Frontends** (Prior art in OpenHands, Devin, Generative UI, and the architecture of **Knot Kommand Kafe**).

---

## Pillar 1: Multi-Agent Coordination & Task Management

### 1. The Breakdown of Linear Pipelines & Master-Slave Hierarchies
Early LLM multi-agent systems (e.g., AutoGen v0.1, BabyAGI, simple sequential chains) relied on rigid turn-taking pipelines or centralized master-slave dispatch. In a heterogeneous, distributed hardware mesh (such as Desktop + Laptop + Steam Deck), these architectures fail catastrophically due to:
- **The "Phone Game" / Context Degradation**: Passing state sequentially through a chain of LLM prompts causes exponential signal decay, hallucination amplification, and lost intent.
- **Rigid Scheduling**: A stalled node (e.g., a Steam Deck sleeping or WiFi jitter) blocks the entire sequential pipeline.
- **Context Window Bloat**: Sending full conversational histories to worker agents consumes tokens pointlessly.

### 2. Prior Art: The Blackboard Pattern & Linda Tuplespaces
Modern state-of-the-art multi-agent research has converged on the **Blackboard Pattern** (originated in Hearsay-II, modernized in 2025/2026 papers such as *LbMAS: LLM-based Multi-Agent Blackboard Systems*):
- **Core Principle**: Agents do not talk directly to each other; they communicate exclusively through a shared, globally observable memory space (the Blackboard).
- **Linda Tuplespace Semantics**: Operations reduce to three primitive, concurrent actions:
  - `OUT(tuple)`: Publish a task, artifact, or partial result to the board.
  - `IN(pattern)`: Atomically claim and withdraw a task matching a specific template.
  - `RD(pattern)`: Inspect current state or wait for a reactive update without removing it.
- **Decoupling**: Strands (Laptop, Deck) do not know about Anchor internals. They simply subscribe to the Blackboard feed, volunteer for tasks matching their capabilities, and post partial solutions.

### 3. Failover, Leasing, and Heartbeat Semantics
To achieve zero-downtime fault tolerance across nodes that may sleep or drop connections:
- **Worker Leases (Kubernetes/Ray Pattern)**: When a strand claims a task from the blackboard, it acquires a time-bounded lease (e.g., 60 seconds with 15-second heartbeat renewals).
- **Dead-Letter Requeuing**: If a strand crashes or loses network connectivity, its lease expires. The Blackboard automatically resets the task state to `UNCLAIMED` and re-alerts other eligible nodes.
- **Idempotency Keys**: All task submissions carry a UUID hash of inputs. Retries produce identical task IDs, preventing duplicate executions.

---

## Pillar 2: Decentralized & Resilient Memory Palace

### 1. The Memory Palace Architecture (*Method of Loci*)
Rather than relying on lossy recursive summarization (where an LLM progressively erases critical nuances), the **Memory Palace** paradigm structures agent memory into a spatial-semantic hierarchy:
- **Wings**: High-level domain contexts (e.g., `infra_mesh`, `frontend_kafe`, `gamepad_inputs`).
- **Halls / Rooms**: Specific sessions, sub-projects, or incident investigations.
- **Drawers**: Atomic, immutable transcripts, tool call records, and JSON execution telemetry.
- **Closets**: Consolidated, verified reference patterns and indexing tables.
This allows an agent to navigate its history hierarchically without overloading its context window.

### 2. Dual-Pool Decentralized Memory (*DecentMem*)
Academic research in heterogeneous multi-agent systems highlights the danger of **Behavioral Homogenization**: if all agents share an identical memory pool, diverse models and agents converge to an identical average policy, losing their unique specialization.
The **Dual-Pool Pattern** equips each node with:
1. **Private Exploration Pool**: Node-local experiments, intermediate scratchpads, and platform-specific hardware tests.
2. **Shared Exploitation Pool**: Mesh-wide verified solutions, stable configuration manifests, and golden procedural runbooks.

### 3. Storage & Replication Engine: `cr-sqlite` + `sqlite-vec`
To achieve true local-first resilience where each node operates even during complete offline mesh partition:
- **Convergent Replicated SQLite (`cr-sqlite` / VLCN)**:
  - Uses Conflict-free Replicated Relations (CRRs).
  - Each node reads and writes to a local SQLite database in microsecond latency with zero network overhead.
  - Changes are tracked via vector clocks and synced asynchronously over WebSockets / SSH tunnels when nodes connect.
  - Automatic convergence with zero merge conflicts.
- **In-Process Semantic Search (`sqlite-vec`)**:
  - Eliminates the need for heavy external vector databases (like Milvus, Pinecone, or Qdrant).
  - Embeddings are stored directly in SQLite tables alongside relational task data, enabling joint vector similarity + SQL filtering in a single local transaction.

---

## Pillar 3: Stateless MCP & Federated Tool Fabrics

### 1. The Evolution to Stateless MCP (2026 Specification)
The Model Context Protocol transitioned from early stateful handshakes (which required sticky session IDs and complex connection state) to **Stateless MCP**:
- **Self-Describing Invocations**: Every request carries protocol versioning and client context in request metadata.
- **Transport Flexibility**: Native support for `StreamableHTTP` and `Stdio`.
- **Horizontal Elasticity**: Any replica of an MCP server can execute any tool call without session setup.

### 2. The Knot MCP Gateway Pattern
Rather than having every agent connect to dozens of disparate MCP servers on multiple machines, the Anchor hosts a unified **Knot MCP Router/Gateway**:
- **Unified Catalog**: Exposes a consolidated tool namespace to Antigravity agents.
- **Hardware-Aware Routing**:
  - Calls to `deck_*` (e.g., `deck_screen_capture`, `deck_gamepad_read`) are routed to the Steam Deck.
  - Calls to `gpu_*` or `x86_build_*` are routed to the Laptop's RTX 3050 and Ryzen 5800H.
  - Calls to `mesh_*` or `kvm_*` are handled locally on the Anchor.
- **Zero-Config Forwarding**: Strands expose lightweight HTTP/Stdio MCP endpoints reachable over the secure WireGuard/mDNS mesh.

---

## Pillar 4: Skills, Rules, and System Prompt Architectures

### 1. Antigravity Skill Standard & Progressive Disclosure
Antigravity CLI and SDK agents enforce **progressive disclosure** to protect context budgets:
- **Level 1 (Discovery)**: Only skill name and short description are injected at startup (~50 tokens per skill).
- **Level 2 (Activation)**: When the model identifies relevance or the user requests it, the agent reads `SKILL.md` to load detailed procedural steps.
- **Level 3 (Execution)**: The skill references localized scripts (`scripts/`), templates (`resources/`), and deep documentation (`references/`).

### 2. Node Persona & Prompt Specialization
System prompts across the Knot Swarm are tiered by hardware role:
- **Anchor (`desktop`)**: *Master Architect & Coordinator*. Oversees overall system design, breaks complex objectives into blackboard tasks, reviews submitted solutions, and manages gitops merges.
- **Strand-Laptop (`devbox`)**: *Heavy Compute & Test Engineer*. Dedicated to compilation, parallel test suites, and GPU-accelerated evaluations.
- **Strand-Handheld (`handheld`)**: *Embedded, Input & Handheld Specialist*. Dedicated to gamepad input validation, Wayland scaling/display tests, and low-power battery-efficient background verification.

---

## Pillar 5: Interactive Swarm Cockpit — Knot Kommand Kafe

### 1. Prior Art Analysis
- **OpenHands / Devin UI**: Excellent for single-agent coding tasks (split-view file tree, terminal, and browser). However, they lack multi-node topology awareness, distributed hardware dials, and concurrent swarm telemetry.
- **Generative UI Widgets**: Antigravity's native generative UI enables rendering rich inline widgets (Mermaid graphs, interactive data tables, progress sliders) dynamically generated by agents.

### 2. Knot Kommand Kafe Architecture
The **Knot Kommand Kafe** will be built as an ultra-fast, local-first GUI dashboard:
- **Runtime**: **Tauri v2 (Rust Core + Webview)**:
  - Memory usage < 50MB (critical for keeping background overhead near zero on Steam Deck and Laptop).
  - Direct native access to system metrics, DBus, and local IPC sockets.
- **Frontend Stack**: React 19 / Svelte 5 + Tailwind CSS + Lucide Icons + KaTeX + Canvas/WebGL.
- **Core Cockpit Views**:
  1. **Mesh Topology Radar**: Live interactive diagram of Desktop, Laptop, Steam Deck, and mobile nodes showing ping, battery, CPU/GPU temperatures, and KVM cursor location.
  2. **The Swarm Blackboard**: Real-time kanban and table view of tasks (`Queued`, `Claimed`, `Running`, `Verifying`, `Completed`) with live token counters and node badges.
  3. **Agent Trajectory Visualizer**: Live streaming logs, thoughts, tool confirmations, and generative UI widgets emitted by active `agy` agents.
  4. **Multi-Node Terminal & Kafe Console**: Seamless crossover terminal to execute prompts or debug commands across any node with zero friction.
  5. **Steam Deck Handheld Mode**: Touch-first, gamepad-navigable compact UI for monitoring swarm status from the couch or on the go.

---

## Synthesis & Implementation Blueprint

```
+-------------------------------------------------------------------------+
|                        KNOT KOMMAND KAFE (Tauri v2)                     |
|    [Topology Radar]     [Blackboard Kanban]    [Trajectory Stream]      |
+-------------------------------------------------------------------------+
                                    | WebSocket (Sub-ms)
+-------------------------------------------------------------------------+
|                     ANCHOR: KNOT HUB (core/hub/)                        |
|  - In-Memory / cr-sqlite Task Blackboard (Linda Tuples: IN, OUT, RD)    |
|  - Worker Lease & Heartbeat Monitor (Auto-failover on disconnect)       |
|  - Federated MCP Gateway (Routes deck_* to Deck, gpu_* to Laptop)       |
|  - Memory Palace Hybrid Index (Wings, Halls, Drawers via sqlite-vec)    |
+-------------------------------------------------------------------------+
              |                                            |
   SSH / WireGuard Pipe                         SSH / WireGuard Pipe
              v                                            v
+-----------------------------+              +-----------------------------+
|    STRAND 1: LAPTOP (x86)   |              |  STRAND 2: STEAM DECK (EOS) |
| - agy CLI (v1.1.19)         |              | - agy CLI (v1.1.27)         |
| - Local Worker Daemon       |              | - Local Worker Daemon       |
| - Local Exploration Memory  |              | - Gamepad & Input Tools     |
| - High-Compute/GPU Worker   |              | - Handheld UI Testbed       |
+-----------------------------+              +-----------------------------+
```
