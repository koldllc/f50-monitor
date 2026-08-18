// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let msg = format!("F50 Monitor Panic:\n{}", info);
        eprintln!("{}", msg);
        if let Some(dir) = dirs::data_local_dir() {
            let app_dir = dir.join("F50Monitor");
            let _ = std::fs::create_dir_all(&app_dir);
            let _ = std::fs::write(app_dir.join("crash.log"), &msg);
        }
        #[cfg(target_os = "windows")]
        unsafe {
            use windows::core::HSTRING;
            use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};
            MessageBoxW(None, &HSTRING::from(msg), &HSTRING::from("F50 Monitor Error"), MB_OK | MB_ICONERROR);
        }
    }));

    if let Err(e) = f50_monitor_lib::run() {
        let msg = format!("F50 Monitor Startup Error:\n{}", e);
        eprintln!("{}", msg);
        if let Some(dir) = dirs::data_local_dir() {
            let app_dir = dir.join("F50Monitor");
            let _ = std::fs::create_dir_all(&app_dir);
            let _ = std::fs::write(app_dir.join("crash.log"), &msg);
        }
        #[cfg(target_os = "windows")]
        unsafe {
            use windows::core::HSTRING;
            use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};
            MessageBoxW(None, &HSTRING::from(msg), &HSTRING::from("F50 Monitor Error"), MB_OK | MB_ICONERROR);
        }
    }
}
