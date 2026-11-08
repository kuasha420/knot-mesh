import { useState, useEffect, useCallback, useRef } from 'react';
import type {
  MeshNode,
  NodeAccountInfo,
  NodeQuotaMatrix,
  DagTask,
  KnotProject,
  ConnectionState,
  NodeId,
  SwarmPowerState,
  MeshActionType,
  MeshActionResult,
  NodePowerStatus,
  NodeActivityInfo,
  SwarmModelsState,
} from '../types/knot';

interface RawBackendNode {
  id?: string;
  node_id?: NodeId;
  user?: string;
  status?: 'ONLINE' | 'OFFLINE' | 'DEGRADED';
  ip?: string;
  port?: number;
  kvm_status?: string;
  ping_ms?: number;
  capabilities?: string[];
  last_seen?: number;
  last_heartbeat?: number;
  selected_model?: string;
  quota_5h_gemini?: number;
  quota_weekly_gemini?: number;
  quota_data?: Record<string, unknown>;
  account?: NodeAccountInfo;
  power?: NodePowerStatus;
  activity?: NodeActivityInfo;
  gpu_info?: {
    name: string;
    vram_used_mb: number;
    vram_total_mb: number;
    util_percent: number;
  };
}

const INITIAL_DEFAULT_NODES: MeshNode[] = [
  {
    node_id: 'anchor',
    user: 'user',
    status: 'ONLINE',
    ip: '127.0.0.1',
    port: 4242,
    kvm_status: 'CONNECTED',
    ping_ms: 0,
    capabilities: ['any', 'general', 'anchor', 'x86_64', 'high_memory'],
    last_seen: Math.floor(Date.now() / 1000),
    selected_model: 'gemini-2.5-pro',
  },
];

const INITIAL_DEFAULT_QUOTAS: NodeQuotaMatrix[] = [
  {
    node_id: 'anchor',
    account: { name: 'Mesh Operator', email: 'operator@mesh.local', subscription: 'Knot Pro' },
    groups: {
      gemini: {
        five_hour: { current: 1.0, limit: 1.0, pct: 100, status: 'OK', next_reset_in: 'Ready' },
        weekly: { current: 1.0, limit: 1.0, pct: 100, status: 'OK', next_reset_in: 'Ready' },
      },
    },
  },
];

