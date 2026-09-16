import React, { useState } from 'react';
import {
  AlertCircle,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Clock,
  GitBranch,
  Layers,
  Lock,
  PlayCircle,
} from 'lucide-react';
import type { DagTask, TaskStatus } from '../../types/knot';

interface DagMatrixProps {
  tasks: DagTask[];
  embedded?: boolean;
}

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
    return { title: meta.command.slice(0, 36), hash };
  }
  const cleanPrompt = (task.prompt || '').replace(/^[#*\s-]+/, '').split('\n')[0].trim();
  if (cleanPrompt.length > 0) {
    const truncated = cleanPrompt.length > 40 ? cleanPrompt.slice(0, 40) + '...' : cleanPrompt;
    return { title: truncated, hash };
  }
  return { title: `Task #${hash}`, hash };
};

export const DagMatrix: React.FC<DagMatrixProps> = ({ tasks, embedded = false }) => {
  const [expandedTasks, setExpandedTasks] = useState<Record<string, boolean>>({});

  const toggleExpand = (taskId: string) => {
    setExpandedTasks((prev) => ({ ...prev, [taskId]: !prev[taskId] }));
  };

  const getStatusBadge = (status: TaskStatus) => {
    switch (status) {
      case 'BLOCKED_ON_DEPS':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-yellow/20 text-night-yellow border border-night-yellow/30">
            <Lock className="w-2.5 h-2.5" /> BLOCKED
          </span>
        );
      case 'QUEUED':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-cyan/20 text-night-cyan border border-night-cyan/30">
            <Clock className="w-2.5 h-2.5" /> QUEUED
          </span>
        );
      case 'CLAIMED':
      case 'RUNNING':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-blue/20 text-night-blue border border-night-blue/30 animate-pulse">
            <PlayCircle className="w-2.5 h-2.5" /> RUNNING
          </span>
        );
      case 'COMPLETED':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-green/20 text-night-green border border-night-green/30">
            <CheckCircle2 className="w-2.5 h-2.5" /> COMPLETED
          </span>
        );
      case 'FAILED':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-red/20 text-night-red border border-night-red/30">
            <AlertCircle className="w-2.5 h-2.5" /> FAILED
          </span>
        );
      default:
        return (
          <span className="text-[9px] font-mono px-2 py-0.5 rounded bg-night-surface text-night-muted">
            {status}
          </span>
        );
    }
  };

  // Group by batch_id
  const batches = tasks.reduce<Record<string, DagTask[]>>((acc, task) => {
    const key = task.batch_id || 'standalone';
    if (!acc[key]) acc[key] = [];
    acc[key].push(task);
    return acc;
  }, {});

  return (
    <div
      className={`flex flex-col h-full min-h-0 ${
        embedded ? '' : 'glass rounded-xl border border-night-border'
      } overflow-hidden`}
    >
      {/* Header (shown if not embedded) */}
      {!embedded && (
        <div className="flex-none px-4 py-2.5 border-b border-night-border flex items-center justify-between bg-night-panel/60">
          <div className="flex items-center space-x-2">
            <GitBranch className="w-4 h-4 text-night-cyan" />
            <h2 className="text-xs font-bold tracking-wider text-night-blue uppercase">
              DAG Task Matrix
            </h2>
          </div>
          <span className="text-[10px] font-mono text-night-muted">
            {tasks.length} TOTAL TASKS
          </span>
        </div>
      )}

      {/* Task List / Batches */}
      <div className="flex-1 min-h-0 overflow-y-auto p-3 space-y-4 overscroll-contain">
        {Object.entries(batches).map(([batchId, batchTasks]) => {
          const completedCount = batchTasks.filter((t) => t.status === 'COMPLETED').length;
          const pct = Math.round((completedCount / batchTasks.length) * 100);

          return (
            <div
              key={batchId}
              className="glass-card rounded-lg border border-night-border/70 overflow-hidden"
            >
              {/* Batch Banner */}
              <div className="px-3 py-2 bg-night-panel/80 border-b border-night-border/60 flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <Layers className="w-3.5 h-3.5 text-night-cyan" />
                  <span className="font-mono text-[10px] text-night-muted">BATCH:</span>
                  <span className="font-mono text-[10px] font-bold text-night-text">
                    {batchId === 'standalone' ? 'STANDALONE TASKS' : `Batch #${batchId.slice(0, 8)}`}
                  </span>
                </div>
                <div className="flex items-center space-x-2 text-[10px] font-mono">
                  <span className="text-night-muted">
                    {completedCount}/{batchTasks.length} DONE
                  </span>
                  <div className="w-12 h-1.5 bg-night-surface rounded-full overflow-hidden">
                    <div
                      className="h-full bg-night-green transition-all"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              </div>

              {/* Tasks inside this batch */}
              <div className="p-2 space-y-2">
                {batchTasks.map((task) => {
                  const isExpanded = expandedTasks[task.id] ?? false;
                  const humanId = getTaskHumanIdentifier(task);
                  const elapsed =
                    task.completed_at && task.claimed_at
                      ? `${(task.completed_at - task.claimed_at).toFixed(2)}s`
                      : null;

                  return (
                    <div
                      key={task.id}
                      className="rounded bg-night-surface/60 border border-night-border/50 p-2 text-xs font-mono"
                    >
                      <div
                        className="flex items-center justify-between cursor-pointer select-none gap-2"
                        onClick={() => toggleExpand(task.id)}
                      >
                        <div className="flex items-center space-x-2 truncate min-w-0 pr-1">
                          {isExpanded ? (
                            <ChevronDown className="w-3 h-3 text-night-muted flex-shrink-0" />
                          ) : (
                            <ChevronRight className="w-3 h-3 text-night-muted flex-shrink-0" />
                          )}
                          <span className="text-night-text font-semibold truncate text-[11px]">
                            {humanId.title}
                          </span>
                          <span className="text-[9px] font-mono font-bold px-1.5 py-0.5 rounded bg-night-surface text-night-cyan border border-night-cyan/30 flex-shrink-0">
                            #{humanId.hash}
                          </span>
                          <span className="text-[10px] text-night-muted font-mono flex-shrink-0">
                            @{task.node_id}
                          </span>
                          {Boolean(task.meta?.model) && (
                            <span className="text-[8px] font-mono px-1 py-0.2 rounded bg-night-panel text-night-muted border border-night-border/40 hidden md:inline-block flex-shrink-0">
                              {String(task.meta.model)}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center space-x-2 flex-shrink-0">
                          {elapsed && (
                            <span className="text-[9px] text-night-muted">{elapsed}</span>
                          )}
                          {getStatusBadge(task.status)}
                        </div>
                      </div>

                      {/* Dependencies chips */}
                      {task.dependencies && task.dependencies.length > 0 && (
                        <div className="flex items-center gap-1 mt-1.5 pl-5">
                          <span className="text-[9px] text-night-muted">DEPS:</span>
                          {task.dependencies.map((depId) => (
                            <span
                              key={depId}
                              className="text-[8px] px-1 py-0.2 rounded bg-night-panel text-night-yellow border border-night-yellow/30"
                            >
                              {depId.slice(0, 8)}
                            </span>
                          ))}
                        </div>
                      )}

                      {/* Expanded Details */}
                      {isExpanded && (
                        <div className="mt-2.5 pt-2 border-t border-night-border/40 pl-5 space-y-2">
                          <div>
                            <span className="text-[9px] font-bold text-night-cyan">
                              PROMPT:
                            </span>
                            <pre className="text-[10px] text-night-text whitespace-pre-wrap bg-night-bg/80 p-2 rounded border border-night-border/40 mt-1 max-h-32 overflow-y-auto">
                              {task.prompt}
                            </pre>
                          </div>

                          {task.result && (
                            <div>
                              <span className="text-[9px] font-bold text-night-green">
                                RESULT:
                              </span>
                              <pre className="text-[10px] text-night-text whitespace-pre-wrap bg-night-bg/80 p-2 rounded border border-night-border/40 mt-1 max-h-48 overflow-y-auto">
                                {task.result}
                              </pre>
                            </div>
                          )}

                          {task.error && (
                            <div>
                              <span className="text-[9px] font-bold text-night-red">
                                ERROR:
                              </span>
                              <pre className="text-[10px] text-night-red whitespace-pre-wrap bg-night-red/10 p-2 rounded border border-night-red/30 mt-1">
                                {task.error}
                              </pre>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
