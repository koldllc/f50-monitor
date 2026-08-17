use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct F50Status {
    pub is_online: bool,
    pub error_message: Option<String>,
    pub ufi_auth_failed: bool,

    pub network_type: String,
    pub signal_bar: i32,
    pub rsrp: String,
    pub rsrq: String,
    pub snr: String,
    pub carrier: String,
    pub current_bands: String,
    pub ppp_status: String,

    pub qci: String,
    pub qos_dl: String,
    pub qos_ul: String,

    pub dl_speed: f64,
    pub ul_speed: f64,
    pub dl_history: Vec<f64>,
    pub ul_history: Vec<f64>,

    pub connected_devices: i32,
    pub sms_unread_count: i32,
    pub cpu_usage: f64,
    pub mem_usage: f64,
    pub temperature: f64,

    pub battery_value: i32,
    pub is_charging: bool,

    pub monthly_rx: u64,
    pub monthly_tx: u64,
    pub daily_rx: u64,
    pub daily_tx: u64,
    pub traffic_limit: u64,
    pub package_rx: u64,
    pub package_tx: u64,
    pub package_total: u64,
    pub ufi_daily_usage: u64,
    pub ufi_monthly_usage: u64,
    pub traffic_reset_day: i32,
    pub days_until_reset: Option<i32>,
}

impl Default for F50Status {
    fn default() -> Self {
        Self {
            is_online: false,
            error_message: None,
            ufi_auth_failed: false,
            network_type: "5G SA".to_string(),
            signal_bar: 0,
            rsrp: "N/A".to_string(),
            rsrq: "N/A".to_string(),
            snr: "N/A".to_string(),
            carrier: "未知".to_string(),
            current_bands: String::new(),
            ppp_status: "未连接".to_string(),
            qci: String::new(),
            qos_dl: String::new(),
            qos_ul: String::new(),
            dl_speed: 0.0,
            ul_speed: 0.0,
            dl_history: Vec::new(),
            ul_history: Vec::new(),
            connected_devices: 0,
            sms_unread_count: 0,
            cpu_usage: 0.0,
            mem_usage: 0.0,
            temperature: 0.0,
            battery_value: -1,
            is_charging: false,
            monthly_rx: 0,
            monthly_tx: 0,
            daily_rx: 0,
            daily_tx: 0,
            traffic_limit: 0,
            package_rx: 0,
            package_tx: 0,
            package_total: 0,
            ufi_daily_usage: 0,
            ufi_monthly_usage: 0,
            traffic_reset_day: 0,
            days_until_reset: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct F50Configuration {
    pub base_url: String,
    pub password: String,
    pub ufi_token: String,
    pub refresh_interval: f64,
    pub display_mode: String,
    pub screen_mirroring_port: u16,
    pub launch_at_login: bool,
}

impl Default for F50Configuration {
    fn default() -> Self {
        Self {
            base_url: "http://192.168.0.1:2333".to_string(),
            password: "admin".to_string(),
            ufi_token: "admin".to_string(),
            refresh_interval: 2.0,
            display_mode: "图标 + 速率".to_string(),
            screen_mirroring_port: 5555,
            launch_at_login: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct F50SMSMessage {
    pub id: String,
    pub number: String,
    pub content: String,
    pub date_text: String,
    pub tag: String,
    pub is_unread: bool,
    pub is_outgoing: bool,
    pub did_fail_to_send: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScrcpyStatus {
    pub has_adb: bool,
    pub has_scrcpy: bool,
    pub is_installed: bool,
    pub adb_path: Option<String>,
    pub scrcpy_path: Option<String>,
}
