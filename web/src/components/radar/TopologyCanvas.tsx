import React, { useState, useEffect } from 'react';
import {
  Monitor,
  Laptop,
  Gamepad2,
  Lock,
  Unlock,
  Camera,
  RefreshCw,
  Sparkles,
  ArrowRight,
  ArrowLeft,
  ArrowDown,
  ArrowUp,
  Maximize2,
  Sliders,
  Layers,
} from 'lucide-react';
import type { MeshTopologyState, MeshNode, MeshTopologyLink } from '../../types/knot';
import { PhotoTopologyModal } from './PhotoTopologyModal';
import { DisplayCalibrationOverlay } from './DisplayCalibrationOverlay';

export interface TopologyCanvasProps {
  nodes: MeshNode[];
  onOpenScreenModal?: (nodeId: string) => void;
}

export const TopologyCanvas: React.FC<TopologyCanvasProps> = ({
  nodes,
  onOpenScreenModal,
}) => {
  const [topology, setTopology] = useState<MeshTopologyState | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isPhotoModalOpen, setIsPhotoModalOpen] = useState<boolean>(false);
  const [isCalibrationOverlayOpen, setIsCalibrationOverlayOpen] = useState<boolean>(false);
  const [isFlashing, setIsFlashing] = useState<boolean>(false);
  const [isAligning, setIsAligning] = useState<boolean>(false);
  const [screenKey, setScreenKey] = useState<number>(() => Date.now());
  const [statusMsg, setStatusMsg] = useState<string | null>(null);

  const fetchTopology = async () => {
    setIsLoading(true);
    try {
      const res = await fetch('/topology');
      if (res.ok) {
        const data = (await res.json()) as MeshTopologyState;
        setTopology(data);
      }
    } catch (err) {
      console.error('Failed to fetch topology:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    void fetchTopology();
  }, []);

  const handleApplyTopology = async (
    layout: Record<string, Record<string, MeshTopologyLink>>,
    screens: string[],
    anchor: string
  ): Promise<boolean> => {
    try {
      const res = await fetch('/topology', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          anchor,
          screens,
          layout,
          locked: topology?.locked || false,
        }),
      });
      if (res.ok) {
        await fetchTopology();
        setStatusMsg('Topology applied and Deskflow recompiled successfully!');
        setTimeout(() => setStatusMsg(null), 3500);
        return true;
      }
      return false;
    } catch (err) {
      console.error('Failed to apply topology:', err);
      return false;
    }
  };

  const toggleLock = async () => {
    if (!topology) return;
    const newLocked = !topology.locked;
    try {
      const res = await fetch('/topology', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...topology,
          locked: newLocked,
        }),
      });
      if (res.ok) {
        setTopology({ ...topology, locked: newLocked });
      }
    } catch (err) {
      console.error('Failed to toggle lock:', err);
    }
  };

  const handleFlashIdentify = async () => {
    setIsFlashing(true);
    try {
      const res = await fetch('/topology/identify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bg: 'white', duration: 15 }),
      });
      if (res.ok) {
        setIsCalibrationOverlayOpen(true);
        setStatusMsg('Display identification pattern flashed swarm-wide across all screens!');
        setTimeout(() => setStatusMsg(null), 4000);
      }
    } catch (err) {
      console.error('Failed to trigger display flash:', err);
    } finally {
      setIsFlashing(false);
    }
  };

  const handleAlignInternal = async () => {
    setIsAligning(true);
    try {
      const res = await fetch('/topology/align', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      });
      if (res.ok) {
        await fetchTopology();
        setStatusMsg('Internal multi-display outputs synchronized via kscreen-doctor!');
        setTimeout(() => setStatusMsg(null), 4000);
      }
    } catch (err) {
      console.error('Failed to align internal displays:', err);
    } finally {
      setIsAligning(false);
    }
  };

  const getDeviceIcon = (role?: string, hname?: string) => {
    const s = `${role || ''} ${hname || ''}`.toLowerCase();
    if (s.includes('deck') || s.includes('ally') || s.includes('handheld')) {
      return <Gamepad2 className="w-4 h-4 text-amber-400" />;
    }
    if (s.includes('laptop') || s.includes('devbox')) {
      return <Laptop className="w-4 h-4 text-sky-400" />;
    }
    return <Monitor className="w-4 h-4 text-night-cyan" />;
  };

  const anchorId = topology?.anchor || 'rog-ally';
  const layout = topology?.layout || {};
  const anchorLayout = layout[anchorId] || {};

  // Extract spatial placements relative to anchor
  const leftLink = anchorLayout['left'];
  const rightLink = anchorLayout['right'];
  const downLink = anchorLayout['down'];
  const upLink = anchorLayout['up'];

  const leftNodeId = leftLink?.node;
  const rightNodeId = rightLink?.node;
  const downNodeId = downLink?.node;
  const upNodeId = upLink?.node;

  const getNodeInfo = (nodeId: string) => {
    const topoNode = topology?.nodes?.[nodeId];
    const liveNode = nodes.find((n) => n.node_id === nodeId);
    const outputs = topoNode?.display?.outputs || [];
    const resolution =
      topoNode?.display?.resolution ||
      outputs[0]?.resolution ||
      (nodeId.includes('deck') ? '800×1280' : nodeId.includes('devbox') ? '1920×1080' : '2560×1440');
    return {
      id: nodeId,
      hostname: topoNode?.hostname || liveNode?.node_id || nodeId,
      status: liveNode?.status || topoNode?.status || 'ONLINE',
      resolution,
      role: topoNode?.role || 'strand',
      outputs,
    };
  };

  const renderScreenCard = (nodeId: string, positionLabel: string, isAnchor = false) => {
    const info = getNodeInfo(nodeId);
    const hasMultipleOutputs = info.outputs.length > 1;

    return (
      <div
        className={`relative flex flex-col rounded-xl border transition-all duration-300 shadow-xl overflow-hidden ${
          isAnchor
            ? 'border-purple-500/60 bg-night-card shadow-purple-500/10 min-w-[280px] max-w-[340px] flex-1'
            : 'border-night-border/80 bg-night-dark/60 hover:border-night-cyan/60 min-w-[220px] max-w-[280px] flex-1'
        }`}
      >
        {/* Screen Header Bar */}
        <div className="flex items-center justify-between px-3 py-2 border-b border-night-border/70 bg-night-dark/90">
          <div className="flex items-center gap-2">
            {getDeviceIcon(info.role, info.id)}
            <span className="text-xs font-bold text-night-white font-mono truncate max-w-[130px]">
              {info.id}
            </span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] px-1.5 py-0.5 rounded font-mono bg-night-black/60 text-night-muted border border-night-border/40">
              {info.resolution}
            </span>
            {isAnchor && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full font-semibold bg-purple-500/20 text-purple-300 border border-purple-500/40">
                ANCHOR
              </span>
            )}
          </div>
        </div>

        {/* Multi-Display Output Chips (if node has multiple outputs) */}
        {hasMultipleOutputs && (
          <div className="px-3 py-1 bg-purple-950/40 border-b border-purple-500/20 flex flex-wrap items-center gap-1.5 text-[10px] font-mono">
            <span className="text-purple-300 font-semibold">Outputs:</span>
            {info.outputs.map((out) => (
              <span
                key={out.name}
                className={`px-1.5 py-0.5 rounded border ${
                  out.primary
                    ? 'bg-purple-500/25 text-purple-200 border-purple-500/40'
                    : 'bg-night-black/60 text-night-muted border-night-border/40'
                }`}
              >
                {out.name} {out.scale ? `(${out.scale}x)` : ''}
              </span>
            ))}
          </div>
        )}

        {/* Live Screen Thumbnail Container */}
        <div
          onClick={() => onOpenScreenModal?.(info.id)}
          className="relative aspect-video bg-black/80 flex items-center justify-center cursor-pointer group overflow-hidden"
          title={`Click to inspect live full-screen stream of ${info.id}`}
        >
          <img
            key={`${info.id}-${screenKey}`}
            src={`/nodes/${info.id}/screen?quality=low&t=${screenKey}`}
            alt={`${info.id} display`}
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            onError={(e) => {
              (e.currentTarget as HTMLElement).style.display = 'none';
            }}
          />

          {/* Hover Overlay */}
          <div className="absolute inset-0 bg-night-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2 backdrop-blur-xs">
            <span className="text-xs font-medium text-night-white flex items-center gap-1 bg-night-black/80 px-2.5 py-1 rounded-lg border border-night-border">
              <Maximize2 className="w-3.5 h-3.5 text-night-cyan" />
              Stream HD
            </span>
          </div>

          {/* Boundary Indicator Glow Strip */}
          <div className="absolute inset-x-0 bottom-0 h-1 bg-gradient-to-r from-night-cyan via-purple-500 to-night-cyan opacity-80" />
        </div>

        {/* Screen Footer with Reciprocal Link info */}
        <div className="px-3 py-1.5 bg-night-dark/40 border-t border-night-border/40 flex items-center justify-between text-[11px] text-night-muted">
          <span className="font-mono text-night-cyan capitalize">{positionLabel}</span>
          <span className="flex items-center gap-1">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
            Active KVM Link
          </span>
        </div>

        {/* Docked Secondary Handheld Console Card (for multi-display anchor, e.g. ROG Ally eDP-1) */}
        {isAnchor && hasMultipleOutputs && (
          <div className="p-2.5 bg-purple-950/20 border-t border-purple-500/30 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Gamepad2 className="w-4 h-4 text-amber-400" />
              <div>
                <div className="text-[11px] font-bold text-night-white font-mono">
                  Console Screen (eDP-1)
                </div>
                <div className="text-[10px] text-night-muted font-mono">
                  640×360 @ 3x (Left 50% bottom edge)
                </div>
              </div>
            </div>
            <span className="text-[9px] px-2 py-0.5 rounded font-mono bg-emerald-500/15 text-emerald-300 border border-emerald-500/30">
              KWin Wayland
            </span>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="flex flex-col h-full w-full bg-night-dark/30 rounded-xl border border-night-border/70 overflow-hidden relative">
      {/* Top Toolbar */}
      <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 border-b border-night-border/70 bg-night-card/80 backdrop-blur-sm">
        <div className="flex items-center gap-2.5">
          <div className="p-1.5 rounded-lg bg-night-cyan/15 text-night-cyan border border-night-cyan/30">
            <Layers className="w-4 h-4" />
          </div>
          <div>
            <h3 className="text-xs font-bold text-night-white flex items-center gap-2">
              Physical Mesh Topology
              <span className="text-[10px] px-1.5 py-0.5 rounded-full font-mono font-normal bg-night-border/60 text-night-muted">
                {topology?.swarm_name || 'Active Mesh'}
              </span>
            </h3>
            <p className="text-[11px] text-night-muted">
              Interactive 2D multi-screen canvas & live vision calibration.
            </p>
          </div>
        </div>

        {/* Toolbar Action Buttons */}
        <div className="flex items-center gap-2">
          {/* Refresh Thumbnails Button */}
          <button
            type="button"
            onClick={() => setScreenKey(Date.now())}
            className="p-1.5 rounded-lg border border-night-border/80 text-night-muted hover:text-night-white hover:bg-night-border/40 transition-colors text-xs flex items-center gap-1"
            title="Refresh workstation thumbnails"
          >
            <RefreshCw className="w-3.5 h-3.5" />
          </button>

          {/* Flash Display ID Pattern */}
          <button
            type="button"
            onClick={handleFlashIdentify}
            disabled={isFlashing}
            className="px-2.5 py-1.5 rounded-lg border border-amber-500/40 bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 text-xs font-medium flex items-center gap-1.5 transition-all shadow-sm"
            title="Flash high-contrast identification pattern across all monitors & handhelds"
          >
            <Sparkles className="w-3.5 h-3.5 text-amber-400" />
            {isFlashing ? 'Flashing...' : 'Flash Display IDs'}
          </button>

          {/* Align Internal Displays */}
          <button
            type="button"
            onClick={handleAlignInternal}
            disabled={isAligning}
            className="px-2.5 py-1.5 rounded-lg border border-night-border/80 bg-night-dark/60 hover:bg-night-border/40 text-night-muted hover:text-night-white text-xs font-medium flex items-center gap-1.5 transition-all"
            title="Synchronize internal displays via kscreen-doctor (e.g. eDP-1 beneath DP-2)"
          >
            <Sliders className="w-3.5 h-3.5 text-night-cyan" />
            {isAligning ? 'Aligning...' : 'Align Internal'}
          </button>

          {/* Lock / Unlock Toggle */}
          <button
            type="button"
            onClick={toggleLock}
            className={`px-2.5 py-1.5 rounded-lg border text-xs font-medium flex items-center gap-1.5 transition-all ${
              topology?.locked
                ? 'bg-amber-500/15 text-amber-300 border-amber-500/40 shadow-sm'
                : 'bg-night-dark/60 text-night-muted hover:text-night-white border-night-border/80'
            }`}
          >
            {topology?.locked ? (
              <>
                <Lock className="w-3.5 h-3.5 text-amber-400" />
                Locked
              </>
            ) : (
              <>
                <Unlock className="w-3.5 h-3.5 text-night-cyan" />
                Dynamic
              </>
            )}
          </button>

          {/* Auto-Arrange from Photo Button */}
          <button
            type="button"
            onClick={() => setIsPhotoModalOpen(true)}
            className="px-3 py-1.5 rounded-lg bg-gradient-to-r from-night-cyan/20 to-purple-500/20 hover:from-night-cyan/30 hover:to-purple-500/30 text-night-white border border-night-cyan/40 text-xs font-semibold flex items-center gap-1.5 transition-all shadow-sm"
          >
            <Camera className="w-3.5 h-3.5 text-night-cyan" />
            Auto-Arrange from Photo
          </button>
        </div>
      </div>

      {/* Save Notification Toast */}
      {statusMsg && (
        <div className="absolute top-14 left-1/2 -translate-x-1/2 z-20 px-4 py-2 rounded-lg bg-emerald-500/20 border border-emerald-500/40 text-emerald-300 text-xs font-medium shadow-lg backdrop-blur-md animate-fade-in">
          {statusMsg}
        </div>
      )}

      {/* Spatial 2D Canvas Viewport */}
      <div className="flex-1 overflow-auto p-4 sm:p-6 flex flex-col items-center justify-center min-h-[360px] bg-[radial-gradient(#1e293b_1px,transparent_1px)] [background-size:16px_16px]">
        {isLoading ? (
          <div className="flex items-center gap-2 text-xs font-mono text-night-muted">
            <RefreshCw className="w-4 h-4 animate-spin text-night-cyan" />
            Loading screen topology...
          </div>
        ) : (
          <div className="flex flex-col items-center gap-4 max-w-5xl w-full">
            {/* Top Display (if present) */}
            {upNodeId && (
              <div className="flex flex-col items-center">
                {renderScreenCard(upNodeId, 'Up (Above Anchor)')}
                <div className="flex flex-col items-center my-1 text-night-cyan/70">
                  <span className="text-[10px] font-mono font-bold tracking-widest">↕ KVM BOUNDARY</span>
                  <div className="w-0.5 h-4 bg-night-cyan/60" />
                </div>
              </div>
            )}

            {/* Main Center Row: Left Flank <-> Anchor <-> Right Flank */}
            <div className="flex flex-wrap md:flex-nowrap items-center justify-center gap-3 w-full">
              {/* Left Screen (e.g. devbox laptop) */}
              {leftNodeId ? (
                renderScreenCard(leftNodeId, 'Left Flank')
              ) : (
                <div className="border border-dashed border-night-border/40 rounded-xl p-4 min-w-[200px] text-center text-xs text-night-muted/60 flex items-center justify-center">
                  No screen on left
                </div>
              )}

              {/* Horizontal Crossover Arrow (Left) */}
              {leftNodeId && (
                <div className="hidden md:flex flex-col items-center text-night-cyan/80 px-2">
                  <div className="flex items-center gap-0.5">
                    <ArrowLeft className="w-4 h-4" />
                    <ArrowRight className="w-4 h-4" />
                  </div>
                  <span className="text-[9px] font-mono font-bold text-night-cyan">
                    {leftLink?.span ? `[${leftLink.span[0]}-${leftLink.span[1]}%]` : 'Full'}
                  </span>
                  <span className="text-[8px] font-mono text-night-muted uppercase">Traverse</span>
                </div>
              )}

              {/* Center Anchor Screen (e.g. rog-ally desktop monitor) */}
              {renderScreenCard(anchorId, 'Center Primary (Anchor)', true)}

              {/* Horizontal Crossover Arrow (Right) */}
              {rightNodeId && (
                <div className="hidden md:flex flex-col items-center text-night-cyan/80 px-2">
                  <div className="flex items-center gap-0.5">
                    <ArrowLeft className="w-4 h-4" />
                    <ArrowRight className="w-4 h-4" />
                  </div>
                  <span className="text-[9px] font-mono font-bold text-night-cyan">
                    {rightLink?.span ? `[${rightLink.span[0]}-${rightLink.span[1]}%]` : 'Full'}
                  </span>
                  <span className="text-[8px] font-mono text-night-muted uppercase">Traverse</span>
                </div>
              )}

              {/* Right Screen (e.g. PurrfectSoftwareLimited) */}
              {rightNodeId ? (
                renderScreenCard(rightNodeId, 'Right Flank')
              ) : (
                <div className="border border-dashed border-night-border/40 rounded-xl p-4 min-w-[200px] text-center text-xs text-night-muted/60 flex items-center justify-center">
                  No screen on right
                </div>
              )}
            </div>

            {/* Down Display (e.g. steamdeck-eos or handheld console) */}
            {downNodeId && (
              <div className="flex flex-col items-center mt-3">
                <div className="flex flex-col items-center my-1 text-night-cyan/80">
                  <div className="w-0.5 h-3 bg-night-cyan/60" />
                  <div className="flex items-center gap-2 px-3 py-1 rounded-full bg-night-card border border-night-border text-[10px] font-mono shadow-sm">
                    <ArrowDown className="w-3 h-3 text-night-cyan" />
                    <span className="text-night-cyan font-bold">
                      {downLink?.span ? `Right [${downLink.span[0]}-${downLink.span[1]}%] ➔ ${downNodeId}` : 'Direct Down'}
                    </span>
                    <span className="text-night-muted">|</span>
                    <span className="text-purple-300">Left [0-50%] ➔ Console eDP-1</span>
                    <ArrowUp className="w-3 h-3 text-night-cyan" />
                  </div>
                  <div className="w-0.5 h-3 bg-night-cyan/60" />
                </div>
                {renderScreenCard(downNodeId, 'Front Handheld / Desk Level')}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Photo Topology Modal */}
      <PhotoTopologyModal
        isOpen={isPhotoModalOpen}
        onClose={() => setIsPhotoModalOpen(false)}
        onApplyTopology={handleApplyTopology}
        currentTopology={topology}
        onFlashIdentify={handleFlashIdentify}
      />

      {/* Display Calibration Pattern Overlay */}
      <DisplayCalibrationOverlay
        isOpen={isCalibrationOverlayOpen}
        onClose={() => setIsCalibrationOverlayOpen(false)}
        nodeId={anchorId}
        outputs={topology?.nodes?.[anchorId]?.display?.outputs || []}
        bg="white"
        duration={15}
      />
    </div>
  );
};
