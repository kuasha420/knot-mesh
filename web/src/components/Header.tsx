import React, { useState, useRef, useEffect } from 'react';
import {
  Activity,
  ChevronDown,
  FolderGit2,
  GitBranch,
  KeyRound,
  LayoutGrid,
  MessageSquare,
  Moon,
  Radio,
  RefreshCw,
  Server,
  Sparkles,
  Zap,
} from 'lucide-react';
import type { ConnectionState, MeshNode, DagTask, CockpitViewMode, KnotProject, SwarmPowerState, SwarmModelsState } from '../types/knot';
import { groupModelsByDepth } from '../utils/models';

export interface HeaderProps {
  connectionState: ConnectionState;
  nodes: MeshNode[];
  tasks: DagTask[];
  onRefresh: () => void;
  viewMode?: CockpitViewMode;
  onViewModeChange?: (view: CockpitViewMode) => void;
  projects?: KnotProject[];
  activeProjectId?: string;
  onProjectChange?: (projectId: string) => void;
  powerStatus?: SwarmPowerState | null;
  onSetWakeHold?: (minutes: number) => Promise<boolean>;
  onReleaseWakeHold?: () => Promise<boolean>;
  models?: SwarmModelsState | null;
  onSelectSwarmModel?: (model: string, nodeId?: string, applyToAll?: boolean) => void;
}

