import React, { useState } from 'react';
import { CheckCheck, FileCode2, KeyRound, Lock, Plus, Unlock } from 'lucide-react';
import type { ArtifactLease, ArtifactStatus, NodeId } from '../../types/knot';

interface ArtifactVaultProps {
  leases: ArtifactLease[];
  onLock: (artifactName: string, holderNode: NodeId, ttlSeconds?: number) => Promise<boolean>;
  onRelease: (
    artifactName: string,
    holderNode: NodeId,
    newStatus: ArtifactStatus
  ) => Promise<boolean>;
  embedded?: boolean;
}

export const ArtifactVault: React.FC<ArtifactVaultProps> = ({
  leases,
  onLock,
  onRelease,
  embedded = false,
}) => {
  const [newArtifactName, setNewArtifactName] = useState('');
  const [holderNode, setHolderNode] = useState<NodeId>('desktop');
  const [ttl, setTtl] = useState(600);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const getStatusBadge = (status: ArtifactStatus) => {
    switch (status) {
      case 'DRAFTING':
        return (
          <span className="text-[9px] font-mono px-2 py-0.5 rounded bg-night-muted/20 text-night-muted border border-night-muted/30">
            DRAFTING
          </span>
        );
      case 'LOCKED_SURGERY':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-orange/20 text-night-orange border border-night-orange/30 animate-pulse">
            <Lock className="w-2.5 h-2.5" /> LOCKED SURGERY
          </span>
        );
      case 'VERIFIED_COMMITTED':
        return (
          <span className="flex items-center gap-1 text-[9px] font-mono px-2 py-0.5 rounded bg-night-green/20 text-night-green border border-night-green/30">
            <CheckCheck className="w-2.5 h-2.5" /> VERIFIED COMMITTED
          </span>
        );
    }
  };

  const handleAcquireLock = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newArtifactName.trim()) return;
    setIsSubmitting(true);
    await onLock(newArtifactName.trim(), holderNode, ttl);
    setNewArtifactName('');
    setIsSubmitting(false);
  };

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
            <KeyRound className="w-4 h-4 text-night-yellow" />
            <h2 className="text-xs font-bold tracking-wider text-night-blue uppercase">
              3-State Artifact Leases
            </h2>
          </div>
          <span className="text-[10px] font-mono text-night-muted">
            {leases.length} ACTIVE LEASES
          </span>
        </div>
      )}

      {/* Lock Acquisition Form */}
      <div className="flex-none p-3 border-b border-night-border/50 bg-night-panel/30">
        <form onSubmit={handleAcquireLock} className="flex items-center gap-2">
          <input
            type="text"
            placeholder="Artifact name (e.g. system_prompt.md)"
            value={newArtifactName}
            onChange={(e) => setNewArtifactName(e.target.value)}
            className="flex-1 glass-input rounded-md px-2.5 py-1.5 text-xs font-mono placeholder:text-night-muted"
          />
          <select
            value={holderNode}
            onChange={(e) => setHolderNode(e.target.value as NodeId)}
            className="glass-input rounded-md px-2 py-1.5 text-xs font-mono"
          >
            <option value="desktop">@desktop</option>
            <option value="laptop">@laptop</option>
            <option value="steamdeck">@steamdeck</option>
          </select>
          <input
            type="number"
            value={ttl}
            onChange={(e) => setTtl(Number(e.target.value) || 600)}
            title="TTL in seconds"
            className="w-16 glass-input rounded-md px-2 py-1.5 text-xs font-mono"
          />
          <button
            type="submit"
            disabled={isSubmitting || !newArtifactName.trim()}
            className="px-2.5 py-1.5 rounded-md bg-night-blue hover:bg-night-blue/80 text-night-bg text-xs font-mono font-bold flex items-center gap-1 disabled:opacity-40 transition-colors"
          >
            <Plus className="w-3.5 h-3.5" /> Lock
          </button>
        </form>
      </div>

      {/* Active Leases List */}
      <div className="flex-1 min-h-0 overflow-y-auto p-3 space-y-3 overscroll-contain">
        {leases.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center p-6 text-night-muted">
            <FileCode2 className="w-8 h-8 mb-2 text-night-yellow/40" />
            <p className="text-xs font-mono text-night-text">No Active Leases</p>
            <p className="text-[10px] text-night-muted mt-1">
              Artifacts are leased atomically across nodes during surgery to guarantee zero-conflict mutations.
            </p>
          </div>
        ) : (
          leases.map((lease) => {
            const now = Math.floor(Date.now() / 1000);
            const remaining = lease.expires_at ? Math.max(0, lease.expires_at - now) : 0;

            return (
              <div
                key={lease.artifact_name}
                className="glass-card rounded-lg p-3 border border-night-border/70 space-y-2"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-2 truncate">
                    <FileCode2 className="w-3.5 h-3.5 text-night-blue flex-shrink-0" />
                    <span className="font-mono text-xs font-bold text-night-text truncate">
                      {lease.artifact_name}
                    </span>
                  </div>
                  {getStatusBadge(lease.status)}
                </div>

                <div className="flex items-center justify-between text-[10px] font-mono text-night-muted">
                  <div>
                    Holder:{' '}
                    <span className="text-night-cyan font-bold">
                      @{lease.holder_node || 'none'}
                    </span>
                  </div>
                  {lease.status === 'LOCKED_SURGERY' && (
                    <div className="text-night-yellow">
                      TTL: <span className="font-bold">{remaining}s</span>
                    </div>
                  )}
                </div>

                {/* Checksum or Commit info */}
                {lease.checksum && (
                  <div className="text-[9px] font-mono text-night-muted truncate pt-1 border-t border-night-border/40">
                    Checksum: <span className="text-night-text">{lease.checksum}</span>
                  </div>
                )}

                {/* Release / Commit action button if currently locked */}
                {lease.status === 'LOCKED_SURGERY' && lease.holder_node && (
                  <div className="pt-2 flex justify-end">
                    <button
                      onClick={() =>
                        void onRelease(
                          lease.artifact_name,
                          lease.holder_node as NodeId,
                          'VERIFIED_COMMITTED'
                        )
                      }
                      className="text-[10px] font-mono px-2 py-1 rounded bg-night-green/20 hover:bg-night-green/30 text-night-green border border-night-green/40 flex items-center gap-1 transition-colors"
                    >
                      <Unlock className="w-3 h-3" /> Commit & Release
                    </button>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
