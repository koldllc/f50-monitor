use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use reqwest::header::{HeaderMap, HeaderValue, COOKIE, REFERER, CONTENT_TYPE};
use chrono::{Datelike, Local, NaiveDate};
use serde_json::Value;

use crate::models::{F50Configuration, F50SMSMessage, F50Status};
use crate::crypto::{kano_sign, gsm_encode, sha256_hex, KANO_SIGN_KEY};

pub struct F50Fetcher {
    pub client: reqwest::Client,
    pub status: Arc<RwLock<F50Status>>,
    pub config: Arc<RwLock<F50Configuration>>,
    session_cookie: Arc<RwLock<Option<String>>>,
}

impl F50Fetcher {
    pub fn new(config: F50Configuration) -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(4))
            .build()
            .unwrap_or_default();

        Self {
            client,
            status: Arc::new(RwLock::new(F50Status::default())),
            config: Arc::new(RwLock::new(config)),
            session_cookie: Arc::new(RwLock::new(None)),
        }
    }

    fn get_endpoints(&self, base_url: &str) -> (String, String) {
        let clean = base_url.trim().trim_end_matches('/');
        let with_scheme = if clean.contains("://") {
            clean.to_string()
        } else {
            format!("http://{}", clean)
        };

        if let Ok(parsed) = reqwest::Url::parse(&with_scheme) {
            let host = parsed.host_str().unwrap_or("192.168.0.1");
            let scheme = parsed.scheme();
            (format!("{}://{}", scheme, host), format!("{}://{}:2333", scheme, host))
        } else {
            ("http://192.168.0.1".to_string(), "http://192.168.0.1:2333".to_string())
        }
    }

    fn build_signed_ufi_headers(&self, path: &str, method: &str, token: &str) -> HeaderMap {
        let mut headers = HeaderMap::new();
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
            .to_string();

        let sign = kano_sign(
            KANO_SIGN_KEY,
            &format!("minikano{}{}{}", method, path, ts),
        );

        if let Ok(v) = HeaderValue::from_str(&ts) {
            headers.insert("kano-t", v);
        }
        if let Ok(v) = HeaderValue::from_str(&sign) {
            headers.insert("kano-sign", v);
        }
        if let Ok(v) = HeaderValue::from_str(token) {
            headers.insert("authorization", v);
        }
        headers
    }

    pub async fn fetch_status(&self) -> F50Status {
        let (base_url, password, ufi_token) = {
            let cfg = self.config.read().await;
            (cfg.base_url.clone(), cfg.password.clone(), cfg.ufi_token.clone())
        };

        let (router_base, ufi_base) = self.get_endpoints(&base_url);

        // 1. Try ZTE Router 80 port
        let router_res = self.fetch_router_status(&router_base, &password).await;
        
        let mut status = self.status.read().await.clone();

        match router_res {
            Ok(payload) => {
                self.parse_status_payload(&mut status, &payload, true);
                status.is_online = true;
                status.error_message = None;
            }
            Err(_) => {
                // 2. Fallback to UFI 2333 port
                match self.fetch_ufi_status(&ufi_base, &ufi_token).await {
                    Ok(payload) => {
                        self.parse_status_payload(&mut status, &payload, false);
                        status.is_online = true;
                        status.error_message = None;
                    }
                    Err(err) => {
                        status.is_online = false;
                        status.error_message = Some(err);
                    }
                }
            }
        }

        // 3. Fetch extensions (Usage & QoS) if online
        if status.is_online {
            let _ = self.fetch_ufi_extensions(&ufi_base, &ufi_token, &mut status).await;
        }

        // 4. Update memory cache
        *self.status.write().await = status.clone();
        status
    }

    async fn fetch_router_status(&self, router_base: &str, _password: &str) -> Result<Value, String> {
        let status_commands = "usb_port_switch,battery_charging,sms_received_flag,sms_unread_num,sms_sim_unread_num,sim_msisdn,battery_value,battery_vol_percent,network_signalbar,network_rssi,cr_version,iccid,imei,imsi,ipv6_wan_ipaddr,lan_ipaddr,mac_address,msisdn,network_information,Lte_ca_status,rssi,Z5g_rsrp,Z5g_snr,lte_rsrp,wifi_access_sta_num,loginfo,realtime_rx_thrpt,realtime_tx_thrpt,network_type,network_provider,ppp_status,ic_temp,cpu_utility,mem_utility,5g_rsrp,5g_rsrq,5g_snr,lte_rsrq,lte_snr,signalbar,qci,ambr,dl_ambr,ul_ambr,realtime_rx_bytes,realtime_tx_bytes,monthly_tx_bytes,monthly_rx_bytes,day_rx_bytes,day_tx_bytes,data_volume_limit_size,data_volume_limit_unit,data_volume_clear_date,monthly_clear_date,billing_day,reset_day";
        
        let url = format!("{}/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd={}", router_base, status_commands);

        let mut req = self.client.get(&url)
            .header(REFERER, format!("{}/index.html", router_base));

        if let Some(cookie) = self.session_cookie.read().await.as_ref() {
            req = req.header(COOKIE, cookie);
        }

        let resp = req.send().await.map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            return Err(format!("Router HTTP {}", resp.status()));
        }

        let json: Value = resp.json().await.map_err(|e| e.to_string())?;
        Ok(json)
    }

    async fn fetch_ufi_status(&self, ufi_base: &str, token: &str) -> Result<Value, String> {
        let commands = "status,battery_value,battery_charging,wifi_access_sta_num,network_provider,network_type,signalbar,realtime_rx_thrpt,realtime_tx_thrpt,monthly_rx_bytes,monthly_tx_bytes,day_rx_bytes,day_tx_bytes,cpu_utility,mem_utility,ic_temp,cpu_temp,data_volume_limit_size,data_volume_limit_unit,data_volume_clear_date,monthly_clear_date,sms_unread_num,qci,dl_ambr,ul_ambr";
        
        let url = format!("{}/api/goform/goform_get_cmd_process?cmd={}&is_all=true", ufi_base, commands);
        let path = "/api/goform/goform_get_cmd_process";

        let headers = self.build_signed_ufi_headers(path, "GET", token);

        let resp = self.client.get(&url)
            .headers(headers)
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !resp.status().is_success() {
            return Err(format!("UFI HTTP {}", resp.status()));
        }

        let json: Value = resp.json().await.map_err(|e| e.to_string())?;
        Ok(json)
    }

    async fn fetch_ufi_extensions(&self, ufi_base: &str, token: &str, status: &mut F50Status) -> Result<(), String> {
        // 1. Fetch cellular usage for today and this month
        let usage_path = "/api/cellularUsage";
        let now = Local::now();
        let today_str = now.format("%Y-%m-%d").to_string();
        let first_day_month = format!("{}-{:02}-01", now.year(), now.month());

        // Monthly usage
        let month_url = format!("{}{}?start_date={}&end_date={}", ufi_base, usage_path, first_day_month, today_str);
        let month_headers = self.build_signed_ufi_headers(usage_path, "GET", token);
        if let Ok(resp) = self.client.get(&month_url).headers(month_headers).send().await {
            if let Ok(json) = resp.json::<Value>().await {
                if let Some(arr) = json.get("usage").and_then(|u| u.as_array()) {
                    let total: u64 = arr.iter().filter_map(|row| row.get("usage").and_then(|v| parse_u64(v))).sum();
                    status.ufi_monthly_usage = total;
                }
            }
        }

        // Daily usage
        let day_url = format!("{}{}?start_date={}&end_date={}", ufi_base, usage_path, today_str, today_str);
        let day_headers = self.build_signed_ufi_headers(usage_path, "GET", token);
        if let Ok(resp) = self.client.get(&day_url).headers(day_headers).send().await {
            if let Ok(json) = resp.json::<Value>().await {
                if let Some(arr) = json.get("usage").and_then(|u| u.as_array()) {
                    let total: u64 = arr.iter().filter_map(|row| row.get("usage").and_then(|v| parse_u64(v))).sum();
                    status.ufi_daily_usage = total;
                }
            }
        }

        Ok(())
    }

    fn parse_status_payload(&self, status: &mut F50Status, payload: &Value, is_router: bool) {
        // Network Type
        if let Some(net_type) = payload.get("network_type").and_then(|v| v.as_str()) {
            status.network_type = net_type.to_string();
        }

        // Carrier
        if let Some(carrier) = payload.get("network_provider").and_then(|v| v.as_str()) {
            status.carrier = carrier.to_string();
        }

        // Signal Bar
        if let Some(bar) = payload.get("signalbar").or_else(|| payload.get("network_signalbar")).and_then(|v| parse_i32(v)) {
            status.signal_bar = bar.clamp(0, 5);
        }

        // RSRP / SINR / RSRQ
        if let Some(rsrp) = payload.get("Z5g_rsrp").or_else(|| payload.get("5g_rsrp")).or_else(|| payload.get("lte_rsrp")).and_then(|v| parse_f64(v)) {
            if rsrp != 0.0 { status.rsrp = format!("{:.0} dBm", rsrp); }
        }
        if let Some(snr) = payload.get("Z5g_snr").or_else(|| payload.get("5g_snr")).or_else(|| payload.get("lte_snr")).and_then(|v| parse_f64(v)) {
            if snr != 0.0 { status.snr = format!("{:.0} dB", snr); }
        }
        if let Some(rsrq) = payload.get("5g_rsrq").or_else(|| payload.get("lte_rsrq")).and_then(|v| parse_f64(v)) {
            if rsrq != 0.0 { status.rsrq = format!("{:.0} dB", rsrq); }
        }

        // Speed Throughput
        let dl_speed = payload.get("realtime_rx_thrpt").and_then(|v| parse_f64(v)).unwrap_or(0.0);
        let ul_speed = payload.get("realtime_tx_thrpt").and_then(|v| parse_f64(v)).unwrap_or(0.0);
        status.dl_speed = dl_speed;
        status.ul_speed = ul_speed;

        status.dl_history.push(dl_speed);
        if status.dl_history.len() > 16 { status.dl_history.remove(0); }
        status.ul_history.push(ul_speed);
        if status.ul_history.len() > 16 { status.ul_history.remove(0); }

        // Connected Devices
        if let Some(sta) = payload.get("wifi_access_sta_num").and_then(|v| parse_i32(v)) {
            status.connected_devices = sta;
        }

        // SMS Unread
        if let Some(unread) = payload.get("sms_unread_num").or_else(|| payload.get("sms_sim_unread_num")).and_then(|v| parse_i32(v)) {
            status.sms_unread_count = unread;
        }

        // CPU / Mem / Temp
        if let Some(cpu) = payload.get("cpu_utility").or_else(|| payload.get("cpu_usage")).and_then(|v| parse_f64(v)) {
            if cpu > 0.0 { status.cpu_usage = cpu; }
        }
        if let Some(mem) = payload.get("mem_utility").or_else(|| payload.get("mem_usage")).and_then(|v| parse_f64(v)) {
            if mem > 0.0 { status.mem_usage = mem; }
        }
        if let Some(temp) = payload.get("ic_temp").or_else(|| payload.get("cpu_temp")).and_then(|v| parse_f64(v)) {
            if temp > 0.0 {
                status.temperature = if temp > 1000.0 { temp / 1000.0 } else { temp };
            }
        }

        // Traffic limits and package usage
        if let Some(rx) = payload.get("monthly_rx_bytes").and_then(|v| parse_u64(v)) {
            status.monthly_rx = rx;
            if is_router { status.package_rx = rx; }
        }
        if let Some(tx) = payload.get("monthly_tx_bytes").and_then(|v| parse_u64(v)) {
            status.monthly_tx = tx;
            if is_router { status.package_tx = tx; }
        }
        status.package_total = status.package_rx + status.package_tx;

        if let Some(rx) = payload.get("day_rx_bytes").and_then(|v| parse_u64(v)) { status.daily_rx = rx; }
        if let Some(tx) = payload.get("day_tx_bytes").and_then(|v| parse_u64(v)) { status.daily_tx = tx; }

        // Traffic limit
        let limit_size = payload.get("data_volume_limit_size");
        let limit_unit = payload.get("data_volume_limit_unit");
        if limit_size.is_some() {
            status.traffic_limit = parse_traffic_limit(limit_size, limit_unit);
        }

        // Reset Day
        let candidate_keys = [
            "data_volume_clear_date", "monthly_clear_date", "clear_date", 
            "billing_day", "reset_day", "traffic_clear_date"
        ];
        for k in candidate_keys {
            if let Some(val) = payload.get(k) {
                if let Some(day) = parse_reset_day(val) {
                    if (1..=31).contains(&day) {
                        status.traffic_reset_day = day;
                        break;
                    }
                }
            }
        }

        // Calculate days until reset
        if (1..=31).contains(&status.traffic_reset_day) {
            let today = Local::now().date_naive();
            let current_day = today.day() as i32;
            let reset_day = status.traffic_reset_day;

            let target_date = if current_day <= reset_day {
                NaiveDate::from_ymd_opt(today.year(), today.month(), reset_day as u32)
                    .unwrap_or(today)
            } else {
                let next_month = if today.month() == 12 { 1 } else { today.month() + 1 };
                let next_year = if today.month() == 12 { today.year() + 1 } else { today.year() };
                NaiveDate::from_ymd_opt(next_year, next_month, reset_day as u32)
                    .unwrap_or(today)
            };

            let diff = (target_date - today).num_days();
            status.days_until_reset = Some(diff.max(0) as i32);
        }
    }

    pub async fn fetch_sms_messages(&self) -> Result<Vec<F50SMSMessage>, String> {
        let (base_url, token) = {
            let cfg = self.config.read().await;
            (cfg.base_url.clone(), cfg.ufi_token.clone())
        };

        let (_, ufi_base) = self.get_endpoints(&base_url);
        let path = "/api/goform/goform_get_cmd_process";
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
        
        let url = format!("{}{}?multi_data=1&isTest=false&cmd=sms_data_total&page=0&data_per_page=100&mem_store=1&tags=100&order_by=order%20by%20id%20desc&_={}", ufi_base, path, ts);
        let headers = self.build_signed_ufi_headers(path, "GET", &token);

        let resp = self.client.get(&url).headers(headers).send().await.map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            return Err(format!("UFI SMS HTTP {}", resp.status()));
        }

        let json: Value = resp.json().await.map_err(|e| e.to_string())?;
        let rows = json.get("messages").and_then(|m| m.as_array()).ok_or("No messages found")?;

        let mut messages = Vec::new();
        for row in rows {
            let id = row.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
            if id.is_empty() { continue; }
            let number = row.get("number").and_then(|v| v.as_str()).unwrap_or("").to_string();
            let raw_content = row.get("content").and_then(|v| v.as_str()).unwrap_or("");
            
            // Try base64 decode
            let content = if let Ok(decoded) = hex::decode(raw_content) {
                String::from_utf8(decoded).unwrap_or_else(|_| raw_content.to_string())
            } else {
                raw_content.to_string()
            };

            let date_raw = row.get("date").and_then(|v| v.as_str()).unwrap_or("");
            let date_text = format_sms_date(date_raw);
            let tag = row.get("tag").and_then(|v| v.as_str()).unwrap_or("0").to_string();

            messages.push(F50SMSMessage {
                id,
                number,
                content,
                date_text,
                is_unread: tag == "1",
                is_outgoing: tag == "2" || tag == "3",
                did_fail_to_send: tag == "3",
                tag,
            });
        }

        Ok(messages)
    }

    pub async fn send_sms(&self, number: &str, content: &str) -> Result<(), String> {
        let (base_url, token) = {
            let cfg = self.config.read().await;
            (cfg.base_url.clone(), cfg.ufi_token.clone())
        };

        let (_, ufi_base) = self.get_endpoints(&base_url);
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();

        // 1. LD Challenge
        let ld_url = format!("{}/api/goform/goform_get_cmd_process?cmd=LD&isTest=false&_={}", ufi_base, ts);
        let ld_headers = self.build_signed_ufi_headers("/api/goform/goform_get_cmd_process", "GET", &token);
        let ld_resp: Value = self.client.get(&ld_url).headers(ld_headers).send().await
            .map_err(|e| e.to_string())?.json().await.map_err(|e| e.to_string())?;

        let ld = ld_resp.get("LD").and_then(|v| v.as_str()).ok_or("Failed to get LD challenge")?;

        // 2. Login
        let pwd_hash = sha256_hex(&format!("{}{}", sha256_hex(&token), ld)).to_uppercase();
        let login_body = format!("goformId=LOGIN&isTest=false&password={}&user=admin", pwd_hash);
        let login_url = format!("{}/api/goform/goform_set_cmd_process", ufi_base);

        let mut login_headers = self.build_signed_ufi_headers("/api/goform/goform_set_cmd_process", "POST", &token);
        login_headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/x-www-form-urlencoded; charset=UTF-8"));

        let login_res = self.client.post(&login_url).headers(login_headers).body(login_body).send().await
            .map_err(|e| e.to_string())?;

        let cookie = login_res.headers().get("kano-cookie")
            .and_then(|c| c.to_str().ok())
            .map(|s| s.split(';').next().unwrap_or(s).to_string())
            .ok_or("Failed to get kano-cookie")?;

        // 3. AD Signature
        let ver_url = format!("{}/api/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version&multi_data=1&isTest=false&_={}", ufi_base, ts);
        let mut ver_headers = self.build_signed_ufi_headers("/api/goform/goform_get_cmd_process", "GET", &token);
        ver_headers.insert(COOKIE, HeaderValue::from_str(&cookie).map_err(|e| e.to_string())?);

        let ver_resp: Value = self.client.get(&ver_url).headers(ver_headers).send().await
            .map_err(|e| e.to_string())?.json().await.map_err(|e| e.to_string())?;

        let wa = ver_resp.get("wa_inner_version").and_then(|v| v.as_str()).unwrap_or("");
        let cr = ver_resp.get("cr_version").and_then(|v| v.as_str()).unwrap_or("");

        let rd_url = format!("{}/api/goform/goform_get_cmd_process?cmd=RD&isTest=false&_={}", ufi_base, ts);
        let mut rd_headers = self.build_signed_ufi_headers("/api/goform/goform_get_cmd_process", "GET", &token);
        rd_headers.insert(COOKIE, HeaderValue::from_str(&cookie).map_err(|e| e.to_string())?);

        let rd_resp: Value = self.client.get(&rd_url).headers(rd_headers).send().await
            .map_err(|e| e.to_string())?.json().await.map_err(|e| e.to_string())?;

        let rd = rd_resp.get("RD").and_then(|v| v.as_str()).unwrap_or("");
        let ad = sha256_hex(&format!("{}{}", sha256_hex(&format!("{}{}", wa, cr)), rd)).to_uppercase();

        // 4. Send SMS POST
        let gsm_body = gsm_encode(content);
        let send_body = format!("goformId=SEND_SMS&Number={}&MessageBody={}&isTest=false&AD={}", number, gsm_body, ad);
        let send_url = format!("{}/api/goform/goform_set_cmd_process", ufi_base);

        let mut send_headers = self.build_signed_ufi_headers("/api/goform/goform_set_cmd_process", "POST", &token);
        send_headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/x-www-form-urlencoded; charset=UTF-8"));
        send_headers.insert(COOKIE, HeaderValue::from_str(&cookie).map_err(|e| e.to_string())?);

        let send_res = self.client.post(&send_url).headers(send_headers).body(send_body).send().await
            .map_err(|e| e.to_string())?;

        let send_json: Value = send_res.json().await.map_err(|e| e.to_string())?;
        if send_json.get("result").and_then(|r| r.as_i64()) == Some(0) {
            Ok(())
        } else {
            Err("SMS send returned failure code".to_string())
        }
    }
}

