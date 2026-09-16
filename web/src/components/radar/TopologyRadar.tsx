import React, { useState, useEffect } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  Cpu,
  ExternalLink,
  Laptop,
  Lock,
  Monitor,
  Pause,
  Play,
  Radio,
  RefreshCw,
  RotateCw,
  Sparkles,
  Stethoscope,
  Terminal,
  Unlock,
  X,
  Zap,
} from 'lucide-react';
import type { MeshNode, NodeQuotaMatrix, MeshActionType, MeshActionResult, SwarmModelsState } from '../../types/knot';
import { groupModelsByDepth } from '../../utils/models';

export interface TopologyRadarProps {
  nodes: MeshNode[];
  quotas: NodeQuotaMatrix[];
  onTriggerAction?: (action: MeshActionType, target?: string) => Promise<MeshActionResult>;
  models?: SwarmModelsState | null;
  onSelectNodeModel?: (nodeId: string, model: string) => void;
  isDedicatedView?: boolean;
}

const formatTokenExpiry = (expiryIso?: string): string => {
  if (!expiryIso) return '-';
  try {
    const clean = expiryIso.replace(/(\.\d{6})\d+/, '$1').replace('Z', '+00:00');
    const exp = new Date(clean).getTime();
    const now = Date.now();
    const diffSec = Math.floor((exp - now) / 1000);
    if (diffSec <= 0) return 'Expired';
    const mins = Math.floor(diffSec / 60);
    if (mins < 60) return `in ${mins}m`;
    const hrs = Math.floor(mins / 60);
    const remMins = mins % 60;
    return `in ${hrs}h ${remMins}m`;
  } catch {
    return expiryIso.slice(11, 19) || '-';
  }
};

