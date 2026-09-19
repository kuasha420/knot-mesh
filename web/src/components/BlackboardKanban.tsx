import React, { useState, useMemo, useEffect, useRef } from 'react';
import {
  Activity,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Clock,
  Coins,
  Cpu,
  Flame,
  Gamepad2,
  Hash,
  Layers,
  Lock,
  RefreshCw,
  Search,
  ShieldCheck,
  Sparkles,
  Zap,
} from 'lucide-react';
import type { DagTask, MeshNode, TaskStatus } from '../types/knot';
import { useGamepadNavigation } from '../hooks/useGamepadNavigation';

export interface BlackboardKanbanProps {
  tasks: DagTask[];
  nodes?: MeshNode[];
  onRefresh?: () => void;
  embedded?: boolean;
}

type KanbanColumnId = 'queued' | 'claimed' | 'running' | 'verifying' | 'completed';

interface KanbanColumnConfig {
  id: KanbanColumnId;
  title: string;
  badgeColor: string;
  borderColor: string;
  accentColor: string;
  icon: React.ReactNode;
}

const KANBAN_COLUMNS: KanbanColumnConfig[] = [
  {
    id: 'queued',
    title: 'Queued',
    badgeColor: 'bg-night-cyan/15 text-night-cyan border-night-cyan/30',
    borderColor: 'border-night-cyan/40',
    accentColor: 'text-night-cyan',
    icon: <Clock className="w-4 h-4" />,
  },
  {
    id: 'claimed',
    title: 'Claimed',
    badgeColor: 'bg-night-yellow/15 text-night-yellow border-night-yellow/30',
    borderColor: 'border-night-yellow/40',
    accentColor: 'text-night-yellow',
    icon: <Layers className="w-4 h-4" />,
  },
  {
    id: 'running',
    title: 'Running',
    badgeColor: 'bg-night-blue/15 text-night-blue border-night-blue/30',
    borderColor: 'border-night-blue/40',
    accentColor: 'text-night-blue',
    icon: <Flame className="w-4 h-4 animate-pulse" />,
  },
  {
    id: 'verifying',
    title: 'Verifying',
    badgeColor: 'bg-purple-500/15 text-purple-400 border-purple-500/30',
    borderColor: 'border-purple-500/40',
    accentColor: 'text-purple-400',
    icon: <ShieldCheck className="w-4 h-4" />,
  },
  {
    id: 'completed',
    title: 'Completed',
    badgeColor: 'bg-night-green/15 text-night-green border-night-green/30',
    borderColor: 'border-night-green/40',
    accentColor: 'text-night-green',
    icon: <CheckCircle2 className="w-4 h-4" />,
  },
];

// Helper to determine token usage from task metadata or prompt estimation
const extractTaskTokenTelemetry = (task: DagTask) => {
  const meta = task.meta || {};
  let inputTokens = 0;
  let outputTokens = 0;

  if (typeof meta.input_tokens === 'number') inputTokens = meta.input_tokens;
  else if (typeof meta.prompt_tokens === 'number') inputTokens = meta.prompt_tokens;
  else if (typeof meta.tokens_in === 'number') inputTokens = meta.tokens_in;
  else if (task.prompt) {
    // Estimation fallback (~4 chars/token)
    inputTokens = Math.ceil(task.prompt.length / 4);
  }

  if (typeof meta.output_tokens === 'number') outputTokens = meta.output_tokens;
  else if (typeof meta.completion_tokens === 'number') outputTokens = meta.completion_tokens;
  else if (typeof meta.tokens_out === 'number') outputTokens = meta.tokens_out;
  else if (task.result) {
    outputTokens = Math.ceil(task.result.length / 4);
  }

  const totalTokens = (typeof meta.total_tokens === 'number' ? meta.total_tokens : 0) || (inputTokens + outputTokens);
  const isNativeZeroToken = meta.zero_token === true || meta.session_type === 'antigravity_pro';

  return {
    inputTokens,
    outputTokens,
    totalTokens,
    isNativeZeroToken,
  };
};

