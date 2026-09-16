# Knot Wayland Desktop Services & Multi-Device KVM Guardrails

These rules govern all Wayland service configurations, LayerShell overlay daemons, portal interactions, and input multiplexing within Knot.

## 1. Wayland Portal Seat Invariant (Zero Runtime Portal Toggling)
- **NEVER call `xdp_input_capture_session_disable()` or D-Bus `Disable()` on an active KWin Wayland session.**
  - KWin's EIS implementation fails to emit `ReleaseAt()` when a session is disabled at runtime, wedging the Wayland input seat, hiding the hardware cursor, and freezing input routing.
- **Cursor confinement / locking MUST be handled via boundary topology nullification:**
  - In software KVM servers (Deskflow/Barrier), omit outbound links for the host screen in `section: links`.
  - The server registers zero pointer barriers with KWin, making boundary crossover physically impossible while leaving KWin's input seat completely untouched.
  - Restart the service via systemd user units (`systemctl --user restart knot-deskflow`). With persistent restore tokens, reloads execute in <10ms with zero display flicker.

## 2. Systemd Graphical Session Binding Invariant
- **NEVER bind Wayland, portal, or LayerShell user units to `default.target`.**
  - Units must wait for the compositor and session environment variables (`WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP`) to be fully initialized.
- **Always specify the full graphical session stanza:**
  ```ini
  [Unit]
  PartOf=graphical-session.target
  After=graphical-session.target
  Requisite=graphical-session.target

  [Install]
  WantedBy=graphical-session.target
  ```

## 3. LayerShell Absolute Bezel Alignment Invariant
- When rendering visual edge indicators or crossover strips that must touch physical screen bezels or overlay desktop panels:
  - Set `LayerShell.Window.layer: LayerShell.Window.LayerOverlay`
  - Set `LayerShell.Window.exclusionZone: -1`
- `exclusionZone: -1` tells the Wayland compositor to ignore panel reservations and position the surface relative to absolute display output coordinates ($Y=0$ to $Y=\text{Screen.height}-1$).
- Always set `LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone` and `flags: Qt.WindowTransparentForInput` so overlays never intercept user input.

## 4. Host vs. Strand Keybinding Architecture
- Background Wayland processes on the Anchor (desktop host) cannot intercept global keystrokes due to Wayland security boundaries.
- **Dual-Channel Strategy:**
  1. **Host Screen**: Capture key events via a passive, non-exclusive `evdev` reader in a user-level daemon (`knot-stripd`). Check that the active screen is the host before executing actions. Enforce a minimum 400ms debounce to reject hardware bounce.
  2. **Desktop Integration**: Deploy a `.desktop` entry in `~/.local/share/applications/` with `X-KDE-GlobalAccel-CommandShortcut=true` and register it in `kglobalshortcutsrc` so users can customize shortcuts through KDE System Settings.
  3. **Strand Screens**: Rely on Deskflow's built-in client keystroke actions (`keystroke(...) = lockCursorToScreen(toggle)`), which execute natively when input is captured on that node.

## 5. Separation of Concerns: KVM Input vs. Payload Sync
- **Software KVM is strictly for raw, zero-latency input multiplexing:**
  - Set `switchDelay = 0` and `clipboardSharing = false` in `deskflow-server.conf`.
  - Eliminate artificial edge pauses and network buffer stalls during screen crossovers.
- **Payload & Clipboard synchronization belongs to KDE Connect:**
  - All text clipboards, images, and file transfers are managed asynchronously over KDE Connect's full-mesh network without stalling mouse movement.

## 6. Multi-DPI Display Geometry Harmonization
- **Fractional Apertures**: When bridging monitors of different sizes or orientations, link only the physically overlapping fractions (e.g. `left(65,100)`, `down(45,85)`), never full 0-100% edges.
- **Logical Plane Alignment**: Match logical heights across neighboring screens (e.g. 1440p @ 200% scale $\rightarrow$ 720px; 1080p @ 150% scale $\rightarrow$ 720px) to ensure seamless horizontal movement without vertical jumps.
- **Cursor Sizing**: Standardize cursor visual proportions across nodes (e.g. 48px on 200% 4K/UW, 36px on 150% 1080p, 32px on 125% 800p).
