use std::fs;
use std::io::Cursor;
use std::path::PathBuf;
use std::process::Command;
use crate::models::ScrcpyStatus;

pub fn get_tools_dir() -> PathBuf {
    let mut dir = dirs::data_local_dir().unwrap_or_else(|| PathBuf::from("."));
    dir.push("F50Monitor");
    dir.push("Tools");
    dir
}

pub fn get_scrcpy_status() -> ScrcpyStatus {
    let tools_dir = get_tools_dir();
    let local_adb = tools_dir.join("adb.exe");
    let local_scrcpy = tools_dir.join("scrcpy.exe");

    let has_local_adb = local_adb.exists();
    let has_local_scrcpy = local_scrcpy.exists();

    let (adb_path, has_adb) = if has_local_adb {
        (Some(local_adb.to_string_lossy().to_string()), true)
    } else if let Ok(output) = Command::new("where").arg("adb").output() {
        if output.status.success() {
            (Some("adb".to_string()), true)
        } else {
            (None, false)
        }
    } else {
        (None, false)
    };

    let (scrcpy_path, has_scrcpy) = if has_local_scrcpy {
        (Some(local_scrcpy.to_string_lossy().to_string()), true)
    } else if let Ok(output) = Command::new("where").arg("scrcpy").output() {
        if output.status.success() {
            (Some("scrcpy".to_string()), true)
        } else {
            (None, false)
        }
    } else {
        (None, false)
    };

    ScrcpyStatus {
        has_adb,
        has_scrcpy,
        is_installed: has_adb && has_scrcpy,
        adb_path,
        scrcpy_path,
    }
}

pub async fn download_and_extract_scrcpy() -> Result<(), String> {
    let tools_dir = get_tools_dir();
    fs::create_dir_all(&tools_dir).map_err(|e| e.to_string())?;

    let download_url = "https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-win64-v3.1.zip";
    let client = reqwest::Client::new();
    let resp = client.get(download_url).send().await.map_err(|e| e.to_string())?;
    
    if !resp.status().is_success() {
        return Err(format!("Download failed with HTTP {}", resp.status()));
    }

    let bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    let cursor = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(cursor).map_err(|e| e.to_string())?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
        let filename = match file.enclosed_name() {
            Some(path) => path.to_owned(),
            None => continue,
        };

        // Flatten top directory
        let target_filename = filename.file_name().unwrap_or_default();
        if target_filename.is_empty() { continue; }

        let outpath = tools_dir.join(target_filename);
        if file.is_dir() {
            fs::create_dir_all(&outpath).map_err(|e| e.to_string())?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    fs::create_dir_all(p).map_err(|e| e.to_string())?;
                }
            }
            let mut outfile = fs::File::create(&outpath).map_err(|e| e.to_string())?;
            std::io::copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

pub fn launch_scrcpy(host: &str, port: u16) -> Result<(), String> {
    let status = get_scrcpy_status();
    let adb = status.adb_path.ok_or("ADB executable not found")?;
    let scrcpy = status.scrcpy_path.ok_or("scrcpy executable not found")?;

    let target = format!("{}:{}", host, port);

    // 1. adb connect <target>
    let connect_output = Command::new(&adb)
        .args(["connect", &target])
        .output()
        .map_err(|e| format!("Failed to run adb: {}", e))?;

    let out_str = String::from_utf8_lossy(&connect_output.stdout);
    if !out_str.contains("connected") && !out_str.contains("already connected") {
        return Err(format!("ADB connect failed: {}", out_str.trim()));
    }

    // 2. scrcpy -s <target> --no-audio
    Command::new(&scrcpy)
        .args(["-s", &target, "--no-audio"])
        .spawn()
        .map_err(|e| format!("Failed to spawn scrcpy: {}", e))?;

    Ok(())
}
