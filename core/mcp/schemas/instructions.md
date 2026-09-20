# Knot Swarm MCP Server Instructions

The `knot` MCP server provides bidirectional coordination, hardware topology inspection, quota visibility, and remote execution across the physical Knot mesh.

## Canonical Tool Suite (4 Tools):

### 1. `knot_node_status`
Inspect mesh health, reachability, hardware architecture, and capability tags across all registered nodes (`desktop`, `laptop`, `steamdeck`).
- **Arguments**: None.
- **Returns**: Status, role, IP, architecture, capabilities, and connectivity for each node.

### 2. `knot_quota_matrix`
Inspect remaining 5-hour and weekly LLM quota budgets across all registered nodes to route heavy jobs to high-capacity nodes.
- **Arguments**: None.
- **Returns**: Per-node breakdown of 5-hour and weekly quota percentages, reset timestamps, and active account email.

### 3. `knot_exec_command`
Execute shell commands directly across the mesh (`desktop`, `laptop`, `steamdeck`, or `--all`) via fast SSH transport with **zero LLM token consumption on the target node**. Ideal for remote inspection, environment checks, and builds without burning AI tokens.
- **Arguments**:
  - `command` (string, required): Shell command to execute.
  - `target_node` (string, optional): Target node ID (`desktop`, `laptop`, `steamdeck`, or `all`). Defaults to `all`.
  - `timeout` (integer, optional): Execution timeout in seconds (default: 30).
- **Returns**: Execution exit code, stdout, and stderr per target node.

### 4. `knot_swarm_topology`
Consolidated single-turn snapshot of the entire swarm (online nodes, IPs, assigned LLM models, active activity, and 5h/weekly quotas).
- **Arguments**: None.
- **Returns**: Complete topological map of active nodes, network addresses, roles, and load indicators.