export function useKnotStore() {
  const [nodes, setNodes] = useState<MeshNode[]>(INITIAL_DEFAULT_NODES);
  const [quotas, setQuotas] = useState<NodeQuotaMatrix[]>(INITIAL_DEFAULT_QUOTAS);
  const [tasks, setTasks] = useState<DagTask[]>([]);
  const [projects, setProjects] = useState<KnotProject[]>([]);
  const [activeProjectId, setActiveProjectId] = useState<string>('knot');
  const [powerStatus, setPowerStatus] = useState<SwarmPowerState | null>(null);
  const [models, setModels] = useState<SwarmModelsState | null>(null);
  const [connectionState, setConnectionState] = useState<ConnectionState>('connecting');

  const activeProjectIdRef = useRef<string>('knot');
  const esRef = useRef<EventSource | null>(null);

  useEffect(() => {
    activeProjectIdRef.current = activeProjectId;
  }, [activeProjectId]);

  const fetchModels = useCallback(async () => {
    try {
      const res = await fetch('/swarm/models');
      if (res.ok) {
        const data = (await res.json()) as SwarmModelsState;
        setModels(data);
      } else {
        console.warn(`Failed to fetch swarm models: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch swarm models:', err);
    }
  }, []);

  const fetchProjects = useCallback(async () => {
    try {
      const res = await fetch('/projects');
      if (res.ok) {
        const data = (await res.json()) as KnotProject[];
        setProjects(data);
        setActiveProjectId((curr) => {
          const match = data.find((p) => p.id === curr || p.name === curr);
          if (match) return match.id;
          const knotProj = data.find((p) => p.name === 'knot');
          return knotProj ? knotProj.id : (data[0]?.id ?? curr);
        });
      } else {
        console.warn(`Failed to fetch projects: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch projects:', err);
    }
  }, []);

  const fetchNodes = useCallback(async () => {
    try {
      const res = await fetch('/nodes');
      if (res.ok) {
        const rawList = (await res.json()) as RawBackendNode[];
        const normalizedNodes: MeshNode[] = rawList.map((n) => {
          const qData = (n.quota_data || {}) as Record<string, unknown>;
          const acc = n.account || (qData.account as NodeAccountInfo | undefined);
          const nodeId = (n.node_id || n.id || 'unknown') as NodeId;
          const resolvedIp = n.ip || '127.0.0.1';
          return {
            node_id: nodeId,
            user: n.user || 'user',
            status: n.status || 'ONLINE',
            ip: resolvedIp,
            port: n.port || 22,
            kvm_status: n.kvm_status || 'CONNECTED',
            ping_ms: n.ping_ms ?? 0,
            capabilities: n.capabilities || ['any', 'general'],
            last_seen: n.last_seen || n.last_heartbeat || 0,
            selected_model: n.selected_model,
            power: n.power,
            activity: n.activity || n.power?.activity,
            gpu_info: n.gpu_info,
            account: acc,
            quota_data: qData,
          };
        });
        setNodes(normalizedNodes);

        const derivedQuotas: NodeQuotaMatrix[] = rawList.map((n) => {
          const qData = (n.quota_data || {}) as Record<string, unknown>;
          const acc = n.account || (qData.account as NodeAccountInfo | undefined);
          const q5h = typeof n.quota_5h_gemini === 'number' ? n.quota_5h_gemini : 1.0;
          const qWk = typeof n.quota_weekly_gemini === 'number' ? n.quota_weekly_gemini : 1.0;
          return {
            node_id: (n.node_id || n.id || 'unknown') as NodeId,
            account: acc,
            groups: {
              gemini: {
                five_hour: {
                  current: q5h,
                  limit: 1.0,
                  pct: Math.round(q5h * 100),
                  status: q5h > 0.3 ? 'OK' : 'LOW',
                  next_reset_in: (qData['gemini_5h_reset_in'] as string) || 'in 1h 33m',
                },
                weekly: {
                  current: qWk,
                  limit: 1.0,
                  pct: Math.round(qWk * 100),
                  status: qWk > 0.3 ? 'OK' : 'LOW',
                  next_reset_in: (qData['gemini_weekly_reset_in'] as string) || 'in 5d 18h',
                },
              },
            },
          };
        });
        setQuotas(derivedQuotas);
      } else {
        console.warn(`Failed to fetch nodes: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch nodes:', err);
    }
  }, []);

  const fetchQuotas = useCallback(async () => {
    try {
      const res = await fetch('/quota');
      if (res.ok) {
        const data = (await res.json()) as NodeQuotaMatrix[];
        if (Array.isArray(data) && data.length > 0) {
          setQuotas(data);
        }
      } else {
        console.warn(`Failed to fetch quotas: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch quotas:', err);
    }
  }, []);

  const fetchTasks = useCallback(async () => {
    try {
      const res = await fetch('/tasks');
      if (res.ok) {
        const data = (await res.json()) as DagTask[];
        setTasks(data);
      } else {
        console.warn(`Failed to fetch tasks: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch tasks:', err);
    }
  }, []);

  const selectProject = useCallback((projectId: string) => {
    setActiveProjectId(projectId);
    activeProjectIdRef.current = projectId;
  }, []);

  const fetchPowerStatus = useCallback(async () => {
    try {
      const res = await fetch('/power/status');
      if (res.ok) {
        const data = (await res.json()) as SwarmPowerState;
        setPowerStatus(data);
      } else {
        console.warn(`Failed to fetch power status: HTTP ${res.status} ${res.statusText}`);
      }
    } catch (err) {
      console.warn('Failed to fetch power status:', err);
    }
  }, []);

  const setSwarmWakeHold = useCallback(
    async (minutes: number): Promise<boolean> => {
      try {
        const duration_sec = minutes * 60;
        const res = await fetch('/swarm/wake', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ duration_sec }),
        });
        if (res.ok) {
          void fetchPowerStatus();
          return true;
        }
        console.warn(`Failed to set swarm wake hold: HTTP ${res.status} ${res.statusText}`);
        return false;
      } catch (err) {
        console.warn('Failed to set swarm wake hold:', err);
        return false;
      }
    },
    [fetchPowerStatus]
  );

  const releaseSwarmWakeHold = useCallback(async (): Promise<boolean> => {
    try {
      const res = await fetch('/swarm/sleep-allow', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      if (res.ok) {
        void fetchPowerStatus();
        return true;
      }
      console.warn(`Failed to release swarm wake hold: HTTP ${res.status} ${res.statusText}`);
      return false;
    } catch (err) {
      console.warn('Failed to release swarm wake hold:', err);
      return false;
    }
  }, [fetchPowerStatus]);

  const triggerMeshAction = useCallback(
    async (action: MeshActionType, target = '--all'): Promise<MeshActionResult> => {
      try {
        const res = await fetch('/mesh/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action, target }),
        });
        if (res.ok) {
          return (await res.json()) as MeshActionResult;
        }
        const errText = await res.text();
        console.warn(`Mesh action failed: HTTP ${res.status} ${res.statusText}:`, errText);
        return { ok: false, action, target, output: errText || 'Action failed', exit_code: res.status };
      } catch (err) {
        console.warn('Failed to trigger mesh action:', err);
        return { ok: false, action, target, output: String(err), exit_code: -1 };
      }
    },
    []
  );

  const setSwarmModel = useCallback(
    async (model: string, nodeId?: string, applyToAll?: boolean) => {
      try {
        const res = await fetch('/swarm/model', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, node_id: nodeId, apply_to_all: applyToAll }),
        });
        if (res.ok) {
          const data = await res.json();
          await Promise.all([fetchModels(), fetchNodes()]);
          return data;
        } else {
          console.warn(`Failed to set swarm model: HTTP ${res.status} ${res.statusText}`);
        }
      } catch (err) {
        console.error('Failed to set swarm model:', err);
      }
    },
    [fetchModels, fetchNodes]
  );
  const refreshAll = useCallback(async () => {
    await Promise.allSettled([
      fetchProjects(),
      fetchNodes(),
      fetchModels(),
      fetchPowerStatus(),
      fetchQuotas(),
      fetchTasks(),
    ]);
  }, [fetchProjects, fetchNodes, fetchModels, fetchPowerStatus, fetchQuotas, fetchTasks]);

  useEffect(() => {
    void refreshAll();

    let retryTimeout: ReturnType<typeof setTimeout> | null = null;

    const connectSSE = () => {
      setConnectionState('connecting');
      const es = new EventSource('/events');
      esRef.current = es;

      es.onopen = () => {
        setConnectionState('connected');
      };

      es.onerror = (err) => {
        console.warn('SSE connection interrupted or encountered error:', err);
        setConnectionState('disconnected');
        es.close();
        esRef.current = null;
        retryTimeout = setTimeout(connectSSE, 3000);
      };

      const handleTaskEvent = (e: MessageEvent) => {
        try {
          const payload = JSON.parse(e.data as string) as Record<string, unknown>;
          const taskId = (payload['task_id'] || payload['id']) as string | undefined;
          if (!taskId) {
            void fetchTasks();
            return;
          }
          setTasks((prev) => {
            const idx = prev.findIndex((t) => t.id === taskId);
            if (idx >= 0) {
              const updated = [...prev];
              const existing = updated[idx];
              if (existing) {
                updated[idx] = { ...existing, ...payload } as DagTask;
              }
              return updated;
            } else {
              return [payload as unknown as DagTask, ...prev];
            }
          });
        } catch (err) {
          console.warn('Failed to parse task event:', err);
          void fetchTasks();
        }
      };

      es.addEventListener('task_queued', handleTaskEvent);
      es.addEventListener('task_started', handleTaskEvent);
      es.addEventListener('task_completed', handleTaskEvent);
      es.addEventListener('task_failed', handleTaskEvent);
      es.addEventListener('task_unblocked', handleTaskEvent);

      es.addEventListener('project_created', () => {
        void fetchProjects();
      });

      es.addEventListener('node_heartbeat', () => {
        void fetchNodes();
        void fetchPowerStatus();
      });

      es.addEventListener('node_activity', (e: MessageEvent) => {
        try {
          const payload = JSON.parse(e.data as string) as { node_id: NodeId; activity: NodeActivityInfo };
          if (payload && payload.node_id && payload.activity) {
            setNodes((prev) =>
              prev.map((n) =>
                n.node_id === payload.node_id
                  ? {
                      ...n,
                      activity: payload.activity,
                      power: {
                        ...(n.power || { on_ac: true, sleep_inhibited: false, is_executing_task: true }),
                        is_executing_task: payload.activity?.is_executing ?? false,
                        activity: payload.activity,
                      },
                    }
                  : n
              )
            );
          }
        } catch (err) {
          console.warn('Failed to parse node activity event:', err);
        }
      });

      es.addEventListener('quota_update', () => {
        void fetchNodes();
      });

      es.addEventListener('swarm_wake_hold', () => {
        void fetchPowerStatus();
      });

      es.addEventListener('swarm_wake_released', () => {
        void fetchPowerStatus();
      });

      es.addEventListener('model_updated', () => {
        void fetchModels();
        void fetchNodes();
      });
    };

    connectSSE();

    return () => {
      if (retryTimeout) clearTimeout(retryTimeout);
      if (esRef.current) {
        esRef.current.close();
        esRef.current = null;
      }
    };
  }, [refreshAll, fetchTasks, fetchNodes, fetchModels, fetchPowerStatus, fetchProjects]);

  return {
    nodes,
    quotas,
    tasks,
    projects,
    activeProjectId,
    connectionState,
    powerStatus,
    models,
    fetchModels,
    setSwarmModel,
    fetchPowerStatus,
    setSwarmWakeHold,
    releaseSwarmWakeHold,
    triggerMeshAction,
    refreshAll,
    selectProject,
  };
}
