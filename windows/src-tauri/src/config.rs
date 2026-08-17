use std::fs;
use std::path::PathBuf;
use crate::models::F50Configuration;

pub fn get_config_dir() -> PathBuf {
    let mut dir = dirs::config_dir().unwrap_or_else(|| PathBuf::from("."));
    dir.push("F50Monitor");
    dir
}

pub fn get_config_path() -> PathBuf {
    let mut path = get_config_dir();
    path.push("config.json");
    path
}

pub fn load_config() -> F50Configuration {
    let path = get_config_path();
    if path.exists() {
        if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(config) = serde_json::from_str::<F50Configuration>(&content) {
                return config;
            }
        }
    }
    let default_config = F50Configuration::default();
    save_config(&default_config);
    default_config
}

pub fn save_config(config: &F50Configuration) {
    let dir = get_config_dir();
    let _ = fs::create_dir_all(&dir);
    let path = get_config_path();
    if let Ok(content) = serde_json::to_string_pretty(config) {
        let _ = fs::write(path, content);
    }
}
