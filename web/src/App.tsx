import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Header } from './components/Header';
import { TopologyRadar } from './components/radar/TopologyRadar';
import { SwarmChat } from './components/chat/SwarmChat';
import { DagMatrix } from './components/dag/DagMatrix';
import { ArtifactVault } from './components/artifacts/ArtifactVault';
import { BlackboardKanban } from './components/BlackboardKanban';
import { useKnotStore } from './hooks/useKnotSSE';
import { useGamepadNavigation } from './hooks/useGamepadNavigation';
import { GitBranch, Kanban, KeyRound } from 'lucide-react';
import type { CockpitViewMode } from './types/knot';

export const App: React.FC = () => {
  const {
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
    setSwarmModel,
    setConversationModel,
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
  } = useKnotStore();

  // Initial read of URL parameters for deep linking
  const [viewMode, setViewModeState] = useState<CockpitViewMode>(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      const urlView = params.get('view') as CockpitViewMode | null;
      if (urlView && ['grid', 'chat', 'radar', 'dag', 'kanban', 'artifacts'].includes(urlView)) {
        return urlView;
      }
      if (window.innerWidth < 1280) {
        return 'chat';
      }
    }
    return 'grid';
  });

  const [rightTab, setRightTabState] = useState<'dag' | 'kanban' | 'artifacts'>(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      const urlTab = params.get('tab');
      if (urlTab === 'dag' || urlTab === 'kanban' || urlTab === 'artifacts') {
        return urlTab;
      }
    }
    return 'dag';
  });

  // Calculate balanced initial sidebar width so left and right start with the exact same size
  const getInitialSidebarWidth = () => {
    if (typeof window === 'undefined') return 340;
    const w = window.innerWidth;
    if (w >= 2560) return 380;
    if (w >= 1920) return 340;
    return 300;
  };

  const [leftWidth, setLeftWidth] = useState<number>(() => {
    if (typeof window === 'undefined') return 340;
    const saved = localStorage.getItem('knot_cockpit_sidebar_left');
    return saved ? Math.max(240, Math.min(650, Number(saved))) : getInitialSidebarWidth();
  });

  const [rightWidth, setRightWidth] = useState<number>(() => {
    if (typeof window === 'undefined') return 340;
    const saved = localStorage.getItem('knot_cockpit_sidebar_right');
    return saved ? Math.max(240, Math.min(650, Number(saved))) : getInitialSidebarWidth();
  });

  const [isDraggingLeft, setIsDraggingLeft] = useState(false);
  const [isDraggingRight, setIsDraggingRight] = useState(false);
  const dashboardContainerRef = useRef<HTMLDivElement>(null);

  // Equalize / reset sidebar widths on double-click
  const resetSidebarWidths = () => {
    const initial = getInitialSidebarWidth();
    setLeftWidth(initial);
    setRightWidth(initial);
    try {
      localStorage.setItem('knot_cockpit_sidebar_left', String(initial));
      localStorage.setItem('knot_cockpit_sidebar_right', String(initial));
    } catch (err) {
      console.warn('Failed to save sidebar widths to localStorage:', err);
    }
  };

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!dashboardContainerRef.current) return;
      const rect = dashboardContainerRef.current.getBoundingClientRect();
      const containerWidth = rect.width;
      const minCenterWidth = 360;
      const minSidebarWidth = 240;
      const maxSidebarWidth = Math.min(650, containerWidth - minCenterWidth - minSidebarWidth);

      if (isDraggingLeft) {
        const newWidth = Math.max(minSidebarWidth, Math.min(e.clientX - rect.left, maxSidebarWidth));
        setLeftWidth(Math.round(newWidth));
      } else if (isDraggingRight) {
        const newWidth = Math.max(minSidebarWidth, Math.min(rect.right - e.clientX, maxSidebarWidth));
        setRightWidth(Math.round(newWidth));
      }
    };

    const handleMouseUp = () => {
      if (isDraggingLeft) {
        setIsDraggingLeft(false);
        try {
          localStorage.setItem('knot_cockpit_sidebar_left', String(leftWidth));
        } catch (err) {
          console.warn('Failed to save left sidebar width:', err);
        }
      }
      if (isDraggingRight) {
        setIsDraggingRight(false);
        try {
          localStorage.setItem('knot_cockpit_sidebar_right', String(rightWidth));
        } catch (err) {
          console.warn('Failed to save right sidebar width:', err);
        }
      }
    };

    if (isDraggingLeft || isDraggingRight) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
    } else {
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    }

    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };
  }, [isDraggingLeft, isDraggingRight, leftWidth, rightWidth]);

  // Helper to sync all active state into URL search params
  const updateUrlParams = useCallback((updates: {
    view?: string;
    channel?: string;
    project?: string;
    tab?: string;
  }) => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    if (updates.view !== undefined) url.searchParams.set('view', updates.view);
    if (updates.channel !== undefined) url.searchParams.set('channel', updates.channel);
    if (updates.project !== undefined) url.searchParams.set('project', updates.project);
    if (updates.tab !== undefined) url.searchParams.set('tab', updates.tab);
    window.history.replaceState({}, '', url.toString());
  }, []);

  const setViewMode = (mode: CockpitViewMode) => {
    setViewModeState(mode);
    updateUrlParams({ view: mode });
  };

  const setRightTab = (tab: 'dag' | 'kanban' | 'artifacts') => {
    setRightTabState(tab);
    updateUrlParams({ tab });
  };

  const ALL_VIEWS: CockpitViewMode[] = ['grid', 'chat', 'radar', 'dag', 'kanban', 'artifacts'];

  const handleNextView = useCallback(() => {
    setViewModeState((curr) => {
      const idx = ALL_VIEWS.indexOf(curr);
      const next = ALL_VIEWS[(idx + 1) % ALL_VIEWS.length];
      updateUrlParams({ view: next });
      return next;
    });
  }, [updateUrlParams]);

  const handlePrevView = useCallback(() => {
    setViewModeState((curr) => {
      const idx = ALL_VIEWS.indexOf(curr);
      const prev = ALL_VIEWS[(idx - 1 + ALL_VIEWS.length) % ALL_VIEWS.length];
      updateUrlParams({ view: prev });
      return prev;
    });
  }, [updateUrlParams]);

  const {
    gamepadConnected,
    handheldMode,
    toggleHandheldMode,
  } = useGamepadNavigation({
    onNextView: handleNextView,
    onPrevView: handlePrevView,
    onRefreshAction: () => void refreshAll(),
    enabled: true,
  });

  // Initial mount: Restore channel and project from deep linked URL if provided
  const initialDeepLinkHandled = useRef(false);
  useEffect(() => {
    if (initialDeepLinkHandled.current) return;
    if (typeof window === 'undefined') return;

    const params = new URLSearchParams(window.location.search);
    const urlProject = params.get('project');
    const urlChannel = params.get('channel') || params.get('conv');

    if (urlProject) {
      selectProject(urlProject);
    }
    if (urlChannel) {
      selectConversation(urlChannel);
    }
    initialDeepLinkHandled.current = true;
  }, [selectProject, selectConversation]);

  // Synchronize URL whenever activeConvId or activeProjectId changes
  useEffect(() => {
    if (!initialDeepLinkHandled.current) return;
    updateUrlParams({
      channel: activeConvId || 'main',
      project: activeProjectId || 'knot',
      view: viewMode,
      tab: rightTab,
    });
  }, [activeConvId, activeProjectId, viewMode, rightTab, updateUrlParams]);

  // Handle browser Back / Forward navigation (popstate)
  useEffect(() => {
    const handlePopState = () => {
      const params = new URLSearchParams(window.location.search);
      const urlView = params.get('view') as CockpitViewMode | null;
      if (urlView && ['grid', 'chat', 'radar', 'dag', 'kanban', 'artifacts'].includes(urlView)) {
        setViewModeState(urlView);
      }
      const urlTab = params.get('tab') as 'dag' | 'kanban' | 'artifacts' | null;
      if (urlTab && ['dag', 'kanban', 'artifacts'].includes(urlTab)) {
        setRightTabState(urlTab);
      }
      const urlProject = params.get('project');
      if (urlProject && urlProject !== activeProjectId) {
        selectProject(urlProject);
      }
      const urlChannel = params.get('channel') || params.get('conv');
      if (urlChannel && urlChannel !== activeConvId) {
        selectConversation(urlChannel);
      }
    };

    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, [activeProjectId, activeConvId, selectProject, selectConversation]);

  return (
    <div
      className={`h-dvh max-h-dvh flex flex-col bg-night-bg text-night-text selection:bg-night-blue selection:text-night-bg overflow-hidden ${
        handheldMode ? 'knot-handheld-scaling' : ''
      }`}
    >
      <Header
        connectionState={connectionState}
        nodes={nodes}
        tasks={tasks}
        onRefresh={() => void refreshAll()}
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        projects={projects}
        activeProjectId={activeProjectId}
        onProjectChange={(pid) => {
          selectProject(pid);
          updateUrlParams({ project: pid });
        }}
        powerStatus={powerStatus}
        onSetWakeHold={setSwarmWakeHold}
        onReleaseWakeHold={releaseSwarmWakeHold}
        models={models}
        onSelectSwarmModel={(model, nodeId, applyToAll) => void setSwarmModel(model, nodeId, applyToAll)}
        handheldMode={handheldMode}
        onToggleHandheld={toggleHandheldMode}
        gamepadConnected={gamepadConnected}
      />

      {/* Main Responsive Viewport */}
      <main className="flex-1 min-h-0 w-full max-w-[2560px] 2xl:max-w-[3440px] mx-auto p-2 sm:p-2.5 overflow-hidden flex flex-col">
        {viewMode === 'grid' && (
          <div
            ref={dashboardContainerRef}
            className="flex-1 min-h-0 flex flex-col xl:flex-row gap-0 h-full overflow-hidden relative"
          >
            {/* Left Column: Topology Radar & Quota Telemetry */}
            <section className="w-full xl:w-auto h-full min-h-0 overflow-hidden flex flex-col shrink-0">
              <div
                style={{ width: `${leftWidth}px` }}
                className="hidden xl:flex flex-col h-full min-h-0 overflow-hidden pr-1"
              >
                <TopologyRadar
                  nodes={nodes}
                  quotas={quotas}
                  onTriggerAction={triggerMeshAction}
                  models={models}
                  onSelectNodeModel={(nodeId, model) => void setSwarmModel(model, nodeId, false)}
                  isDedicatedView={false}
                />
              </div>
              <div className="flex xl:hidden flex-col h-full min-h-0 overflow-hidden">
                <TopologyRadar
                  nodes={nodes}
                  quotas={quotas}
                  onTriggerAction={triggerMeshAction}
                  models={models}
                  onSelectNodeModel={(nodeId, model) => void setSwarmModel(model, nodeId, false)}
                  isDedicatedView={false}
                />
              </div>
            </section>

            {/* Left <-> Center Drag Resize Handle */}
            <div
              onMouseDown={(e) => {
                e.preventDefault();
                setIsDraggingLeft(true);
              }}
              onDoubleClick={resetSidebarWidths}
              className="hidden xl:flex w-2.5 items-center justify-center cursor-col-resize select-none z-20 group relative hover:bg-night-cyan/10 transition-colors shrink-0"
              title="Drag to resize sidebar • Double-click to equalize sidebars"
            >
              <div
                className={`w-0.5 h-10 rounded-full transition-all ${
                  isDraggingLeft
                    ? 'w-1 bg-night-cyan shadow-[0_0_8px_rgba(6,182,212,0.6)]'
                    : 'bg-night-border group-hover:bg-night-cyan/70 group-hover:h-16'
                }`}
              />
            </div>

            {/* Center Column: Swarm Konversations Chat */}
            <section className="flex-1 min-w-[360px] h-full min-h-0 overflow-hidden flex flex-col px-0 xl:px-1">
              <SwarmChat
                messages={messages}
                onSendMessage={sendMessage}
                conversations={conversations}
                activeConvId={activeConvId}
                onSelectConversation={(cid) => {
                  selectConversation(cid);
                  updateUrlParams({ channel: cid });
                }}
                onCreateConversation={createConversation}
                activeProjectId={activeProjectId}
                tasks={tasks}
                nodes={nodes}
                models={models}
                onSelectConversationModel={setConversationModel}
                isDedicatedView={false}
              />
            </section>

            {/* Center <-> Right Drag Resize Handle */}
            <div
              onMouseDown={(e) => {
                e.preventDefault();
                setIsDraggingRight(true);
              }}
              onDoubleClick={resetSidebarWidths}
              className="hidden xl:flex w-2.5 items-center justify-center cursor-col-resize select-none z-20 group relative hover:bg-night-cyan/10 transition-colors shrink-0"
              title="Drag to resize sidebar • Double-click to equalize sidebars"
            >
              <div
                className={`w-0.5 h-10 rounded-full transition-all ${
                  isDraggingRight
                    ? 'w-1 bg-night-cyan shadow-[0_0_8px_rgba(6,182,212,0.6)]'
                    : 'bg-night-border group-hover:bg-night-cyan/70 group-hover:h-16'
                }`}
              />
            </div>

            {/* Right Column: Split Tabbed DAG Task Matrix & Artifact Vault */}
            <section className="w-full xl:w-auto h-full min-h-0 overflow-hidden flex flex-col shrink-0">
              <div
                style={{ width: `${rightWidth}px` }}
                className="hidden xl:flex flex-col h-full min-h-0 overflow-hidden pl-1"
              >
                <div className="flex-1 min-h-0 overflow-hidden flex flex-col glass rounded-xl border border-night-border">
                  {/* Sub Tab Switcher */}
                  <div className="flex-none flex border-b border-night-border bg-night-panel/60 p-1">
                    <button
                      onClick={() => setRightTab('dag')}
                      className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                        rightTab === 'dag'
                          ? 'bg-night-surface text-night-cyan shadow-sm border border-night-cyan/30'
                          : 'text-night-muted hover:text-night-text'
                      }`}
                      title="Directed Acyclic Graph Task Matrix"
                    >
                      <GitBranch className="w-3.5 h-3.5 shrink-0" />
                      <span className="truncate">DAG ({tasks.length})</span>
                    </button>
                    <button
                      onClick={() => setRightTab('kanban')}
                      className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                        rightTab === 'kanban'
                          ? 'bg-night-surface text-night-cyan shadow-sm border border-night-cyan/30'
                          : 'text-night-muted hover:text-night-text'
                      }`}
                      title="Blackboard Kanban Board"
                    >
                      <Kanban className="w-3.5 h-3.5 shrink-0" />
                      <span className="truncate">Kanban</span>
                    </button>
                    <button
                      onClick={() => setRightTab('artifacts')}
                      className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                        rightTab === 'artifacts'
                          ? 'bg-night-surface text-night-yellow shadow-sm border border-night-yellow/30'
                          : 'text-night-muted hover:text-night-text'
                      }`}
                      title="3-State Atomic Artifact Lease Vault"
                    >
                      <KeyRound className="w-3.5 h-3.5 shrink-0" />
                      <span className="truncate">Vault ({leases.length})</span>
                    </button>
                  </div>

                  {/* Tab Content */}
                  <div className="flex-1 min-h-0 overflow-hidden">
                    {rightTab === 'dag' ? (
                      <DagMatrix tasks={tasks} embedded />
                    ) : rightTab === 'kanban' ? (
                      <BlackboardKanban
                        tasks={tasks}
                        nodes={nodes}
                        onRefresh={() => void refreshAll()}
                        handheldMode={handheldMode}
                        onToggleHandheld={toggleHandheldMode}
                        embedded
                      />
                    ) : (
                      <ArtifactVault
                        leases={leases}
                        onLock={lockArtifact}
                        onRelease={releaseArtifact}
                        embedded
                      />
                    )}
                  </div>
                </div>
              </div>

              {/* Mobile / Tablet fallback */}
              <div className="flex xl:hidden flex-col h-full min-h-0 overflow-hidden glass rounded-xl border border-night-border">
                <div className="flex-none flex border-b border-night-border bg-night-panel/60 p-1">
                  <button
                    onClick={() => setRightTab('dag')}
                    className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                      rightTab === 'dag'
                        ? 'bg-night-surface text-night-cyan shadow-sm border border-night-cyan/30'
                        : 'text-night-muted hover:text-night-text'
                    }`}
                    title="Directed Acyclic Graph Task Matrix"
                  >
                    <GitBranch className="w-3.5 h-3.5 shrink-0" />
                    <span className="truncate">DAG ({tasks.length})</span>
                  </button>
                  <button
                    onClick={() => setRightTab('kanban')}
                    className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                      rightTab === 'kanban'
                        ? 'bg-night-surface text-night-cyan shadow-sm border border-night-cyan/30'
                        : 'text-night-muted hover:text-night-text'
                    }`}
                    title="Blackboard Kanban Board"
                  >
                    <Kanban className="w-3.5 h-3.5 shrink-0" />
                    <span className="truncate">Kanban</span>
                  </button>
                  <button
                    onClick={() => setRightTab('artifacts')}
                    className={`flex-1 py-1.5 px-2 rounded-lg text-xs font-mono font-bold flex items-center justify-center gap-1 transition-all truncate ${
                      rightTab === 'artifacts'
                        ? 'bg-night-surface text-night-yellow shadow-sm border border-night-yellow/30'
                        : 'text-night-muted hover:text-night-text'
                    }`}
                    title="3-State Atomic Artifact Lease Vault"
                  >
                    <KeyRound className="w-3.5 h-3.5 shrink-0" />
                    <span className="truncate">Vault ({leases.length})</span>
                  </button>
                </div>
                <div className="flex-1 min-h-0 overflow-hidden">
                  {rightTab === 'dag' ? (
                    <DagMatrix tasks={tasks} embedded />
                  ) : rightTab === 'kanban' ? (
                    <BlackboardKanban
                      tasks={tasks}
                      nodes={nodes}
                      onRefresh={() => void refreshAll()}
                      handheldMode={handheldMode}
                      onToggleHandheld={toggleHandheldMode}
                      embedded
                    />
                  ) : (
                    <ArtifactVault
                      leases={leases}
                      onLock={lockArtifact}
                      onRelease={releaseArtifact}
                      embedded
                    />
                  )}
                </div>
              </div>
            </section>
          </div>
        )}

        {viewMode === 'chat' && (
          <div className="flex-1 min-h-0 h-full w-full max-w-[2560px] 2xl:max-w-[3440px] mx-auto overflow-hidden flex flex-col">
            <SwarmChat
              messages={messages}
              onSendMessage={sendMessage}
              conversations={conversations}
              activeConvId={activeConvId}
              onSelectConversation={(cid) => {
                selectConversation(cid);
                updateUrlParams({ channel: cid });
              }}
              onCreateConversation={createConversation}
              activeProjectId={activeProjectId}
              tasks={tasks}
              nodes={nodes}
              models={models}
              onSelectConversationModel={setConversationModel}
              isDedicatedView={true}
            />
          </div>
        )}

        {viewMode === 'radar' && (
          <div className="flex-1 min-h-0 h-full w-full max-w-7xl mx-auto overflow-hidden flex flex-col">
            <TopologyRadar
              nodes={nodes}
              quotas={quotas}
              onTriggerAction={triggerMeshAction}
              models={models}
              onSelectNodeModel={(nodeId, model) => void setSwarmModel(model, nodeId, false)}
              isDedicatedView={true}
            />
          </div>
        )}

        {viewMode === 'dag' && (
          <div className="flex-1 min-h-0 h-full w-full max-w-5xl mx-auto overflow-hidden flex flex-col">
            <DagMatrix tasks={tasks} />
          </div>
        )}

        {viewMode === 'kanban' && (
          <div className="flex-1 min-h-0 h-full w-full max-w-[2560px] 2xl:max-w-[3440px] mx-auto overflow-hidden flex flex-col">
            <BlackboardKanban
              tasks={tasks}
              nodes={nodes}
              onRefresh={() => void refreshAll()}
              handheldMode={handheldMode}
              onToggleHandheld={toggleHandheldMode}
            />
          </div>
        )}

        {viewMode === 'artifacts' && (
          <div className="flex-1 min-h-0 h-full w-full max-w-5xl mx-auto overflow-hidden flex flex-col">
            <ArtifactVault
              leases={leases}
              onLock={lockArtifact}
              onRelease={releaseArtifact}
            />
          </div>
        )}
      </main>
    </div>
  );
};

export default App;
