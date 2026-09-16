import React, { useState, useRef, useEffect } from 'react';
import {
  AssistantRuntimeProvider,
  ThreadPrimitive,
} from '@assistant-ui/react';
import {
  Activity,
  AtSign,
  Bold,
  Bot,
  Code,
  Cpu,
  Gamepad2,
  Hash,
  Laptop,
  Monitor,
  Plus,
  Send,
  Sparkles,
  Terminal,
  User,
  X,
} from 'lucide-react';
import type { DagTask, KnotChatMessage, KnotConversation, MeshNode, NodeId, SwarmModelsState } from '../../types/knot';
import { useKnotChatRuntime } from '../../hooks/useKnotChatRuntime';
import { groupModelsByDepth } from '../../utils/models';
import { MessageContent } from './MessageContent';
import { ThinkingIndicator } from './ThinkingIndicator';
import { SwarmActivityBar } from './SwarmActivityBar';

interface SwarmChatProps {
  messages: KnotChatMessage[];
  onSendMessage: (content: string, targetNode?: NodeId | null, convId?: string) => Promise<void>;
  conversations?: KnotConversation[];
  activeConvId?: string;
  onSelectConversation?: (convId: string) => void;
  onCreateConversation?: (id: string, title?: string, description?: string) => Promise<boolean>;
  activeProjectId?: string;
  tasks?: DagTask[];
  nodes?: MeshNode[];
  models?: SwarmModelsState | null;
  onSelectConversationModel?: (convId: string, model: string, nodeId?: string) => Promise<unknown>;
  isDedicatedView?: boolean;
}

