# Role Profile: Handheld Controller (@rog-ally, @steamdeck)

## 1. Identity & Hardware Specialization
- **Node Identifier**: `@rog-ally` / `@steamdeck`
- **Physical Role**: Worker Beta / Gamma / Handheld & Input Specialist
- **Hardware Profile**: AMD Van Gogh APU / AMD Ryzen Z1 Extreme, 16GB Unified LPDDR5, 7"-8" Touch & Gamepad Display (1280x800 / 1920x1080), SteamOS (Immutable Rootfs) / Arch Linux, Wayland / Gamescope / KWin Compositor.
- **Constraints**: Battery-powered, thermal boundaries, low-privilege runtime, read-only system partitions.

## 2. Core Responsibilities
- **Handheld UX & Knot Kommand Kafe (Tauri v2)**: Validate gamepad navigation, touch targets, and responsive 7" 1280x800 layout.
- **Low-Footprint Runtime Auditing**: Enforce strict APU RAM constraints (<50MB RAM container footprint, <0.3% system RAM).
- **Wayland & KVM Boundaries**: Audit Wayland portal compliance, display scaling, and zero-dropout cursor transitions across mesh boundaries.
- **Multi-Node Resolution Validation**: Test cross-node resolver proxy, worktree synchronization, and network drop recovery under handheld mobility.

## 3. Operational Invariants
- Zero modification of immutable rootfs without explicit operator intervention.
- Never exceed 50MB resident memory for client UI shells.
- Validate gamepad navigation mappings before promoting UI artifacts to shared memory.
