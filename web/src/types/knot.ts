export type NodeId = 'desktop' | 'laptop' | 'steamdeck' | string;

export interface NodeActivityInfo {
  is_executing: boolean;
  node_id?: NodeId;
  task_id?: string | null;
  task_title?: string;
  conv_id?: string;
  step_index?: number;
  status?: 'THINKING' | 'TOOL_USE' | 'COMMAND' | 'WAITING' | 'DISPATCHING' | 'IDLE' | string;
  tool_name?: string | null;
  tool_action?: string | null;
  tool_summary?: string | null;
  command?: string | null;
  args_summary?: string | null;
  thinking_snippet?: string | null;
  model?: string;
  started_at?: number;
  elapsed_sec?: number;
  last_updated?: number;
}

export interface NodePowerStatus {
  on_ac: boolean;
  sleep_inhibited: boolean;
  is_executing_task: boolean;
  activity?: NodeActivityInfo;
}

export interface NodeAccountInfo {
  email: string;
  name: string;
  picture?: string;
  subscription: string;
  token_expiry?: string;
  auth_method?: string;
}

export interface SwarmModel {
  id: string;
  name: string;
  tier: 'flash' | 'pro' | 'claude' | 'oss' | string;
  provider: 'google' | 'anthropic' | 'openai' | string;
  description?: string;
}

export interface SwarmModelsState {
  available_models: SwarmModel[];
  default_model: string;
  node_models: Record<string, string>;
}

export interface MeshNode {
  node_id: NodeId;
  user: string;
  status: 'ONLINE' | 'OFFLINE' | 'DEGRADED';
  ip: string;
  port: number;
  kvm_status: string;
  ping_ms: number;
  capabilities: string[];
  last_seen: number;
  selected_model?: string;
  power?: NodePowerStatus;
  activity?: NodeActivityInfo;
  gpu_info?: {
    name: string;
    vram_used_mb: number;
    vram_total_mb: number;
    util_percent: number;
  };
  account?: NodeAccountInfo;
  quota_data?: Record<string, unknown>;
}

export interface QuotaWindow {
  current: number;
  limit: number;
  pct: number;
  status: 'OK' | 'LOW' | 'EXHAUSTED';
  next_reset_in: string;
}

export interface NodeQuotaGroup {
  five_hour: QuotaWindow;
  weekly: QuotaWindow;
}

export interface NodeQuotaMatrix {
  node_id: NodeId;
  account?: NodeAccountInfo;
  groups: Record<string, NodeQuotaGroup>;
}

export type TaskStatus =
  | 'BLOCKED_ON_DEPS'
  | 'QUEUED'
  | 'CLAIMED'
  | 'RUNNING'
  | 'COMPLETED'
  | 'FAILED';

export interface DagTask {
  id: string;
  title?: string;
  batch_id: string | null;
  parent_id: string | null;
  dependencies: string[];
  node_id: NodeId;
  status: TaskStatus;
  prompt: string;
  result: string | null;
  error: string | null;
  created_at: number;
  claimed_at: number | null;
  completed_at: number | null;
  meta: Record<string, unknown>;
}

export interface TaskBatch {
  batch_id: string;
  total_tasks: number;
  completed_tasks: number;
  tasks: DagTask[];
}

export type ArtifactStatus = 'DRAFTING' | 'LOCKED_SURGERY' | 'VERIFIED_COMMITTED';

export interface ArtifactLease {
  artifact_name: string;
  status: ArtifactStatus;
  holder_node: NodeId | null;
  acquired_at: number | null;
  expires_at: number | null;
  checksum: string | null;
}

export interface KnotChatMessage {
  id: string;
  channel: string;
  conv_id?: string;
  sender_id: string;
  content: string;
  target_node: NodeId | null;
  timestamp: number;
  meta: Record<string, unknown>;
}

export interface KnotProject {
  id: string;
  name: string;
  description: string;
  folders: string[];
  default_channel: string;
  created_at: number;
  updated_at: number;
}

