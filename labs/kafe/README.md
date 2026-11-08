# Knot Kafe (Quarantined Experimental Cockpit)

> [!WARNING]
> **Quarantine Notice**: Knot Kafe (Tauri v2 + React 19 web cockpit) is quarantined under `labs/kafe/` and decoupled from Knot's core headless mesh packaging and default runtime dependencies.
> It is preserved here for R&D, experimentation, and standalone UI development.

---

## Architecture

- **`web/`**: Vite + React 19 + Tailwind CSS + `@assistant-ui` cockpit.
- **`src-tauri/`**: Rust Tauri v2 desktop application wrapper.

---

## Local Development & Testing

### 1. Web Cockpit (Standalone Browser Mode)
To run the web interface directly in your browser with Hot Module Replacement (HMR):

```bash
pnpm --dir labs/kafe/web install
pnpm --dir labs/kafe/web dev
```

The web interface will be accessible at `http://localhost:5173`.

### 2. Tauri v2 Desktop Container
To build and run the native desktop window locally (requires Rust and WebKitGTK / GTK3):

```bash
# Ensure WebKitGTK and GTK3 are installed on Arch Linux:
sudo pacman -S --needed webkit2gtk-4.1 gtk3 cargo

# Run Tauri in development mode:
cd labs/kafe/src-tauri
cargo tauri dev
```

### 3. Production Build
```bash
# Build the web bundle:
pnpm --dir labs/kafe/web build

# Compile release desktop binary:
cargo build --release --manifest-path labs/kafe/src-tauri/Cargo.toml
```
