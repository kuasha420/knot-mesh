---
name: knot-swarm
description: Complete coordination skill for the Knot Swarm mesh. Covers zero-token remote command execution, consolidated topology inspection, Linda Tuplespace batch fanouts, barrier joins, and hardware acceleration roles. Use whenever coordinating tasks across desktop, laptop, or steamdeck.
---

# Knot Swarm Coordination Skill

This skill guides autonomous agents across the Knot mesh to operate with maximum efficiency, zero token waste, and proper hardware acceleration routing.

---

## 1. Golden Rule: Zero-Token CLI vs. Autonomous Task Delegation

Before triggering any remote operation, choose the right execution path:

| Scenario | Tool to Use | Token Burn on Target | Latency |
| :--- | :--- | :---: | :---: |
| **Deterministic Command** (e.g. `free -m`, `nvidia-smi`, `git pull`, `cargo build`, `pacman -S`, running benchmarks) | `knot_exec_command(target, command)` | **0 Tokens** | < 150 ms |
| **Autonomous Reasoning** (e.g. debugging complex failure, refactoring codebase, multi-step problem solving) | `knot_task_fanout(tasks, barrier_task)` or `knot_task_post(prompt, target_plane)` | Full LLM Turn | Minutes |

> [!IMPORTANT]
> **NEVER** post an autonomous task (`knot_task_post`) just to execute a shell command, check a file, or inspect system metrics on another machine. Use `knot_exec_command` to avoid burning hundreds of thousands of tokens.

---

## 2. Single-Turn Swarm Topology (`knot_swarm_topology`)

Do not make iterative queries or inspect raw schema JSONs to understand the swarm. Call `knot_swarm_topology` once:
- Returns online/offline status and IP addresses for all nodes.
- Shows assigned LLM models (e.g. `gemini-3.1-pro-high` on desktop, `gemini-3.8-flash-high` on laptop/deck).
- Lists GPU hardware backends (NVIDIA CUDA, AMD ROCm/Vulkan, APU UMA).
- Summarizes 5-hour and weekly token quotas.

---

## 3. Hardware Specialization & Routing

| Node ID | Hardware & Accelerators | Primary Role | Target Plane Tag |
| :--- | :--- | :--- | :--- |
| **`@desktop`** | Intel Core i7 (16 threads), 32 GB RAM, AMD RX 6600 XT (8 GB), Fast Gen4 NVMe | Mesh Anchor, Coordinator, heavy compiling, primary storage | `desktop`, `general`, `any` |
| **`@laptop`** | Intel Core i5, 16 GB RAM, NVIDIA RTX 3050 (4 GB GDDR6, CUDA) | CUDA compute, PyTorch inference, GPU model offload (`ggml-cuda`) | `laptop`, `gpu_cuda`, `rtx_3050` |
| **`@steamdeck`** | AMD Van Gogh Zen2/RDNA2 APU, 16 GB Unified LPDDR5 | Low-power handheld testbed, Vulkan/RADV compute, portable node | `steamdeck`, `handheld_display` |

---

## 4. Zero-Token Remote Command Execution (`knot_exec_command`)

Executes commands via SSH transport directly on target machines with full exit code, stdout, and stderr returned:

```json
// Example: Inspect memory and CUDA GPU on laptop with 0 tokens burned
{
  "name": "knot_exec_command",
  "arguments": {
    "target": "laptop",
    "command": "free -h && nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader"
  }
}
```

Broadcast across all nodes:
```json
{
  "name": "knot_exec_command",
  "arguments": {
    "target": "--all",
    "command": "uptime -p"
  }
}
```

---

## 5. Linda Tuplespace Task Fanout & Barrier Synchronization

When distributed autonomous reasoning IS required, use `knot_task_fanout` to post parallel subtasks and automatically hold a barrier synthesizer task in `BLOCKED_ON_DEPS` until all workers finish:

```json
{
  "name": "knot_task_fanout",
  "arguments": {
    "tasks": [
      {
        "title": "CUDA Optimization",
        "target_plane": "laptop",
        "prompt": "Evaluate CUDA matrix performance using local llama-bench."
      },
      {
        "title": "Vulkan Handheld Benchmark",
        "target_plane": "steamdeck",
        "prompt": "Evaluate Van Gogh APU inference using Vulkan backend."
      }
    ],
    "barrier_task": {
      "title": "Swarm Benchmark Synthesis",
      "target_plane": "desktop",
      "prompt": "Synthesize the benchmark results from @laptop and @steamdeck, write comparison table, and store in Memory Palace."
    }
  }
}
```

To wait for results:
- Call `knot_task_wait(task_id)` on the `barrier_task.id` to block until the entire pipeline is complete and receive the final synthesized output.

---

## 6. Decentralized Memory Palace Persistence

Persist durable findings, benchmark tables, and architecture decisions in SurrealDB Memory Palace:
```json
{
  "name": "knot_memory_store",
  "arguments": {
    "wing": "benchmarks",
    "hall": "gemma4",
    "drawer": "swarm_results",
    "title": "Gemma-4 Multi-Node Swarm Evaluation",
    "content": "Detailed markdown report with tok/s, CUDA acceleration metrics, and memory usage.",
    "importance": 0.9,
    "tags": ["gemma4", "cuda", "vulkan", "benchmark"]
  }
}
```
