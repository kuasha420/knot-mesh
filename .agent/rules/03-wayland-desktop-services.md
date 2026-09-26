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
- **Zero-Interaction Trust Bootstrapping (`knot kdeconnect pair`):**
  - Uses existing Ed25519 SSH mesh credentials as out-of-band trust anchors.
  - Automatically requests and accepts pairings via DBus (`openKdeConnect -d <id> pair` and `acceptPairing`) without manual GUI confirmation prompts.
  - Automatically detects and prunes obsolete device identities caused by cryptographic key algorithm shifts (e.g. RSA to EC) via `knot kdeconnect prune-stale`.
- **KDE Plasma 6 Klipper DBus Pipeline:**
  - Authoritative Wayland clipboard transport uses `org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents` and `getClipboardContents`.
  - Transparent fallback to `wl-copy` / `wl-paste` when Klipper DBus is unreachable.
  - **Subshell Command Substitution Invariant**: NEVER wrap `wl-copy` directly in a bash command substitution subshell (e.g. `out=$(printf ... | wl-copy 2>&1)`). `wl-copy` forks into the background to serve selection requests and holds inherited file descriptors open, causing bash command substitution to hang indefinitely waiting for EOF. Klipper DBus calls execute synchronously in <10ms without background daemon forking hazards.
  - Full support for arbitrary large payloads (>21KB), multi-line snippets, and long URLs with query parameters.
- **Tier 1 D2D Continuous Self-Healing & Systemd Timer Invariant:**
  - Continuous pairing reconciliation belongs strictly to Tier 1 D2D physical workspace fabric; it must never be embedded in Tier 2 A2A cognitive agents (`knot-agent`).
  - Reconciler service (`knot-kdeconnect-reconcile.service`) must bind to `graphical-session.target` to access session DBus and compositor state.
  - Network roaming events trigger immediate background execution via `knot-guard` (`systemctl --user start --no-block knot-kdeconnect-reconcile.service`).
  - Auto-acceptance of pairing requests must enforce strict active swarm manifest verification and reciprocal Ed25519 SSH connectivity probes. Unrecognized devices on LAN are strictly ignored.
- **Cross-Strand Piping & Integrated Workflow Hooks:**
  - Operators and subagents can pipe clipboard payloads directly across nodes: `echo "payload" | knot kdeconnect share --target <node>`.
  - Fleet-wide broadcast: `knot kdeconnect sync-clipboard [--all]`.
  - E2E Automated Verification: `knot kdeconnect test-clipboard [--all]`.
  - Integrated into `knot auth login`: Pre-synchronizes device IP hints and broadcasts OAuth URLs / tokens across all screens immediately upon login.
  - Integrated into `knot-installer`: `knot-installer invite` automatically broadcasts enrollment tokens to the fleet clipboard; `knot-installer join` automatically detects clipboard tokens when omitted.

## 6. Multi-DPI Display Geometry Harmonization
- **Fractional Apertures**: When bridging monitors of different sizes or orientations, link only the physically overlapping fractions (e.g. `left(65,100)`, `down(45,85)`), never full 0-100% edges.
- **Logical Plane Alignment**: Match logical heights across neighboring screens (e.g. 1440p @ 200% scale $\rightarrow$ 720px; 1080p @ 150% scale $\rightarrow$ 720px) to ensure seamless horizontal movement without vertical jumps.
- **Cursor Sizing**: Standardize cursor visual proportions across nodes (e.g. 48px on 200% 4K/UW, 36px on 150% 1080p, 32px on 125% 800p).

## 7. Wayland Virtual Monitor Fabric (D2D Auxiliary Display Extension)
- **Host Output Creation**: Host creates dynamic headless Wayland outputs in KWin using `krdpserver` (from package `krdp`) with `--virtual-monitor <WIDTHxHEIGHT@SCALE> --plasma`. KWin tears down the virtual display output automatically when the process terminates.
- **Client Rendering**: Client renders the RDP stream via `krdc` (from `krdc` + `freerdp`), handling `rdp://` URI schemes passed via `QDesktopServices::openUrl()`.
- **Signaling & Ephemeral Security**:
  - Handled entirely over KDE Connect's TLS encrypted DBus interface (`org.kde.kdeconnect.device.virtualmonitor`).
  - Passwords are auto-generated single-use UUID tokens; zero manual credential entry or persistent shared secrets.
- **Subnet Port Invariant**: `krdpserver` listens on ports `5900-5910/tcp` (`knot-vmon`). Host firewalls (UFW/firewalld) must scope allow rules strictly to the local mesh subnet (`192.168.68.0/24`).
- **Host TLS Certificate Invariant**:
  - `krdpserver` will crash or refuse to start headless streaming without a valid TLS certificate configured at `~/.local/share/krdpserver/krdp.crt` and `krdp.key`, declared in `~/.config/krdpserverrc`.
  - `knot doctor` and `knot repair` automatically generate a 10-year RSA 2048 self-signed certificate via `kdeconnect_vmon_ensure_host_certs` and configure `ListeningPort=5900` via `kwriteconfig6`.
- **FreeRDP Dynamic Port Range Pre-Trust Invariant**:
  - In KDE Connect's `virtualmonitorplugin.cpp`, the listening port is dynamically incremented on every session (`static uint s_port = DEFAULT_PORT; s_port++`).
  - FreeRDP 3 strictly validates server certificates keyed by `~/.config/freerdp/server/<peer_ip>_<port>.pem`. Standard GUI certificate approval fails on subsequent connections because the port changes dynamically.
  - `knot display extend` and `knot kdeconnect vmon start` automatically pre-seed the target strand's FreeRDP certificate store over SSH, pushing the host `krdp.crt` and establishing symlinks across the entire dynamic port range `5900..5920` (`<peer_ip>_<port>.pem -> <peer_ip>.pem`).
- **Client Zero-Prompt Mode Invariant (`krdcrc`)**:
  - The client's `~/.config/krdcrc` must configure `ShowPreferencesForNewConnections=false` and `FullscreenOnConnect=true` under `[Preferences]` to bypass GUI prompt dialogs and guarantee immediate fullscreen virtual display presentation.
- **Remote Viewer Process Cleanup Invariant**:
  - Stopping a virtual monitor stream (`knot display stop` or `knot kdeconnect vmon stop`) must terminate the DBus stream on the host and issue a targeted remote SSH process cleanup (`pkill -f 'krdc.*rdp://.*<my_ip>'`) to cleanly close lingering KRDC viewer windows on the client strand without leaving orphaned windows.
- **Deskflow KVM Coexistence**:
  - **Mode A (Independent KVM Strand)**: Strand runs its local desktop session, and mouse/keyboard transit across screens via Deskflow KVM.
  - **Mode B (Auxiliary Desktop HUD)**: Strand displays the Anchor's headless virtual display full-screen via KRDC. The Anchor's desktop workspace expands directly onto the handheld or laptop display.


