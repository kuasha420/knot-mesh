import { useState, useEffect, useCallback, useRef } from 'react';
import type {
  MeshNode,
  NodeAccountInfo,
  NodeQuotaMatrix,
  DagTask,
  ArtifactLease,
  KnotChatMessage,
  KnotProject,
  KnotConversation,
  ConnectionState,
  NodeId,
  ArtifactStatus,
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

interface RawBackendChatMessage {
  id: string;
  conv_id?: string;
  channel?: string;
  sender?: string;
  sender_id?: string;
  content: string;
  target_node?: NodeId | null;
  mentions?: string[];
  created_at?: number;
  timestamp?: number;
  meta?: Record<string, unknown>;
}

interface RawBackendLease {
  name?: string;
  artifact_name?: string;
  state?: ArtifactStatus;
  status?: ArtifactStatus;
  locked_by?: NodeId | null;
  holder_node?: NodeId | null;
  lease_ttl_sec?: number;
  locked_at?: number | null;
  acquired_at?: number | null;
  expires_at?: number | null;
  checksum?: string | null;
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
    node_id: 'desktop',
    account: { name: 'Fahim', email: 'itsfahim.net@gmail.com', subscription: 'Google AI Pro' },
    groups: {
      gemini: {
        five_hour: { current: 0.74, limit: 1.0, pct: 74, status: 'OK', next_reset_in: 'in 22m' },
        weekly: { current: 0.95, limit: 1.0, pct: 95, status: 'OK', next_reset_in: 'in 5d 14h' },
      },
    },
  },
  {
    node_id: 'laptop',
    account: { name: 'MASUD PERVEZ', email: 'rocklucifer113@gmail.com', subscription: 'Google AI Pro' },
    groups: {
      gemini: {
        five_hour: { current: 0.24, limit: 1.0, pct: 24, status: 'LOW', next_reset_in: 'in 2h 18m' },
        weekly: { current: 0.87, limit: 1.0, pct: 87, status: 'OK', next_reset_in: 'in 6d 21h' },
      },
    },
  },
  {
    node_id: 'steamdeck',
    account: { name: 'Arafat Zahan', email: 'therealdaddyarafat@gmail.com', subscription: 'Google AI Pro' },
    groups: {
      gemini: {
        five_hour: { current: 0.66, limit: 1.0, pct: 66, status: 'OK', next_reset_in: 'in 1h 42m' },
        weekly: { current: 0.74, limit: 1.0, pct: 74, status: 'OK', next_reset_in: 'in 1d 21h' },
      },
    },
  },
];

