import React, { useState, useEffect } from 'react';
import {
  Activity,
  Brain,
  Clock,
  Code,
  Gamepad2,
  Info,
  Laptop,
  Monitor,
  Sparkles,
  Terminal,
  Wrench,
  Zap,
} from 'lucide-react';
import type { DagTask, MeshNode, NodeActivityInfo, NodeId } from '../../types/knot';

interface SwarmActivityBarProps {
  tasks: DagTask[];
  nodes?: MeshNode[];
}

interface UnifiedActiveItem {
  id: string;
  node_id: NodeId | string;
  title: string;
  prompt?: string;
  status: string;
  model?: string;
  step_index?: number;
  tool_name?: string | null;
  tool_action?: string | null;
  tool_summary?: string | null;
  command?: string | null;
  args_summary?: string | null;
  thinking_snippet?: string | null;
  started_at: number;
  conv_id?: string;
}

export const SwarmActivityBar: React.FC<SwarmActivityBarProps> = ({ tasks, nodes = [] }) => {
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [pinnedId, setPinnedId] = useState<string | null>(null);
  const [, setNowTs] = useState(Date.now());

  // Ticking interval for smooth real-time seconds counters
  useEffect(() => {
    const interval = setInterval(() => setNowTs(Date.now()), 1000);
    return () => clearInterval(interval);
  }, []);

  // 1. Gather all executing nodes with live telemetry
  const executingNodes = nodes.filter((n) => {
    const act = n.activity || n.power?.activity;
    return act?.is_executing || n.power?.is_executing_task;
  });

  // 2. Active tasks from Tuplespace
  const activeTasks = tasks.filter(
    (t) => t.status === 'RUNNING' || t.status === 'CLAIMED'
  );

  if (activeTasks.length === 0 && executingNodes.length === 0) {
    return null;
  }

  // 3. Build unified list of active items, merging task & node activity where applicable
  const unifiedItems: UnifiedActiveItem[] = [];
  const handledTaskIds = new Set<string>();
  const handledNodeIds = new Set<string>();

  for (const node of executingNodes) {
    const act: NodeActivityInfo | undefined = node.activity || node.power?.activity;
    const matchingTask = act?.task_id
      ? activeTasks.find((t) => t.id === act.task_id)
      : activeTasks.find((t) => t.node_id === node.node_id);

    if (matchingTask) {
      handledTaskIds.add(matchingTask.id);
    }
    handledNodeIds.add(node.node_id);

    const startedAt = act?.started_at
      ? act.started_at * 1000
      : matchingTask?.claimed_at
      ? matchingTask.claimed_at * 1000
      : Date.now();

    unifiedItems.push({
      id: `node-${node.node_id}-${act?.task_id || 'turn'}`,
      node_id: node.node_id,
      title: act?.task_title || matchingTask?.title || `Autonomous Turn (@${node.node_id})`,
      prompt: matchingTask?.prompt,
      status: act?.status || matchingTask?.status || 'RUNNING',
      model: act?.model || node.selected_model,
      step_index: act?.step_index,
      tool_name: act?.tool_name,
      tool_action: act?.tool_action,
      tool_summary: act?.tool_summary,
      command: act?.command,
      args_summary: act?.args_summary,
      thinking_snippet: act?.thinking_snippet,
      started_at: startedAt,
      conv_id: act?.conv_id,
    });
  }

  // Add any unmerged active tasks (e.g. claimed by node before node activity payload arrived)
  for (const task of activeTasks) {
    if (!handledTaskIds.has(task.id)) {
      unifiedItems.push({
        id: `task-${task.id}`,
        node_id: task.node_id || 'any',
        title: task.title || task.prompt.slice(0, 50),
        prompt: task.prompt,
        status: task.status,
        started_at: task.claimed_at ? task.claimed_at * 1000 : Date.now(),
      });
    }
  }

  const getNodeBadge = (nodeId: NodeId | string, activeModel?: string) => {
    const node = nodes.find((n) => n.node_id === nodeId);
    const caps = node?.capabilities || [];
    let role = 'Worker Node';
    if (caps.includes('anchor') || caps.includes('master_planner') || nodeId === 'desktop') {
      role = 'Master Planner / Fleet Anchor';
    } else if (caps.includes('gpu_cuda') || caps.includes('rtx_3050') || nodeId === 'laptop') {
      role = 'CUDA Accelerated (RTX 3050)';
    } else if (caps.includes('embedded_gamepad') || caps.includes('steamdeck') || nodeId === 'steamdeck') {
      role = 'Van Gogh Handheld APU';
    }
    const resolvedModel = activeModel || node?.selected_model;
    const fullRole = resolvedModel ? `${role} (${resolvedModel})` : role;

    switch (nodeId) {
      case 'desktop':
        return {
          icon: <Monitor className="w-3 h-3 text-night-magenta" />,
          role: fullRole,
          color: 'text-night-magenta border-night-magenta/30 bg-night-magenta/10',
          barColor: 'from-night-magenta/80 to-night-blue/80',
          glow: 'shadow-[0_0_10px_rgba(187,154,247,0.25)]',
        };
      case 'laptop':
        return {
          icon: <Laptop className="w-3 h-3 text-night-cyan" />,
          role: fullRole,
          color: 'text-night-cyan border-night-cyan/30 bg-night-cyan/10',
          barColor: 'from-night-cyan/80 to-night-blue/80',
          glow: 'shadow-[0_0_10px_rgba(125,207,255,0.25)]',
        };
      case 'steamdeck':
        return {
          icon: <Gamepad2 className="w-3 h-3 text-night-orange" />,
          role: fullRole,
          color: 'text-night-orange border-night-orange/30 bg-night-orange/10',
          barColor: 'from-night-orange/80 to-night-yellow/80',
          glow: 'shadow-[0_0_10px_rgba(255,158,100,0.25)]',
        };
      default:
        return {
          icon: <Sparkles className="w-3 h-3 text-night-yellow" />,
          role: fullRole,
          color: 'text-night-yellow border-night-yellow/30 bg-night-yellow/10',
          barColor: 'from-night-yellow/80 to-night-orange/80',
          glow: 'shadow-[0_0_10px_rgba(224,175,104,0.25)]',
        };
    }
  };

  const getStatusBadge = (status: string) => {
    const s = (status || '').toUpperCase();
    if (s.includes('WAIT')) {
      return {
        label: 'WAITING',
        color: 'text-amber-400 bg-amber-950/60 border-amber-500/40',
        icon: <Clock className="w-2.5 h-2.5 animate-spin" />,
      };
    }
    if (s.includes('CMD') || s.includes('COMMAND')) {
      return {
        label: 'RUNNING CMD',
        color: 'text-emerald-400 bg-emerald-950/60 border-emerald-500/40',
        icon: <Terminal className="w-2.5 h-2.5 animate-pulse" />,
      };
    }
    if (s.includes('DISPATCH') || s.includes('FANOUT')) {
      return {
        label: 'FAN-OUT',
        color: 'text-pink-400 bg-pink-950/60 border-pink-500/40',
        icon: <Zap className="w-2.5 h-2.5 animate-bounce" />,
      };
    }
    if (s.includes('THINK') || s.includes('SYNTH')) {
      return {
        label: 'THINKING',
        color: 'text-purple-400 bg-purple-950/60 border-purple-500/40',
        icon: <Brain className="w-2.5 h-2.5 animate-pulse" />,
      };
    }
    if (s.includes('TOOL')) {
      return {
        label: 'TOOL USE',
        color: 'text-cyan-400 bg-cyan-950/60 border-cyan-500/40',
        icon: <Wrench className="w-2.5 h-2.5 animate-pulse" />,
      };
    }
    return {
      label: s || 'EXECUTING',
      color: 'text-night-cyan bg-night-panel border-night-cyan/40',
      icon: <Activity className="w-2.5 h-2.5 animate-pulse" />,
    };
  };

  return (
    <div className="flex-none px-3 py-2 bg-night-panel/95 border-t border-night-border/70 border-b border-night-border/40 shadow-inner flex flex-col gap-1.5 transition-all">
      <div className="flex items-center justify-between text-[10px] font-mono">
        <div className="flex items-center gap-1.5 text-night-yellow font-bold uppercase tracking-wider">
          <Activity className="w-3.5 h-3.5 animate-pulse text-night-yellow" />
          <span>Active Swarm Work ({unifiedItems.length})</span>
          <span className="inline-block w-1.5 h-1.5 rounded-full bg-night-green animate-ping ml-0.5" />
        </div>
        <span className="text-night-muted">Click or hover for live inspector</span>
      </div>

      <div className="flex flex-col gap-1.5">
        {unifiedItems.map((item) => {
          const badge = getNodeBadge(item.node_id, item.model);
          const statusBadge = getStatusBadge(item.status);
          const elapsedSec = Math.max(0, Math.floor((Date.now() - item.started_at) / 1000));
          const isHovered = hoveredId === item.id || pinnedId === item.id;

          // Main display text: tool action if available, else item title
          const actionText = item.tool_action || item.title;

          return (
            <div
              key={item.id}
              onMouseEnter={() => setHoveredId(item.id)}
              onMouseLeave={() => setHoveredId(null)}
              onClick={() => setPinnedId((curr) => (curr === item.id ? null : item.id))}
              className="relative group cursor-pointer"
            >
              {/* Colored Activity Bar */}
              <div
                className={`flex items-center justify-between px-2.5 py-1.5 rounded-lg bg-night-surface/90 hover:bg-night-surface border ${
                  isHovered ? 'border-night-blue' : 'border-night-border/70'
                } ${badge.glow} transition-all text-[11px] font-mono relative overflow-hidden`}
              >
                {/* Background Shimmer Bar */}
                <div
                  className={`absolute inset-0 opacity-15 bg-gradient-to-r ${badge.barColor} animate-shimmer`}
                />

                <div className="flex items-center gap-2 min-w-0 z-10">
                  {/* Node Badge */}
                  <span
                    className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded border ${badge.color} text-[10px] font-bold flex-shrink-0`}
                  >
                    {badge.icon}
                    @{item.node_id}
                  </span>

                  {/* Active Model Pill */}
                  {item.model && (
                    <span className="px-1.5 py-0.2 rounded bg-night-surface/90 text-night-cyan border border-night-cyan/30 text-[9px] font-mono font-medium hidden md:inline-block flex-shrink-0">
                      {item.model.split('-').slice(0, 3).join('-')}
                    </span>
                  )}

                  {/* Step Index Pill */}
                  {typeof item.step_index === 'number' && item.step_index > 0 && (
                    <span className="px-1.5 py-0.2 rounded bg-night-panel/80 text-night-muted border border-night-border/60 text-[9px] font-bold flex-shrink-0">
                      Step {item.step_index}
                    </span>
                  )}

                  {/* Tool Action or Title */}
                  <span className="text-night-text truncate font-medium flex items-center gap-1">
                    {item.command ? (
                      <Terminal className="w-3 h-3 text-emerald-400 flex-shrink-0 inline" />
                    ) : item.tool_name ? (
                      <Wrench className="w-3 h-3 text-night-blue flex-shrink-0 inline" />
                    ) : null}
                    <span className="truncate">{actionText}</span>
                  </span>
                </div>

                {/* Right Metrics: Timer & Status */}
                <div className="flex items-center gap-2 text-[10px] text-night-muted z-10 flex-shrink-0 ml-2">
                  <span className="flex items-center gap-1 font-mono text-night-text/90">
                    <Clock className="w-2.5 h-2.5 text-night-cyan" />
                    {elapsedSec}s
                  </span>
                  <span
                    className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded border ${statusBadge.color} font-bold uppercase text-[9px]`}
                  >
                    {statusBadge.icon}
                    {statusBadge.label}
                  </span>
                </div>
              </div>

              {/* Hover Live Inspector Card */}
              {isHovered && (
                <div
                  className="absolute bottom-full left-1 right-1 mb-2 z-50 p-3.5 rounded-xl bg-night-panel/98 border border-night-blue/60 shadow-2xl backdrop-blur-md text-[11px] font-mono flex flex-col gap-2.5 animate-fade-in"
                  onClick={(e) => e.stopPropagation()}
                >
                  {/* Inspector Header */}
                  <div className="flex items-center justify-between border-b border-night-border/70 pb-2">
                    <div className="flex items-center gap-2">
                      <div className={`p-1 rounded-md border ${badge.color}`}>
                        {badge.icon}
                      </div>
                      <div className="flex flex-col">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="font-bold text-night-text text-xs">
                            @{item.node_id}
                          </span>
                          {item.model && (
                            <span className="text-[9px] px-1.5 py-0.2 rounded bg-purple-500/15 text-purple-300 border border-purple-500/30 font-mono font-bold">
                              {item.model}
                            </span>
                          )}
                        </div>
                        {item.conv_id && (
                          <span className="text-[10px] text-night-blue">
                            Channel: #{item.conv_id}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <span
                        className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border ${statusBadge.color} text-[10px] font-bold`}
                      >
                        {statusBadge.icon}
                        {statusBadge.label}
                      </span>
                      <span className="flex items-center gap-1 px-2 py-0.5 rounded bg-night-surface border border-night-border text-[10px] text-night-cyan font-bold">
                        <Clock className="w-3 h-3" />
                        {elapsedSec}s
                      </span>
                    </div>
                  </div>

                  {/* Goal / Task Title */}
                  <div className="flex items-start gap-1.5 text-[11px] bg-night-surface/70 p-2 rounded-lg border border-night-border/50">
                    <Info className="w-3.5 h-3.5 text-night-cyan flex-shrink-0 mt-0.5" />
                    <div className="flex flex-col min-w-0">
                      <span className="text-[10px] text-night-muted font-semibold uppercase tracking-wider">
                        Task Goal
                      </span>
                      <span className="text-night-text font-medium leading-snug">
                        {item.title}
                      </span>
                    </div>
                  </div>

                  {/* Live Tool Action & Step */}
                  {(item.tool_action || item.tool_name) && (
                    <div className="flex items-start gap-1.5 text-[11px] bg-night-surface/70 p-2 rounded-lg border border-night-border/50">
                      <Wrench className="w-3.5 h-3.5 text-night-magenta flex-shrink-0 mt-0.5" />
                      <div className="flex flex-col min-w-0 w-full">
                        <div className="flex items-center justify-between">
                          <span className="text-[10px] text-night-muted font-semibold uppercase tracking-wider">
                            Active Step {item.step_index ? `#${item.step_index}` : ''}
                          </span>
                          {item.tool_name && (
                            <span className="text-[9px] text-night-magenta font-mono bg-night-magenta/10 px-1 rounded border border-night-magenta/30">
                              {item.tool_name}
                            </span>
                          )}
                        </div>
                        <span className="text-night-text font-medium leading-snug">
                          {item.tool_action || 'Executing tool...'}
                        </span>
                      </div>
                    </div>
                  )}

                  {/* Executing Command Snippet */}
                  {item.command && (
                    <div className="flex flex-col gap-1 bg-black/70 p-2 rounded-lg border border-emerald-500/30 text-[10px]">
                      <span className="text-emerald-400 font-bold flex items-center gap-1 text-[9px] uppercase tracking-wider">
                        <Terminal className="w-3 h-3" /> Executing Shell Command
                      </span>
                      <pre className="text-emerald-300 overflow-x-auto whitespace-pre-wrap break-all font-mono">
                        $ {item.command}
                      </pre>
                    </div>
                  )}

                  {/* Tool Arguments / Details */}
                  {item.args_summary && !item.command && (
                    <div className="flex flex-col gap-1 bg-black/60 p-2 rounded-lg border border-night-blue/30 text-[10px]">
                      <span className="text-night-blue font-bold flex items-center gap-1 text-[9px] uppercase tracking-wider">
                        <Code className="w-3 h-3" /> Tool Parameters
                      </span>
                      <pre className="text-night-text/90 overflow-x-auto whitespace-pre-wrap break-all font-mono">
                        {item.args_summary}
                      </pre>
                    </div>
                  )}

                  {/* Agent Thinking Snippet */}
                  {item.thinking_snippet && (
                    <div className="flex flex-col gap-1 bg-purple-950/20 p-2 rounded-lg border border-purple-500/30 text-[10px]">
                      <span className="text-purple-400 font-bold flex items-center gap-1 text-[9px] uppercase tracking-wider">
                        <Brain className="w-3 h-3" /> Agent Reasoning
                      </span>
                      <span className="text-night-text/80 italic leading-relaxed">
                        "{item.thinking_snippet}..."
                      </span>
                    </div>
                  )}

                  {/* Task Prompt Preview (if available) */}
                  {item.prompt && (
                    <div className="text-[10px] text-night-muted leading-relaxed line-clamp-2 pt-0.5 border-t border-night-border/40">
                      <strong className="text-night-text font-semibold">Prompt: </strong>
                      {item.prompt}
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
};
