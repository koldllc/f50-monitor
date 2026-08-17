use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, PhysicalPosition,
};

pub fn create_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show_i = MenuItem::with_id(app, "show", "显示/隐藏面板", true, None::<&str>)?;
    let ufi_i = MenuItem::with_id(app, "open_ufi", "打开 UFI 后台 (2333)", true, None::<&str>)?;
    let router_i = MenuItem::with_id(app, "open_router", "打开中兴后台 (80)", true, None::<&str>)?;
    let refresh_i = MenuItem::with_id(app, "refresh", "立即刷新", true, None::<&str>)?;
    let quit_i = MenuItem::with_id(app, "quit", "退出 F50 Monitor", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&show_i, &ufi_i, &router_i, &refresh_i, &quit_i])?;

    let mut tray_builder = TrayIconBuilder::new()
        .tooltip("F50 Monitor")
        .menu(&menu)
        .show_menu_on_left_click(false);

    if let Some(icon) = app.default_window_icon() {
        tray_builder = tray_builder.icon(icon.clone());
    }

    let _tray = tray_builder
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                toggle_window(app);
            }
            "open_ufi" => {
                let _ = tauri_plugin_opener::open_url("http://192.168.0.1:2333", None::<&str>);
            }
            "open_router" => {
                let _ = tauri_plugin_opener::open_url("http://192.168.0.1", None::<&str>);
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

pub fn toggle_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            // Position window at bottom right on Windows
            if let Ok(Some(monitor)) = window.primary_monitor() {
                let size = monitor.size();
                let win_width = 380;
                let win_height = 580;
                let x = size.width as i32 - win_width - 16;
                let y = size.height as i32 - win_height - 56; // Leave space for Windows taskbar
                let _ = window.set_position(PhysicalPosition::new(x, y));
            }
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}
