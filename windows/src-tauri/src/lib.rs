pub mod models;
pub mod crypto;
pub mod config;
pub mod fetcher;
pub mod scrcpy;
pub mod autostart;
pub mod tray;

use std::sync::Arc;
use tauri::{AppHandle, State};
use models::{F50Configuration, F50SMSMessage, F50Status, ScrcpyStatus};
use fetcher::F50Fetcher;

#[tauri::command]
async fn get_status(fetcher: State<'_, Arc<F50Fetcher>>) -> Result<F50Status, String> {
    Ok(fetcher.fetch_status().await)
}

#[tauri::command]
async fn get_config(fetcher: State<'_, Arc<F50Fetcher>>) -> Result<F50Configuration, String> {
    Ok(fetcher.config.read().await.clone())
}

#[tauri::command]
async fn save_config(
    config: F50Configuration,
    fetcher: State<'_, Arc<F50Fetcher>>,
) -> Result<(), String> {
    config::save_config(&config);
    let _ = autostart::set_autostart(config.launch_at_login);
    *fetcher.config.write().await = config;
    Ok(())
}

#[tauri::command]
async fn get_sms_messages(fetcher: State<'_, Arc<F50Fetcher>>) -> Result<Vec<F50SMSMessage>, String> {
    fetcher.fetch_sms_messages().await
}

#[tauri::command]
async fn send_sms(
    number: String,
    content: String,
    fetcher: State<'_, Arc<F50Fetcher>>,
) -> Result<(), String> {
    fetcher.send_sms(&number, &content).await
}

#[tauri::command]
fn get_scrcpy_status() -> ScrcpyStatus {
    scrcpy::get_scrcpy_status()
}

#[tauri::command]
async fn download_scrcpy() -> Result<(), String> {
    scrcpy::download_and_extract_scrcpy().await
}

#[tauri::command]
async fn launch_scrcpy(
    port: u16,
    fetcher: State<'_, Arc<F50Fetcher>>,
) -> Result<(), String> {
    let base_url = fetcher.config.read().await.base_url.clone();
    let clean = base_url.replace("http://", "").replace("https://", "");
    let host = clean.split('/').next().unwrap_or("").split(':').next().unwrap_or("192.168.0.1");
    scrcpy::launch_scrcpy(host, port)
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    let _ = tauri_plugin_opener::open_url(&url, None::<&str>);
    Ok(())
}

#[tauri::command]
fn toggle_window(app: AppHandle) {
    tray::toggle_window(&app);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let initial_config = config::load_config();
    let fetcher = Arc::new(F50Fetcher::new(initial_config));
    let fetcher_for_tray = fetcher.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            tray::show_window(app);
        }))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--autostart"])))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .manage(fetcher)
        .setup(move |app| {
            let _ = tray::create_tray(app.handle());
            
            // Check if launched via autostart
            let args: Vec<String> = std::env::args().collect();
            let is_autostart = args.iter().any(|arg| arg == "--autostart");
            if !is_autostart {
                tray::show_window(app.handle());
            }

            // Background Polling Worker
            let fetcher_bg = fetcher_for_tray.clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    let interval = {
                        let cfg = fetcher_bg.config.read().await;
                        cfg.refresh_interval.max(1.0)
                    };
                    let _ = fetcher_bg.fetch_status().await;
                    tokio::time::sleep(std::time::Duration::from_secs_f64(interval)).await;
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_config,
            save_config,
            get_sms_messages,
            send_sms,
            get_scrcpy_status,
            download_scrcpy,
            launch_scrcpy,
            open_url,
            toggle_window
        ])
        .run(tauri::generate_context!())?;

    Ok(())
}