const getModelBadge = (modelId: string) => {
  if (modelId.includes('pro')) {
    return { label: 'PRO', bg: 'bg-purple-500/15 text-purple-300 border-purple-500/30' };
  } else if (modelId.includes('claude')) {
    return { label: 'CLAUDE', bg: 'bg-amber-500/15 text-amber-300 border-amber-500/30' };
  } else if (modelId.includes('oss')) {
    return { label: 'OSS', bg: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30' };
  }
  return { label: 'FLASH', bg: 'bg-night-cyan/15 text-night-cyan border-night-cyan/30' };
};

export const TopologyRadar: React.FC<TopologyRadarProps> = ({
  nodes,
  quotas,
  onTriggerAction,
  models,
  onSelectNodeModel,
  isDedicatedView = false,
}) => {
  const [runningAction, setRunningAction] = useState<string | null>(null);
  const [actionResult, setActionResult] = useState<MeshActionResult | null>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [screenKey, setScreenKey] = useState<number>(() => Date.now());
  const [expandedScreenNode, setExpandedScreenNode] = useState<string | null>(() => {
    if (typeof window === 'undefined') return null;
    const params = new URLSearchParams(window.location.search);
    const screenParam = params.get('screen') || params.get('inspect');
    if (screenParam && ['desktop', 'laptop', 'steamdeck'].includes(screenParam.toLowerCase())) {
      return screenParam.toLowerCase();
    }
    return null;
  });
  const [refreshingScreen, setRefreshingScreen] = useState<string | null>(null);
  const [streamIntervalMs, setStreamIntervalMs] = useState<number>(1500);
  const [isStreamPaused, setIsStreamPaused] = useState<boolean>(false);
  const [activeModalSrc, setActiveModalSrc] = useState<string | null>(null);
  const [lastFrameTime, setLastFrameTime] = useState<string>('');
  const [isFrameLoading, setIsFrameLoading] = useState<boolean>(false);

  // Periodically refresh workstation display captures for thumbnails every 10 seconds
  useEffect(() => {
    const timer = setInterval(() => {
      setScreenKey(Date.now());
    }, 10000);
    return () => clearInterval(timer);
  }, []);

  // Initialize and stream high-quality screenshots when expanded modal is open
  useEffect(() => {
    if (!expandedScreenNode) {
      setActiveModalSrc(null);
      return;
    }

    // Immediately load high-quality frame
    const initialUrl = `/nodes/${expandedScreenNode}/screen?quality=high&t=${Date.now()}`;
    setActiveModalSrc(initialUrl);
    setLastFrameTime(new Date().toLocaleTimeString());

    if (isStreamPaused) return;

    // Fast stream interval using double-buffered preload
    const timer = setInterval(() => {
      const nextUrl = `/nodes/${expandedScreenNode}/screen?quality=high&t=${Date.now()}`;
      setIsFrameLoading(true);
      const img = new Image();
      img.src = nextUrl;
      img.onload = () => {
        setActiveModalSrc(nextUrl);
        setLastFrameTime(new Date().toLocaleTimeString());
        setIsFrameLoading(false);
      };
      img.onerror = () => {
        setIsFrameLoading(false);
      };
    }, streamIntervalMs);

    return () => clearInterval(timer);
  }, [expandedScreenNode, isStreamPaused, streamIntervalMs]);

  // Deep link support: auto-open expanded modal if ?screen=<nodeId> is present
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const params = new URLSearchParams(window.location.search);
    const screenParam = params.get('screen') || params.get('inspect');
    if (screenParam && ['desktop', 'laptop', 'steamdeck'].includes(screenParam.toLowerCase())) {
      setExpandedScreenNode(screenParam.toLowerCase());
    }
  }, []);

  const handleOpenScreenModal = (nodeId: string) => {
    setExpandedScreenNode(nodeId);
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      url.searchParams.set('screen', nodeId);
      window.history.replaceState({}, '', url.toString());
    }
  };

  const handleCloseScreenModal = () => {
    setExpandedScreenNode(null);
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      url.searchParams.delete('screen');
      url.searchParams.delete('inspect');
      window.history.replaceState({}, '', url.toString());
    }
  };

  const handleRefreshScreen = async (nodeId: string, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    setRefreshingScreen(nodeId);
    try {
      const qualityParam = expandedScreenNode === nodeId ? '&quality=high' : '';
      const url = `/nodes/${nodeId}/screen?force=1${qualityParam}&t=${Date.now()}`;
      await fetch(url);
      setScreenKey(Date.now());
      if (expandedScreenNode === nodeId) {
        setActiveModalSrc(url);
        setLastFrameTime(new Date().toLocaleTimeString());
      }
    } catch {
      // Ignored
    } finally {
      setTimeout(() => setRefreshingScreen(null), 400);
    }
  };

  const handleAction = async (action: MeshActionType, target = '--all') => {
    if (!onTriggerAction || runningAction) return;
    setRunningAction(`${action}:${target}`);
    try {
      const res = await onTriggerAction(action, target);
      setActionResult(res);
      setIsModalOpen(true);
    } catch (err) {
      setActionResult({
        action,
        target,
        ok: false,
        exit_code: 1,
        output: String(err),
      });
      setIsModalOpen(true);
    } finally {
      setRunningAction(null);
    }
  };

  const getNodeIcon = (nodeId: string) => {
    switch (nodeId.toLowerCase()) {
      case 'desktop':
        return <Monitor className="w-4 h-4 text-night-blue shrink-0" />;
      case 'laptop':
        return <Laptop className="w-4 h-4 text-night-cyan shrink-0" />;
      case 'steamdeck':
        return <Terminal className="w-4 h-4 text-night-orange shrink-0" />;
      default:
        return <Cpu className="w-4 h-4 text-night-muted shrink-0" />;
    }
  };

  const getQuotaForNode = (nodeId: string) => {
    return quotas.find((q) => q.node_id === nodeId);
  };

  return (
    <div className="flex flex-col h-full min-h-0 glass rounded-xl border border-night-border overflow-hidden relative">
      {/* Header */}
      <div className="flex-none px-3.5 py-2 border-b border-night-border flex items-center justify-between bg-night-panel/60">
        <div className="flex items-center space-x-2">
          <Radio className="w-3.5 h-3.5 text-night-cyan animate-pulse" />
          <h2 className="text-xs font-bold tracking-wider text-night-blue uppercase">
            Topology Radar & Quota
          </h2>
        </div>
        <div className="flex items-center gap-2 text-[10px] font-mono text-night-muted">
          <span className="inline-flex items-center gap-1 text-night-green">
            <span className="w-1.5 h-1.5 rounded-full bg-night-green animate-ping" />
            {nodes.filter((n) => n.status === 'ONLINE').length}/{nodes.length} ONLINE
          </span>
          <span>•</span>
          <span className="hidden sm:inline">3-TIER MESH</span>
        </div>
      </div>

      {/* Quick Action Deck */}
      {onTriggerAction && (
        <div className="flex-none px-2.5 py-1.5 border-b border-night-border/70 bg-night-panel/40">
          <div className="flex items-center justify-between mb-1">
            <span className="text-[9px] font-mono font-bold text-night-blue uppercase tracking-wider flex items-center gap-1">
              <Zap className="w-3 h-3 text-night-yellow" />
              Quick Action Deck
            </span>
            {runningAction && (
              <span className="text-[9px] font-mono text-night-cyan animate-pulse">
                Executing...
              </span>
            )}
          </div>

          <div className={`grid gap-1.5 ${isDedicatedView ? 'grid-cols-2 lg:grid-cols-4' : 'grid-cols-4 gap-1'}`}>
            <button
              onClick={() => handleAction('restart_kvm')}
              disabled={Boolean(runningAction)}
              className="flex items-center justify-center gap-1 px-1.5 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-[9px] font-mono hover:border-night-cyan/50 transition-all disabled:opacity-50"
              title="Restart Deskflow KVM server and clients across the entire mesh"
            >
              <RotateCw
                className={`w-3 h-3 text-night-cyan shrink-0 ${
                  runningAction === 'restart_kvm:--all' ? 'animate-spin' : ''
                }`}
              />
              <span className="truncate">{isDedicatedView ? 'Restart KVM' : 'KVM'}</span>
            </button>

            <button
              onClick={() => handleAction('doctor')}
              disabled={Boolean(runningAction)}
              className="flex items-center justify-center gap-1 px-1.5 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-[9px] font-mono hover:border-night-green/50 transition-all disabled:opacity-50"
              title="Run comprehensive Knot mesh, portal, and KVM diagnosis"
            >
              <Stethoscope
                className={`w-3 h-3 text-night-green shrink-0 ${
                  runningAction === 'doctor:--all' ? 'animate-pulse' : ''
                }`}
              />
              <span className="truncate">{isDedicatedView ? 'Mesh Doctor' : 'Doctor'}</span>
            </button>

            <button
              onClick={() => handleAction('screen_lock')}
              disabled={Boolean(runningAction)}
              className="flex items-center justify-center gap-1 px-1.5 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-[9px] font-mono hover:border-night-yellow/50 transition-all disabled:opacity-50"
              title="Lock screens across the entire mesh"
            >
              <Lock className="w-3 h-3 text-night-yellow shrink-0" />
              <span className="truncate">{isDedicatedView ? 'Lock Mesh' : 'Lock'}</span>
            </button>

            <button
              onClick={() => handleAction('screen_unlock')}
              disabled={Boolean(runningAction)}
              className="flex items-center justify-center gap-1 px-1.5 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-[9px] font-mono hover:border-night-cyan/50 transition-all disabled:opacity-50"
              title="Unlock screens across the entire mesh"
            >
              <Unlock className="w-3 h-3 text-night-cyan shrink-0" />
              <span className="truncate">{isDedicatedView ? 'Unlock Mesh' : 'Unlock'}</span>
            </button>
          </div>
        </div>
      )}

      {/* Main Content Area */}
      <div
        className={`flex-1 min-h-0 overflow-y-auto p-2.5 overscroll-contain scrollbar-subtle ${
          isDedicatedView
            ? 'grid grid-cols-1 lg:grid-cols-3 gap-3.5 space-y-0'
            : 'space-y-2.5'
        }`}
      >

        {/* Nodes Telemetry Cards */}
        {nodes.map((node) => {
          const nodeQuota = getQuotaForNode(node.node_id);
          const geminiQuota = nodeQuota?.groups['gemini'] || nodeQuota?.groups['default'];
          const nodeAccount = node.account || nodeQuota?.account;
          const assignedModel =
            node.selected_model ||
            models?.node_models[node.node_id] ||
            models?.default_model ||
            'gemini-3.8-flash-high';
          const badge = getModelBadge(assignedModel);

          // Dedicated Radar Page: Full Rich Telemetry Card
          if (isDedicatedView) {
            return (
              <div
                key={node.node_id}
                className="glass-card rounded-lg p-2.5 border border-night-border/70 hover:border-night-blue/40 transition-colors"
              >
                {/* Header: Icon + ID + Status + Real IP + Ping */}
                <div className="flex items-center justify-between gap-1.5 pb-1.5 mb-1.5 border-b border-night-border/50">
                  <div className="flex items-center gap-1.5 min-w-0">
                    {getNodeIcon(node.node_id)}
                    <span className="font-mono text-xs font-bold text-night-text uppercase truncate">
                      {node.node_id}
                    </span>
                    <span
                      className={`text-[8px] px-1 py-0.2 rounded font-mono font-bold ${
                        node.status === 'ONLINE'
                          ? 'bg-night-green/20 text-night-green border border-night-green/30'
                          : 'bg-night-red/20 text-night-red border border-night-red/30'
                      }`}
                    >
                      {node.status}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 text-[9px] font-mono text-night-muted shrink-0">
                    <span className="text-night-text font-medium">{node.ip}</span>
                    <span className="text-night-muted/80">{node.ping_ms}ms</span>
                  </div>
                </div>

                {/* Full Model Selector with Native Antigravity Depth Grouping */}
                <div className="mb-1.5 p-1 rounded bg-night-surface/60 border border-night-border/60 flex items-center gap-1.5 text-[10px]">
                  <Sparkles className="w-3 h-3 text-night-cyan shrink-0" />
                  <div className="flex-1 min-w-0">
                    {models && onSelectNodeModel ? (
                      <select
                        value={assignedModel}
                        onChange={(e) => onSelectNodeModel(node.node_id, e.target.value)}
                        className="w-full bg-transparent text-night-text text-[10px] font-mono font-medium focus:outline-none cursor-pointer truncate"
                        title={`Change model for @${node.node_id}`}
                      >
                        {groupModelsByDepth(models.available_models).map((group) => (
                          <optgroup
                            key={group.groupName}
                            label={group.groupName}
                            className="bg-night-panel text-night-cyan font-bold text-[10px]"
                          >
                            {group.models.map((m) => (
                              <option
                                key={m.id}
                                value={m.id}
                                className="bg-night-surface text-night-text font-normal font-mono"
                              >
                                {m.shortLabel}
                              </option>
                            ))}
                          </optgroup>
                        ))}
                      </select>
                    ) : (
                      <span className="text-[10px] font-mono text-night-text truncate block">{assignedModel}</span>
                    )}
                  </div>
                  <span className={`text-[8px] font-mono font-bold px-1 py-0.2 rounded border shrink-0 ${badge.bg}`}>
                    {badge.label}
                  </span>
                </div>

                {/* Full Account & Subscription Row */}
                {nodeAccount?.email && (
                  <div className="mb-1.5 p-1.5 rounded bg-night-surface/50 border border-night-border/50 flex items-center gap-2 text-[10px]">
                    <div className="relative w-6 h-6 rounded-full overflow-hidden shrink-0 border border-night-cyan/60">
                      {nodeAccount.picture ? (
                        <img
                          src={nodeAccount.picture}
                          alt=""
                          className="w-full h-full object-cover"
                          referrerPolicy="no-referrer"
                        />
                      ) : (
                        <div className="w-full h-full bg-night-surface flex items-center justify-center text-night-cyan font-mono text-[9px] font-bold">
                          {(nodeAccount.name || node.node_id)[0].toUpperCase()}
                        </div>
                      )}
                    </div>
                    <div className="min-w-0 flex-1 flex items-center justify-between gap-1">
                      <div className="truncate">
                        <span className="font-semibold text-night-text text-[10px] block truncate leading-tight">
                          {nodeAccount.name || nodeAccount.email.split('@')[0]}
                        </span>
                        <span className="text-[8px] text-night-muted font-mono truncate block">
                          {nodeAccount.email}
                        </span>
                      </div>
                      <div className="text-right shrink-0">
                        <span className="text-[8px] font-mono font-bold px-1 py-0.2 rounded bg-purple-500/15 text-purple-300 border border-purple-500/30 block mb-0.5">
                          {nodeAccount.subscription || 'Google AI Pro'}
                        </span>
                        {nodeAccount.token_expiry && (
                          <span className="text-[8px] font-mono text-night-cyan block">
                            ref {formatTokenExpiry(nodeAccount.token_expiry)}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                )}

                {/* Full Live Power & KVM Row */}
                <div className="flex items-center gap-1 mb-1.5 text-[8px] font-mono flex-wrap">
                  {node.power && (
                    <>
                      <span
                        className={`px-1 py-0.2 rounded border font-medium ${
                          node.power.on_ac
                            ? 'bg-night-green/10 text-night-green border-night-green/30'
                            : 'bg-night-orange/10 text-night-orange border-night-orange/30'
                        }`}
                      >
                        {node.power.on_ac ? '⚡ MAINS' : '🔋 BATT'}
                      </span>

                      {node.power.sleep_inhibited && (
                        <span className="px-1 py-0.2 rounded bg-night-yellow/10 text-night-yellow border border-night-yellow/30 font-semibold">
                          🛡️ SLEEP LOCK
                        </span>
                      )}

                      {node.power.is_executing_task && (
                        <span className="px-1 py-0.2 rounded bg-night-cyan/10 text-night-cyan border border-night-cyan/30 animate-pulse">
                          RUNNING
                        </span>
                      )}
                    </>
                  )}
                  <span className="ml-auto text-night-muted text-[9px]">
                    KVM: <strong className="text-night-text font-normal">{node.kvm_status || 'IDLE'}</strong>
                  </span>
                </div>

                {/* Quota Progress Meters */}
                {geminiQuota ? (
                  <div className="space-y-1 pt-1.5 border-t border-night-border/40 text-[9px] font-mono">
                    <div className="flex items-center justify-between text-night-muted">
                      <span>
                        5h Limit: <strong className="text-night-text font-semibold">{geminiQuota.five_hour.pct}%</strong>
                      </span>
                      <span className="text-[8px] text-night-muted/80">{geminiQuota.five_hour.next_reset_in}</span>
                    </div>
                    <div className="w-full h-1 bg-night-surface rounded-full overflow-hidden">
                      <div
                        className={`h-full transition-all duration-500 ${
                          geminiQuota.five_hour.pct > 50
                            ? 'bg-night-green'
                            : geminiQuota.five_hour.pct > 20
                            ? 'bg-night-yellow'
                            : 'bg-night-red'
                        }`}
                        style={{ width: `${Math.max(4, geminiQuota.five_hour.pct)}%` }}
                      />
                    </div>
                    <div className="flex items-center justify-between text-night-muted mt-1">
                      <span>
                        Weekly: <strong className="text-night-text font-semibold">{geminiQuota.weekly.pct}%</strong>
                      </span>
                      <span className="text-[8px] text-night-muted/80">{geminiQuota.weekly.next_reset_in}</span>
                    </div>
                    <div className="w-full h-1 bg-night-surface rounded-full overflow-hidden">
                      <div
                        className={`h-full transition-all duration-500 ${
                          geminiQuota.weekly.pct > 50
                            ? 'bg-night-green'
                            : geminiQuota.weekly.pct > 20
                            ? 'bg-night-yellow'
                            : 'bg-night-red'
                        }`}
                        style={{ width: `${Math.max(4, geminiQuota.weekly.pct)}%` }}
                      />
                    </div>
                  </div>
                ) : (
                  <div className="text-[8px] font-mono text-night-muted italic pt-1 border-t border-night-border/30">
                    Awaiting quota sync...
                  </div>
                )}

                {/* Workstation Display Thumbnail */}
                <div className="mt-2 pt-1.5 border-t border-night-border/40">
                  <div className="flex items-center justify-between mb-1 text-[9px] font-mono">
                    <div className="flex items-center gap-1 text-night-muted">
                      <Monitor className="w-3 h-3 text-night-cyan" />
                      <span className="uppercase tracking-wider">Display</span>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={(e) => handleRefreshScreen(node.node_id, e)}
                        className="text-night-muted hover:text-night-cyan transition-colors"
                        title="Force refresh workstation screen capture"
                      >
                        <RefreshCw
                          className={`w-2.5 h-2.5 ${
                            refreshingScreen === node.node_id ? 'animate-spin text-night-cyan' : ''
                          }`}
                        />
                      </button>
                      <button
                        onClick={() => handleOpenScreenModal(node.node_id)}
                        className="text-[8px] text-night-cyan hover:underline font-mono"
                      >
                        Expand
                      </button>
                    </div>
                  </div>
                  <div
                    onClick={() => handleOpenScreenModal(node.node_id)}
                    className="relative aspect-video rounded-lg overflow-hidden bg-black/90 border border-night-border/80 hover:border-night-cyan shadow-[0_0_15px_rgba(0,0,0,0.5)] hover:shadow-[0_0_15px_rgba(6,182,212,0.2)] transition-all cursor-pointer group/screen"
                  >
                    <img
                      src={`/nodes/${node.node_id}/screen?t=${screenKey}`}
                      alt={`Workstation display @${node.node_id}`}
                      className="w-full h-full object-cover group-hover/screen:scale-105 transition-transform duration-300"
                      loading="eager"
                    />
                    {/* Live badge overlay */}
                    <div className="absolute top-1.5 left-1.5 flex items-center gap-1 px-1.5 py-0.5 rounded bg-black/70 backdrop-blur-sm border border-white/10 text-[8px] font-mono">
                      <span className="w-1.5 h-1.5 rounded-full bg-night-green animate-pulse" />
                      <span className="text-white font-medium">LIVE</span>
                    </div>

                    {/* Bottom overlay with inspect prompt */}
                    <div className="absolute inset-0 bg-gradient-to-t from-night-bg/90 via-transparent to-transparent opacity-0 group-hover/screen:opacity-100 transition-opacity flex items-end justify-between p-2">
                      <span className="text-[9px] font-mono text-night-cyan font-bold">
                        Inspect Screen
                      </span>
                      <span className="text-[8px] font-mono text-night-muted">Click to enlarge</span>
                    </div>
                  </div>
                </div>

                {/* Capabilities */}
                <div className="relative group/caps mt-2 pt-1.5 border-t border-night-border/30 flex items-center justify-between text-[9px] font-mono">
                  <div className="flex items-center gap-1 min-w-0">
                    <span className="text-night-muted text-[8px] uppercase tracking-wider">Role:</span>
                    <span className="px-1.5 py-0.2 rounded bg-night-cyan/10 text-night-cyan border border-night-cyan/30 text-[8px] font-semibold truncate max-w-[130px]">
                      {node.capabilities[0] === 'any' && node.capabilities[1] ? node.capabilities[1] : node.capabilities[0]}
                    </span>
                    {node.capabilities.length > 1 && (
                      <span className="px-1 py-0.2 rounded bg-night-surface text-night-muted border border-night-border text-[8px] cursor-help">
                        +{node.capabilities.length - 1}
                      </span>
                    )}
                  </div>

                  {/* Hover HUD Tooltip showing full capabilities */}
                  <div className="absolute left-0 bottom-full mb-1 hidden group-hover/caps:flex flex-wrap gap-1 p-2 bg-night-panel/95 backdrop-blur-md border border-night-border/90 rounded-lg shadow-2xl z-30 max-w-[280px]">
                    <div className="w-full text-[8px] uppercase tracking-wider text-night-muted pb-1 mb-1 border-b border-night-border/50 flex justify-between">
                      <span>Capabilities (@{node.node_id})</span>
                      <span>{node.capabilities.length} tags</span>
                    </div>
                    {node.capabilities.map((cap) => (
                      <span
                        key={cap}
                        className="text-[8px] font-mono px-1 py-0.2 rounded bg-night-surface text-night-cyan border border-night-border/70"
                      >
                        {cap}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            );
          }

          // Dashboard View: Small, Space-Efficient Compact Node Card (4 rows)
          return (
            <div
              key={node.node_id}
              className="glass-card rounded-lg border border-night-border/70 hover:border-night-blue/40 transition-colors p-2"
            >
              {/* Row 1: Header: Icon + ID + Status + Real IP + Power badge + Ping */}
              <div className="flex items-center justify-between gap-1 pb-1 mb-1 border-b border-night-border/40">
                <div className="flex items-center gap-1.5 min-w-0">
                  {getNodeIcon(node.node_id)}
                  <span className="font-mono text-xs font-bold text-night-text uppercase truncate">
                    {node.node_id}
                  </span>
                  <span
                    className={`text-[8px] px-1 py-0.2 rounded font-mono font-bold ${
                      node.status === 'ONLINE'
                        ? 'bg-night-green/20 text-night-green border border-night-green/30'
                        : 'bg-night-red/20 text-night-red border border-night-red/30'
                    }`}
                  >
                    {node.status}
                  </span>
                  <span className="text-[9px] font-mono text-night-muted truncate hidden sm:inline">
                    {node.ip}
                  </span>
                </div>
                <div className="flex items-center gap-1.5 text-[9px] font-mono shrink-0">
                  {node.power && (
                    <span
                      className={`px-1 py-0.2 rounded border text-[8px] font-medium ${
                        node.power.on_ac
                          ? 'bg-night-green/10 text-night-green border-night-green/30'
                          : 'bg-night-orange/10 text-night-orange border-night-orange/30'
                      }`}
                      title={node.power.on_ac ? 'Mains AC Power' : 'Battery Power'}
                    >
                      {node.power.on_ac ? '⚡' : '🔋'}
                    </span>
                  )}
                  <span className="text-night-muted/80">{node.ping_ms}ms</span>
                </div>
              </div>

              {/* Row 2: Compact Model Selector & Account */}
              <div className="flex items-center gap-1.5 mb-1.5">
                {/* Model selector dropdown */}
                <div className="flex-1 min-w-0 p-0.5 px-1.5 rounded bg-night-surface/60 border border-night-border/60 flex items-center gap-1 text-[9px]">
                  <Sparkles className="w-2.5 h-2.5 text-night-cyan shrink-0" />
                  <div className="flex-1 min-w-0">
                    {models && onSelectNodeModel ? (
                      <select
                        value={assignedModel}
                        onChange={(e) => onSelectNodeModel(node.node_id, e.target.value)}
                        className="w-full bg-transparent text-night-text text-[9px] font-mono font-medium focus:outline-none cursor-pointer truncate"
                        title={`Change model for @${node.node_id}`}
                      >
                        {groupModelsByDepth(models.available_models).map((group) => (
                          <optgroup
                            key={group.groupName}
                            label={group.groupName}
                            className="bg-night-panel text-night-cyan font-bold text-[9px]"
                          >
                            {group.models.map((m) => (
                              <option
                                key={m.id}
                                value={m.id}
                                className="bg-night-surface text-night-text font-normal font-mono"
                              >
                                {m.shortLabel}
                              </option>
                            ))}
                          </optgroup>
                        ))}
                      </select>
                    ) : (
                      <span className="text-[9px] font-mono text-night-text truncate block">{assignedModel}</span>
                    )}
                  </div>
                  <span className={`text-[7px] font-mono font-bold px-1 py-0.1 rounded border shrink-0 ${badge.bg}`}>
                    {badge.label}
                  </span>
                </div>

                {/* Compact Account Chip */}
                {nodeAccount?.email && (
                  <div
                    className="relative group/acc shrink-0 flex items-center gap-1 p-0.5 px-1.5 rounded bg-night-surface/50 border border-night-border/50 text-[9px] font-mono cursor-help"
                    title={nodeAccount.email}
                  >
                    <div className="w-4 h-4 rounded-full overflow-hidden shrink-0 border border-night-cyan/60">
                      {nodeAccount.picture ? (
                        <img
                          src={nodeAccount.picture}
                          alt=""
                          className="w-full h-full object-cover"
                          referrerPolicy="no-referrer"
                        />
                      ) : (
                        <div className="w-full h-full bg-night-surface flex items-center justify-center text-night-cyan text-[7px] font-bold">
                          {(nodeAccount.name || node.node_id)[0].toUpperCase()}
                        </div>
                      )}
                    </div>
                    <span className="text-[8px] text-night-text font-medium truncate max-w-[50px]">
                      {nodeAccount.name?.split(' ')[0] || nodeAccount.email.split('@')[0]}
                    </span>
                    <span className="text-[7px] px-1 py-0.1 rounded bg-purple-500/15 text-purple-300 border border-purple-500/30 font-bold">
                      {nodeAccount.subscription?.includes('Pro') ? 'Pro' : 'AI'}
                    </span>

                    {/* Account Hover Tooltip */}
                    <div className="absolute right-0 bottom-full mb-1 hidden group-hover/acc:block p-2 bg-night-panel/95 backdrop-blur-md border border-night-border rounded-lg shadow-xl z-30 min-w-[180px] text-[8px]">
                      <div className="font-bold text-night-text">{nodeAccount.name || 'Swarm Account'}</div>
                      <div className="text-night-muted">{nodeAccount.email}</div>
                      <div className="text-night-cyan mt-1">Tier: {nodeAccount.subscription || 'Google AI Pro'}</div>
                      {nodeAccount.token_expiry && (
                        <div className="text-night-muted mt-0.5">Expires in: {formatTokenExpiry(nodeAccount.token_expiry)}</div>
                      )}
                    </div>
                  </div>
                )}
              </div>

              {/* Row 3: Dual Inline Quotas */}
              {geminiQuota ? (
                <div className="grid grid-cols-2 gap-2 pt-1 border-t border-night-border/30 text-[8px] font-mono">
                  {/* 5h Gauge */}
                  <div>
                    <div className="flex items-center justify-between text-night-muted mb-0.5">
                      <span>5h: <b className="text-night-text">{geminiQuota.five_hour.pct}%</b></span>
                      <span className="text-night-muted/70">{geminiQuota.five_hour.next_reset_in}</span>
                    </div>
                    <div className="w-full h-1 bg-night-surface rounded-full overflow-hidden">
                      <div
                        className={`h-full transition-all duration-500 ${
                          geminiQuota.five_hour.pct > 50
                            ? 'bg-night-green'
                            : geminiQuota.five_hour.pct > 20
                            ? 'bg-night-yellow'
                            : 'bg-night-red'
                        }`}
                        style={{ width: `${Math.max(4, geminiQuota.five_hour.pct)}%` }}
                      />
                    </div>
                  </div>

                  {/* Weekly Gauge */}
                  <div>
                    <div className="flex items-center justify-between text-night-muted mb-0.5">
                      <span>Wk: <b className="text-night-text">{geminiQuota.weekly.pct}%</b></span>
                      <span className="text-night-muted/70">{geminiQuota.weekly.next_reset_in}</span>
                    </div>
                    <div className="w-full h-1 bg-night-surface rounded-full overflow-hidden">
                      <div
                        className={`h-full transition-all duration-500 ${
                          geminiQuota.weekly.pct > 50
                            ? 'bg-night-green'
                            : geminiQuota.weekly.pct > 20
                            ? 'bg-night-yellow'
                            : 'bg-night-red'
                        }`}
                        style={{ width: `${Math.max(4, geminiQuota.weekly.pct)}%` }}
                      />
                    </div>
                  </div>
                </div>
              ) : (
                <div className="text-[8px] font-mono text-night-muted italic pt-1 border-t border-night-border/30">
                  Awaiting quota sync...
                </div>
              )}

              {/* Row 4: Compact Capabilities with Hover HUD Tooltip & KVM Status */}
              <div className="relative group/caps mt-1.5 pt-1 border-t border-night-border/30 flex items-center justify-between text-[8px] font-mono">
                <div className="flex items-center gap-1 min-w-0">
                  <span className="text-night-muted text-[7px] uppercase tracking-wider">Role:</span>
                  <span className="px-1.5 py-0.2 rounded bg-night-cyan/10 text-night-cyan border border-night-cyan/30 text-[8px] font-semibold truncate max-w-[120px]">
                    {node.capabilities[0] === 'any' && node.capabilities[1] ? node.capabilities[1] : node.capabilities[0]}
                  </span>
                  {node.capabilities.length > 1 && (
                    <span className="px-1 py-0.2 rounded bg-night-surface text-night-muted border border-night-border text-[7px] cursor-help">
                      +{node.capabilities.length - 1}
                    </span>
                  )}
                </div>

                <span className="text-night-muted text-[8px] shrink-0">
                  KVM: <strong className="text-night-text font-normal">{node.kvm_status || 'IDLE'}</strong>
                </span>

                {/* Hover HUD Tooltip showing full capabilities */}
                <div className="absolute left-0 bottom-full mb-1 hidden group-hover/caps:flex flex-wrap gap-1 p-2 bg-night-panel/95 backdrop-blur-md border border-night-border/90 rounded-lg shadow-2xl z-30 max-w-[280px]">
                  <div className="w-full text-[8px] uppercase tracking-wider text-night-muted pb-1 mb-1 border-b border-night-border/50 flex justify-between">
                    <span>Capabilities (@{node.node_id})</span>
                    <span>{node.capabilities.length} tags</span>
                  </div>
                  {node.capabilities.map((cap) => (
                    <span
                      key={cap}
                      className="text-[8px] font-mono px-1 py-0.2 rounded bg-night-surface text-night-cyan border border-night-border/70"
                    >
                      {cap}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Expanded Workstation Screen Modal with High-Res Fast Streaming */}
      {expandedScreenNode && (
        <div className="fixed inset-0 bg-night-bg/85 backdrop-blur-md z-50 flex items-center justify-center p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-5xl bg-night-panel border border-night-border rounded-xl shadow-2xl flex flex-col overflow-hidden font-mono text-xs">
            {/* Modal Header */}
            <div className="px-4 py-2.5 border-b border-night-border flex items-center justify-between bg-night-surface/60 flex-wrap gap-2">
              <div className="flex items-center space-x-2 min-w-0">
                <Monitor className="w-4 h-4 text-night-cyan flex-shrink-0" />
                <span className="font-bold text-night-text uppercase truncate">
                  Workstation Live Display: @{expandedScreenNode}
                </span>
                <span className="text-[9px] px-1.5 py-0.2 rounded bg-night-green/20 text-night-green font-bold flex items-center gap-1">
                  <span
                    className={`w-1.5 h-1.5 rounded-full ${
                      isStreamPaused ? 'bg-night-yellow' : 'bg-night-green animate-pulse'
                    }`}
                  />
                  {isStreamPaused ? 'PAUSED' : `HD STREAM (${(streamIntervalMs / 1000).toFixed(1)}s)`}
                </span>
                <span className="text-[9px] px-1.5 py-0.2 rounded bg-night-surface text-night-cyan border border-night-border font-mono hidden sm:inline">
                  1280px Crisp
                </span>
              </div>

              {/* Stream Controls */}
              <div className="flex items-center space-x-2">
                {/* Interval selector */}
                <div className="hidden sm:flex items-center rounded bg-night-surface border border-night-border p-0.5 text-[9px]">
                  {[1000, 1500, 3000].map((ms) => (
                    <button
                      key={ms}
                      onClick={() => {
                        setStreamIntervalMs(ms);
                        setIsStreamPaused(false);
                      }}
                      className={`px-1.5 py-0.5 rounded transition-colors ${
                        streamIntervalMs === ms && !isStreamPaused
                          ? 'bg-night-cyan text-night-bg font-bold'
                          : 'text-night-muted hover:text-night-text'
                      }`}
                      title={`Stream at ${(ms / 1000).toFixed(1)}s interval`}
                    >
                      {(ms / 1000).toFixed(1)}s
                    </button>
                  ))}
                </div>

                {/* Pause / Resume button */}
                <button
                  onClick={() => setIsStreamPaused(!isStreamPaused)}
                  className={`px-2 py-1 rounded border text-xs flex items-center gap-1 transition-colors ${
                    isStreamPaused
                      ? 'bg-night-green/20 text-night-green border-night-green/30 hover:bg-night-green/30'
                      : 'bg-night-yellow/20 text-night-yellow border-night-yellow/30 hover:bg-night-yellow/30'
                  }`}
                  title={isStreamPaused ? 'Resume live frame streaming' : 'Pause live streaming'}
                >
                  {isStreamPaused ? (
                    <>
                      <Play className="w-3 h-3 text-night-green fill-night-green" />
                      <span>Resume</span>
                    </>
                  ) : (
                    <>
                      <Pause className="w-3 h-3 text-night-yellow fill-night-yellow" />
                      <span>Pause</span>
                    </>
                  )}
                </button>

                {/* Force capture button */}
                <button
                  onClick={() => handleRefreshScreen(expandedScreenNode)}
                  className="px-2.5 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-cyan text-xs flex items-center gap-1"
                  title="Capture fresh frame immediately"
                >
                  <RefreshCw
                    className={`w-3.5 h-3.5 ${
                      refreshingScreen === expandedScreenNode ? 'animate-spin' : ''
                    }`}
                  />
                  <span className="hidden sm:inline">Refresh</span>
                </button>

                <a
                  href={`/nodes/${expandedScreenNode}/screen?quality=high&force=1&t=${Date.now()}`}
                  target="_blank"
                  rel="noreferrer"
                  className="p-1 rounded text-night-muted hover:text-night-text hover:bg-night-surface"
                  title="Open raw high-res image in new tab"
                >
                  <ExternalLink className="w-4 h-4" />
                </a>

                <button
                  onClick={handleCloseScreenModal}
                  className="p-1 rounded text-night-muted hover:text-night-text hover:bg-night-surface ml-1"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            </div>

            {/* Modal Screen Body */}
            <div className="relative bg-black flex items-center justify-center p-2 overflow-hidden aspect-video max-h-[75vh]">
              {/* Instant low-res backdrop so screen is immediately visible without blank flash */}
              <img
                src={`/nodes/${expandedScreenNode}/screen`}
                alt=""
                className="absolute inset-0 w-full h-full object-contain filter blur-sm opacity-40 pointer-events-none"
              />
              <img
                src={activeModalSrc || `/nodes/${expandedScreenNode}/screen?quality=high`}
                alt={`Expanded workstation display @${expandedScreenNode}`}
                className="relative max-w-full max-h-full object-contain rounded border border-night-border/40 shadow-2xl z-10"
              />

              {/* Streaming loading indicator overlay */}
              {isFrameLoading && (
                <div className="absolute top-3 right-3 z-20 flex items-center gap-1 px-1.5 py-0.5 rounded bg-black/70 backdrop-blur-sm border border-white/10 text-[8px] font-mono text-night-cyan">
                  <RefreshCw className="w-2.5 h-2.5 animate-spin" />
                  <span>Streaming frame...</span>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="px-4 py-2 border-t border-night-border flex items-center justify-between bg-night-surface/40 text-[10px] text-night-muted font-mono">
              <div className="flex items-center gap-2">
                <span>Fast Wayland telemetry stream</span>
                {lastFrameTime && (
                  <>
                    <span>•</span>
                    <span className="text-night-text">Last frame: {lastFrameTime}</span>
                  </>
                )}
              </div>
              <button
                onClick={handleCloseScreenModal}
                className="px-3 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-xs"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Action Result Modal Dialog */}
      {isModalOpen && actionResult && (
        <div className="absolute inset-0 bg-night-bg/85 backdrop-blur-sm z-50 flex items-center justify-center p-3 animate-in fade-in duration-150">
          <div className="w-full max-h-[85%] bg-night-panel border border-night-border rounded-xl shadow-2xl flex flex-col overflow-hidden font-mono text-xs">
            {/* Modal Header */}
            <div className="px-3.5 py-2.5 border-b border-night-border flex items-center justify-between bg-night-surface/60">
              <div className="flex items-center space-x-2 min-w-0">
                {actionResult.ok ? (
                  <CheckCircle2 className="w-4 h-4 text-night-green flex-shrink-0" />
                ) : (
                  <AlertTriangle className="w-4 h-4 text-night-red flex-shrink-0" />
                )}
                <span className="font-bold text-night-text uppercase truncate">
                  Action: {actionResult.action}
                </span>
                <span
                  className={`text-[9px] px-1.5 py-0.2 rounded font-bold flex-shrink-0 ${
                    actionResult.ok
                      ? 'bg-night-green/20 text-night-green'
                      : 'bg-night-red/20 text-night-red'
                  }`}
                >
                  {actionResult.ok ? 'SUCCESS' : `EXIT ${actionResult.exit_code}`}
                </span>
              </div>
              <button
                onClick={() => setIsModalOpen(false)}
                className="p-1 rounded text-night-muted hover:text-night-text hover:bg-night-surface ml-2"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Modal Terminal Output Body */}
            <div className="flex-1 overflow-y-auto p-3 bg-night-bg/95 font-mono text-[11px] leading-relaxed text-night-text select-text">
              <pre className="whitespace-pre-wrap break-all font-mono">
                {actionResult.output || '(No output returned)'}
              </pre>
            </div>

            {/* Modal Footer */}
            <div className="px-3 py-2 border-t border-night-border flex justify-end bg-night-surface/40">
              <button
                onClick={() => setIsModalOpen(false)}
                className="px-3 py-1 rounded bg-night-surface hover:bg-night-surface/80 border border-night-border text-night-text text-xs"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