const getTaskHumanIdentifier = (task: DagTask) => {
  const hash = task.id.slice(0, 8);
  if (task.title && task.title.trim() && !task.title.toLowerCase().startsWith('task-') && task.title !== task.id) {
    return { title: task.title.trim(), hash };
  }
  const meta = task.meta || {};
  if (typeof meta.action === 'string' && meta.action) {
    return { title: meta.action.replace(/_/g, ' '), hash };
  }
  if (typeof meta.name === 'string' && meta.name) {
    return { title: meta.name, hash };
  }
  if (typeof meta.command === 'string' && meta.command) {
    return { title: meta.command.slice(0, 40), hash };
  }
  const cleanPrompt = (task.prompt || '').replace(/^[#*\s-]+/, '').split('\n')[0].trim();
  if (cleanPrompt.length > 0) {
    const truncated = cleanPrompt.length > 45 ? cleanPrompt.slice(0, 45) + '...' : cleanPrompt;
    return { title: truncated, hash };
  }
  return { title: `Task #${hash}`, hash };
};

export const BlackboardKanban: React.FC<BlackboardKanbanProps> = ({
  tasks,
  nodes = [],
  onRefresh,
  embedded = false,
}) => {
  const [searchFilter, setSearchFilter] = useState('');
  const [selectedBatch, setSelectedBatch] = useState<string>('all');
  const [expandedTaskId, setExpandedTaskId] = useState<string | null>(null);

  // Group tasks into the 5 Kanban columns
  const partitionedTasks = useMemo(() => {
    const cols: Record<KanbanColumnId, DagTask[]> = {
      queued: [],
      claimed: [],
      running: [],
      verifying: [],
      completed: [],
    };

    tasks.forEach((task) => {
      // Filter by search
      if (searchFilter) {
        const query = searchFilter.toLowerCase();
        const matchesPrompt = task.prompt && task.prompt.toLowerCase().includes(query);
        const matchesTitle = task.title && task.title.toLowerCase().includes(query);
        const matchesId = task.id.toLowerCase().includes(query);
        const matchesNode = task.node_id && task.node_id.toLowerCase().includes(query);
        if (!matchesPrompt && !matchesTitle && !matchesId && !matchesNode) {
          return;
        }
      }

      // Filter by batch
      if (selectedBatch !== 'all') {
        const tBatch = task.batch_id || 'standalone';
        if (tBatch !== selectedBatch) return;
      }

      const meta = task.meta || {};
      const isVerifying =
        task.status === ('VERIFYING' as TaskStatus) ||
        meta.status === 'VERIFYING' ||
        meta.verifying === true ||
        meta.stage === 'verifying';

      if (isVerifying) {
        cols.verifying.push(task);
      } else if (task.status === 'QUEUED' || task.status === 'BLOCKED_ON_DEPS') {
        cols.queued.push(task);
      } else if (task.status === 'CLAIMED') {
        cols.claimed.push(task);
      } else if (task.status === 'RUNNING') {
        cols.running.push(task);
      } else if (task.status === 'COMPLETED' || task.status === 'FAILED') {
        cols.completed.push(task);
      } else {
        cols.queued.push(task);
      }
    });

    return cols;
  }, [tasks, searchFilter, selectedBatch]);

  // Aggregate Token Telemetry calculations
  const telemetry = useMemo(() => {
    let totalIn = 0;
    let totalOut = 0;
    let totalAll = 0;
    let zeroTokenCount = 0;
    const activeNodes = new Set<string>();

    tasks.forEach((task) => {
      const { inputTokens, outputTokens, totalTokens, isNativeZeroToken } = extractTaskTokenTelemetry(task);
      totalIn += inputTokens;
      totalOut += outputTokens;
      totalAll += totalTokens;
      if (isNativeZeroToken) zeroTokenCount++;
      if (task.status === 'RUNNING' || task.status === 'CLAIMED') {
        if (task.node_id) activeNodes.add(task.node_id);
      }
    });

    // Approximate cost estimation (Claude 3.5 / Gemini Pro standard blend: $3/1M in, $15/1M out)
    const costEstimate = (totalIn / 1_000_000) * 3.0 + (totalOut / 1_000_000) * 15.0;

    return {
      totalInputTokens: totalIn,
      totalOutputTokens: totalOut,
      totalTokens: totalAll,
      zeroTokenRatio: tasks.length > 0 ? Math.round((zeroTokenCount / tasks.length) * 100) : 0,
      estimatedCostUsd: costEstimate,
      activeWorkerCount: activeNodes.size,
    };
  }, [tasks]);

  // Gamepad integration
  const activeColList = useMemo(() => {
    return [
      partitionedTasks.queued,
      partitionedTasks.claimed,
      partitionedTasks.running,
      partitionedTasks.verifying,
      partitionedTasks.completed,
    ];
  }, [partitionedTasks]);

  const cardRefs = useRef<Map<string, HTMLDivElement>>(new Map());

  const {
    gamepadConnected,
    gamepadName,
    handheldMode,
    toggleHandheldMode,
    selectedCol,
    selectedCard,
    setSelectedCol,
    setSelectedCard,
  } = useGamepadNavigation({
    columnCount: 5,
    getColumnItemCount: (colIdx) => activeColList[colIdx]?.length ?? 0,
    onSelectAction: (colIdx, itemIdx) => {
      const targetTask = activeColList[colIdx]?.[itemIdx];
      if (targetTask) {
        setExpandedTaskId((prev) => (prev === targetTask.id ? null : targetTask.id));
      }
    },
    onBackAction: () => {
      setExpandedTaskId(null);
    },
    onRefreshAction: onRefresh,
  });

  // Smooth scroll selected card into viewport when navigated via Gamepad
  useEffect(() => {
    const targetTask = activeColList[selectedCol]?.[selectedCard];
    if (targetTask) {
      const el = cardRefs.current.get(targetTask.id);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
      }
    }
  }, [selectedCol, selectedCard, activeColList]);

  // Unique batches for filter
  const batches = useMemo(() => {
    const s = new Set<string>();
    tasks.forEach((t) => {
      if (t.batch_id) s.add(t.batch_id);
    });
    return Array.from(s);
  }, [tasks]);

  return (
    <div
      className={`flex flex-col h-full min-h-0 ${
        embedded ? '' : 'glass rounded-xl border border-night-border'
      } overflow-hidden ${handheldMode ? 'knot-handheld-viewport' : ''}`}
    >
      {/* Telemetry & Control Bar */}
      <div className="flex-none p-2.5 sm:p-3 bg-night-panel/80 border-b border-night-border flex flex-col gap-2">
        {/* Top Header Row */}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center space-x-2">
            <Layers className="w-4 h-4 text-night-blue" />
            <h2 className="text-xs sm:text-sm font-bold tracking-wider text-night-blue uppercase flex items-center gap-2">
              Blackboard Kanban
              <span className="text-[10px] font-mono font-normal px-2 py-0.5 rounded-full bg-night-surface border border-night-border text-night-cyan">
                {tasks.length} Tasks
              </span>
            </h2>
          </div>

          {/* Quick HUD Metrics */}
          <div className="flex items-center gap-1.5 sm:gap-3 text-xs font-mono">
            {/* Handheld Mode Toggle */}
            <button
              onClick={toggleHandheldMode}
              className={`flex items-center gap-1 px-2 py-1 rounded-md text-[11px] font-mono border transition-all ${
                handheldMode
                  ? 'bg-night-cyan/20 border-night-cyan text-night-cyan font-bold shadow-[0_0_10px_rgba(6,182,212,0.3)]'
                  : 'bg-night-surface border-night-border text-night-muted hover:text-night-text'
              }`}
              title="Toggle Steam Deck / ROG Ally 1280x800 Handheld Mode"
            >
              <Gamepad2 className="w-3.5 h-3.5" />
              <span className="hidden xs:inline">Handheld</span>
              <span className="text-[9px] font-semibold">{handheldMode ? 'ON' : 'OFF'}</span>
            </button>

            {/* Refresh Button */}
            {onRefresh && (
              <button
                onClick={onRefresh}
                className="p-1.5 rounded-md bg-night-surface hover:bg-night-border/40 text-night-muted hover:text-night-cyan transition-colors"
                title="Refresh Kanban Blackboard"
              >
                <RefreshCw className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        {/* Aggregate Token Telemetry Banner */}
        <div className="grid grid-cols-2 xs:grid-cols-4 lg:grid-cols-5 gap-2 pt-1 border-t border-night-border/50 text-xs font-mono">
          <div className="bg-night-surface/70 border border-night-border rounded-lg p-1.5 flex flex-col">
            <span className="text-[10px] text-night-muted flex items-center gap-1">
              <Zap className="w-3 h-3 text-night-yellow" /> Total Tokens
            </span>
            <span className="text-sm font-bold text-night-yellow truncate">
              {telemetry.totalTokens.toLocaleString()}
            </span>
          </div>

          <div className="bg-night-surface/70 border border-night-border rounded-lg p-1.5 flex flex-col">
            <span className="text-[10px] text-night-muted flex items-center gap-1">
              <Sparkles className="w-3 h-3 text-night-cyan" /> Prompt / In
            </span>
            <span className="text-sm font-bold text-night-cyan truncate">
              {telemetry.totalInputTokens.toLocaleString()}
            </span>
          </div>

          <div className="bg-night-surface/70 border border-night-border rounded-lg p-1.5 flex flex-col">
            <span className="text-[10px] text-night-muted flex items-center gap-1">
              <Activity className="w-3 h-3 text-night-green" /> Output / Comp
            </span>
            <span className="text-sm font-bold text-night-green truncate">
              {telemetry.totalOutputTokens.toLocaleString()}
            </span>
          </div>

          <div className="bg-night-surface/70 border border-night-border rounded-lg p-1.5 flex flex-col">
            <span className="text-[10px] text-night-muted flex items-center gap-1">
              <Coins className="w-3 h-3 text-purple-400" /> Est. Cost
            </span>
            <span className="text-sm font-bold text-purple-400 truncate">
              ${telemetry.estimatedCostUsd.toFixed(4)}
            </span>
          </div>

          <div className="hidden lg:flex bg-night-surface/70 border border-night-border rounded-lg p-1.5 flex-col">
            <span className="text-[10px] text-night-muted flex items-center gap-1">
              <Cpu className="w-3 h-3 text-night-blue" /> Active Workers
            </span>
            <span className="text-sm font-bold text-night-blue truncate">
              {telemetry.activeWorkerCount} / {nodes.length > 0 ? nodes.length : 3} Nodes
            </span>
          </div>
        </div>

        {/* Search & Filter Toolbar */}
        <div className="flex items-center gap-2 pt-0.5">
          <div className="relative flex-1">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-night-muted" />
            <input
              type="text"
              value={searchFilter}
              onChange={(e) => setSearchFilter(e.target.value)}
              placeholder="Filter tasks by title, node, prompt..."
              className="w-full pl-8 pr-3 py-1 bg-night-surface/90 border border-night-border rounded-lg text-xs font-mono text-night-text placeholder:text-night-muted/60 focus:outline-none focus:border-night-cyan/50"
            />
          </div>

          {batches.length > 0 && (
            <select
              value={selectedBatch}
              onChange={(e) => setSelectedBatch(e.target.value)}
              className="bg-night-surface/90 border border-night-border rounded-lg px-2.5 py-1 text-xs font-mono text-night-text focus:outline-none focus:border-night-cyan/50 cursor-pointer max-w-[140px] truncate"
            >
              <option value="all">All Batches</option>
              {batches.map((b) => (
                <option key={b} value={b}>
                  Batch #{b.slice(0, 6)}
                </option>
              ))}
            </select>
          )}

          {/* Quick Column Selector for Handheld 7-inch Touch */}
          {handheldMode && (
            <div className="flex items-center gap-1 bg-night-surface p-0.5 rounded-lg border border-night-border overflow-x-auto">
              {KANBAN_COLUMNS.map((col, idx) => (
                <button
                  key={col.id}
                  onClick={() => {
                    setSelectedCol(idx);
                    setSelectedCard(0);
                  }}
                  className={`px-2 py-1 rounded text-[10px] font-mono font-bold transition-all ${
                    selectedCol === idx
                      ? 'bg-night-panel text-night-cyan border border-night-cyan/40 shadow-sm'
                      : 'text-night-muted hover:text-night-text'
                  }`}
                >
                  {col.title[0]} ({partitionedTasks[col.id].length})
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* 5-Column Kanban Board Layout */}
      <div className="flex-1 min-h-0 overflow-x-auto overflow-y-hidden p-2 sm:p-3 flex gap-2.5 sm:gap-3 snap-x snap-mandatory">
        {KANBAN_COLUMNS.map((col, colIdx) => {
          const colTasks = partitionedTasks[col.id];
          const isCurrentCol = selectedCol === colIdx;

          return (
            <div
              key={col.id}
              className={`flex-1 min-w-[240px] sm:min-w-[270px] max-w-[340px] flex flex-col h-full min-h-0 rounded-xl bg-night-panel/50 border transition-all snap-start ${
                isCurrentCol
                  ? `${col.borderColor} shadow-[0_0_12px_rgba(6,182,212,0.15)]`
                  : 'border-night-border'
              }`}
            >
              {/* Column Header */}
              <div className="flex-none p-2.5 border-b border-night-border flex items-center justify-between bg-night-surface/60 rounded-t-xl">
                <div className="flex items-center gap-2">
                  <span className={col.accentColor}>{col.icon}</span>
                  <span className="text-xs font-bold uppercase tracking-wider font-mono text-night-text">
                    {col.title}
                  </span>
                </div>
                <span
                  className={`text-[10px] font-mono px-2 py-0.5 rounded-full border ${col.badgeColor}`}
                >
                  {colTasks.length}
                </span>
              </div>

              {/* Tasks List */}
              <div className="flex-1 min-h-0 overflow-y-auto p-2 space-y-2 select-none">
                {colTasks.length === 0 ? (
                  <div className="h-28 flex flex-col items-center justify-center text-night-muted text-xs font-mono italic opacity-60">
                    No tasks {col.title.toLowerCase()}
                  </div>
                ) : (
                  colTasks.map((task, itemIdx) => {
                    const { title, hash } = getTaskHumanIdentifier(task);
                    const isSelected = isCurrentCol && selectedCard === itemIdx;
                    const isExpanded = expandedTaskId === task.id;
                    const taskTele = extractTaskTokenTelemetry(task);

                    return (
                      <div
                        key={task.id}
                        ref={(el) => {
                          if (el) cardRefs.current.set(task.id, el);
                          else cardRefs.current.delete(task.id);
                        }}
                        onClick={() => {
                          setSelectedCol(colIdx);
                          setSelectedCard(itemIdx);
                          setExpandedTaskId((prev) => (prev === task.id ? null : task.id));
                        }}
                        className={`p-2.5 rounded-lg border transition-all cursor-pointer bg-night-surface/90 ${
                          isSelected
                            ? 'border-night-cyan ring-2 ring-night-cyan/70 shadow-[0_0_14px_rgba(6,182,212,0.4)]'
                            : 'border-night-border hover:border-night-border/80 hover:bg-night-surface'
                        } ${handheldMode ? 'min-h-[52px]' : ''}`}
                      >
                        {/* Top Meta Line: ID + Node + Status */}
                        <div className="flex items-center justify-between gap-1 text-[10px] font-mono text-night-muted mb-1.5">
                          <span className="flex items-center gap-1 font-semibold text-night-cyan truncate">
                            <Hash className="w-2.5 h-2.5 text-night-muted" />
                            {hash}
                          </span>
                          <div className="flex items-center gap-1">
                            {task.node_id && (
                              <span className="px-1.5 py-0.2 rounded bg-night-panel border border-night-border text-night-text truncate max-w-[80px]">
                                @{task.node_id}
                              </span>
                            )}
                            {task.batch_id && (
                              <span className="px-1 py-0.2 rounded bg-night-border/50 text-[9px] text-night-muted">
                                B#{task.batch_id.slice(0, 4)}
                              </span>
                            )}
                          </div>
                        </div>

                        {/* Title */}
                        <h4 className="text-xs font-semibold text-night-text line-clamp-2 mb-2 font-mono">
                          {title}
                        </h4>

                        {/* Bottom Row: Token Telemetry + Dependencies + Expander */}
                        <div className="flex items-center justify-between gap-1 pt-1.5 border-t border-night-border/50 text-[10px] font-mono">
                          {/* Token badge */}
                          <span
                            className="flex items-center gap-1 text-night-yellow truncate"
                            title={`In: ${taskTele.inputTokens} | Out: ${taskTele.outputTokens}`}
                          >
                            <Zap className="w-2.5 h-2.5 shrink-0" />
                            <span>{taskTele.totalTokens.toLocaleString()} tok</span>
                          </span>

                          <div className="flex items-center gap-1 text-night-muted">
                            {task.dependencies && task.dependencies.length > 0 && (
                              <span className="flex items-center gap-0.5 text-night-muted">
                                <Lock className="w-2.5 h-2.5" />
                                {task.dependencies.length}
                              </span>
                            )}
                            <span className="text-night-muted">
                              {isExpanded ? (
                                <ChevronDown className="w-3.5 h-3.5" />
                              ) : (
                                <ChevronRight className="w-3.5 h-3.5" />
                              )}
                            </span>
                          </div>
                        </div>

                        {/* Expanded Details Drawer */}
                        {isExpanded && (
                          <div className="mt-2 pt-2 border-t border-night-border space-y-1.5 text-xs font-mono">
                            {task.prompt && (
                              <div>
                                <span className="text-[10px] text-night-muted uppercase font-semibold">
                                  Prompt
                                </span>
                                <div className="p-2 rounded bg-night-panel/80 text-night-text text-[11px] whitespace-pre-wrap max-h-36 overflow-y-auto mt-0.5">
                                  {task.prompt}
                                </div>
                              </div>
                            )}

                            {task.result && (
                              <div>
                                <span className="text-[10px] text-night-green uppercase font-semibold">
                                  Result
                                </span>
                                <div className="p-2 rounded bg-night-green/10 border border-night-green/20 text-night-green text-[11px] whitespace-pre-wrap max-h-36 overflow-y-auto mt-0.5">
                                  {task.result}
                                </div>
                              </div>
                            )}

                            {task.error && (
                              <div>
                                <span className="text-[10px] text-night-red uppercase font-semibold">
                                  Error
                                </span>
                                <div className="p-2 rounded bg-night-red/10 border border-night-red/20 text-night-red text-[11px] whitespace-pre-wrap max-h-36 overflow-y-auto mt-0.5">
                                  {task.error}
                                </div>
                              </div>
                            )}

                            <div className="flex flex-wrap gap-2 text-[10px] text-night-muted pt-1">
                              <span>Created: {new Date(task.created_at * 1000).toLocaleTimeString()}</span>
                              {task.claimed_at && (
                                <span>Claimed: {new Date(task.claimed_at * 1000).toLocaleTimeString()}</span>
                              )}
                              {task.completed_at && (
                                <span>Done: {new Date(task.completed_at * 1000).toLocaleTimeString()}</span>
                              )}
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Handheld Controller Navigation Footer Bar */}
      {(handheldMode || gamepadConnected) && (
        <div className="flex-none px-3 py-1.5 bg-night-panel border-t border-night-border flex items-center justify-between text-[11px] font-mono select-none">
          <div className="flex items-center gap-2">
            <Gamepad2 className="w-3.5 h-3.5 text-night-cyan animate-pulse" />
            <span className="text-night-text font-semibold truncate max-w-[200px] sm:max-w-none">
              {gamepadName || 'Handheld Controller Ready'}
            </span>
          </div>

          {/* Steam Deck / Handheld Button Prompts */}
          <div className="flex items-center gap-3 text-night-muted">
            <span className="hidden sm:inline">
              <kbd className="px-1 py-0.5 rounded bg-night-surface border border-night-border text-night-cyan">
                D-Pad
              </kbd>{' '}
              Move
            </span>
            <span>
              <kbd className="px-1 py-0.5 rounded bg-night-surface border border-night-border text-night-cyan">
                L1/R1
              </kbd>{' '}
              Column
            </span>
            <span>
              <kbd className="px-1 py-0.5 rounded bg-night-surface border border-night-border text-night-cyan">
                A
              </kbd>{' '}
              Inspect
            </span>
            <span className="hidden xs:inline">
              <kbd className="px-1 py-0.5 rounded bg-night-surface border border-night-border text-night-cyan">
                Y
              </kbd>{' '}
              Handheld
            </span>
          </div>
        </div>
      )}
    </div>
  );
};

export default BlackboardKanban;
