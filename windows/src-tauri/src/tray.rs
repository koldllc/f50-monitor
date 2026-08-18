use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, PhysicalPosition,
};

pub fn create_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show_i = MenuItem::with_id(app, "show", "显示/隐藏面板", true, None::<&str>)?;
    let ufi_i = MenuItem::with_id(app, "open_ufi", "UFI后台（2333端口）", true, None::<&str>)?;
    let router_i = MenuItem::with_id(app, "open_router", "中兴后台（80端口）", true, None::<&str>)?;
    let refresh_i = MenuItem::with_id(app, "refresh", "立即刷新", true, None::<&str>)?;
    let quit_i = MenuItem::with_id(app, "quit", "退出 F50 Monitor", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&show_i, &ufi_i, &router_i, &refresh_i, &quit_i])?;

    let icon_img = tauri::image::Image::from_bytes(include_bytes!("../icons/32x32.png")).ok()
        .or_else(|| app.default_window_icon().cloned());

    let mut tray_builder = TrayIconBuilder::with_id("f50_tray")
        .tooltip("F50 Monitor")
        .menu(&menu)
        .show_menu_on_left_click(false);

    if let Some(icon) = icon_img {
        tray_builder = tray_builder.icon(icon);
    }

    let _tray = tray_builder
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                toggle_window(app);
            }
            "open_ufi" => {
                let app_clone = app.clone();
                tauri::async_runtime::spawn(async move {
                    let base_url = if let Some(fetcher) = app_clone.try_state::<std::sync::Arc<crate::fetcher::F50Fetcher>>() {
                        fetcher.config.read().await.base_url.clone()
                    } else {
                        "http://192.168.0.1:2333".to_string()
                    };
                    let clean = base_url.trim().trim_end_matches('/');
                    let host = clean.replace("http://", "").replace("https://", "").split(':').next().unwrap_or("192.168.0.1").to_string();
                    let _ = tauri_plugin_opener::open_url(format!("http://{}:2333", host), None::<&str>);
                });
            }
            "open_router" => {
                let app_clone = app.clone();
                tauri::async_runtime::spawn(async move {
                    let base_url = if let Some(fetcher) = app_clone.try_state::<std::sync::Arc<crate::fetcher::F50Fetcher>>() {
                        fetcher.config.read().await.base_url.clone()
                    } else {
                        "http://192.168.0.1".to_string()
                    };
                    let clean = base_url.trim().trim_end_matches('/');
                    let host = clean.replace("http://", "").replace("https://", "").split(':').next().unwrap_or("192.168.0.1").to_string();
                    let _ = tauri_plugin_opener::open_url(format!("http://{}", host), None::<&str>);
                });
            }
            "refresh" => {
                let app_clone = app.clone();
                tauri::async_runtime::spawn(async move {
                    if let Some(fetcher) = app_clone.try_state::<std::sync::Arc<crate::fetcher::F50Fetcher>>() {
                        let _ = fetcher.fetch_status().await;
                    }
                });
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
                toggle_window(app);
            }
        })
        .build(app)?;

    Ok(())
}

pub fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        // Position window at bottom right on Windows with DPI scaling support
        if let Ok(Some(monitor)) = window.primary_monitor() {
            let scale = monitor.scale_factor();
            let size = monitor.size();
            let mon_pos = monitor.position();
            let win_width = (380.0 * scale) as i32;
            let win_height = (580.0 * scale) as i32;
            let margin_x = (16.0 * scale) as i32;
            let margin_y = (64.0 * scale) as i32; // Space for Windows taskbar
            let x = mon_pos.x + size.width as i32 - win_width - margin_x;
            let y = mon_pos.y + size.height as i32 - win_height - margin_y;
            let _ = window.set_position(PhysicalPosition::new(x, y));
        }
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

pub fn toggle_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            show_window(app);
        }
    }
}