export interface KnotConversation {
  id: string;
  project_id: string;
  title: string;
  description: string;
  created_by: string;
  is_archived: number;
  selected_model?: string;
  node_models?: Record<string, string>;
  message_count?: number;
  last_message?: {
    id: string;
    sender: string;
    content: string;
    created_at: number;
  } | null;
  created_at: number;
  updated_at: number;
}

export type SSEEventType =
  | 'task_queued'
  | 'task_started'
  | 'task_completed'
  | 'task_failed'
  | 'task_unblocked'
  | 'node_heartbeat'
  | 'node_activity'
  | 'quota_update'
  | 'chat_message'
  | 'project_created'
  | 'conversation_created'
  | 'conversation_model_updated'
  | 'artifact_locked'
  | 'artifact_released'
  | 'swarm_wake_hold'
  | 'swarm_wake_released'
  | 'model_updated';

export interface SSEMessagePayload {
  event: SSEEventType;
  data: Record<string, unknown>;
}

export interface SwarmPowerActivity {
  active: boolean;
  reasons: string[];
  active_tasks_count: number;
  last_activity_sec_ago: number;
  idle_timeout_sec: number;
  manual_hold_sec_remaining: number;
}

export interface SwarmPowerState {
  swarm_active: boolean;
  activity: SwarmPowerActivity;
  nodes: Array<{
    id: string;
    hostname: string;
    status: string;
    last_heartbeat: number;
    power: NodePowerStatus;
  }>;
}

export type MeshActionType =
  | 'restart_kvm'
  | 'screen_lock'
  | 'screen_unlock'
  | 'screen_status'
  | 'doctor';

export interface MeshActionResult {
  ok: boolean;
  action: string;
  target?: string;
  output: string;
  exit_code: number;
}

export type ConnectionState = 'connecting' | 'connected' | 'disconnected';

export type CockpitViewMode = 'grid' | 'chat' | 'radar' | 'dag' | 'artifacts' | 'kanban';

export interface TaskTokenTelemetry {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  estimatedCostUsd?: number;
}

export interface MeshTopologyOutput {
  name: string;
  primary?: boolean;
  priority?: number;
  resolution?: string;
  refresh_rate?: number;
  scale?: number;
  geometry?: string;
}

export interface MeshTopologyDisplay {
  resolution?: string;
  refresh_rate?: number;
  scale?: number;
  outputs?: MeshTopologyOutput[];
}

export interface MeshTopologyLink {
  node: string;
  span: [number, number];
  target_span?: [number, number];
}

export interface MeshTopologyNode {
  id: string;
  hostname: string;
  role: string;
  display?: MeshTopologyDisplay;
  user?: string;
  status?: string;
  ip_hint?: string;
  has_thumbnail?: boolean;
}

export interface TopologyScreenDetection {
  box_2d: [number, number, number, number]; // [ymin, xmin, ymax, xmax] 0-1000
  device_type: 'desktop_monitor' | 'laptop' | 'handheld_pc' | string;
  device_name: string;
  matched_node_id: string;
  position_relative_to_anchor: 'left' | 'right' | 'up' | 'down' | 'anchor' | 'anchor_internal' | string;
  span: [number, number];
  target_span?: [number, number];
  confidence: number;
  description?: string;
}

export interface TopologyAnalysisResult {
  engine: 'swarm_ai' | 'offline' | string;
  anchor_node_id: string;
  screens: TopologyScreenDetection[];
  proposed_layout: Record<string, Record<string, MeshTopologyLink>>;
  reasoning: string;
  metadata?: {
    image_width?: number;
    image_height?: number;
    detection_time_ms?: number;
    color_matches_used?: number;
    model?: string;
  };
}

export interface MeshTopologyState {
  swarm_id: string;
  swarm_name?: string;
  anchor: string;
  screens: string[];
  layout: Record<string, Record<string, MeshTopologyLink>>;
  locked: boolean;
  nodes: Record<string, MeshTopologyNode>;
}
