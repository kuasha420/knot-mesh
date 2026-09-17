import React, { useState, useRef } from 'react';
import {
  Camera,
  Upload,
  Sparkles,
  Zap,
  CheckCircle2,
  AlertCircle,
  X,
  RefreshCw,
  Layers,
  Sliders,
  FileImage,
  HelpCircle,
  ChevronDown,
  ChevronUp,
} from 'lucide-react';
import type {
  MeshTopologyState,
  TopologyAnalysisResult,
  TopologyScreenDetection,
  MeshTopologyLink,
} from '../../types/knot';

export interface PhotoTopologyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onApplyTopology: (
    layout: Record<string, Record<string, MeshTopologyLink>>,
    screens: string[],
    anchor: string
  ) => Promise<boolean>;
  currentTopology: MeshTopologyState | null;
  onFlashIdentify?: (bg: 'white' | 'black' | 'neon') => void;
}

export const PhotoTopologyModal: React.FC<PhotoTopologyModalProps> = ({
  isOpen,
  onClose,
  onApplyTopology,
  currentTopology,
  onFlashIdentify,
}) => {
  const [file, setFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [mode, setMode] = useState<'auto' | 'offline' | 'swarm'>('auto');
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [analysisResult, setAnalysisResult] = useState<TopologyAnalysisResult | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [isApplying, setIsApplying] = useState(false);
  const [applySuccess, setApplySuccess] = useState(false);
  const [hoveredScreenIndex, setHoveredScreenIndex] = useState<number | null>(null);
  const [isGuideOpen, setIsGuideOpen] = useState<boolean>(true);
  const [flashBg, setFlashBg] = useState<'white' | 'black' | 'neon'>('white');
  const [isFlashing, setIsFlashing] = useState<boolean>(false);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const timerRef = useRef<number | null>(null);

  if (!isOpen) return null;

  const handleFileSelect = (selectedFile: File) => {
    setFile(selectedFile);
    setErrorMsg(null);
    setAnalysisResult(null);
    setApplySuccess(false);

    const reader = new FileReader();
    reader.onload = () => {
      setImagePreview(reader.result as string);
    };
    reader.readAsDataURL(selectedFile);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      handleFileSelect(e.dataTransfer.files[0]);
    }
  };

  const handleTriggerFlash = async () => {
    setIsFlashing(true);
    try {
      if (onFlashIdentify) {
        onFlashIdentify(flashBg);
      } else {
        await fetch('/topology/identify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ bg: flashBg, duration: 15 }),
        });
      }
    } catch (err) {
      console.error('Failed to trigger display flash:', err);
    } finally {
      setTimeout(() => setIsFlashing(false), 2000);
    }
  };

  const runAnalysis = async () => {
    if (!imagePreview) return;

    setIsAnalyzing(true);
    setErrorMsg(null);
    setApplySuccess(false);
    setElapsedMs(0);

    const startTime = Date.now();
    timerRef.current = window.setInterval(() => {
      setElapsedMs(Date.now() - startTime);
    }, 50);

    try {
      const res = await fetch('/topology/analyze-photo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          image_base64: imagePreview,
          mode,
        }),
      });

      if (!res.ok) {
        const err = await res.text();
        throw new Error(err || `Analysis failed (status ${res.status})`);
      }

      const data = await res.json();
      if (data.ok && data.result) {
        setAnalysisResult(data.result as TopologyAnalysisResult);
      } else {
        throw new Error(data.error || 'Invalid analysis response');
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
      setIsAnalyzing(false);
    }
  };

  const handleApply = async () => {
    if (!analysisResult) return;
    setIsApplying(true);
    try {
      const anchor = analysisResult.anchor_node_id || currentTopology?.anchor || 'rog-ally';
      const screens = Array.from(
        new Set(analysisResult.screens.map((s) => s.matched_node_id).filter(Boolean))
      );
      const ok = await onApplyTopology(analysisResult.proposed_layout, screens, anchor);
      if (ok) {
        setApplySuccess(true);
        setTimeout(() => {
          onClose();
        }, 1500);
      } else {
        setErrorMsg('Failed to apply topology configuration to mesh.');
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : String(err));
    } finally {
      setIsApplying(false);
    }
  };

  const getScreenColor = (screen: TopologyScreenDetection, isHovered: boolean) => {
    if (screen.position_relative_to_anchor === 'anchor') {
      return {
        stroke: isHovered ? '#ec4899' : '#c084fc',
        fill: 'rgba(192, 132, 252, 0.18)',
        badge: 'bg-purple-500/20 text-purple-300 border-purple-500/40',
      };
    }
    if (screen.position_relative_to_anchor === 'anchor_internal') {
      return {
        stroke: isHovered ? '#a855f7' : '#7e22ce',
        fill: 'rgba(168, 85, 247, 0.18)',
        badge: 'bg-purple-900/40 text-purple-200 border-purple-500/50',
      };
    }
    if (screen.device_type === 'laptop') {
      return {
        stroke: isHovered ? '#38bdf8' : '#0284c7',
        fill: 'rgba(56, 189, 248, 0.15)',
        badge: 'bg-sky-500/20 text-sky-300 border-sky-500/40',
      };
    }
    if (screen.device_type === 'handheld_pc') {
      return {
        stroke: isHovered ? '#fbbf24' : '#d97706',
        fill: 'rgba(251, 191, 36, 0.15)',
        badge: 'bg-amber-500/20 text-amber-300 border-amber-500/40',
      };
    }
    return {
      stroke: isHovered ? '#2dd4bf' : '#0d9488',
      fill: 'rgba(45, 212, 191, 0.15)',
      badge: 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40',
    };
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-night-black/80 backdrop-blur-md animate-fade-in">
      <div className="bg-night-card border border-night-border rounded-xl shadow-2xl w-full max-w-4xl max-h-[92vh] flex flex-col overflow-hidden text-night-text">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-night-border bg-night-dark/60">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-lg bg-night-cyan/15 text-night-cyan border border-night-cyan/30">
              <Camera className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-night-white flex items-center gap-2">
                Live Photo Topology Refresh
                <span className="text-xs px-2 py-0.5 rounded-full font-mono font-normal bg-night-cyan/15 text-night-cyan border border-night-cyan/30">
                  Vision & Spatial AI
                </span>
              </h2>
              <p className="text-xs text-night-muted">
                Photograph your physical desk setup to auto-detect displays and synthesize Deskflow KVM topology.
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-night-muted hover:text-night-white hover:bg-night-border/40 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4">
          {/* Photography Guidance & Calibration Flash Panel */}
          <div className="rounded-xl border border-night-cyan/30 bg-night-dark/50 overflow-hidden">
            <button
              type="button"
              onClick={() => setIsGuideOpen(!isGuideOpen)}
              className="w-full flex items-center justify-between px-4 py-2.5 text-xs font-semibold text-night-white hover:bg-night-border/20 transition-colors"
            >
              <div className="flex items-center gap-2">
                <HelpCircle className="w-4 h-4 text-night-cyan" />
                <span>Photography Best Practices & Swarm Display Flash</span>
              </div>
              {isGuideOpen ? <ChevronUp className="w-4 h-4 text-night-muted" /> : <ChevronDown className="w-4 h-4 text-night-muted" />}
            </button>

            {isGuideOpen && (
              <div className="px-4 pb-3.5 pt-1 text-xs text-night-muted space-y-3 border-t border-night-border/40">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2.5">
                  <div className="p-2.5 rounded-lg bg-night-black/40 border border-night-border/50">
                    <div className="font-bold text-night-cyan mb-1">1. Flash Display IDs</div>
                    <p className="text-[11px] leading-relaxed">
                      Flash high-contrast pattern with corner markers for 100% boundary accuracy.
                    </p>
                  </div>
                  <div className="p-2.5 rounded-lg bg-night-black/40 border border-night-border/50">
                    <div className="font-bold text-night-white mb-1">2. Stand Back 2m</div>
                    <p className="text-[11px] leading-relaxed">
                      Ensure all monitors, laptops, and handhelds fit into a single wide photo.
                    </p>
                  </div>
                  <div className="p-2.5 rounded-lg bg-night-black/40 border border-night-border/50">
                    <div className="font-bold text-night-white mb-1">3. Hold Eye-Level</div>
                    <p className="text-[11px] leading-relaxed">
                      Keep camera level with center screen (parallel to desk plane).
                    </p>
                  </div>
                  <div className="p-2.5 rounded-lg bg-night-black/40 border border-night-border/50">
                    <div className="font-bold text-night-white mb-1">4. Snap & Refresh</div>
                    <p className="text-[11px] leading-relaxed">
                      Drop photo below to compile reciprocal Deskflow spans instantly.
                    </p>
                  </div>
                </div>

                {/* Flash Pattern Control Bar */}
                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-night-border/30">
                  <div className="flex items-center gap-2">
                    <span className="text-[11px] text-night-muted font-medium">Flash Background:</span>
                    <div className="flex items-center gap-1">
                      {(['white', 'black', 'neon'] as const).map((bgOption) => (
                        <button
                          key={bgOption}
                          type="button"
                          onClick={() => setFlashBg(bgOption)}
                          className={`px-2 py-0.5 rounded text-[10px] font-mono capitalize transition-all ${
                            flashBg === bgOption
                              ? 'bg-night-cyan text-night-black font-bold'
                              : 'bg-night-black/60 text-night-muted hover:text-night-text border border-night-border/40'
                          }`}
                        >
                          {bgOption}
                        </button>
                      ))}
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={handleTriggerFlash}
                    disabled={isFlashing}
                    className="px-3 py-1 rounded-lg bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 text-xs font-semibold flex items-center gap-1.5 transition-all shadow-sm"
                  >
                    <Sparkles className="w-3.5 h-3.5 text-amber-400" />
                    {isFlashing ? 'Flashing Screens...' : '📸 Flash Display ID Pattern'}
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Engine Selector */}
          <div className="flex flex-wrap items-center justify-between gap-3 p-3 rounded-lg bg-night-dark/40 border border-night-border/70">
            <div className="flex items-center gap-2">
              <Sliders className="w-4 h-4 text-night-cyan" />
              <span className="text-xs font-medium text-night-white">Vision & Reasoning Tier:</span>
            </div>
            <div className="flex items-center gap-1.5 bg-night-black/60 p-1 rounded-lg border border-night-border/50">
              <button
                type="button"
                onClick={() => setMode('auto')}
                className={`px-3 py-1 rounded text-xs font-medium transition-all flex items-center gap-1.5 ${
                  mode === 'auto'
                    ? 'bg-night-cyan/25 text-night-cyan border border-night-cyan/40 shadow-sm'
                    : 'text-night-muted hover:text-night-text'
                }`}
              >
                <Sparkles className="w-3.5 h-3.5" />
                Auto Dual-Tier
              </button>
              <button
                type="button"
                onClick={() => setMode('offline')}
                className={`px-3 py-1 rounded text-xs font-medium transition-all flex items-center gap-1.5 ${
                  mode === 'offline'
                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 shadow-sm'
                    : 'text-night-muted hover:text-night-text'
                }`}
              >
                <Zap className="w-3.5 h-3.5" />
                Offline CV (Local)
              </button>
              <button
                type="button"
                onClick={() => setMode('swarm')}
                className={`px-3 py-1 rounded text-xs font-medium transition-all flex items-center gap-1.5 ${
                  mode === 'swarm'
                    ? 'bg-purple-500/20 text-purple-300 border border-purple-500/40 shadow-sm'
                    : 'text-night-muted hover:text-night-text'
                }`}
              >
                <Layers className="w-3.5 h-3.5" />
                Swarm AI (Gemini)
              </button>
            </div>
          </div>

          {/* Upload / Preview Viewport */}
          {!imagePreview ? (
            <div
              onDragOver={(e) => e.preventDefault()}
              onDrop={handleDrop}
              onClick={() => fileInputRef.current?.click()}
              className="border-2 border-dashed border-night-border/80 hover:border-night-cyan/60 rounded-xl p-8 text-center cursor-pointer transition-colors bg-night-dark/30 hover:bg-night-dark/60 flex flex-col items-center justify-center min-h-[220px]"
            >
              <Upload className="w-10 h-10 text-night-cyan/70 mb-3 animate-bounce" />
              <p className="text-sm font-semibold text-night-white">
                Drop your desk photograph here, or click to browse
              </p>
              <p className="text-xs text-night-muted mt-1">
                Supports JPG, PNG, WEBP up to 20MB. Captures full physical desk workstation layout.
              </p>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => {
                  if (e.target.files && e.target.files[0]) {
                    handleFileSelect(e.target.files[0]);
                  }
                }}
              />
            </div>
          ) : (
            <div className="space-y-3">
              {/* Image Container with SVG Overlay */}
              <div className="relative rounded-xl border border-night-border overflow-hidden bg-black/90 max-h-[460px] flex items-center justify-center">
                <img
                  src={imagePreview}
                  alt="Desk Layout"
                  className="max-h-[460px] w-auto object-contain mx-auto select-none"
                />

                {/* SVG Bounding Boxes Overlay */}
                {analysisResult && (
                  <svg
                    viewBox="0 0 1000 1000"
                    preserveAspectRatio="none"
                    className="absolute inset-0 w-full h-full pointer-events-none"
                  >
                    {analysisResult.screens.map((screen, idx) => {
                      const [ymin, xmin, ymax, xmax] = screen.box_2d;
                      const w = xmax - xmin;
                      const h = ymax - ymin;
                      const isHovered = hoveredScreenIndex === idx;
                      const colors = getScreenColor(screen, isHovered);

                      return (
                        <g key={idx}>
                          <rect
                            x={xmin}
                            y={ymin}
                            width={w}
                            height={h}
                            fill={colors.fill}
                            stroke={colors.stroke}
                            strokeWidth={isHovered ? 4 : 2.5}
                            strokeDasharray={screen.position_relative_to_anchor === 'anchor_internal' ? '6 3' : 'none'}
                            className="transition-all duration-150"
                          />
                          <g transform={`translate(${xmin}, ${Math.max(20, ymin)})`}>
                            <rect
                              x={0}
                              y={-18}
                              width={Math.max(80, screen.matched_node_id.length * 10 + 44)}
                              height={24}
                              fill="rgba(10, 15, 29, 0.85)"
                              stroke={colors.stroke}
                              strokeWidth={1.5}
                              rx={4}
                            />
                            <text
                              x={6}
                              y={-2}
                              fill="#ffffff"
                              fontSize={13}
                              fontFamily="monospace"
                              fontWeight="bold"
                            >
                              {screen.matched_node_id} ({Math.round(screen.confidence * 100)}%)
                            </text>
                          </g>
                        </g>
                      );
                    })}
                  </svg>
                )}

                {/* Scanning Laser Animation */}
                {isAnalyzing && (
                  <div className="absolute inset-0 bg-night-cyan/10 pointer-events-none flex flex-col justify-between">
                    <div className="h-0.5 w-full bg-night-cyan shadow-[0_0_12px_#06b6d4] animate-pulse" />
                    <div className="text-center py-2 bg-night-black/75 backdrop-blur-sm text-xs font-mono text-night-cyan">
                      Analyzing contours & identifying workstation devices... ({elapsedMs}ms)
                    </div>
                  </div>
                )}

                {/* Replace photo button */}
                <div className="absolute top-2 right-2 flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => {
                      setImagePreview(null);
                      setAnalysisResult(null);
                    }}
                    className="p-1.5 rounded-lg bg-night-black/80 text-night-muted hover:text-night-white border border-night-border text-xs flex items-center gap-1 backdrop-blur-sm"
                  >
                    <RefreshCw className="w-3.5 h-3.5" />
                    Change Photo
                  </button>
                </div>
              </div>

              {/* Action bar below preview */}
              <div className="flex items-center justify-between">
                <div className="text-xs text-night-muted flex items-center gap-2">
                  <FileImage className="w-4 h-4 text-night-cyan" />
                  <span>{file?.name || 'Photo selected'}</span>
                  {analysisResult && (
                    <span className="text-night-cyan font-mono">
                      • {analysisResult.screens.length} displays detected ({analysisResult.metadata?.detection_time_ms || 0}ms)
                    </span>
                  )}
                </div>

                {!analysisResult && (
                  <button
                    type="button"
                    disabled={isAnalyzing}
                    onClick={runAnalysis}
                    className="px-4 py-2 rounded-lg bg-night-cyan text-night-black font-semibold text-xs flex items-center gap-2 hover:bg-night-cyan/90 transition-all shadow-md shadow-night-cyan/20 disabled:opacity-50"
                  >
                    {isAnalyzing ? (
                      <>
                        <RefreshCw className="w-4 h-4 animate-spin" />
                        Scanning Setup... ({elapsedMs}ms)
                      </>
                    ) : (
                      <>
                        <Sparkles className="w-4 h-4" />
                        Analyze Physical Layout
                      </>
                    )}
                  </button>
                )}
              </div>
            </div>
          )}

          {/* Analysis Results Display */}
          {analysisResult && (
            <div className="space-y-4 animate-fade-in">
              {/* Detected Screens Badges */}
              <div>
                <h3 className="text-xs font-semibold text-night-white uppercase tracking-wider mb-2 flex items-center gap-1.5">
                  <Layers className="w-3.5 h-3.5 text-night-cyan" />
                  Detected Physical Displays
                </h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
                  {analysisResult.screens.map((screen, idx) => {
                    const isHovered = hoveredScreenIndex === idx;
                    const colors = getScreenColor(screen, isHovered);

                    return (
                      <div
                        key={idx}
                        onMouseEnter={() => setHoveredScreenIndex(idx)}
                        onMouseLeave={() => setHoveredScreenIndex(null)}
                        className={`p-2.5 rounded-lg border transition-all cursor-pointer bg-night-dark/40 ${
                          isHovered
                            ? 'border-night-cyan bg-night-dark/80 shadow-md'
                            : 'border-night-border/70 hover:border-night-border'
                        }`}
                      >
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs font-bold text-night-white font-mono">
                            {screen.matched_node_id}
                          </span>
                          <span className={`text-[10px] px-1.5 py-0.5 rounded border font-mono ${colors.badge}`}>
                            {screen.position_relative_to_anchor === 'anchor_internal' ? 'internal' : screen.device_type}
                          </span>
                        </div>
                        <div className="flex items-center justify-between text-[11px] text-night-muted">
                          <span className="capitalize">
                            Pos: <strong className="text-night-text">{screen.position_relative_to_anchor}</strong>
                          </span>
                          {screen.span && (screen.span[0] > 0 || screen.span[1] < 100) ? (
                            <span className="font-mono text-night-cyan text-[10px]">
                              span: {screen.span[0]}-{screen.span[1]}%
                            </span>
                          ) : (
                            <span>{Math.round(screen.confidence * 100)}% match</span>
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Reciprocal Spatial Map Comparison */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {/* Proposed Layout */}
                <div className="p-3 rounded-lg border border-night-cyan/30 bg-night-cyan/5">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs font-semibold text-night-cyan flex items-center gap-1.5">
                      <CheckCircle2 className="w-3.5 h-3.5" />
                      Proposed Mesh Layout
                    </span>
                    <span className="text-[10px] px-2 py-0.5 rounded bg-night-cyan/20 text-night-cyan font-mono">
                      Anchor: {analysisResult.anchor_node_id}
                    </span>
                  </div>
                  <div className="space-y-1 text-xs">
                    {Object.entries(analysisResult.proposed_layout).map(([nodeId, dirs]) => (
                      <div key={nodeId} className="flex flex-wrap items-center gap-1.5 py-1 border-b border-night-cyan/10 font-mono text-[11px]">
                        <span className="text-night-white font-bold">{nodeId}</span>
                        {Object.entries(dirs).map(([dir, info]) => {
                          const spanStr = info.span ? `[${info.span[0]}-${info.span[1]}%]` : '';
                          return (
                            <span key={dir} className="px-1.5 py-0.5 rounded bg-night-black/60 text-night-muted border border-night-border/40">
                              {dir} {spanStr} ➔ <strong className="text-night-cyan">{info.node}</strong>
                            </span>
                          );
                        })}
                      </div>
                    ))}
                  </div>
                </div>

                {/* AI / Heuristic Reasoning */}
                <div className="p-3 rounded-lg border border-night-border bg-night-dark/30">
                  <span className="text-xs font-semibold text-night-white flex items-center gap-1.5 mb-2">
                    <Sparkles className="w-3.5 h-3.5 text-purple-400" />
                    Spatial Reasoning
                  </span>
                  <div className="text-xs text-night-muted whitespace-pre-line max-h-32 overflow-y-auto leading-relaxed font-sans">
                    {analysisResult.reasoning}
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Error Message */}
          {errorMsg && (
            <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/30 text-red-300 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 text-red-400" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Success Message */}
          {applySuccess && (
            <div className="p-3 rounded-lg bg-emerald-500/15 border border-emerald-500/40 text-emerald-300 text-xs flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 shrink-0 text-emerald-400" />
              <span>Topology successfully refreshed! Deskflow KVM and LayerShell boundary strips reloaded.</span>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-5 py-3 border-t border-night-border bg-night-dark/60 flex items-center justify-between">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-lg border border-night-border text-xs text-night-muted hover:text-night-white hover:bg-night-border/30 transition-colors"
          >
            Cancel
          </button>

          {analysisResult && (
            <button
              type="button"
              disabled={isApplying || applySuccess}
              onClick={handleApply}
              className="px-5 py-2 rounded-lg bg-night-cyan text-night-black font-semibold text-xs flex items-center gap-2 hover:bg-night-cyan/90 transition-all shadow-md shadow-night-cyan/20 disabled:opacity-50"
            >
              {isApplying ? (
                <>
                  <RefreshCw className="w-4 h-4 animate-spin" />
                  Applying to Mesh...
                </>
              ) : applySuccess ? (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  Applied!
                </>
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4" />
                  Apply Topology to Mesh
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
