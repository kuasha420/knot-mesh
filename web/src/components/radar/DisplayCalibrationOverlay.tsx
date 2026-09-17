import React, { useState, useEffect } from 'react';
import { X, Monitor } from 'lucide-react';
import type { MeshTopologyOutput } from '../../types/knot';

export interface DisplayCalibrationOverlayProps {
  isOpen?: boolean;
  onClose?: () => void;
  nodeId?: string;
  outputs?: MeshTopologyOutput[];
  bg?: 'white' | 'black' | 'neon';
  duration?: number;
}

export const DisplayCalibrationOverlay: React.FC<DisplayCalibrationOverlayProps> = ({
  isOpen: initialIsOpen = false,
  onClose,
  nodeId = 'rog-ally',
  outputs = [],
  bg: initialBg = 'white',
  duration: initialDuration = 15,
}) => {
  const [active, setActive] = useState<boolean>(initialIsOpen);
  const [currentBg, setCurrentBg] = useState<'white' | 'black' | 'neon'>(initialBg);
  const [remainingSec, setRemainingSec] = useState<number>(initialDuration);

  // Sync prop changes
  useEffect(() => {
    setActive(initialIsOpen);
    if (initialIsOpen) {
      setRemainingSec(initialDuration);
    }
  }, [initialIsOpen, initialDuration]);

  // Listen for swarm-wide SSE events on /events or EventSource
  useEffect(() => {
    if (typeof window === 'undefined') return;

    let es: EventSource | null = null;
    try {
      es = new EventSource('/events');
      es.addEventListener('display_identify', (evt: MessageEvent) => {
        try {
          const payload = JSON.parse(evt.data);
          if (payload.bg) setCurrentBg(payload.bg);
          const dur = payload.duration || 15;
          setRemainingSec(dur);
          setActive(true);
        } catch (e) {
          console.error('Failed to parse display_identify event:', e);
        }
      });
    } catch (e) {
      console.warn('EventSource not supported or failed to connect:', e);
    }

    return () => {
      es?.close();
    };
  }, []);

  // Countdown timer
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => {
      setRemainingSec((prev) => {
        if (prev <= 1) {
          setActive(false);
          onClose?.();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [active, onClose]);

  // Keyboard shortcut ESC to dismiss
  useEffect(() => {
    if (!active) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setActive(false);
        onClose?.();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [active, onClose]);

  if (!active) return null;

  const bgStyles = {
    white: {
      container: 'bg-white text-black',
      border: 'border-black',
      badge: 'bg-black text-white',
      accent: 'text-blue-700',
      crosshair: '#000000',
      subText: 'text-neutral-700',
    },
    black: {
      container: 'bg-black text-white',
      border: 'border-white',
      badge: 'bg-white text-black',
      accent: 'text-cyan-400',
      crosshair: '#ffffff',
      subText: 'text-neutral-300',
    },
    neon: {
      container: 'bg-[#001408] text-[#00ff66]',
      border: 'border-[#00ff66]',
      badge: 'bg-[#00ff66] text-black font-bold',
      accent: 'text-[#39ff14]',
      crosshair: '#00ff66',
      subText: 'text-[#a3ffcb]',
    },
  }[currentBg];

  const screenRes = typeof window !== 'undefined' ? `${window.innerWidth}×${window.innerHeight}` : '1920×1080';
  const dpr = typeof window !== 'undefined' ? window.devicePixelRatio : 1.0;

  return (
    <div
      onClick={() => {
        setActive(false);
        onClose?.();
      }}
      className={`fixed inset-0 z-[9999] flex flex-col justify-between p-8 select-none cursor-pointer transition-colors duration-200 ${bgStyles.container}`}
      style={{ minHeight: '100vh', minWidth: '100vw' }}
    >
      {/* Corner Fiducials (+) for sub-pixel boundary detection */}
      <div className="absolute top-6 left-6 font-mono text-3xl font-black leading-none pointer-events-none">
        +
      </div>
      <div className="absolute top-6 right-6 font-mono text-3xl font-black leading-none pointer-events-none">
        +
      </div>
      <div className="absolute bottom-6 left-6 font-mono text-3xl font-black leading-none pointer-events-none">
        +
      </div>
      <div className="absolute bottom-6 right-6 font-mono text-3xl font-black leading-none pointer-events-none">
        +
      </div>

      {/* Center Reticle Crosshair */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 pointer-events-none opacity-30">
        <div className="w-24 h-24 border border-dashed rounded-full flex items-center justify-center border-current">
          <div className="w-1.5 h-1.5 rounded-full bg-current" />
        </div>
      </div>

      {/* Top Banner */}
      <div className="flex items-center justify-between z-10">
        <div className="flex items-center gap-3">
          <span className={`text-xs px-3 py-1 rounded-full uppercase tracking-widest font-mono font-bold ${bgStyles.badge}`}>
            KNOT VISION CALIBRATION
          </span>
          <span className={`text-sm font-mono ${bgStyles.subText}`}>
            Viewport: {screenRes} (Scale {dpr.toFixed(2)})
          </span>
        </div>
        <div className="flex items-center gap-4">
          <span className="text-sm font-mono font-semibold">
            Auto-close in {remainingSec}s [ESC or Click]
          </span>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setActive(false);
              onClose?.();
            }}
            className="p-1 rounded hover:opacity-75"
          >
            <X className="w-6 h-6" />
          </button>
        </div>
      </div>

      {/* Center Huge Machine-Readable Identification Card */}
      <div className="flex flex-col items-center justify-center my-auto text-center z-10">
        <div className="flex items-center gap-4 mb-2">
          <Monitor className="w-16 h-16 stroke-[2.5]" />
          <h1 className="text-7xl md:text-9xl font-black tracking-tight font-mono uppercase">
            {nodeId}
          </h1>
        </div>

        <p className={`text-2xl md:text-3xl font-mono font-bold mt-2 uppercase ${bgStyles.accent}`}>
          KNOT SWARM MESH NODE
        </p>

        {/* Display Output Details */}
        {outputs && outputs.length > 0 ? (
          <div className="flex flex-wrap items-center justify-center gap-4 mt-6">
            {outputs.map((out, idx) => (
              <div
                key={out.name || idx}
                className={`flex items-center gap-3 px-5 py-3 rounded-xl border-2 font-mono text-lg md:text-xl font-bold ${bgStyles.border}`}
              >
                <span>{out.name}</span>
                <span className={`text-sm px-2 py-0.5 rounded ${bgStyles.badge}`}>
                  {out.primary ? 'PRIMARY' : 'SECONDARY'}
                </span>
                <span className="text-base font-normal">
                  {out.resolution} @ {out.scale}x
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className={`mt-6 px-6 py-2 rounded-xl border-2 font-mono text-xl font-bold ${bgStyles.border}`}>
            PRIMARY DISPLAY • {screenRes} @ {dpr.toFixed(2)}x
          </div>
        )}
      </div>

      {/* Bottom Instructions */}
      <div className="flex items-center justify-between z-10 border-t-2 pt-4 font-mono text-xs md:text-sm border-current opacity-80">
        <div>
          <span>OPTIMAL PHOTO: Hold camera parallel to desk • Frame all screens • 1.5 - 2.5m distance</span>
        </div>
        <div>
          <span>PRESS ESC OR CLICK ANYWHERE TO DISMISS</span>
        </div>
      </div>
    </div>
  );
};
