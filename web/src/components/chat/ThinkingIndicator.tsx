import React, { useState, useEffect } from 'react';
import {
  Bot,
  Brain,
  Gamepad2,
  Laptop,
  Monitor,
  Sparkles,
  Terminal,
} from 'lucide-react';
import type { MeshNode, NodeActivityInfo, NodeId } from '../../types/knot';

interface ThinkingIndicatorProps {
  targetNode: NodeId | null;
  startTime?: number;
  channelName?: string;
  taskTitle?: string;
  activity?: NodeActivityInfo;
  nodes?: MeshNode[];
}

export const ThinkingIndicator: React.FC<ThinkingIndicatorProps> = ({
  targetNode,
  startTime,
  channelName,
  taskTitle,
  activity,
  nodes = [],
}) => {
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    const start = startTime || (activity?.started_at ? activity.started_at * 1000 : Date.now());
    const interval = setInterval(() => {
      setElapsed(Math.max(0, Math.floor((Date.now() - start) / 1000)));
    }, 250);
    return () => clearInterval(interval);
  }, [startTime, activity?.started_at]);

  const getNodeInfo = (nodeId: NodeId | null) => {
    const matchedNode = nodes.find((n) => n.node_id === nodeId);
    const caps = matchedNode?.capabilities || [];
    let role = 'Worker Node';
    if (caps.includes('anchor') || caps.includes('master_planner') || nodeId === 'desktop') {
      role = 'Master Planner / Fleet Anchor';
    } else if (caps.includes('gpu_cuda') || caps.includes('rtx_3050') || nodeId === 'laptop') {
      role = 'CUDA Accelerated (RTX 3050)';
    } else if (caps.includes('embedded_gamepad') || caps.includes('steamdeck') || nodeId === 'steamdeck') {
      role = 'Van Gogh Handheld APU';
    }
    const resolvedModel = activity?.model || matchedNode?.selected_model;
    const fullRole = resolvedModel ? `${role} (${resolvedModel})` : role;

    switch (nodeId) {
      case 'desktop':
        return {
          name: '@desktop',
          role: fullRole,
          color: 'text-night-magenta border-night-magenta/40 bg-night-magenta/10',
          halo: 'border-night-magenta shadow-[0_0_12px_rgba(187,154,247,0.4)]',
          icon: <Monitor className="w-3.5 h-3.5 text-night-magenta" />,
        };
      case 'laptop':
        return {
          name: '@laptop',
          role: fullRole,
          color: 'text-night-cyan border-night-cyan/40 bg-night-cyan/10',
          halo: 'border-night-cyan shadow-[0_0_12px_rgba(125,207,255,0.4)]',
          icon: <Laptop className="w-3.5 h-3.5 text-night-cyan" />,
        };
      case 'steamdeck':
        return {
          name: '@steamdeck',
          role: fullRole,
          color: 'text-night-orange border-night-orange/40 bg-night-orange/10',
          halo: 'border-night-orange shadow-[0_0_12px_rgba(255,158,100,0.4)]',
          icon: <Gamepad2 className="w-3.5 h-3.5 text-night-orange" />,
        };
      case 'swarm':
      default:
        return {
          name: '@swarm',
          role: fullRole,
          color: 'text-night-yellow border-night-yellow/40 bg-night-yellow/10',
          halo: 'border-night-yellow shadow-[0_0_12px_rgba(224,175,104,0.4)]',
          icon: <Sparkles className="w-3.5 h-3.5 text-night-yellow" />,
        };
    }
  };

  const node = getNodeInfo(targetNode);
  const liveAction = activity?.tool_action;
  const stepNumber = activity?.step_index;

  return (
    <div className="flex flex-col items-start transition-all animate-fade-in my-1">
      {/* Meta Header */}
      <div className="flex items-center space-x-2 text-[10px] font-mono text-night-muted mb-1 px-1">
        <span className="flex items-center gap-1 font-semibold text-night-muted">
          <Bot className="w-3 h-3 text-night-blue animate-spin" /> Autonomous Agent Turn
        </span>
        <span>•</span>
        <span>#{channelName || 'main'}</span>
      </div>

      {/* Liveness Card */}
      <div
        className={`max-w-[85%] rounded-xl rounded-tl-none px-4 py-3 border ${node.color} bg-night-panel/95 backdrop-blur-md shadow-lg flex flex-col gap-2.5 relative overflow-hidden`}
      >
        {/* Animated Shimmer Line */}
        <div className="absolute top-0 left-0 right-0 h-[2px] bg-gradient-to-r from-transparent via-night-blue to-transparent animate-shimmer" />

        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            {/* Spinning Pulse Icon */}
            <div
              className={`w-6 h-6 rounded-full flex items-center justify-center border ${node.halo} bg-night-surface flex-shrink-0`}
            >
              {node.icon}
            </div>

            <div className="flex flex-col">
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-bold font-mono tracking-wide">{node.name}</span>
                <span className="text-[10px] font-mono text-night-muted hidden sm:inline">
                  ({node.role})
                </span>
              </div>
              <div className="flex items-center gap-1.5 text-[11px] font-mono text-night-text/85">
                {liveAction ? (
                  <span className="text-night-cyan font-medium flex items-center gap-1">
                    {stepNumber && stepNumber > 0 && (
                      <span className="text-[10px] text-night-muted bg-night-surface px-1 rounded border border-night-border">
                        Step {stepNumber}
                      </span>
                    )}
                    <span>{liveAction}</span>
                  </span>
                ) : (
                  <span>Executing native turn</span>
                )}

                {/* 3 Pulsing Wave Dots */}
                <span className="inline-flex items-center space-x-0.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-night-blue animate-ping" />
                  <span className="w-1.5 h-1.5 rounded-full bg-night-cyan animate-pulse delay-100" />
                  <span className="w-1.5 h-1.5 rounded-full bg-night-magenta animate-pulse delay-200" />
                </span>
              </div>
            </div>
          </div>

          {/* Live Timer Badge */}
          <div className="flex items-center gap-1 px-2 py-0.5 rounded bg-night-surface/90 border border-night-border/70 text-[10px] font-mono text-night-muted flex-shrink-0">
            <span className="w-1.5 h-1.5 rounded-full bg-night-green animate-pulse" />
            <span>{elapsed}s</span>
          </div>
        </div>

        {/* Executing Command Preview */}
        {activity?.command && (
          <div className="flex flex-col gap-0.5 bg-black/60 p-2 rounded-lg border border-emerald-500/30 text-[10px] font-mono">
            <span className="text-emerald-400 font-bold flex items-center gap-1 text-[9px] uppercase tracking-wider">
              <Terminal className="w-3 h-3" /> Shell Command
            </span>
            <span className="text-emerald-300 truncate">$ {activity.command}</span>
          </div>
        )}

        {/* Agent Thought / Reasoning Preview */}
        {activity?.thinking_snippet && !activity.command && (
          <div className="flex items-start gap-1 text-[10px] text-night-text/80 bg-purple-950/20 p-1.5 rounded border border-purple-500/20 italic">
            <Brain className="w-3 h-3 text-purple-400 flex-shrink-0 mt-0.5" />
            <span className="line-clamp-2">"{activity.thinking_snippet}..."</span>
          </div>
        )}

        {/* Task Title if available */}
        {(taskTitle || activity?.task_title) && (
          <div className="text-[10px] font-mono text-night-muted truncate pl-8 border-t border-night-border/40 pt-1">
            <span className="text-night-blue font-semibold">Goal:</span>{' '}
            {taskTitle || activity?.task_title}
          </div>
        )}
      </div>
    </div>
  );
};