// Helpers
fn parse_i32(v: &Value) -> Option<i32> {
    if let Some(i) = v.as_i64() { return Some(i as i32); }
    if let Some(s) = v.as_str() { return s.trim().parse::<i32>().ok(); }
    None
}

fn parse_u64(v: &Value) -> Option<u64> {
    if let Some(u) = v.as_u64() { return Some(u); }
    if let Some(i) = v.as_i64() { return Some(i.max(0) as u64); }
    if let Some(s) = v.as_str() {
        let clean = s.trim();
        if clean.starts_with("0x") || clean.starts_with("0X") {
            return u64::from_str_radix(&clean[2..], 16).ok();
        }
        return clean.parse::<u64>().ok();
    }
    None
}

fn parse_f64(v: &Value) -> Option<f64> {
    if let Some(f) = v.as_f64() { return Some(f); }
    if let Some(i) = v.as_i64() { return Some(i as f64); }
    if let Some(s) = v.as_str() {
        let clean = s.replace("dBm", "").replace("dB", "").replace("℃", "").replace('%', "");
        return clean.trim().parse::<f64>().ok();
    }
    None
}

fn parse_reset_day(v: &Value) -> Option<i32> {
    if let Some(i) = v.as_i64() { return Some(i as i32); }
    if let Some(s) = v.as_str() {
        let trimmed = s.trim();
        if let Ok(d) = trimmed.parse::<i32>() { return Some(d); }
        if let Ok(date) = NaiveDate::parse_from_str(trimmed, "%Y-%m-%d") {
            return Some(date.day() as i32);
        }
    }
    None
}

fn parse_traffic_limit(size_val: Option<&Value>, unit_val: Option<&Value>) -> u64 {
    let size_str = size_val.and_then(|v| v.as_str()).unwrap_or("").trim();
    if size_str.is_empty() || size_str == "0" { return 0; }

    let unit_str = unit_val.and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
    let num_val: f64 = size_str.parse().unwrap_or(0.0);
    if num_val <= 0.0 { return 0; }

    let multiplier = match unit_str.as_str() {
        "gb" | "1" | "g" => 1024.0 * 1024.0 * 1024.0,
        "mb" | "0" | "m" => 1024.0 * 1024.0,
        "tb" | "2" | "t" => 1024.0 * 1024.0 * 1024.0 * 1024.0,
        _ => 1024.0 * 1024.0 * 1024.0,
    };

    (num_val * multiplier) as u64
}

fn format_sms_date(raw: &str) -> String {
    let parts: Vec<&str> = raw.split(',').collect();
    if parts.len() >= 6 {
        format!("{}-{}-{} {}:{}:{}", parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
    } else {
        raw.to_string()
    }
}