export const Header: React.FC<HeaderProps> = ({
  connectionState,
  nodes,
  tasks,
  onRefresh,
  viewMode = 'grid',
  onViewModeChange,
  projects = [],
  activeProjectId,
  onProjectChange,
  powerStatus,
  onSetWakeHold,
  onReleaseWakeHold,
  models,
  onSelectSwarmModel,
}) => {
  const [isPowerMenuOpen, setIsPowerMenuOpen] = useState(false);
  const powerMenuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (powerMenuRef.current && !powerMenuRef.current.contains(event.target as Node)) {
        setIsPowerMenuOpen(false);
      }
    };
    if (isPowerMenuOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isPowerMenuOpen]);

  const swarmActive = powerStatus?.swarm_active ?? true;
  const holdSecRemaining = powerStatus?.activity?.manual_hold_sec_remaining ?? 0;
  const holdMinRemaining = Math.ceil(holdSecRemaining / 60);
  const onlineCount = nodes.filter((n) => n.status === 'ONLINE').length;
  const activeTasks = tasks.filter((t) =>
    ['QUEUED', 'CLAIMED', 'RUNNING', 'BLOCKED_ON_DEPS'].includes(t.status)
  ).length;

  return (
    <header className="h-14 flex-none glass border-b border-night-border px-3 sm:px-5 flex items-center justify-between z-50 select-none">
      {/* Brand / Logo + Project Selector */}
      <div className="flex items-center space-x-2 sm:space-x-3 flex-shrink-0">
        <span className="text-xl sm:text-2xl select-none">🪢</span>
        <div className="flex items-center gap-1.5 sm:gap-2">
          <h1 className="text-xs sm:text-sm font-bold tracking-wider text-night-blue whitespace-nowrap">
            KNOT COCKPIT
          </h1>
          <span className="text-[9px] sm:text-[10px] px-1.5 sm:px-2 py-0.5 rounded-full bg-night-surface text-night-cyan font-mono border border-night-border hidden xs:inline-block">
            v1.5
          </span>
        </div>

        {/* Native Antigravity Project Selector Dropdown */}
        {projects.length > 0 && onProjectChange && (
          <div className="relative group ml-1 sm:ml-2">
            <div className="flex items-center gap-1.5 bg-night-surface/90 hover:bg-night-surface border border-night-border hover:border-night-blue/50 rounded-lg px-2 sm:px-2.5 py-1 text-xs font-mono transition-all">
              <FolderGit2 className="w-3.5 h-3.5 text-night-blue flex-shrink-0" />
              <select
                value={activeProjectId}
                onChange={(e) => onProjectChange(e.target.value)}
                className="bg-transparent text-night-text text-xs font-mono font-medium focus:outline-none cursor-pointer pr-1 truncate max-w-[140px] sm:max-w-[190px]"
                title="Active Native Antigravity Project"
              >
                {projects.map((proj) => {
                  const folderCount = proj.folders ? proj.folders.length : 1;
                  return (
                    <option key={proj.id} value={proj.id} className="bg-night-panel text-night-text">
                      {proj.name} ({folderCount} {folderCount === 1 ? 'folder' : 'folders'})
                    </option>
                  );
                })}
              </select>
              <ChevronDown className="w-3 h-3 text-night-muted pointer-events-none" />
            </div>
          </div>
        )}

        {/* Unified Swarm Model Selector Dropdown */}
        {models && onSelectSwarmModel && (
          <div className="relative group ml-1 sm:ml-2">
            <div className="flex items-center gap-1.5 bg-night-surface/90 hover:bg-night-surface border border-night-border hover:border-night-cyan/50 rounded-lg px-2 sm:px-2.5 py-1 text-xs font-mono transition-all">
              <Sparkles className="w-3.5 h-3.5 text-night-cyan flex-shrink-0" />
              <div className="flex items-center gap-1">
                <span className="text-[10px] text-night-muted uppercase tracking-wider hidden 2xl:inline">
                  Swarm:
                </span>
                <select
                  value={models.default_model}
                  onChange={(e) => onSelectSwarmModel(e.target.value, undefined, true)}
                  className="bg-transparent text-night-text text-xs font-mono font-medium focus:outline-none cursor-pointer pr-1 truncate max-w-[140px] sm:max-w-[200px]"
                  title="Unified Swarm Model: Sets active default AI model for the entire mesh"
                >
                  {groupModelsByDepth(models.available_models).map((group) => (
                    <optgroup key={group.groupName} label={group.groupName} className="bg-night-panel text-night-cyan font-bold text-xs">
                      {group.models.map((m) => (
                        <option key={m.id} value={m.id} className="bg-night-surface text-night-text font-normal font-mono">
                          {m.shortLabel}
                        </option>
                      ))}
                    </optgroup>
                  ))}
                </select>
              </div>
              <ChevronDown className="w-3 h-3 text-night-muted pointer-events-none" />
            </div>
          </div>
        )}
      </div>

      {/* Responsive View Switcher Tabs */}
      {onViewModeChange && (
        <nav className="flex items-center bg-night-surface/80 p-0.5 sm:p-1 rounded-lg border border-night-border text-xs font-mono">
          <button
            onClick={() => onViewModeChange('grid')}
            title="Dashboard Grid (3-Column)"
            className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-md transition-all ${
              viewMode === 'grid'
                ? 'bg-night-panel text-night-blue font-bold shadow-sm border border-night-blue/40'
                : 'text-night-muted hover:text-night-text'
            }`}
          >
            <LayoutGrid className="w-3.5 h-3.5" />
            <span className="hidden lg:inline">Dashboard</span>
          </button>

          <button
            onClick={() => onViewModeChange('chat')}
            title="Swarm Konversations Chat"
            className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-md transition-all ${
              viewMode === 'chat'
                ? 'bg-night-panel text-night-cyan font-bold shadow-sm border border-night-cyan/40'
                : 'text-night-muted hover:text-night-text'
            }`}
          >
            <MessageSquare className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Chat</span>
          </button>

          <button
            onClick={() => onViewModeChange('radar')}
            title="Topology Radar & Quotas"
            className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-md transition-all ${
              viewMode === 'radar'
                ? 'bg-night-panel text-night-green font-bold shadow-sm border border-night-green/40'
                : 'text-night-muted hover:text-night-text'
            }`}
          >
            <Radio className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Radar</span>
          </button>

          <button
            onClick={() => onViewModeChange('dag')}
            title="DAG Task Matrix"
            className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-md transition-all ${
              viewMode === 'dag'
                ? 'bg-night-panel text-night-yellow font-bold shadow-sm border border-night-yellow/40'
                : 'text-night-muted hover:text-night-text'
            }`}
          >
            <GitBranch className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Tasks</span>
          </button>

          <button
            onClick={() => onViewModeChange('artifacts')}
            title="Artifact Leases Vault"
            className={`flex items-center gap-1 sm:gap-1.5 px-2 sm:px-2.5 py-1 rounded-md transition-all ${
              viewMode === 'artifacts'
                ? 'bg-night-panel text-night-magenta font-bold shadow-sm border border-night-magenta/40'
                : 'text-night-muted hover:text-night-text'
            }`}
          >
            <KeyRound className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Vault</span>
          </button>
        </nav>
      )}

      {/* Right Telemetry & Status Badges */}
      <div className="flex items-center space-x-2 sm:space-x-4 text-xs font-mono flex-shrink-0">
        {/* SSE Live Status */}
        <div className="flex items-center space-x-1.5" title={`SSE Status: ${connectionState}`}>
          <span
            className={`w-2 h-2 rounded-full ${
              connectionState === 'connected'
                ? 'bg-night-green animate-pulse'
                : connectionState === 'connecting'
                ? 'bg-night-yellow animate-ping'
                : 'bg-night-red'
            }`}
          />
          <span className="hidden xl:inline text-[11px] text-night-muted uppercase tracking-wider">
            {connectionState === 'connected' ? 'LIVE' : connectionState}
          </span>
        </div>

        {/* Mesh Nodes Status */}
        <div className="flex items-center space-x-1.5">
          <Server className="w-3 h-3 text-night-muted hidden sm:inline" />
          <span
            className={`px-1.5 sm:px-2 py-0.5 rounded font-mono text-[10px] sm:text-xs font-semibold border ${
              onlineCount === nodes.length && nodes.length > 0
                ? 'bg-night-surface text-night-green border-night-green/30'
                : 'bg-night-surface text-night-yellow border-night-yellow/30'
            }`}
          >
            {onlineCount}/{nodes.length || 3} <span className="hidden md:inline">MESH</span>
          </span>
        </div>

        {/* Active Tasks Status */}
        <div className="flex items-center space-x-1.5">
          <Activity className="w-3 h-3 text-night-muted hidden sm:inline" />
          <span className="px-1.5 sm:px-2 py-0.5 rounded font-mono text-[10px] sm:text-xs font-semibold bg-night-surface text-night-cyan border border-night-cyan/30">
            {activeTasks} <span className="hidden md:inline">TASKS</span>
          </span>
        </div>

        {/* Swarm Power & Sleep Inhibitor Lock Badge & Dropdown */}
        <div className="relative" ref={powerMenuRef}>
          <button
            onClick={() => setIsPowerMenuOpen((prev) => !prev)}
            className={`flex items-center space-x-1.5 px-2 py-0.5 rounded font-mono text-[10px] sm:text-xs font-semibold border transition-all ${
              swarmActive
                ? 'bg-night-surface text-night-yellow border-night-yellow/40 hover:bg-night-yellow/10 shadow-[0_0_10px_rgba(224,175,104,0.15)]'
                : 'bg-night-surface text-night-muted border-night-border hover:bg-night-surface/80'
            }`}
            title="Swarm Sleep Inhibitor & Power Management (Click to configure)"
          >
            {swarmActive ? (
              <Zap className="w-3 h-3 text-night-yellow animate-pulse" />
            ) : (
              <Moon className="w-3 h-3 text-night-muted" />
            )}
            <span>
              {swarmActive ? (
                <>
                  <span className="hidden md:inline">AWAKE</span>
                  {holdMinRemaining > 0 ? ` (${holdMinRemaining}m)` : ' (LOCK)'}
                </>
              ) : (
                'SLEEP OK'
              )}
            </span>
            <ChevronDown className="w-2.5 h-2.5 opacity-70" />
          </button>

          {isPowerMenuOpen && (
            <div className="absolute right-0 mt-1.5 w-60 rounded-xl bg-night-panel border border-night-border shadow-2xl z-50 py-1.5 font-mono text-xs overflow-hidden backdrop-blur-md">
              <div className="px-3 py-1.5 border-b border-night-border/70 text-[10px] text-night-muted">
                <span className="text-night-text font-bold uppercase tracking-wider block mb-0.5">
                  Swarm Power & Sleep
                </span>
                {powerStatus?.activity?.reasons?.length ? (
                  <span className="text-night-cyan text-[9px] block">
                    Active: {powerStatus.activity.reasons.join(', ')}
                  </span>
                ) : (
                  <span className="text-[9px] block">Dynamic AC sleep inhibitor active</span>
                )}
              </div>

              <div className="py-1">
                <button
                  onClick={() => {
                    void onSetWakeHold?.(60);
                    setIsPowerMenuOpen(false);
                  }}
                  className="w-full px-3 py-1.5 text-left text-night-text hover:bg-night-surface flex items-center space-x-2 transition-colors"
                >
                  <Zap className="w-3.5 h-3.5 text-night-yellow" />
                  <span>Hold Awake (1 Hour)</span>
                </button>

                <button
                  onClick={() => {
                    void onSetWakeHold?.(240);
                    setIsPowerMenuOpen(false);
                  }}
                  className="w-full px-3 py-1.5 text-left text-night-text hover:bg-night-surface flex items-center space-x-2 transition-colors"
                >
                  <Zap className="w-3.5 h-3.5 text-night-orange" />
                  <span>Hold Awake (4 Hours)</span>
                </button>

                <button
                  onClick={() => {
                    void onSetWakeHold?.(720);
                    setIsPowerMenuOpen(false);
                  }}
                  className="w-full px-3 py-1.5 text-left text-night-text hover:bg-night-surface flex items-center space-x-2 transition-colors"
                >
                  <Zap className="w-3.5 h-3.5 text-night-magenta" />
                  <span>Hold Awake (12 Hours)</span>
                </button>

                <div className="border-t border-night-border/70 my-1" />

                <button
                  onClick={() => {
                    void onReleaseWakeHold?.();
                    setIsPowerMenuOpen(false);
                  }}
                  className="w-full px-3 py-1.5 text-left text-night-muted hover:text-night-red hover:bg-night-surface flex items-center space-x-2 transition-colors"
                >
                  <Moon className="w-3.5 h-3.5 text-night-muted" />
                  <span>Allow Dynamic Sleep</span>
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Manual Refresh Button */}
        <button
          onClick={onRefresh}
          title="Refresh Swarm Telemetry"
          className="p-1 sm:p-1.5 rounded-lg bg-night-surface hover:bg-night-surface/80 text-night-muted hover:text-night-blue border border-night-border transition-colors flex-shrink-0"
        >
          <RefreshCw className="w-3.5 h-3.5" />
        </button>
      </div>
    </header>
  );
};