export function useKnotStore() {
  const [nodes, setNodes] = useState<MeshNode[]>(INITIAL_DEFAULT_NODES);
  const [quotas, setQuotas] = useState<NodeQuotaMatrix[]>(INITIAL_DEFAULT_QUOTAS);
  const [tasks, setTasks] = useState<DagTask[]>([]);
  const [leases, setLeases] = useState<ArtifactLease[]>([]);
  const [messages, setMessages] = useState<KnotChatMessage[]>([]);
  const [projects, setProjects] = useState<KnotProject[]>([]);
  const [activeProjectId, setActiveProjectId] = useState<string>('knot');
  const [conversations, setConversations] = useState<KnotConversation[]>([]);
  const [activeConvId, setActiveConvId] = useState<string>('main');
  const [powerStatus, setPowerStatus] = useState<SwarmPowerState | null>(null);
  const [models, setModels] = useState<SwarmModelsState | null>(null);
  const [connectionState, setConnectionState] = useState<ConnectionState>('connecting');

  const activeConvIdRef = useRef<string>('main');
  const activeProjectIdRef = useRef<string>('knot');
  const esRef = useRef<EventSource | null>(null);

  useEffect(() => {
    activeConvIdRef.current = activeConvId;
  }, [activeConvId]);

  useEffect(() => {
    activeProjectIdRef.current = activeProjectId;
  }, [activeProjectId]);

  const fetchModels = useCallback(async () => {
    try {
      const res = await fetch('/swarm/models');
      if (res.ok) {
        const data = (await res.json()) as SwarmModelsState;
        setModels(data);
      }
    } catch {
      // Ignored
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
      }
    } catch {
      // Ignored
    }
  }, []);

  const fetchConversations = useCallback(async (projectId?: string) => {
    try {
      const pid = projectId ?? activeProjectIdRef.current;
      const url = pid ? `/chat/conversations?project_id=${encodeURIComponent(pid)}` : '/chat/conversations';
      const res = await fetch(url);
      if (res.ok) {
        const data = (await res.json()) as KnotConversation[];
        setConversations(data);
      }
    } catch {
      // Ignored
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
      }
    } catch {
      // Ignored
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
      }
    } catch {
      // Ignored
    }
  }, []);

  const fetchTasks = useCallback(async () => {
    try {
      const res = await fetch('/tasks');
      if (res.ok) {
        const data = (await res.json()) as DagTask[];
        setTasks(data);
      }
    } catch {
      // Ignored
    }
  }, []);

  const fetchLeases = useCallback(async () => {
    try {
      const res = await fetch('/artifacts/leases');
      if (res.ok) {
        const rawList = (await res.json()) as RawBackendLease[];
        const normalizedLeases: ArtifactLease[] = rawList.map((l) => ({
          artifact_name: l.artifact_name || l.name || '',
          status: l.status || l.state || 'DRAFTING',
          holder_node: l.holder_node || l.locked_by || null,
          acquired_at: l.acquired_at || l.locked_at || null,
          expires_at: l.expires_at || null,
          checksum: l.checksum || null,
        }));
        setLeases(normalizedLeases);
      }
    } catch {
      // Ignored
    }
  }, []);

  const fetchMessages = useCallback(async (convId?: string) => {
    try {
      const target = convId ?? activeConvIdRef.current;
      const res = await fetch(`/chat/messages?conv_id=${encodeURIComponent(target)}&limit=100`);
      if (res.ok) {
        const rawList = (await res.json()) as RawBackendChatMessage[];
        const normalizedMessages: KnotChatMessage[] = rawList.map((m) => {
          const senderId = m.sender_id || m.sender || 'unknown';
          const target = m.target_node || (m.mentions && m.mentions.length > 0 ? (m.mentions[0] as NodeId) : null);
          return {
            id: m.id,
            channel: m.channel || m.conv_id || 'main',
            sender_id: senderId,
            content: m.content,
            target_node: target,
            timestamp: m.timestamp || m.created_at || Math.floor(Date.now() / 1000),
            meta: m.meta || {},
          };
        });
        setMessages(normalizedMessages);
      }
    } catch {
      // Ignored
    }
  }, []);

  const selectProject = useCallback((projectId: string) => {
    setActiveProjectId(projectId);
    activeProjectIdRef.current = projectId;
    const proj = projects.find((p) => p.id === projectId);
    const defChan = proj?.default_channel || 'main';
    setActiveConvId(defChan);
    activeConvIdRef.current = defChan;
    void fetchConversations(projectId);
    void fetchMessages(defChan);
  }, [projects, fetchConversations, fetchMessages]);

  const selectConversation = useCallback((convId: string) => {
    setActiveConvId(convId);
    activeConvIdRef.current = convId;
    void fetchMessages(convId);
  }, [fetchMessages]);

  const createConversation = useCallback(async (
    id: string,
    title?: string,
    description?: string,
    projectId?: string
  ): Promise<boolean> => {
    try {
      const targetProject = projectId ?? activeProjectIdRef.current;
      const res = await fetch('/chat/conversations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id,
          title: title || `#${id}`,
          description: description || '',
          project_id: targetProject,
          created_by: 'human@desktop',
        }),
      });
      if (res.ok) {
        await fetchConversations(targetProject);
        selectConversation(id);
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }, [fetchConversations, selectConversation]);

  const fetchPowerStatus = useCallback(async () => {
    try {
      const res = await fetch('/power/status');
      if (res.ok) {
        const data = (await res.json()) as SwarmPowerState;
        setPowerStatus(data);
      }
    } catch {
      // Ignored
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
        return false;
      } catch {
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
      return false;
    } catch {
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
        return { ok: false, action, target, output: errText || 'Action failed', exit_code: res.status };
      } catch (err) {
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
        }
      } catch (err) {
        console.error('Failed to set swarm model:', err);
      }
    },
    [fetchModels, fetchNodes]
  );

  const setConversationModel = useCallback(
    async (convId: string, model: string, nodeId?: string) => {
      try {
        const res = await fetch(`/chat/conversations/${convId}/model`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model, node_id: nodeId }),
        });
        if (res.ok) {
          const data = await res.json();
          await fetchConversations();
          return data;
        }
      } catch (err) {
        console.error('Failed to set conversation model:', err);
      }
    },
    [fetchConversations]
  );

  const refreshAll = useCallback(async () => {
    await Promise.allSettled([
      fetchProjects(),
      fetchConversations(),
      fetchNodes(),
      fetchModels(),
      fetchPowerStatus(),
      fetchQuotas(),
      fetchTasks(),
      fetchLeases(),
      fetchMessages(),
    ]);
  }, [fetchProjects, fetchConversations, fetchNodes, fetchModels, fetchPowerStatus, fetchQuotas, fetchTasks, fetchLeases, fetchMessages]);

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

      es.onerror = () => {
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
        } catch {
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

      es.addEventListener('conversation_created', () => {
        void fetchConversations(activeProjectIdRef.current);
      });

      es.addEventListener('chat_message', (e: MessageEvent) => {
        try {
          const raw = JSON.parse(e.data as string) as RawBackendChatMessage;
          const chan = raw.channel || raw.conv_id || 'main';
          const msg: KnotChatMessage = {
            id: raw.id,
            channel: chan,
            sender_id: raw.sender_id || raw.sender || 'unknown',
            content: raw.content,
            target_node: raw.target_node || (raw.mentions && raw.mentions.length > 0 ? (raw.mentions[0] as NodeId) : null),
            timestamp: raw.timestamp || raw.created_at || Math.floor(Date.now() / 1000),
            meta: raw.meta || {},
          };

          // Update conversation message counts and last message in real-time
          setConversations((prev) =>
            prev.map((c) =>
              c.id === chan
                ? {
                    ...c,
                    message_count: (c.message_count || 0) + 1,
                    last_message: {
                      id: msg.id,
                      sender: msg.sender_id,
                      content: msg.content,
                      created_at: msg.timestamp,
                    },
                    updated_at: msg.timestamp,
                  }
                : c
            )
          );

          // If message is in the active channel, append to active messages
          if (chan === activeConvIdRef.current) {
            setMessages((prev) => {
              if (prev.some((m) => m.id === msg.id)) return prev;
              return [...prev, msg];
            });
          }
        } catch {
          void fetchMessages();
        }
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
        } catch {
          // Ignored
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

      es.addEventListener('conversation_model_updated', () => {
        void fetchConversations();
      });

      const handleLeaseEvent = () => {
        void fetchLeases();
      };
      es.addEventListener('artifact_locked', handleLeaseEvent);
      es.addEventListener('artifact_released', handleLeaseEvent);
    };

    connectSSE();

    return () => {
      if (retryTimeout) clearTimeout(retryTimeout);
      if (esRef.current) {
        esRef.current.close();
        esRef.current = null;
      }
    };
  }, [refreshAll, fetchTasks, fetchMessages, fetchNodes, fetchModels, fetchPowerStatus, fetchLeases, fetchProjects, fetchConversations]);

  const sendMessage = useCallback(
    async (content: string, targetNode?: NodeId | null, convId?: string) => {
      let resolvedTarget: NodeId | null = targetNode ?? null;
      if (!resolvedTarget) {
        const match = content.match(/@(swarm|all|desktop|laptop|steamdeck)/i);
        if (match && match[1]) {
          resolvedTarget = match[1].toLowerCase() as NodeId;
        }
      }

      // Extract all distinct @mentions from message content
      const matches = content.match(/@([a-zA-Z0-9_-]+)/g);
      const textMentions = matches
        ? Array.from(new Set(matches.map((m) => m.slice(1).toLowerCase())))
        : [];
      if (resolvedTarget && !textMentions.includes(resolvedTarget)) {
        textMentions.push(resolvedTarget);
      }

      const targetConv = convId ?? activeConvIdRef.current;

      await fetch('/chat/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          conv_id: targetConv,
          sender: 'human@desktop',
          content,
          mentions: textMentions,
        }),
      });
    },
    []
  );

  const lockArtifact = useCallback(
    async (artifactName: string, holderNode: NodeId, ttlSeconds = 600): Promise<boolean> => {
      try {
        const res = await fetch('/artifacts/lock', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: artifactName,
            node_id: holderNode,
            ttl: ttlSeconds,
            state: 'LOCKED_SURGERY',
          }),
        });
        const data = (await res.json()) as { ok?: boolean; success?: boolean };
        void fetchLeases();
        return Boolean(data.ok || data.success);
      } catch {
        return false;
      }
    },
    [fetchLeases]
  );

  const releaseArtifact = useCallback(
    async (
      artifactName: string,
      holderNode: NodeId,
      newStatus: ArtifactStatus = 'VERIFIED_COMMITTED'
    ): Promise<boolean> => {
      try {
        const res = await fetch('/artifacts/release', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            name: artifactName,
            node_id: holderNode,
            state: newStatus,
          }),
        });
        const data = (await res.json()) as { ok?: boolean; success?: boolean };
        void fetchLeases();
        return Boolean(data.ok || data.success);
      } catch {
        return false;
      }
    },
    [fetchLeases]
  );

  return {
    nodes,
    quotas,
    tasks,
    leases,
    messages,
    projects,
    activeProjectId,
    conversations,
    activeConvId,
    connectionState,
    powerStatus,
    models,
    fetchModels,
    setSwarmModel,
    setConversationModel,
    fetchPowerStatus,
    setSwarmWakeHold,
    releaseSwarmWakeHold,
    triggerMeshAction,
    refreshAll,
    selectProject,
    selectConversation,
    createConversation,
    sendMessage,
    lockArtifact,
    releaseArtifact,
  };
}
