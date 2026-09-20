#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use serde_json::json;
use std::process::Command;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};
use tauri_plugin_notification::NotificationExt;

#[derive(Debug, Serialize, Deserialize)]
pub struct SystemTelemetry {
    pub ram_total_mb: u64,
    pub ram_used_mb: u64,
    pub ram_free_mb: u64,
    pub swap_total_mb: u64,
    pub swap_used_mb: u64,
    pub load_avg: Vec<f64>,
    pub is_handheld: bool,
    pub battery_percent: Option<f32>,
    pub on_ac: Option<bool>,
}

#[tauri::command]
fn knot_ping() -> &'static str {
    "pong"
}

#[tauri::command]
async fn execute_knot_cmd(command: String, args: Vec<String>) -> Result<String, String> {
    // Whitelist commands for security
    let allowed = ["status", "topology", "quota", "doctor", "task", "hub", "agent", "kafe", "chat"];
    if !allowed.iter().any(|&c| c == command) {
        return Err(format!("Command '{}' not permitted via Knot IPC bridge", command));
    }

    let mut cmd = Command::new("knot");
    cmd.arg(&command);
    for arg in args {
        cmd.arg(arg);
    }

    let output = cmd.output().map_err(|e| format!("Failed to execute knot: {}", e))?;
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if output.status.success() {
        Ok(stdout)
    } else {
        Err(format!("Exit code {}: {}", output.status.code().unwrap_or(-1), stderr))
    }
}

#[tauri::command]
async fn get_knot_status() -> Result<serde_json::Value, String> {
    let output = Command::new("knot")
        .arg("status")
        .output()
        .map_err(|e| format!("Failed to run knot status: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(json!({
        "status": if output.status.success() { "OK" } else { "ERROR" },
        "output": stdout
    }))
}

#[tauri::command]
async fn get_system_telemetry() -> Result<SystemTelemetry, String> {
    let mut total = 0u64;
    let mut free = 0u64;
    let mut swap_total = 0u64;
    let mut swap_free = 0u64;

    if let Ok(meminfo) = std::fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let key = parts[0];
                let val: u64 = parts[1].parse().unwrap_or(0);
                match key {
                    "MemTotal:" => total = val / 1024,
                    "MemAvailable:" | "MemFree:" if free == 0 => free = val / 1024,
                    "SwapTotal:" => swap_total = val / 1024,
                    "SwapFree:" => swap_free = val / 1024,
                    _ => {}
                }
            }
        }
    }

    let mut load = vec![0.0, 0.0, 0.0];
    if let Ok(loadavg) = std::fs::read_to_string("/proc/loadavg") {
        let parts: Vec<&str> = loadavg.split_whitespace().collect();
        if parts.len() >= 3 {
            load[0] = parts[0].parse().unwrap_or(0.0);
            load[1] = parts[1].parse().unwrap_or(0.0);
            load[2] = parts[2].parse().unwrap_or(0.0);
        }
    }

    // Handheld detection: Steam Deck APU or ROG Ally chassis
    let is_deck = std::path::Path::new("/sys/devices/virtual/dmi/id/product_name")
        .exists() && std::fs::read_to_string("/sys/devices/virtual/dmi/id/product_name")
            .map(|s| s.contains("Jupiter") || s.contains("Galileo") || s.contains("ROG Ally"))
            .unwrap_or(false);

    let (battery, on_ac) = if let Ok(capacity) = std::fs::read_to_string("/sys/class/power_supply/BAT1/capacity")
        .or_else(|_| std::fs::read_to_string("/sys/class/power_supply/BAT0/capacity")) {
        let pct: f32 = capacity.trim().parse().unwrap_or(0.0);
        let ac = std::fs::read_to_string("/sys/class/power_supply/ACAD/online")
            .or_else(|_| std::fs::read_to_string("/sys/class/power_supply/AC/online"))
            .map(|s| s.trim() == "1")
            .ok();
        (Some(pct), ac)
    } else {
        (None, None)
    };

    Ok(SystemTelemetry {
        ram_total_mb: total,
        ram_used_mb: total.saturating_sub(free),
        ram_free_mb: free,
        swap_total_mb: swap_total,
        swap_used_mb: swap_total.saturating_sub(swap_free),
        load_avg: load,
        is_handheld: is_deck,
        battery_percent: battery,
        on_ac,
    })
}

#[tauri::command]
async fn notify_task_event(app: tauri::AppHandle, title: String, body: String) -> Result<(), String> {
    app.notification()
        .builder()
        .title(title)
        .body(body)
        .show()
        .map_err(|e| format!("Notification error: {}", e))?;
    Ok(())
}

#[tauri::command]
async fn toggle_handheld_resolution(window: tauri::Window) -> Result<bool, String> {
    let current_size = window.outer_size().map_err(|e| e.to_string())?;
    // Toggle between 1280x800 and 1600x1000
    let is_currently_handheld = current_size.width == 1280 && current_size.height == 800;
    let target_width = if is_currently_handheld { 1600 } else { 1280 };
    let target_height = if is_currently_handheld { 1000 } else { 800 };

    window.set_size(tauri::Size::Physical(tauri::PhysicalSize {
        width: target_width,
        height: target_height,
    })).map_err(|e| e.to_string())?;

    Ok(!is_currently_handheld)
}

fn main() {
    let mut builder = tauri::Builder::default();

    builder = builder
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            // Build system tray menu
            let toggle_i = MenuItem::with_id(app, "toggle", "Show/Hide Knot Kafe", true, None::<&str>)?;
            let handheld_i = MenuItem::with_id(app, "handheld", "Handheld 1280x800", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "Quit Kafe", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&toggle_i, &handheld_i, &quit_i])?;

            let mut tray_builder = TrayIconBuilder::with_id("main-tray")
                .tooltip("Knot Kommand Kafe")
                .menu(&menu)
                .show_menu_on_left_click(false);

            if let Some(icon) = app.default_window_icon() {
                tray_builder = tray_builder.icon(icon.clone());
            } else {
                eprintln!("[warn] Default window icon not found for system tray; proceeding without icon");
            }

            let _tray = tray_builder
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "toggle" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let is_visible = window.is_visible().unwrap_or(false);
                            if is_visible {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                    "handheld" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.set_size(tauri::Size::Physical(tauri::PhysicalSize {
                                width: 1280,
                                height: 800,
                            }));
                        }
                    }
                    "quit" => {
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let is_visible = window.is_visible().unwrap_or(false);
                            if is_visible {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            knot_ping,
            execute_knot_cmd,
            get_knot_status,
            get_system_telemetry,
            notify_task_event,
            toggle_handheld_resolution
        ]);

    builder
        .run(tauri::generate_context!())
        .expect("error while running Knot Kommand Kafe");
}