export const SwarmChat: React.FC<SwarmChatProps> = ({
  messages,
  onSendMessage,
  conversations = [],
  activeConvId = 'main',
  onSelectConversation,
  onCreateConversation,
  activeProjectId = 'knot',
  tasks = [],
  nodes = [],
  models,
  onSelectConversationModel,
  isDedicatedView = false,
}) => {
  const [selectedTarget, setSelectedTarget] = useState<NodeId | null>(null);
  const [inputText, setInputText] = useState('');
  const [isWaiting, setIsWaiting] = useState(false);
  const [pendingTarget, setPendingTarget] = useState<NodeId | null>(null);
  const [pendingStartTime, setPendingStartTime] = useState<number>(Date.now());
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [newChannelId, setNewChannelId] = useState('');
  const [newChannelTitle, setNewChannelTitle] = useState('');
  const [newChannelDesc, setNewChannelDesc] = useState('');

  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const viewportEndRef = useRef<HTMLDivElement | null>(null);

  const runtime = useKnotChatRuntime({
    messages,
    onSendMessage,
    selectedTarget,
    activeConvId,
    isRunning: isWaiting,
  });

  // Automatically reset waiting state when an assistant message arrives
  useEffect(() => {
    if (!isWaiting) return;
    const latest = messages[messages.length - 1];
    if (latest) {
      const isAgent =
        !latest.sender_id.startsWith('human') &&
        latest.sender_id !== 'user' &&
        latest.sender_id !== 'operator';
      if (isAgent && latest.timestamp >= Math.floor(pendingStartTime / 1000)) {
        setIsWaiting(false);
      }
    }
  }, [messages, isWaiting, pendingStartTime]);

  // Safety timeout for waiting state (90 seconds)
  useEffect(() => {
    if (!isWaiting) return;
    const timer = setTimeout(() => {
      setIsWaiting(false);
    }, 90000);
    return () => clearTimeout(timer);
  }, [isWaiting]);

  // Detect active autonomous node execution in this channel
  const channelExecutingNode = nodes.find((n) => {
    const act = n.activity || n.power?.activity;
    return (
      (act?.is_executing || n.power?.is_executing_task) &&
      (act?.conv_id === activeConvId || !act?.conv_id || act?.conv_id === 'knot')
    );
  });

  // Auto-scroll viewport to bottom on new messages or waiting state
  useEffect(() => {
    viewportEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length, isWaiting, Boolean(channelExecutingNode)]);

  const currentConv = conversations.find((c) => c.id === activeConvId);

  const getNodeModel = (nodeId: NodeId) => {
    const nodeConvModel = currentConv?.node_models?.[nodeId];
    if (nodeConvModel) return nodeConvModel;
    if (currentConv?.selected_model) return currentConv.selected_model;
    const node = nodes.find((n) => n.node_id === nodeId);
    if (node?.selected_model) return node.selected_model;
    if (models?.node_models?.[nodeId]) return models.node_models[nodeId];
    return models?.default_model || null;
  };

  const mentionOptions: { label: string; node: NodeId; color: string; icon: React.ReactNode; glow: string }[] = [
    {
      label: '@desktop',
      node: 'desktop',
      color: 'text-night-magenta border-night-magenta/40 bg-night-magenta/10 hover:bg-night-magenta/20',
      icon: <Monitor className="w-3 h-3 text-night-magenta" />,
      glow: 'border-night-magenta/60 shadow-[0_0_15px_rgba(187,154,247,0.15)]',
    },
    {
      label: '@laptop',
      node: 'laptop',
      color: 'text-night-cyan border-night-cyan/40 bg-night-cyan/10 hover:bg-night-cyan/20',
      icon: <Laptop className="w-3 h-3 text-night-cyan" />,
      glow: 'border-night-cyan/60 shadow-[0_0_15px_rgba(125,207,255,0.15)]',
    },
    {
      label: '@steamdeck',
      node: 'steamdeck',
      color: 'text-night-orange border-night-orange/40 bg-night-orange/10 hover:bg-night-orange/20',
      icon: <Gamepad2 className="w-3 h-3 text-night-orange" />,
      glow: 'border-night-orange/60 shadow-[0_0_15px_rgba(255,158,100,0.15)]',
    },
    {
      label: '@swarm',
      node: 'swarm',
      color: 'text-night-yellow border-night-yellow/40 bg-night-yellow/10 hover:bg-night-yellow/20',
      icon: <Sparkles className="w-3 h-3 text-night-yellow" />,
      glow: 'border-night-yellow/60 shadow-[0_0_15px_rgba(224,175,104,0.15)]',
    },
  ];

  // Helper to insert text at cursor position in textarea
  const insertTextAtCursor = (textToInsert: string) => {
    const textarea = textareaRef.current;
    if (!textarea) {
      setInputText((prev) => prev + textToInsert);
      return;
    }

    const start = textarea.selectionStart || 0;
    const end = textarea.selectionEnd || 0;
    const prev = textarea.value;
    const next = prev.substring(0, start) + textToInsert + prev.substring(end);

    setInputText(next);
    setTimeout(() => {
      textarea.focus();
      const newCursor = start + textToInsert.length;
      textarea.setSelectionRange(newCursor, newCursor);
    }, 10);
  };

  const handleMentionClick = (node: NodeId) => {
    setSelectedTarget((prev) => (prev === node ? null : node));
    insertTextAtCursor(`@${node} `);
  };

  const handleInsertCodeBlock = () => {
    insertTextAtCursor('\n```bash\n# run command or paste script\n\n```\n');
  };

  const handleInsertInlineCode = () => {
    insertTextAtCursor('`code`');
  };

  const handleInsertBold = () => {
    insertTextAtCursor('**bold text**');
  };

  const handleSendMessage = async () => {
    const trimmed = inputText.trim();
    if (!trimmed) return;

    // Detect target plane from text mentions if not explicitly selected
    let target = selectedTarget;
    if (!target) {
      if (trimmed.includes('@swarm') || trimmed.includes('@all')) target = 'swarm';
      else if (trimmed.includes('@desktop')) target = 'desktop';
      else if (trimmed.includes('@laptop')) target = 'laptop';
      else if (trimmed.includes('@steamdeck')) target = 'steamdeck';
    }

    setInputText('');
    setIsWaiting(true);
    setPendingTarget(target);
    setPendingStartTime(Date.now());

    try {
      await onSendMessage(trimmed, target, activeConvId);
    } catch {
      setIsWaiting(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void handleSendMessage();
    }
  };

  // Filter conversations for active project
  const filteredConversations = conversations.filter(
    (c) =>
      c.project_id === activeProjectId ||
      (c as unknown as { project_name?: string }).project_name === activeProjectId
  );
  const displayConversations =
    filteredConversations.length > 0
      ? filteredConversations
      : conversations.length > 0
      ? conversations
      : [
          {
            id: 'main',
            project_id: activeProjectId,
            title: 'Main Swarm',
            description: 'Primary coordination channel',
            created_by: 'system',
            is_archived: 0,
            created_at: Math.floor(Date.now() / 1000),
            updated_at: Math.floor(Date.now() / 1000),
          },
        ];

  // Active glow based on target
  const activeGlow =
    mentionOptions.find((m) => m.node === selectedTarget)?.glow ||
    'border-night-border focus-within:border-night-blue/70 focus-within:shadow-[0_0_15px_rgba(122,162,247,0.15)]';

  const getNodeSenderInfo = (senderId: string) => {
    const matchedNode = nodes.find((n) => senderId.includes(n.node_id));
    const nodeId =
      matchedNode?.node_id ||
      (senderId.includes('desktop')
        ? 'desktop'
        : senderId.includes('laptop')
        ? 'laptop'
        : senderId.includes('steamdeck')
        ? 'steamdeck'
        : senderId.replace(/^@/, ''));
    const caps = matchedNode?.capabilities || [];
    let role = 'Swarm Agent';
    if (caps.includes('anchor') || caps.includes('master_planner') || nodeId === 'desktop') {
      role = 'Master Planner / Fleet Anchor';
    } else if (caps.includes('gpu_cuda') || caps.includes('rtx_3050') || nodeId === 'laptop') {
      role = 'CUDA Accelerated (RTX 3050)';
    } else if (caps.includes('embedded_gamepad') || caps.includes('steamdeck') || nodeId === 'steamdeck') {
      role = 'Van Gogh Handheld APU';
    }

    const convNodeModel = currentConv?.node_models?.[nodeId];
    const resolvedModel =
      convNodeModel ||
      currentConv?.selected_model ||
      matchedNode?.selected_model ||
      models?.node_models?.[nodeId] ||
      models?.default_model;

    const badge = resolvedModel ? `${role} • ${resolvedModel}` : role;

    if (nodeId === 'desktop') {
      return {
        name: '@desktop',
        badge,
        color: 'text-night-magenta',
        border: 'border-night-magenta/30 bg-night-panel/95',
        icon: <Monitor className="w-3.5 h-3.5 text-night-magenta" />,
      };
    }
    if (nodeId === 'laptop') {
      return {
        name: '@laptop',
        badge,
        color: 'text-night-cyan',
        border: 'border-night-cyan/30 bg-night-panel/95',
        icon: <Laptop className="w-3.5 h-3.5 text-night-cyan" />,
      };
    }
    if (nodeId === 'steamdeck') {
      return {
        name: '@steamdeck',
        badge,
        color: 'text-night-orange',
        border: 'border-night-orange/30 bg-night-panel/95',
        icon: <Gamepad2 className="w-3.5 h-3.5 text-night-orange" />,
      };
    }
    return {
      name: `@${nodeId}`,
      badge,
      color: 'text-night-blue',
      border: 'border-night-border bg-night-panel/90',
      icon: <Bot className="w-3.5 h-3.5 text-night-blue" />,
    };
  };

  return (
    <AssistantRuntimeProvider runtime={runtime}>
      <div className="flex h-full min-h-0 glass rounded-xl border border-night-border overflow-hidden relative">
        {/* Dedicated View: Left Channel Rail (xl+) */}
        {isDedicatedView && (
          <aside className="hidden xl:flex flex-col w-64 2xl:w-72 border-r border-night-border bg-night-panel/60 p-3 shrink-0 select-none">
            <div className="flex items-center justify-between pb-2.5 mb-2.5 border-b border-night-border">
              <div className="flex items-center space-x-1.5">
                <Hash className="w-4 h-4 text-night-blue" />
                <span className="text-xs font-bold text-night-blue uppercase tracking-wider">Channels</span>
              </div>
              {onCreateConversation && (
                <button
                  onClick={() => setIsCreateModalOpen(true)}
                  className="p-1 rounded hover:bg-night-surface text-night-muted hover:text-night-text transition-colors"
                  title="Create Channel"
                >
                  <Plus className="w-3.5 h-3.5" />
                </button>
              )}
            </div>

            <div className="flex-1 overflow-y-auto space-y-1 scrollbar-subtle pr-1">
              {displayConversations.map((conv) => {
                const isActive = conv.id === activeConvId;
                const msgCount =
                  conv.message_count ??
                  messages.filter((m) => (m.channel || m.conv_id) === conv.id).length;
                return (
                  <button
                    key={conv.id}
                    onClick={() => onSelectConversation?.(conv.id)}
                    className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-lg text-xs font-mono transition-all text-left ${
                      isActive
                        ? 'bg-night-surface text-night-cyan border border-night-cyan/30 shadow-sm font-semibold'
                        : 'text-night-muted hover:text-night-text hover:bg-night-surface/40 border border-transparent'
                    }`}
                  >
                    <div className="flex items-center space-x-1.5 min-w-0">
                      <Hash className={`w-3.5 h-3.5 shrink-0 ${isActive ? 'text-night-cyan' : 'text-night-muted'}`} />
                      <span className="truncate">{conv.title || conv.id}</span>
                    </div>
                    {msgCount > 0 && (
                      <span
                        className={`text-[9px] px-1.5 py-0.2 rounded-full font-bold shrink-0 ${
                          isActive
                            ? 'bg-night-cyan/20 text-night-cyan border border-night-cyan/30'
                            : 'bg-night-panel text-night-muted'
                        }`}
                      >
                        {msgCount}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>

            <div className="pt-3 mt-3 border-t border-night-border text-[10px] font-mono space-y-2">
              <div className="text-night-muted uppercase tracking-wider font-semibold text-[9px] flex items-center justify-between">
                <span>Active Channel</span>
                <span className="text-night-cyan font-bold">#{activeConvId}</span>
              </div>
              <div className="bg-night-surface/50 rounded-lg p-2 border border-night-border/70 space-y-1.5">
                <div className="flex items-center justify-between text-[10px]">
                  <span className="text-night-muted">Project:</span>
                  <span className="text-night-blue font-semibold truncate max-w-[120px]">{activeProjectId}</span>
                </div>
                <div className="flex items-center justify-between text-[10px]">
                  <span className="text-night-muted">Channel Model:</span>
                  <span
                    className="text-night-cyan font-semibold truncate max-w-[110px]"
                    title={currentConv?.selected_model || models?.default_model || 'Default'}
                  >
                    {currentConv?.selected_model || 'Default'}
                  </span>
                </div>
              </div>
            </div>
          </aside>
        )}

        {/* Center Column: Main Chat Stream */}
        <div className="flex-1 min-w-0 flex flex-col h-full overflow-hidden">
          {/* Channel Header Bar */}
          <div className="flex-none px-3.5 py-2 border-b border-night-border flex items-center justify-between gap-2 bg-night-panel/80 min-w-0">
            <div className="flex items-center space-x-2 min-w-0">
              <Hash className="w-3.5 h-3.5 text-night-blue flex-shrink-0" />
              <h2 className="text-xs font-bold tracking-wider text-night-blue uppercase truncate">
                <span className="hidden sm:inline">Swarm </span>Konversations
              </h2>
              <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-night-surface text-night-cyan border border-night-cyan/30 font-semibold flex-shrink-0">
                #{activeConvId}
              </span>
            </div>

            <div className="flex items-center space-x-2 text-[10px] font-mono text-night-muted flex-shrink-0">
              <span>{messages.length} msgs</span>
              <span>•</span>
              <span
                className="text-night-blue font-semibold truncate max-w-[120px] inline-block align-bottom"
                title={`Active Project: ${activeProjectId}`}
              >
                {activeProjectId}
              </span>
            </div>
          </div>

          {/* Channel Tabs Navigation (shown on grid view, or on smaller screens in dedicated view) */}
          <div
            className={`flex-none px-3 py-1.5 border-b border-night-border/70 bg-night-panel/50 flex items-center justify-between gap-2 overflow-x-auto scrollbar-subtle ${
              isDedicatedView ? 'xl:hidden' : ''
            }`}
          >
            <div className="flex items-center space-x-1.5 overflow-x-auto py-0.5 scrollbar-subtle">
              {displayConversations.map((conv) => {
                const isActive = conv.id === activeConvId;
                const msgCount =
                  conv.message_count ??
                  messages.filter((m) => (m.channel || m.conv_id) === conv.id).length;

                return (
                  <button
                    key={conv.id}
                    onClick={() => onSelectConversation?.(conv.id)}
                    className={`flex items-center space-x-1.5 px-2.5 py-1 rounded-lg text-xs font-mono font-medium transition-all ${
                      isActive
                        ? 'bg-night-surface text-night-cyan border border-night-cyan/40 shadow-sm'
                        : 'text-night-muted hover:text-night-text hover:bg-night-surface/40'
                    }`}
                    title={conv.description || conv.title}
                  >
                    <Hash className={`w-3 h-3 ${isActive ? 'text-night-cyan' : 'text-night-muted'}`} />
                    <span className="truncate max-w-[120px]">{conv.title || conv.id}</span>
                    {msgCount > 0 && (
                      <span
                        className={`text-[9px] px-1 py-0.2 rounded-full font-bold ${
                          isActive
                            ? 'bg-night-cyan/20 text-night-cyan border border-night-cyan/30'
                            : 'bg-night-panel text-night-muted'
                        }`}
                      >
                        {msgCount}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>

            {onCreateConversation && (
              <button
                onClick={() => setIsCreateModalOpen(true)}
                className="flex items-center space-x-1 px-2 py-1 rounded-lg text-[10px] font-mono text-night-muted hover:text-night-text hover:bg-night-surface/60 border border-night-border transition-colors flex-shrink-0"
                title="Create new group channel"
              >
                <Plus className="w-3 h-3 text-night-blue" />
                <span>New Channel</span>
              </button>
            )}
          </div>

          {/* Messages Viewport */}
          <ThreadPrimitive.Root className="flex-1 min-h-0 flex flex-col overflow-hidden">
            <ThreadPrimitive.Viewport className="flex-1 min-h-0 overflow-y-auto p-4 space-y-4 overscroll-contain scrollbar-subtle">
              <div className="w-full max-w-4xl 2xl:max-w-5xl mx-auto space-y-4">
                {messages.length === 0 && !isWaiting ? (
                  <div className="flex flex-col items-center justify-center h-full text-center p-6 text-night-muted">
                    <Sparkles className="w-8 h-8 mb-2 text-night-blue/50 animate-pulse" />
                    <p className="text-xs font-mono text-night-text">Swarm Channel #{activeConvId}</p>
                    <p className="text-[10px] text-night-muted mt-1 max-w-sm">
                      Mention <span className="text-night-magenta font-semibold">@desktop</span>,{' '}
                      <span className="text-night-cyan font-semibold">@laptop</span>,{' '}
                      <span className="text-night-orange font-semibold">@steamdeck</span>, or{' '}
                      <span className="text-night-yellow font-semibold">@swarm</span> to trigger an autonomous agent turn.
                    </p>
                  </div>
                ) : (
                  messages.map((msg) => {
                    const isHuman =
                      msg.sender_id.startsWith('human') ||
                      msg.sender_id === 'user' ||
                      msg.sender_id === 'operator';

                    const agentInfo = !isHuman ? getNodeSenderInfo(msg.sender_id) : null;

                    return (
                      <div
                        key={msg.id}
                        className={`flex flex-col ${
                          isHuman ? 'items-end' : 'items-start'
                        } transition-all`}
                      >
                        {/* Sender Header Line */}
                        <div className="flex items-center space-x-2 text-[10px] font-mono text-night-muted mb-1 px-1">
                          {isHuman ? (
                            <>
                              <span className="text-night-green font-semibold flex items-center gap-1">
                                <User className="w-3 h-3 text-night-green" /> {msg.sender_id}
                              </span>
                              <span>•</span>
                              <span>
                                {new Date(msg.timestamp * 1000).toLocaleTimeString([], {
                                  hour: '2-digit',
                                  minute: '2-digit',
                                  second: '2-digit',
                                })}
                              </span>
                            </>
                          ) : (
                            <>
                              <span className={`font-semibold flex items-center gap-1 ${agentInfo?.color}`}>
                                {agentInfo?.icon} {agentInfo?.name}
                              </span>
                              <span className="text-[9px] px-1.5 py-0.2 rounded bg-night-surface text-night-muted border border-night-border/50">
                                {agentInfo?.badge}
                              </span>
                              {msg.target_node && (
                                <span className="px-1.5 py-0.2 rounded bg-night-surface text-night-yellow border border-night-yellow/30 font-bold">
                                  @{msg.target_node}
                                </span>
                              )}
                              <span>•</span>
                              <span>
                                {new Date(msg.timestamp * 1000).toLocaleTimeString([], {
                                  hour: '2-digit',
                                  minute: '2-digit',
                                  second: '2-digit',
                                })}
                              </span>
                            </>
                          )}
                        </div>

                        {/* Styled Message Card */}
                        <div
                          className={`max-w-[88%] rounded-xl px-4 py-3 text-xs font-mono leading-relaxed border shadow-md ${
                            isHuman
                              ? 'bg-night-surface/95 text-night-text border-night-blue/40 rounded-tr-none shadow-night-blue/5'
                              : `${agentInfo?.border} text-night-text rounded-tl-none`
                          }`}
                        >
                          {/* Markdown & Code Block Formatter */}
                          <MessageContent content={msg.content} meta={msg.meta} />
                        </div>
                      </div>
                    );
                  })
                )}

                {/* In-Stream Liveness / Thinking Indicator */}
                {(isWaiting || Boolean(channelExecutingNode)) && (
                  <ThinkingIndicator
                    nodes={nodes}
                    targetNode={pendingTarget || channelExecutingNode?.node_id || null}
                    startTime={
                      pendingStartTime ||
                      (channelExecutingNode?.activity?.started_at
                        ? channelExecutingNode.activity.started_at * 1000
                        : Date.now())
                    }
                    channelName={activeConvId}
                    activity={channelExecutingNode?.activity || channelExecutingNode?.power?.activity}
                    taskTitle={
                      channelExecutingNode?.activity?.task_title ||
                      channelExecutingNode?.power?.activity?.task_title
                    }
                  />
                )}

                <div ref={viewportEndRef} />
              </div>
            </ThreadPrimitive.Viewport>

            {/* Pinned Swarm Long-Running Task Activity Bar */}
            <SwarmActivityBar tasks={tasks} nodes={nodes} />

            {/* Composer Footer Container */}
            <div className="flex-none p-3 border-t border-night-border bg-night-panel/90 flex flex-col gap-2">
              <div className="w-full max-w-4xl 2xl:max-w-5xl mx-auto flex flex-col gap-2">
                {/* Model Override Deck: Channel Model & Node-Specific Channel Overrides */}
                <div className="flex items-center justify-between gap-2 overflow-x-auto pb-1 text-[10px] font-mono scrollbar-subtle border-b border-night-border/40">
                  <div className="flex items-center space-x-2 flex-wrap gap-y-1">
                    {/* Channel-wide Model Selector */}
                    <div className="flex items-center space-x-1.5 bg-night-surface/60 px-2 py-0.5 rounded border border-night-border/70">
                      <Cpu className="w-3 h-3 text-night-blue flex-shrink-0" />
                      <span className="text-night-muted font-semibold">Channel Model:</span>
                      <select
                        value={currentConv?.selected_model || ''}
                        onChange={(e) => {
                          const val = e.target.value;
                          if (onSelectConversationModel && activeConvId) {
                            void onSelectConversationModel(activeConvId, val);
                          }
                        }}
                        className="bg-transparent text-night-cyan font-semibold focus:outline-none cursor-pointer text-[10px] max-w-[160px] truncate"
                      >
                        <option value="" className="bg-night-panel text-night-text">
                          Default ({models?.default_model ? models.default_model.split('-').slice(0, 3).join('-') : 'Swarm'})
                        </option>
                        {groupModelsByDepth(models?.available_models || []).map((group) => (
                          <optgroup key={group.groupName} label={group.groupName} className="bg-night-panel text-night-cyan font-bold text-[10px]">
                            {group.models.map((m) => (
                              <option key={m.id} value={m.id} className="bg-night-surface text-night-text font-normal font-mono">
                                {m.shortLabel}
                              </option>
                            ))}
                          </optgroup>
                        ))}
                      </select>
                    </div>

                    {/* Per-Node Channel Overrides */}
                    <div className="flex items-center space-x-1 flex-wrap gap-1">
                      <span className="text-night-muted text-[9px] uppercase tracking-wider font-semibold">Node Overrides:</span>
                      {nodes.map((node) => {
                        const nodeOverride = currentConv?.node_models?.[node.node_id];
                        const effectiveModel =
                          nodeOverride ||
                          currentConv?.selected_model ||
                          node.selected_model ||
                          models?.node_models?.[node.node_id] ||
                          models?.default_model;

                        const isOverridden = Boolean(nodeOverride);

                        return (
                          <div
                            key={node.node_id}
                            className={`inline-flex items-center space-x-1 px-1.5 py-0.5 rounded text-[9px] border transition-colors ${
                              isOverridden
                                ? 'bg-night-surface text-night-yellow border-night-yellow/50 font-bold'
                                : 'bg-night-surface/40 text-night-muted border-night-border/50'
                            }`}
                            title={`Node @${node.node_id}: using ${effectiveModel || 'default'}${isOverridden ? ' (channel override)' : ''}`}
                          >
                            <span className="font-semibold">@{node.node_id}:</span>
                            <select
                              value={nodeOverride || ''}
                              onChange={(e) => {
                                const val = e.target.value;
                                if (onSelectConversationModel && activeConvId) {
                                  void onSelectConversationModel(activeConvId, val, node.node_id);
                                }
                              }}
                              className={`bg-transparent focus:outline-none cursor-pointer text-[9px] font-semibold max-w-[110px] truncate ${
                                isOverridden ? 'text-night-yellow' : 'text-night-text'
                              }`}
                            >
                              <option value="" className="bg-night-panel text-night-muted">
                                Inherit ({effectiveModel ? effectiveModel.split('-').slice(0, 3).join('-') : 'Channel'})
                              </option>
                              {groupModelsByDepth(models?.available_models || []).map((group) => (
                                <optgroup key={group.groupName} label={group.groupName} className="bg-night-panel text-night-cyan font-bold text-[9px]">
                                  {group.models.map((m) => (
                                    <option key={m.id} value={m.id} className="bg-night-surface text-night-text font-normal font-mono">
                                      {m.shortLabel}
                                    </option>
                                  ))}
                                </optgroup>
                              ))}
                            </select>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>

                {/* Formatting & Mention Insertion Toolbar */}
                <div className="flex items-center justify-between gap-2 overflow-x-auto pb-1 text-[10px] font-mono scrollbar-subtle">
                  {/* Quick Mention Insert Pills */}
                  <div className="flex items-center space-x-1.5 flex-shrink-0">
                    <span className="text-night-muted flex items-center gap-0.5 uppercase tracking-wider font-semibold">
                      <AtSign className="w-3 h-3 text-night-blue" />
                      Route:
                    </span>
                    {mentionOptions.map((opt) => {
                      const nodeModel = getNodeModel(opt.node);
                      return (
                        <button
                          key={opt.node}
                          type="button"
                          onClick={() => handleMentionClick(opt.node)}
                          className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full border text-[10px] font-semibold transition-all ${
                            selectedTarget === opt.node
                              ? `${opt.color} shadow-sm ring-1 ring-night-blue/50`
                              : 'text-night-muted border-night-border/70 hover:text-night-text hover:border-night-border bg-night-surface/40'
                          }`}
                          title={`Route turn to ${opt.label}${nodeModel ? ` (${nodeModel})` : ''}`}
                        >
                          {opt.icon}
                          <span>{opt.label}</span>
                        </button>
                      );
                    })}
                  </div>

                  {/* Quick Formatting Buttons */}
                  <div className="flex items-center space-x-1 flex-shrink-0 text-night-muted border-l border-night-border/70 pl-2">
                    <button
                      type="button"
                      onClick={handleInsertCodeBlock}
                      className="p-1 rounded hover:text-night-cyan hover:bg-night-surface transition-colors flex items-center gap-0.5"
                      title="Insert code block (```bash)"
                    >
                      <Terminal className="w-3 h-3" />
                      <span className="hidden sm:inline">Code</span>
                    </button>
                    <button
                      type="button"
                      onClick={handleInsertInlineCode}
                      className="p-1 rounded hover:text-night-cyan hover:bg-night-surface transition-colors flex items-center gap-0.5"
                      title="Insert inline code (`code`)"
                    >
                      <Code className="w-3 h-3" />
                    </button>
                    <button
                      type="button"
                      onClick={handleInsertBold}
                      className="p-1 rounded hover:text-night-cyan hover:bg-night-surface transition-colors flex items-center gap-0.5"
                      title="Insert bold (**text**)"
                    >
                      <Bold className="w-3 h-3" />
                    </button>
                  </div>
                </div>

                {/* Input & Send Area */}
                <div className={`flex items-end gap-2 w-full rounded-xl p-1.5 glass-input border transition-all ${activeGlow}`}>
                  <textarea
                    ref={textareaRef}
                    value={inputText}
                    onChange={(e) => setInputText(e.target.value)}
                    onKeyDown={handleKeyDown}
                    placeholder={
                      selectedTarget
                        ? `Message @${selectedTarget} in #${activeConvId}... (Enter to send, Shift+Enter for new line)`
                        : `Message #${activeConvId} or mention @desktop, @laptop, @steamdeck, @swarm...`
                    }
                    rows={Math.min(4, Math.max(1, inputText.split('\n').length))}
                    className="flex-1 bg-transparent px-2.5 py-1.5 text-xs font-mono resize-none focus:outline-none placeholder:text-night-muted/80 leading-relaxed max-h-32 overflow-y-auto scrollbar-subtle"
                  />

                  <button
                    type="button"
                    onClick={() => void handleSendMessage()}
                    disabled={!inputText.trim()}
                    className={`p-2 rounded-lg transition-all flex items-center justify-center flex-shrink-0 ${
                      inputText.trim()
                        ? 'bg-night-blue hover:bg-night-blue/80 text-night-bg shadow-sm hover:shadow-night-blue/30'
                        : 'bg-night-surface text-night-muted opacity-40 cursor-not-allowed'
                    }`}
                    title="Send Message (Enter)"
                  >
                    {isWaiting ? (
                      <Sparkles className="w-4 h-4 animate-spin text-night-yellow" />
                    ) : (
                      <Send className="w-4 h-4" />
                    )}
                  </button>
                </div>
              </div>
            </div>
          </ThreadPrimitive.Root>
        </div>

        {/* Dedicated View: Right Swarm Telemetry Rail (2xl+) */}
        {isDedicatedView && (
          <aside className="hidden 2xl:flex flex-col w-72 2xl:w-80 border-l border-night-border bg-night-panel/60 p-3 shrink-0 overflow-y-auto scrollbar-subtle space-y-3 select-none">
            <div className="flex items-center justify-between pb-2 border-b border-night-border">
              <div className="flex items-center space-x-1.5">
                <Activity className="w-4 h-4 text-night-magenta" />
                <span className="text-xs font-bold text-night-magenta uppercase tracking-wider">Swarm Telemetry</span>
              </div>
              <span className="text-[10px] font-mono text-night-muted">
                {nodes.filter((n) => n.status === 'ONLINE').length}/{nodes.length} online
              </span>
            </div>

            {/* Live Nodes List */}
            <div className="space-y-2">
              {nodes.map((node) => {
                const effectiveModel =
                  currentConv?.node_models?.[node.node_id] ||
                  currentConv?.selected_model ||
                  node.selected_model ||
                  models?.node_models?.[node.node_id] ||
                  models?.default_model;

                return (
                  <div
                    key={node.node_id}
                    className="glass-panel p-2.5 rounded-lg border border-night-border space-y-1.5 text-xs font-mono"
                  >
                    <div className="flex items-center justify-between">
                      <span className="font-bold text-night-text flex items-center gap-1.5">
                        <span
                          className={`w-2 h-2 rounded-full ${
                            node.status === 'ONLINE'
                              ? 'bg-night-green shadow-[0_0_6px_rgba(158,206,106,0.6)]'
                              : 'bg-night-red'
                          }`}
                        />
                        @{node.node_id}
                      </span>
                      <span className="text-[9px] px-1.5 py-0.2 rounded bg-night-surface border border-night-border text-night-muted">
                        {node.ip}
                      </span>
                    </div>

                    <div className="text-[10px] text-night-muted truncate" title={node.capabilities?.join(', ')}>
                      {node.capabilities?.includes('master_planner') || node.capabilities?.includes('anchor') || node.node_id === 'desktop'
                        ? 'Master Planner / Fleet Anchor'
                        : node.capabilities?.includes('gpu_cuda') || node.node_id === 'laptop'
                        ? 'CUDA Accelerated (RTX 3050)'
                        : node.capabilities?.includes('embedded_gamepad') || node.node_id === 'steamdeck'
                        ? 'Handheld APU (Steam Deck)'
                        : 'Worker Node'}
                    </div>

                    <div className="flex items-center justify-between text-[10px] pt-1 border-t border-night-border/40">
                      <span className="text-night-muted">Model:</span>
                      <span className="text-night-cyan font-semibold truncate max-w-[140px]" title={effectiveModel}>
                        {effectiveModel || 'Default'}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Active DAG Tasks in dedicated sidebar */}
            {tasks.length > 0 && (
              <div className="pt-2 space-y-1.5">
                <div className="text-[10px] font-mono text-night-muted uppercase tracking-wider font-semibold">
                  Active Tasks ({tasks.length})
                </div>
                <div className="space-y-1.5 max-h-48 overflow-y-auto scrollbar-subtle pr-1">
                  {tasks.slice(0, 5).map((task) => (
                    <div
                      key={task.id}
                      className="p-2 rounded bg-night-surface/50 border border-night-border/60 text-[10px] font-mono"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-night-blue font-bold truncate max-w-[140px]">
                          {task.title || task.id}
                        </span>
                        <span
                          className={`text-[9px] uppercase px-1 py-0.2 rounded font-bold ${
                            task.status === 'RUNNING'
                              ? 'bg-night-yellow/20 text-night-yellow'
                              : task.status === 'COMPLETED'
                              ? 'bg-night-green/20 text-night-green'
                              : 'bg-night-muted/20 text-night-muted'
                          }`}
                        >
                          {task.status}
                        </span>
                      </div>
                      {task.node_id && (
                        <div className="text-night-muted text-[9px] mt-0.5">Assigned: @{task.node_id}</div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </aside>
        )}

        {/* Modal to Create New Channel */}
        {isCreateModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-fade-in">
            <div className="glass rounded-xl border border-night-border w-full max-w-md p-5 bg-night-panel shadow-2xl flex flex-col gap-4 font-mono">
              <div className="flex items-center justify-between border-b border-night-border pb-3">
                <div className="flex items-center gap-2">
                  <Hash className="w-4 h-4 text-night-blue" />
                  <h3 className="text-sm font-bold text-night-blue">Create Swarm Channel</h3>
                </div>
                <button
                  onClick={() => setIsCreateModalOpen(false)}
                  className="p-1 rounded text-night-muted hover:text-night-text hover:bg-night-surface transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              <div className="flex flex-col gap-3 text-xs">
                <div>
                  <label className="block text-night-muted mb-1 font-semibold">Channel ID / Slug *</label>
                  <div className="flex items-center rounded-lg border border-night-border bg-night-bg px-2.5 py-1.5 focus-within:border-night-blue">
                    <span className="text-night-muted mr-1">#</span>
                    <input
                      type="text"
                      value={newChannelId}
                      onChange={(e) =>
                        setNewChannelId(e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, ''))
                      }
                      placeholder="e.g. perf-audit"
                      className="bg-transparent flex-1 text-night-text focus:outline-none"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-night-muted mb-1 font-semibold">Channel Title</label>
                  <input
                    type="text"
                    value={newChannelTitle}
                    onChange={(e) => setNewChannelTitle(e.target.value)}
                    placeholder="e.g. Performance Audit & Diagnostics"
                    className="w-full rounded-lg border border-night-border bg-night-bg px-2.5 py-1.5 text-night-text focus:outline-none focus:border-night-blue"
                  />
                </div>

                <div>
                  <label className="block text-night-muted mb-1 font-semibold">Description</label>
                  <textarea
                    value={newChannelDesc}
                    onChange={(e) => setNewChannelDesc(e.target.value)}
                    placeholder="Channel purpose or context..."
                    rows={2}
                    className="w-full rounded-lg border border-night-border bg-night-bg px-2.5 py-1.5 text-night-text focus:outline-none focus:border-night-blue resize-none"
                  />
                </div>

                <div className="text-[10px] text-night-muted">
                  Project Scope:{' '}
                  <span className="text-night-cyan font-bold">{activeProjectId}</span>
                </div>
              </div>

              <div className="flex items-center justify-end gap-2 border-t border-night-border pt-3">
                <button
                  onClick={() => setIsCreateModalOpen(false)}
                  className="px-3 py-1.5 rounded-lg border border-night-border text-night-muted hover:text-night-text text-xs transition-colors"
                >
                  Cancel
                </button>
                <button
                  disabled={!newChannelId.trim()}
                  onClick={async () => {
                    if (onCreateConversation && newChannelId.trim()) {
                      const ok = await onCreateConversation(
                        newChannelId.trim(),
                        newChannelTitle.trim() || undefined,
                        newChannelDesc.trim() || undefined
                      );
                      if (ok) {
                        setIsCreateModalOpen(false);
                        setNewChannelId('');
                        setNewChannelTitle('');
                        setNewChannelDesc('');
                      }
                    }
                  }}
                  className="px-4 py-1.5 rounded-lg bg-night-blue hover:bg-night-blue/80 text-night-bg text-xs font-bold transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  Create Channel
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AssistantRuntimeProvider>
  );
};
