import { useState, useEffect, useRef, useCallback } from 'react';

export interface GamepadActionState {
  dpadUp: boolean;
  dpadDown: boolean;
  dpadLeft: boolean;
  dpadRight: boolean;
  buttonA: boolean; // Confirm / Select
  buttonB: boolean; // Back / Cancel
  buttonX: boolean; // Action / Refresh
  buttonY: boolean; // Toggle Handheld Mode
  bumperLeft: boolean;  // Prev tab/column
  bumperRight: boolean; // Next tab/column
  triggerLeft: boolean;
  triggerRight: boolean;
  select: boolean;
  start: boolean;
}

export interface UseGamepadNavigationOptions {
  columnCount?: number;
  getColumnItemCount?: (colIndex: number) => number;
  onSelectAction?: (colIndex: number, itemIndex: number) => void;
  onBackAction?: () => void;
  onRefreshAction?: () => void;
  onPrevView?: () => void;
  onNextView?: () => void;
  enabled?: boolean;
}

export function useGamepadNavigation(options: UseGamepadNavigationOptions = {}) {
  const {
    columnCount = 5,
    getColumnItemCount,
    onSelectAction,
    onBackAction,
    onRefreshAction,
    onPrevView,
    onNextView,
    enabled = true,
  } = options;

  const [gamepadConnected, setGamepadConnected] = useState<boolean>(false);
  const [gamepadName, setGamepadName] = useState<string | null>(null);
  
  // Handheld mode state (auto-detected for 1280x800 Steam Deck / ROG Ally or manual override)
  const [handheldMode, setHandheldMode] = useState<boolean>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('knot_cockpit_handheld_mode');
      if (saved !== null) {
        return saved === 'true';
      }
      // Auto-detect 1280x800 or touch-primary screens
      const isDeckRes = (window.innerWidth === 1280 && window.innerHeight <= 800) ||
                        (window.screen.width === 1280 && window.screen.height <= 800);
      const isTouch = window.matchMedia('(pointer: coarse)').matches;
      return isDeckRes || (isTouch && window.innerWidth <= 1366);
    }
    return false;
  });

  const toggleHandheldMode = useCallback(() => {
    setHandheldMode((prev) => {
      const next = !prev;
      try {
        localStorage.setItem('knot_cockpit_handheld_mode', String(next));
      } catch (err) {
        console.warn('Unable to persist handheld mode preference:', err);
      }
      return next;
    });
  }, []);

  // Navigation indices
  const [selectedCol, setSelectedCol] = useState<number>(0);
  const [selectedCard, setSelectedCard] = useState<number>(0);

  // Keep refs for callback stability
  const optionsRef = useRef(options);
  optionsRef.current = options;
  const colRef = useRef(selectedCol);
  colRef.current = selectedCol;
  const cardRef = useRef(selectedCard);
  cardRef.current = selectedCard;

  // Rate limiting / cooldown for stick / d-pad inputs
  const lastInputTime = useRef<number>(0);
  const prevButtonStates = useRef<Record<number, boolean>>({});

  useEffect(() => {
    const handleConnected = (e: GamepadEvent) => {
      setGamepadConnected(true);
      setGamepadName(e.gamepad.id || 'Handheld Gamepad');
    };

    const handleDisconnected = () => {
      // Check if any other gamepad is still connected
      const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
      const anyRemaining = Array.from(gamepads).some((gp) => gp !== null);
      if (!anyRemaining) {
        setGamepadConnected(false);
        setGamepadName(null);
      }
    };

    window.addEventListener('gamepadconnected', handleConnected);
    window.addEventListener('gamepaddisconnected', handleDisconnected);

    // Initial check
    if (typeof navigator !== 'undefined' && navigator.getGamepads) {
      const gps = navigator.getGamepads();
      for (let i = 0; i < gps.length; i++) {
        if (gps[i]) {
          setGamepadConnected(true);
          setGamepadName(gps[i]?.id || 'Handheld Gamepad');
          break;
        }
      }
    }

    return () => {
      window.removeEventListener('gamepadconnected', handleConnected);
      window.removeEventListener('gamepaddisconnected', handleDisconnected);
    };
  }, []);

  // Main Gamepad Polling Loop
  useEffect(() => {
    if (!enabled) return;

    let animFrameId: number;

    const pollGamepad = () => {
      const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
      const gp = Array.from(gamepads).find((g) => g !== null && g.connected);

      if (gp) {
        const now = performance.now();
        const COOLDOWN_MS = 180;
        const canTriggerNav = now - lastInputTime.current > COOLDOWN_MS;

        // Standard Gamepad Mapping:
        // Buttons: 0: A/Cross, 1: B/Circle, 2: X/Square, 3: Y/Triangle
        // 4: L1/LB, 5: R1/RB, 6: L2/LT, 7: R2/RT
        // 8: Back/Select, 9: Start/Menu
        // 12: Dpad Up, 13: Dpad Down, 14: Dpad Left, 15: Dpad Right
        // Axes: 0: Left Stick X, 1: Left Stick Y
        const axesX = gp.axes[0] ?? 0;
        const axesY = gp.axes[1] ?? 0;
        const STICK_DEADZONE = 0.5;

        const isDpadLeft = (gp.buttons[14]?.pressed ?? false) || axesX < -STICK_DEADZONE;
        const isDpadRight = (gp.buttons[15]?.pressed ?? false) || axesX > STICK_DEADZONE;
        const isDpadUp = (gp.buttons[12]?.pressed ?? false) || axesY < -STICK_DEADZONE;
        const isDpadDown = (gp.buttons[13]?.pressed ?? false) || axesY > STICK_DEADZONE;

        const isBumperLeft = gp.buttons[4]?.pressed ?? false;
        const isBumperRight = gp.buttons[5]?.pressed ?? false;
        const isTriggerLeft = (gp.buttons[6]?.pressed ?? false) || (gp.buttons[6]?.value ?? 0) > 0.5;
        const isTriggerRight = (gp.buttons[7]?.pressed ?? false) || (gp.buttons[7]?.value ?? 0) > 0.5;

        const isBtnA = gp.buttons[0]?.pressed ?? false;
        const isBtnB = gp.buttons[1]?.pressed ?? false;
        const isBtnX = gp.buttons[2]?.pressed ?? false;
        const isBtnY = gp.buttons[3]?.pressed ?? false;

        // Handle Directional Navigation
        if (canTriggerNav) {
          if (isDpadLeft) {
            setSelectedCol((prev) => Math.max(0, prev - 1));
            setSelectedCard(0);
            lastInputTime.current = now;
          } else if (isDpadRight) {
            setSelectedCol((prev) => Math.min(columnCount - 1, prev + 1));
            setSelectedCard(0);
            lastInputTime.current = now;
          } else if (isDpadUp) {
            setSelectedCard((prev) => Math.max(0, prev - 1));
            lastInputTime.current = now;
          } else if (isDpadDown) {
            const count = getColumnItemCount ? getColumnItemCount(colRef.current) : 10;
            if (count > 0) {
              setSelectedCard((prev) => Math.min(count - 1, prev + 1));
              lastInputTime.current = now;
            }
          }
        }

        // Handle Bumpers for View / Column switching (L1/R1 or L2/R2)
        const prevL1 = prevButtonStates.current[4] ?? false;
        const prevR1 = prevButtonStates.current[5] ?? false;
        const prevL2 = prevButtonStates.current[6] ?? false;
        const prevR2 = prevButtonStates.current[7] ?? false;

        if (isBumperLeft && !prevL1) {
          if (onPrevView) onPrevView();
          else setSelectedCol((prev) => Math.max(0, prev - 1));
        }
        if (isBumperRight && !prevR1) {
          if (onNextView) onNextView();
          else setSelectedCol((prev) => Math.min(columnCount - 1, prev + 1));
        }

        if (isTriggerLeft && !prevL2 && onPrevView) {
          onPrevView();
        }
        if (isTriggerRight && !prevR2 && onNextView) {
          onNextView();
        }

        // Action Buttons with edge-triggering
        const prevA = prevButtonStates.current[0] ?? false;
        const prevB = prevButtonStates.current[1] ?? false;
        const prevX = prevButtonStates.current[2] ?? false;
        const prevY = prevButtonStates.current[3] ?? false;

        if (isBtnA && !prevA) {
          if (onSelectAction) {
            onSelectAction(colRef.current, cardRef.current);
          }
        }
        if (isBtnB && !prevB) {
          if (onBackAction) {
            onBackAction();
          }
        }
        if (isBtnX && !prevX) {
          if (onRefreshAction) {
            onRefreshAction();
          }
        }
        if (isBtnY && !prevY) {
          toggleHandheldMode();
        }

        // Update previous button states
        prevButtonStates.current[0] = isBtnA;
        prevButtonStates.current[1] = isBtnB;
        prevButtonStates.current[2] = isBtnX;
        prevButtonStates.current[3] = isBtnY;
        prevButtonStates.current[4] = isBumperLeft;
        prevButtonStates.current[5] = isBumperRight;
        prevButtonStates.current[6] = isTriggerLeft;
        prevButtonStates.current[7] = isTriggerRight;
      }

      animFrameId = requestAnimationFrame(pollGamepad);
    };

    animFrameId = requestAnimationFrame(pollGamepad);
    return () => cancelAnimationFrame(animFrameId);
  }, [
    enabled,
    columnCount,
    getColumnItemCount,
    onSelectAction,
    onBackAction,
    onRefreshAction,
    onPrevView,
    onNextView,
    toggleHandheldMode,
  ]);

  return {
    gamepadConnected,
    gamepadName,
    handheldMode,
    setHandheldMode,
    toggleHandheldMode,
    selectedCol,
    selectedCard,
    setSelectedCol,
    setSelectedCard,
  };
}
