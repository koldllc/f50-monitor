use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use reqwest::header::{HeaderMap, HeaderValue, COOKIE, REFERER, CONTENT_TYPE};
use chrono::{Datelike, Local, NaiveDate, TimeZone};
use serde_json::Value;
use regex::Regex;

use crate::models::{F50Configuration, F50SMSMessage, F50Status};
use crate::crypto::{kano_sign, gsm_encode, percent_encode_form, base64_decode, base64_encode, sha256_hex, KANO_SIGN_KEY};

pub struct F50Fetcher {
    pub client: reqwest::Client,
    pub status: Arc<RwLock<F50Status>>,
    pub config: Arc<RwLock<F50Configuration>>,
    session_cookie: Arc<RwLock<Option<String>>>,
    prev_total_cpu: Arc<RwLock<f64>>,
    prev_idle_cpu: Arc<RwLock<f64>>,
    cached_valid_token: Arc<RwLock<Option<String>>>,
    last_traffic_refresh: Arc<RwLock<Option<Instant>>>,
    last_adb_hardware_refresh: Arc<RwLock<Option<Instant>>>,
    last_qos_refresh: Arc<RwLock<Option<Instant>>>,
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
            prev_total_cpu: Arc::new(RwLock::new(0.0)),
            prev_idle_cpu: Arc::new(RwLock::new(0.0)),
            cached_valid_token: Arc::new(RwLock::new(None)),
            last_traffic_refresh: Arc::new(RwLock::new(None)),
            last_adb_hardware_refresh: Arc::new(RwLock::new(None)),
            last_qos_refresh: Arc::new(RwLock::new(None)),
        }
    }

    pub fn is_ip_address(host: &str) -> bool {
        let parts: Vec<&str> = host.split('.').collect();
        if parts.len() == 4 && parts.iter().all(|p| p.parse::<u8>().is_ok()) {
            return true;
        }
        if host.contains(':') || (host.starts_with('[') && host.ends_with(']')) {
            return true;
        }
        false
    }

    pub fn get_endpoints_static(base_url: &str) -> (String, String) {
        let clean = base_url.trim().trim_end_matches('/');
        let with_scheme = if clean.contains("://") {
            clean.to_string()
        } else {
            format!("http://{}", clean)
        };

        if let Ok(parsed) = reqwest::Url::parse(&with_scheme) {
            let host = parsed.host_str().unwrap_or("192.168.0.1");
            let scheme = parsed.scheme();
            let is_ip = Self::is_ip_address(host);

            if let Some(port) = parsed.port() {
                if is_ip && port == 2333 {
                    (format!("{}://{}", scheme, host), format!("{}://{}:2333", scheme, host))
                } else {
                    (format!("{}://{}:{}", scheme, host, port), format!("{}://{}:{}", scheme, host, port))
                }
            } else {
                if is_ip {
                    (format!("{}://{}", scheme, host), format!("{}://{}:2333", scheme, host))
                } else {
                    (format!("{}://{}", scheme, host), format!("{}://{}", scheme, host))
                }
            }
        } else {
            ("http://192.168.0.1".to_string(), "http://192.168.0.1:2333".to_string())
        }
    }

    fn get_endpoints(&self, base_url: &str) -> (String, String) {
        Self::get_endpoints_static(base_url)
    }

    fn candidate_tokens(&self, ufi_token: &str, password: &str) -> Vec<String> {
        let mut tokens = Vec::new();
        let t1 = ufi_token.trim();
        if !t1.is_empty() {
            tokens.push(sha256_hex(t1));
            tokens.push(sha256_hex(&t1.to_lowercase()));
            tokens.push(sha256_hex(&t1.to_uppercase()));
            tokens.push(t1.to_string());
        }
        let t2 = password.trim();
        if !t2.is_empty() {
            tokens.push(sha256_hex(t2));
            tokens.push(sha256_hex(&t2.to_lowercase()));
            tokens.push(sha256_hex(&t2.to_uppercase()));
            tokens.push(t2.to_string());
        }
        tokens.push(sha256_hex("admin"));

        let mut unique = Vec::new();
        for t in tokens {
            if !unique.contains(&t) {
                unique.push(t);
            }
        }
        unique
    }

    pub(crate) fn diagnostic_candidate_tokens(&self, ufi_token: &str, password: &str) -> Vec<String> {
        self.candidate_tokens(ufi_token, password)
    }

    pub(crate) async fn diagnostic_session_cookie(&self) -> Option<String> {
        self.session_cookie.read().await.clone()
    }

    pub(crate) fn build_signed_ufi_headers(&self, path: &str, method: &str, token: &str) -> HeaderMap {
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
        let previous_status = self.status.read().await.clone();
        let mut status = previous_status.clone();
        let refresh_traffic = refresh_due(&self.last_traffic_refresh, Duration::from_secs(30)).await;

        let clean_for_check = if base_url.contains("://") { base_url.clone() } else { format!("http://{}", base_url.trim()) };
        let is_ip = if let Ok(parsed) = reqwest::Url::parse(&clean_for_check) {
            Self::is_ip_address(parsed.host_str().unwrap_or("192.168.0.1"))
        } else {
            true
        };

        let mut success = false;
        let mut router_payload: Option<Value> = None;
        let mut source_payload: Option<Value> = None;
        let tokens = self.candidate_tokens(&ufi_token, &password);

        if !is_ip {
            // 域名内网穿透优先走 UFI 2333 接口直连
            for token in &tokens {
                if let Ok(payload) = self.fetch_ufi_status(&ufi_base, token, refresh_traffic).await {
                    self.parse_status_payload(&mut status, &payload, false, refresh_traffic);
                    source_payload = Some(payload);
                    status.is_online = true;
                    status.error_message = None;
                    *self.cached_valid_token.write().await = Some(token.clone());
                    success = true;
                    break;
                }
            }
            if !success {
                if let Ok(payload) = self.fetch_router_status(&router_base, refresh_traffic).await {
                    self.parse_status_payload(&mut status, &payload, true, refresh_traffic);
                    source_payload = Some(payload.clone());
                    router_payload = Some(payload);
                    status.is_online = true;
                    status.error_message = None;
                    success = true;
                }
            }
        } else {
            // 本地 IP 优先走中兴 Router 80 端口
            match self.fetch_router_status(&router_base, refresh_traffic).await {
                Ok(payload) => {
                    self.parse_status_payload(&mut status, &payload, true, refresh_traffic);
                    source_payload = Some(payload.clone());
                    router_payload = Some(payload);
                    status.is_online = true;
                    status.error_message = None;
                    success = true;
                }
                Err(e) => {
                    if e.contains("401") || e.contains("auth") {
                        if self.perform_zte_login(&router_base, &password).await {
                            if let Ok(payload) = self.fetch_router_status(&router_base, refresh_traffic).await {
                                self.parse_status_payload(&mut status, &payload, true, refresh_traffic);
                                source_payload = Some(payload.clone());
                                router_payload = Some(payload);
                                status.is_online = true;
                                status.error_message = None;
                                success = true;
                            }
                        }
                    }
                }
            }

            if !success {
                for token in &tokens {
                    if let Ok(payload) = self.fetch_ufi_status(&ufi_base, token, refresh_traffic).await {
                        self.parse_status_payload(&mut status, &payload, false, refresh_traffic);
                        source_payload = Some(payload);
                        status.is_online = true;
                        status.error_message = None;
                        *self.cached_valid_token.write().await = Some(token.clone());
                        success = true;
                        break;
                    }
                }
            }
        }

        if !success {
            status.is_online = false;
            status.error_message = Some("无法连接中兴/UFI后台".to_string());
        }

        let qos_context_changed = requires_qos_refresh(&status, &previous_status);
        if qos_context_changed {
            // 承载上下文变化后不能继续展示旧 QCI，只保留本轮 80 端口明确返回的值。
            status.qci.clear();
            status.qos_dl.clear();
            status.qos_ul.clear();
            if let Some(payload) = source_payload.as_ref() {
                merge_payload_qos(&mut status, payload);
            }
        }

        // 3. 本地设备按字段执行 80 → 原生 ADB 5555 → UFI 2333 降级。
        if status.is_online {
            let router_has_hardware = router_payload.as_ref().is_some_and(payload_has_hardware);
            let router_has_qos = router_payload.as_ref().is_some_and(payload_has_qos);
            let source_has_hardware = source_payload.as_ref().is_some_and(payload_has_hardware);
            let source_has_qos = source_payload.as_ref().is_some_and(payload_has_qos);
            let (router_has_cpu, router_has_memory, router_has_temperature) = router_payload
                .as_ref()
                .map(payload_hardware_fields)
                .unwrap_or((false, false, false));
            let (router_has_qci, router_has_qos_dl, router_has_qos_ul) = router_payload
                .as_ref()
                .map(payload_qos_fields)
                .unwrap_or((false, false, false));
            let (source_has_cpu, source_has_memory, source_has_temperature) = source_payload
                .as_ref()
                .map(payload_hardware_fields)
                .unwrap_or((false, false, false));
            let (source_has_qci, source_has_qos_dl, source_has_qos_ul) = source_payload
                .as_ref()
                .map(payload_qos_fields)
                .unwrap_or((false, false, false));
            let hardware_missing = if is_ip { !router_has_hardware } else { !source_has_hardware };
            let qos_missing = if is_ip { !router_has_qos } else { !source_has_qos };
            let hardware_due = hardware_missing
                && refresh_due(&self.last_adb_hardware_refresh, Duration::from_secs(10)).await;
            let qos_due = qos_missing
                && (qos_context_changed
                    || refresh_due(&self.last_qos_refresh, Duration::from_secs(300)).await);

            if hardware_due {
                if !source_has_cpu { status.cpu_usage = 0.0; }
                if !source_has_memory { status.mem_usage = 0.0; }
                if !source_has_temperature { status.temperature = 0.0; }
            }
            if qos_due {
                if !source_has_qci { status.qci.clear(); }
                if !source_has_qos_dl { status.qos_dl.clear(); }
                if !source_has_qos_ul { status.qos_ul.clear(); }
            }

            if is_ip && (hardware_due || qos_due) {
                let host = reqwest::Url::parse(&router_base)
                    .ok()
                    .and_then(|url| url.host_str().map(str::to_string))
                    .unwrap_or_else(|| "192.168.0.1".to_string());
                let hardware_command = "for f in /sys/class/thermal/thermal_zone*; do [ -d \"$f\" ] || continue; type=; temp=; read -r type < \"$f/type\"; read -r temp < \"$f/temp\"; printf '%s:%s\\n' \"$type\" \"$temp\"; done; read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat; printf 'cpu %s %s %s %s %s %s %s %s %s %s\\n' \"$user\" \"$nice\" \"$system\" \"$idle\" \"$iowait\" \"$irq\" \"$softirq\" \"$steal\" \"$guest\" \"$guest_nice\"; while IFS= read -r line; do case \"$line\" in MemTotal:*|MemAvailable:*|MemFree:*|Buffers:*|Cached:*) printf '%s\\n' \"$line\";; esac; done < /proc/meminfo";
                let (hardware_output, qos_output) = tokio::join!(
                    async {
                        if hardware_due {
                            crate::adb::execute_shell(&host, hardware_command, 3).await
                        } else {
                            None
                        }
                    },
                    async {
                        if qos_due {
                            crate::adb::execute_at(&host, "AT+CGEQOSRDP=1").await
                        } else {
                            None
                        }
                    }
                );

                if hardware_due {
                    *self.last_adb_hardware_refresh.write().await = Some(Instant::now());
                }
                if qos_due {
                    *self.last_qos_refresh.write().await = Some(Instant::now());
                }
                if let Some(output) = hardware_output {
                    let mut adb_status = F50Status::default();
                    self.parse_linux_shell_output(&output, &mut adb_status).await;
                    if !router_has_cpu && adb_status.cpu_usage > 0.0 { status.cpu_usage = adb_status.cpu_usage; }
                    if !router_has_memory && adb_status.mem_usage > 0.0 { status.mem_usage = adb_status.mem_usage; }
                    if !router_has_temperature && adb_status.temperature > 0.0 { status.temperature = adb_status.temperature; }
                }
                if let Some(output) = qos_output {
                    if let Some((qci, dl, ul)) = parse_qos_response(&output) {
                        if !router_has_qci { status.qci = qci; }
                        if !router_has_qos_dl { status.qos_dl = dl; }
                        if !router_has_qos_ul { status.qos_ul = ul; }
                    }
                }
            }

            self.fetch_ufi_extensions(
                &ufi_base,
                &tokens,
                &mut status,
                refresh_traffic,
                hardware_due,
                qos_due,
            ).await;
            if hardware_due {
                *self.last_adb_hardware_refresh.write().await = Some(Instant::now());
            }
            if qos_due {
                *self.last_qos_refresh.write().await = Some(Instant::now());
            }
            if refresh_traffic {
                *self.last_traffic_refresh.write().await = Some(Instant::now());
            }
        }

        // 4. Update memory cache
        *self.status.write().await = status.clone();
        status
    }

    async fn perform_zte_login(&self, router_base: &str, password: &str) -> bool {
        if password.is_empty() { return false; }
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
        let ld_url = format!("{}/goform/goform_get_cmd_process?isTest=false&cmd=LD&_={}", router_base, ts);

        let ld_res = self.client.get(&ld_url)
            .header(REFERER, format!("{}/index.html", router_base))
            .send().await;

        let ld = match ld_res {
            Ok(resp) => {
                if let Ok(json) = resp.json::<Value>().await {
                    json.get("LD").and_then(|v| v.as_str()).unwrap_or("").to_string()
                } else {
                    String::new()
                }
            }
            Err(_) => String::new(),
        };

        if ld.is_empty() { return false; }

        let pwd_hash1 = sha256_hex(password);
        let pwd_hash2 = sha256_hex(&format!("{}{}", pwd_hash1, ld)).to_uppercase();

        let login_url = format!("{}/goform/goform_set_cmd_process", router_base);
        let body = format!("goformId=LOGIN&isTest=false&user=admin&password={}", pwd_hash2);

        let login_res = self.client.post(&login_url)
            .header(REFERER, format!("{}/index.html", router_base))
            .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
            .body(body)
            .send().await;

        if let Ok(resp) = login_res {
            if let Some(cookie) = resp.headers().get("Set-Cookie").and_then(|c| c.to_str().ok()) {
                let cookie_val = cookie.split(';').next().unwrap_or(cookie).to_string();
                *self.session_cookie.write().await = Some(cookie_val);
                return true;
            }
            if let Ok(json) = resp.json::<Value>().await {
                if let Some(r) = json.get("result").and_then(|v| v.as_i64()) {
                    if r == 0 || r == 3 { return true; }
                }
            }
        }
        false
    }

    async fn fetch_router_status(&self, router_base: &str, refresh_traffic: bool) -> Result<Value, String> {
        // V50 (MU3351) reports hardware metrics via temperature / cpu_temp;
        // keep ic_temp for older F50 firmware.
        let status_commands = "usb_port_switch,battery_charging,sms_received_flag,sms_unread_num,sms_sim_unread_num,sim_msisdn,battery_value,battery_vol_percent,network_signalbar,network_rssi,cr_version,iccid,imei,imsi,ipv6_wan_ipaddr,lan_ipaddr,mac_address,msisdn,network_information,Lte_ca_status,rssi,Z5g_rsrp,Z5g_snr,lte_rsrp,wifi_access_sta_num,loginfo,realtime_rx_thrpt,realtime_tx_thrpt,network_type,network_provider,ppp_status,temperature,cpu_temp,internal_temperature,ic_temp,cpu_utility,mem_utility,5g_rsrp,5g_rsrq,5g_snr,lte_rsrq,lte_snr,signalbar,qci,ambr,dl_ambr,ul_ambr";
        let traffic_commands = "realtime_rx_bytes,realtime_tx_bytes,monthly_tx_bytes,monthly_rx_bytes,day_rx_bytes,day_tx_bytes,data_volume_limit_size,data_volume_limit_unit,data_volume_clear_date,monthly_clear_date,billing_day,reset_day,traffic_clear_date,clear_date";
        let commands = if refresh_traffic {
            format!("{status_commands},{traffic_commands}")
        } else {
            status_commands.to_string()
        };
        
        let url = format!("{}/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd={}", router_base, commands);

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

    async fn fetch_ufi_status(&self, ufi_base: &str, token: &str, refresh_traffic: bool) -> Result<Value, String> {
        let status_commands = "status,battery_value,battery_charging,wifi_access_sta_num,network_provider,network_type,signalbar,network_signalbar,network_information,realtime_rx_thrpt,realtime_tx_thrpt,cpu_utility,mem_utility,ic_temp,cpu_temp,sms_unread_num,sms_sim_unread_num,qci,dl_ambr,ul_ambr,Z5g_rsrp,5g_rsrp,lte_rsrp,Z5g_snr,5g_snr,lte_snr,5g_rsrq,lte_rsrq,Nr_snr,nr_snr,sinr";
        let traffic_commands = "realtime_rx_bytes,realtime_tx_bytes,monthly_rx_bytes,monthly_tx_bytes,total_rx_bytes,total_tx_bytes,day_rx_bytes,day_tx_bytes,data_volume_limit_size,data_volume_limit_unit,data_volume_clear_date,monthly_clear_date";
        let commands = if refresh_traffic {
            format!("{status_commands},{traffic_commands}")
        } else {
            status_commands.to_string()
        };
        
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

    async fn fetch_ufi_extensions(
        &self,
        ufi_base: &str,
        candidate_tokens: &[String],
        status: &mut F50Status,
        refresh_traffic: bool,
        allow_hardware_fallback: bool,
        allow_qos_fallback: bool,
    ) {
        let needs_hardware = allow_hardware_fallback
            && (status.cpu_usage <= 0.0 || status.mem_usage <= 0.0 || status.temperature <= 0.0);
        if needs_hardware {
            let mut fallback = F50Status::default();
            self.fetch_linux_shell_metrics(ufi_base, candidate_tokens, &mut fallback).await;
            if status.cpu_usage <= 0.0 { status.cpu_usage = fallback.cpu_usage; }
            if status.mem_usage <= 0.0 { status.mem_usage = fallback.mem_usage; }
            if status.temperature <= 0.0 { status.temperature = fallback.temperature; }
        }

        let needs_qos = allow_qos_fallback
            && (status.qci.is_empty() || status.qos_dl.is_empty() || status.qos_ul.is_empty());
        if needs_qos {
            let mut fallback = F50Status::default();
            self.fetch_qos_metrics(ufi_base, candidate_tokens, &mut fallback).await;
            if status.qci.is_empty() { status.qci = fallback.qci; }
            if status.qos_dl.is_empty() { status.qos_dl = fallback.qos_dl; }
            if status.qos_ul.is_empty() { status.qos_ul = fallback.qos_ul; }
        }

        if refresh_traffic {
            self.fetch_cellular_usage_metrics(ufi_base, candidate_tokens, status).await;
        }
    }

    async fn fetch_linux_shell_metrics(&self, ufi_base: &str, candidate_tokens: &[String], status: &mut F50Status) {
        let candidate_paths = ["/api/root_shell", "/api/user_shell"];
        let cmd = "cat /proc/stat | grep \"cpu \"; cat /proc/meminfo | grep -E \"MemTotal|MemAvailable\"; for f in /sys/class/thermal/thermal_zone*; do echo \"$(cat $f/type 2>/dev/null):$(cat $f/temp 2>/dev/null)\"; done; cat /proc/net/dev 2>/dev/null | grep -E \"rmnet|wlan|eth|usb\"; dumpsys netstats 2>/dev/null | grep -i -E \"rmnet|wlan\" | head -n 30; cat /data/data/com.kano*/files/* 2>/dev/null; cat /sdcard/ufi* 2>/dev/null";
        let body = serde_json::json!({ "command": cmd });

        'path_loop: for path in candidate_paths {
            let url = format!("{}{}", ufi_base, path);
            for token in candidate_tokens {
                let mut headers = self.build_signed_ufi_headers(path, "POST", token);
                headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));

                let req = self.client.post(&url)
                    .headers(headers)
                    .json(&body);

                if let Ok(resp) = req.send().await {
                    let status_code = resp.status();
                    if status_code.is_success() {
                        if let Ok(json) = resp.json::<Value>().await {
                            let raw_output = if let Some(dict) = json.get("result").and_then(|r| r.as_object()) {
                                dict.get("content").and_then(|c| c.as_str()).unwrap_or("")
                            } else if let Some(s) = json.get("result").and_then(|r| r.as_str()) {
                                s
                            } else {
                                ""
                            };

                            if !raw_output.is_empty() {
                                self.parse_linux_shell_output(raw_output, status).await;
                                break 'path_loop;
                            }
                        }
                    } else if status_code.as_u16() == 404 {
                        break;
                    }
                }
            }
        }
    }

    async fn parse_linux_shell_output(&self, output: &str, status: &mut F50Status) {
        let lines: Vec<&str> = output.lines().collect();
        let mut max_soc_cpu_temp: f64 = 0.0;
        let mut fallback_temp: f64 = 0.0;
        let mut mem_total_kb: f64 = 0.0;
        let mut mem_avail_kb: f64 = 0.0;

        for line in lines {
            let trimmed = line.trim();

            // 1. CPU Stat Line
            if trimmed.starts_with("cpu ") {
                let parts: Vec<f64> = trimmed.split_whitespace()
                    .skip(1)
                    .filter_map(|s| s.parse::<f64>().ok())
                    .collect();
                if parts.len() >= 4 {
                    let total: f64 = parts.iter().sum();
                    let idle = parts[3] + if parts.len() > 4 { parts[4] } else { 0.0 };

                    let mut prev_total = self.prev_total_cpu.write().await;
                    let mut prev_idle = self.prev_idle_cpu.write().await;

                    if *prev_total > 0.0 {
                        let total_delta = total - *prev_total;
                        let idle_delta = idle - *prev_idle;
                        if total_delta > 0.0 {
                            let usage = ((1.0 - (idle_delta / total_delta)) * 100.0).clamp(0.0, 100.0);
                            status.cpu_usage = usage;
                        }
                    }
                    *prev_total = total;
                    *prev_idle = idle;
                }
            }

            // 2. Memory Lines
            if trimmed.starts_with("MemTotal:") {
                let clean = trimmed.replace("MemTotal:", "").replace("kB", "").trim().to_string();
                if let Ok(kb) = clean.parse::<f64>() {
                    mem_total_kb = kb;
                }
            }
            if trimmed.starts_with("MemAvailable:") {
                let clean = trimmed.replace("MemAvailable:", "").replace("kB", "").trim().to_string();
                if let Ok(kb) = clean.parse::<f64>() {
                    mem_avail_kb = kb;
                }
            }

            // 3. Thermal Zone Lines: "type:temp"
            if let Some((zone_type, zone_temp)) = trimmed.split_once(':') {
                let z_type = zone_type.trim();
                let z_temp = zone_temp.trim();
                if let Ok(raw_val) = z_temp.parse::<f64>() {
                    if raw_val > 0.0 {
                        let val_c = if raw_val > 1000.0 { raw_val / 1000.0 } else { raw_val };
                        if val_c > 10.0 && val_c < 120.0 {
                            if matches!(z_type, "soc-thmzone" | "nr0-thmzone" | "apcpu0-thmzone" | "apcpu1-thmzone" | "cpu-thmzone") {
                                if val_c > max_soc_cpu_temp {
                                    max_soc_cpu_temp = val_c;
                                }
                            } else if fallback_temp == 0.0 {
                                fallback_temp = val_c;
                            }
                        }
                    }
                }
            }
        }

        // Compute Memory %
        if mem_total_kb > 0.0 && mem_avail_kb > 0.0 {
            status.mem_usage = ((1.0 - (mem_avail_kb / mem_total_kb)) * 100.0).clamp(0.0, 100.0);
        }

        // Temperature selection
        let final_temp = if max_soc_cpu_temp > 0.0 { max_soc_cpu_temp } else { fallback_temp };
        if final_temp > 0.0 {
            status.temperature = final_temp;
        }
    }

    async fn fetch_qos_metrics(&self, ufi_base: &str, candidate_tokens: &[String], status: &mut F50Status) {
        let path = "/api/AT";
        let url = format!("{}{}?command=AT%2BCGEQOSRDP%3D1&slot=0", ufi_base, path);

        for token in candidate_tokens {
            let headers = self.build_signed_ufi_headers(path, "GET", token);
            if let Ok(resp) = self.client.get(&url).headers(headers).send().await {
                if resp.status().is_success() {
                    if let Ok(json) = resp.json::<Value>().await {
                        if let Some(res_str) = json.get("result").and_then(|r| r.as_str()) {
                            if let Some((qci, dl, ul)) = parse_qos_response(res_str) {
                                status.qci = qci;
                                status.qos_dl = dl;
                                status.qos_ul = ul;
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    async fn fetch_cellular_usage_metrics(&self, ufi_base: &str, candidate_tokens: &[String], status: &mut F50Status) {
        let now = Local::now();
        let today_start = Local.with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0).single();
        let month_start = Local.with_ymd_and_hms(now.year(), now.month(), 1, 0, 0, 0).single();

        let end_ts = now.timestamp_millis();

        if let Some(t_start) = today_start {
            let start_ts = t_start.timestamp_millis();
            if let Some(usage) = self.query_cellular_usage(ufi_base, start_ts, end_ts, candidate_tokens).await {
                status.ufi_daily_usage = usage;
            }
        }

        if let Some(m_start) = month_start {
            let start_ts = m_start.timestamp_millis();
            if let Some(usage) = self.query_cellular_usage(ufi_base, start_ts, end_ts, candidate_tokens).await {
                status.ufi_monthly_usage = usage;
            }
        }
    }

    async fn query_cellular_usage(&self, ufi_base: &str, start_ts: i64, end_ts: i64, candidate_tokens: &[String]) -> Option<u64> {
        let path = "/api/cellularUsage";
        let url = format!("{}{}?startTime={}&endTime={}&method=date-range", ufi_base, path, start_ts, end_ts);

        for token in candidate_tokens {
            let headers = self.build_signed_ufi_headers(path, "GET", token);
            if let Ok(resp) = self.client.get(&url).headers(headers).send().await {
                if resp.status().is_success() {
                    if let Ok(json) = resp.json::<Value>().await {
                        if let Some(arr) = json.get("usage").and_then(|u| u.as_array()) {
                            let total: u64 = arr.iter().filter_map(|row| row.get("usage").and_then(parse_u64)).sum();
                            return Some(total);
                        }
                    }
                }
            }
        }
        None
    }

    fn parse_status_payload(
        &self,
        status: &mut F50Status,
        payload: &Value,
        is_router: bool,
        refresh_traffic: bool,
    ) {
        // Lowercase key lookup map for case-insensitive access
        let mut map: HashMap<String, &Value> = HashMap::new();
        if let Some(obj) = payload.as_object() {
            for (k, v) in obj {
                map.insert(k.to_lowercase(), v);
            }
        }

        // 1. Network Type
        let raw_type = map.get("network_type").and_then(|v| v.as_str()).unwrap_or("").trim();
        let mut parsed_type = match raw_type {
            "20" => "5G SA".to_string(),
            "19" => "5G NSA".to_string(),
            "10" | "11" => "4G LTE".to_string(),
            s if s.contains("5G SA") || s.contains("5G_SA") => "5G SA".to_string(),
            s if s.contains("5G NSA") || s.contains("5G_NSA") => "5G NSA".to_string(),
            s if s.to_lowercase().contains("4g") || s.to_lowercase().contains("lte") => "4G LTE".to_string(),
            "5G" | "5g" => "5G".to_string(),
            s if !s.is_empty() && s != "0" => s.to_string(),
            _ => String::new(),
        };

        // Fallback refinement for network type using signal keys
        let has_nr = first_valid_signal_value(&map, &["nr_rsrp", "z5g_rsrp", "5g_rsrp"]).is_some();
        let has_lte = first_valid_signal_value(&map, &["lte_rsrp"]).is_some();

        if parsed_type.is_empty() || parsed_type == "0" || parsed_type == "5G" {
            if has_nr && !has_lte {
                parsed_type = "5G SA".to_string();
            } else if has_nr && has_lte {
                parsed_type = "5G NSA".to_string();
            } else if has_lte {
                parsed_type = "4G LTE".to_string();
            } else if parsed_type.is_empty() || parsed_type == "0" {
                parsed_type = "5G".to_string();
            }
        }
        status.network_type = parsed_type.clone();

        // Current Bands
        let current_bands = parse_current_bands(&map, &parsed_type);
        if !current_bands.is_empty() {
            status.current_bands = current_bands;
        }

        // Carrier / Provider
        if let Some(carrier) = map.get("network_provider").and_then(|v| v.as_str()) {
            if !carrier.trim().is_empty() {
                status.carrier = carrier.trim().to_string();
            }
        }

        // Signal Bar
        if let Some(bar) = map.get("signalbar").or_else(|| map.get("network_signalbar")).or_else(|| map.get("rssi")).and_then(|v| parse_i32(v)) {
            status.signal_bar = bar.clamp(0, 5);
        }

        // RSRP / SINR / RSRQ with case-insensitive and multi-key fallback
        let rsrp_keys = ["nr_rsrp", "z5g_rsrp", "5g_rsrp", "lte_rsrp", "nr_signal_strength"];
        let rsrq_keys = ["nr_rsrq", "z5g_rsrq", "5g_rsrq", "lte_rsrq"];
        let snr_keys = ["nr_snr", "z5g_snr", "5g_snr", "lte_snr", "sinr", "nr_sinr", "5g_sinr", "lte_sinr"];

        if let Some(rsrp) = first_valid_signal_value(&map, &rsrp_keys) {
            status.rsrp = format!("{:.0} dBm", rsrp);
        }
        if let Some(rsrq) = first_valid_signal_value(&map, &rsrq_keys) {
            status.rsrq = format!("{:.0} dB", rsrq);
        }
        if let Some(snr) = first_valid_signal_value(&map, &snr_keys) {
            status.snr = format!("{:.0} dB", snr);
        }

        // 80 端口直接返回的硬件与 QoS 字段拥有最高优先级。
        if let Some(value) = first_positive_metric(&map, &["cpu_utility", "cpu_usage", "cpu_percent", "cpu_rate", "cpu", "cpu_load"]) {
            status.cpu_usage = value.clamp(0.0, 100.0);
        }
        if let Some(value) = first_positive_metric(&map, &["mem_utility", "mem_usage", "mem_percent", "memory_rate", "memory", "mem_used_percent"]) {
            status.mem_usage = value.clamp(0.0, 100.0);
        }
        if let Some(mut value) = first_positive_metric(&map, &["cpu_temp", "temperature", "temp", "ic_temp", "soc_temp", "modem_temp", "internal_temperature", "chip_temp", "device_temp"]) {
            if value > 1000.0 { value /= 1000.0; }
            if value < 130.0 { status.temperature = value; }
        }
        merge_payload_qos(status, payload);

        // PPP Status
        if let Some(ppp) = map.get("ppp_status").and_then(|v| v.as_str()) {
            let clean = ppp.trim().to_lowercase();
            status.ppp_status = if clean == "connected" || clean == "connect" || clean == "1" {
                "已连接".to_string()
            } else if clean == "disconnected" || clean == "disconnect" || clean == "0" {
                "未连接".to_string()
            } else {
                ppp.to_string()
            };
        }

        // Speed Throughput
        let dl_speed = map.get("realtime_rx_thrpt").and_then(|v| parse_f64(v)).unwrap_or(0.0);
        let ul_speed = map.get("realtime_tx_thrpt").and_then(|v| parse_f64(v)).unwrap_or(0.0);
        status.dl_speed = dl_speed;
        status.ul_speed = ul_speed;

        status.dl_history.push(dl_speed);
        if status.dl_history.len() > 16 { status.dl_history.remove(0); }
        status.ul_history.push(ul_speed);
        if status.ul_history.len() > 16 { status.ul_history.remove(0); }

        // Connected Devices
        if let Some(sta) = map.get("wifi_access_sta_num").or_else(|| map.get("station_num")).and_then(|v| parse_i32(v)) {
            status.connected_devices = sta;
        }

        // SMS Unread
        if let Some(unread) = map.get("sms_unread_num").or_else(|| map.get("sms_sim_unread_num")).and_then(|v| parse_i32(v)) {
            status.sms_unread_count = unread;
        }

        // Battery
        if let Some(bat) = map.get("battery_value").or_else(|| map.get("battery_vol_percent")).and_then(|v| parse_i32(v)) {
            status.battery_value = bat;
        }
        if let Some(chg) = map.get("battery_charging").and_then(|v| v.as_str()) {
            status.is_charging = chg == "1" || chg.eq_ignore_ascii_case("true") || chg.eq_ignore_ascii_case("charging");
        }

        if refresh_traffic {
            // 流量统计独立 30 秒刷新，避免拖慢高频状态采集。
            if let Some(rx) = map.get("monthly_rx_bytes").and_then(|v| parse_u64(v)) {
                status.monthly_rx = rx;
                if is_router { status.package_rx = rx; }
            }
            if let Some(tx) = map.get("monthly_tx_bytes").and_then(|v| parse_u64(v)) {
                status.monthly_tx = tx;
                if is_router { status.package_tx = tx; }
            }
            status.package_total = status.package_rx + status.package_tx;

            if let Some(rx) = map.get("day_rx_bytes").or_else(|| map.get("today_rx_bytes")).and_then(|v| parse_u64(v)) {
                status.daily_rx = rx;
            }
            if let Some(tx) = map.get("day_tx_bytes").or_else(|| map.get("today_tx_bytes")).and_then(|v| parse_u64(v)) {
                status.daily_tx = tx;
            }

            let limit_size = map.get("data_volume_limit_size");
            let limit_unit = map.get("data_volume_limit_unit");
            if limit_size.is_some() {
                status.traffic_limit = parse_traffic_limit(limit_size.copied(), limit_unit.copied());
            }
        }

        // Reset Day
        let candidate_keys = [
            "traffic_clear_date", "data_volume_clear_date", "monthly_clear_date",
            "clear_date", "data_volume_reset_date", "billing_date",
            "data_volume_clear_day", "monthly_clear_day", "clear_day",
            "data_volume_reset_day", "billing_day", "reset_day",
            "monthly_reset_day", "traffic_clear_day"
        ];
        for k in candidate_keys {
            if let Some(val) = map.get(k) {
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

            let target_date = if current_day < reset_day {
                let mut day_to_use = reset_day as u32;
                while day_to_use > 28 && NaiveDate::from_ymd_opt(today.year(), today.month(), day_to_use).is_none() {
                    day_to_use -= 1;
                }
                NaiveDate::from_ymd_opt(today.year(), today.month(), day_to_use).unwrap_or(today)
            } else {
                let next_month = if today.month() == 12 { 1 } else { today.month() + 1 };
                let next_year = if today.month() == 12 { today.year() + 1 } else { today.year() };
                let mut day_to_use = reset_day as u32;
                while day_to_use > 28 && NaiveDate::from_ymd_opt(next_year, next_month, day_to_use).is_none() {
                    day_to_use -= 1;
                }
                NaiveDate::from_ymd_opt(next_year, next_month, day_to_use).unwrap_or(today)
            };

            let diff = (target_date - today).num_days();
            status.days_until_reset = Some(diff.max(0) as i32);
        }
    }

    pub async fn fetch_sms_messages(&self) -> Result<Vec<F50SMSMessage>, String> {
        let (base_url, password, ufi_token) = {
            let cfg = self.config.read().await;
            (cfg.base_url.clone(), cfg.password.clone(), cfg.ufi_token.clone())
        };

        let (_, ufi_base) = self.get_endpoints(&base_url);
        let path = "/api/goform/goform_get_cmd_process";
        let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
        let url = format!("{}{}?multi_data=1&isTest=false&cmd=sms_data_total&page=0&data_per_page=100&mem_store=1&tags=100&order_by=order%20by%20id%20desc&_={}", ufi_base, path, ts);

        let tokens = self.candidate_tokens(&ufi_token, &password);
        for token in &tokens {
            let headers = self.build_signed_ufi_headers(path, "GET", token);
            if let Ok(resp) = self.client.get(&url).headers(headers).send().await {
                if resp.status().is_success() {
                    if let Ok(json) = resp.json::<Value>().await {
                        if let Some(rows) = json.get("messages").and_then(|m| m.as_array()) {
                            let mut messages = Vec::new();
                            for row in rows {
                                let id = row.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                if id.is_empty() { continue; }
                                let number = row.get("number").and_then(|v| v.as_str()).unwrap_or("").to_string();
                                let raw_content = row.get("content").and_then(|v| v.as_str()).unwrap_or("");
                                let content = decode_sms_content(raw_content);

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
                            return Ok(messages);
                        }
                    }
                }
            }
        }

        Err("无法获取短信列表".to_string())
    }

    pub async fn send_sms(&self, number: &str, content: &str) -> Result<(), String> {
        let (base_url, password, ufi_token) = {
            let cfg = self.config.read().await;
            (cfg.base_url.clone(), cfg.password.clone(), cfg.ufi_token.clone())
        };

        let (_, ufi_base) = self.get_endpoints(&base_url);
        let tokens = self.candidate_tokens(&ufi_token, &password);

        let clean_num: String = number.chars().filter(|c| c.is_ascii_digit() || *c == '+').collect();
        let b64_body = base64_encode(content.as_bytes());

        let root_cmd = format!(
            "sub_id=$(content query --uri content://telephony/siminfo --projection _id --where \"sim_id>=0\" 2>/dev/null | grep -o \"_id=[0-9]*\" | head -n 1 | cut -d= -f2)\nif [ -z \"$sub_id\" ]; then sub_id=3; fi\nBODY=$(echo \"{}\" | base64 -d)\nservice call isms 6 i32 $sub_id s16 \"com.android.phone\" s16 \"null\" s16 \"{}\" s16 \"null\" s16 \"$BODY\" s16 \"null\" s16 \"null\" i32 1 || \\\nservice call isms 7 i32 $sub_id s16 \"com.android.phone\" s16 \"null\" s16 \"{}\" s16 \"null\" s16 \"$BODY\" s16 \"null\" s16 \"null\" i32 1 || \\\nservice call isms 5 i32 $sub_id s16 \"com.android.phone\" s16 \"null\" s16 \"{}\" s16 \"null\" s16 \"$BODY\" s16 \"null\" s16 \"null\" i32 1\n",
            b64_body, clean_num, clean_num, clean_num
        );

        for token in &tokens {
            // 策略 1：/api/root_shell
            let root_url = format!("{}/api/root_shell", ufi_base);
            let mut root_headers = self.build_signed_ufi_headers("/api/root_shell", "POST", token);
            root_headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
            let body_json = serde_json::json!({ "command": root_cmd });

            if let Ok(resp) = self.client.post(&root_url).headers(root_headers).json(&body_json).send().await {
                if resp.status().is_success() {
                    if let Ok(json) = resp.json::<Value>().await {
                        let res_str = json.get("result").and_then(|v| v.as_str()).unwrap_or("");
                        if res_str.contains("Result: Parcel") && !res_str.contains("Exception") {
                            return Ok(());
                        }
                    }
                }
            }

            // 策略 2：Goform
            let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
            let ver_url = format!("{}/api/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version&multi_data=1&isTest=false&_={}", ufi_base, ts);
            let ver_headers = self.build_signed_ufi_headers("/api/goform/goform_get_cmd_process", "GET", token);
            let ver_resp: Value = match self.client.get(&ver_url).headers(ver_headers).send().await {
                Ok(r) => r.json::<Value>().await.unwrap_or_default(),
                Err(_) => Value::Null,
            };
            let wa = ver_resp.get("wa_inner_version").or_else(|| ver_resp.get("wa_version")).and_then(|v| v.as_str()).unwrap_or("");
            let cr = ver_resp.get("cr_version").and_then(|v| v.as_str()).unwrap_or("");

            let rd_url = format!("{}/api/goform/goform_get_cmd_process?cmd=RD&isTest=false&_={}", ufi_base, ts);
            let rd_headers = self.build_signed_ufi_headers("/api/goform/goform_get_cmd_process", "GET", token);
            let rd_resp: Value = match self.client.get(&rd_url).headers(rd_headers).send().await {
                Ok(r) => r.json::<Value>().await.unwrap_or_default(),
                Err(_) => Value::Null,
            };
            let rd = rd_resp.get("RD").and_then(|v| v.as_str()).unwrap_or("");
            let ad = sha256_hex(&format!("{}{}", sha256_hex(&format!("{}{}", wa, cr)), rd)).to_uppercase();

            let now = Local::now();
            let tz_offset_hours = now.offset().local_minus_utc() / 3600;
            let tz_sign = if tz_offset_hours >= 0 { "+" } else { "-" };
            let raw_sms_time = format!("{};{}{}", now.format("%y;%m;%d;%H;%M;%S"), tz_sign, tz_offset_hours.abs());

            let clean_num: String = number.chars().filter(|c| !c.is_whitespace() && *c != '-' && *c != '(' && *c != ')').collect();
            let encoded_num = percent_encode_form(&clean_num);
            let encoded_time = percent_encode_form(&raw_sms_time);
            let gsm_body = gsm_encode(content);

            let mut form_parts = vec![
                "isTest=false".to_string(),
                "goformId=SEND_SMS".to_string(),
                "notCallback=true".to_string(),
                format!("Number={}", encoded_num),
                format!("sms_time={}", encoded_time),
                format!("MessageBody={}", gsm_body),
                "ID=-1".to_string(),
                "encode_type=UNICODE".to_string(),
            ];
            if !ad.is_empty() {
                form_parts.push(format!("AD={}", ad));
            }
            let send_body = form_parts.join("&");
            let send_url = format!("{}/api/goform/goform_set_cmd_process", ufi_base);

            let mut send_headers = self.build_signed_ufi_headers("/api/goform/goform_set_cmd_process", "POST", token);
            send_headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/x-www-form-urlencoded; charset=UTF-8"));

            if let Ok(send_res) = self.client.post(&send_url).headers(send_headers).body(send_body).send().await {
                if let Ok(send_json) = send_res.json::<Value>().await {
                    let result_int = send_json.get("result").and_then(|r| r.as_i64());
                    let result_str = send_json.get("result").and_then(|r| r.as_str());
                    if result_int == Some(0) || result_int == Some(3) || result_str == Some("0") || result_str == Some("3") || result_str == Some("success") {
                        return Ok(());
                    }
                }
            }
        }

        Err("短信发送失败，请检查口令与设备网络状态".to_string())
    }
}

// Helpers

async fn refresh_due(last_refresh: &RwLock<Option<Instant>>, interval: Duration) -> bool {
    last_refresh
        .read()
        .await
        .is_none_or(|instant| instant.elapsed() >= interval)
}

fn requires_qos_refresh(current: &F50Status, previous: &F50Status) -> bool {
    (current.is_online && !previous.is_online)
        || (current.ppp_status == "已连接" && previous.ppp_status != "已连接")
        || (current.carrier != previous.carrier && current.carrier != "未知")
        || (current.network_type != previous.network_type && !current.network_type.is_empty())
        || (current.current_bands != previous.current_bands && !current.current_bands.is_empty())
}

fn payload_map(payload: &Value) -> HashMap<String, &Value> {
    payload
        .as_object()
        .map(|object| {
            object
                .iter()
                .map(|(key, value)| (key.to_lowercase(), value))
                .collect()
        })
        .unwrap_or_default()
}

fn has_positive_metric(map: &HashMap<String, &Value>, keys: &[&str]) -> bool {
    first_positive_metric(map, keys).is_some()
}

fn first_positive_metric(map: &HashMap<String, &Value>, keys: &[&str]) -> Option<f64> {
    keys.iter().find_map(|key| {
        map.get(*key)
            .and_then(|value| parse_f64(value))
            .filter(|value| *value > 0.0)
    })
}

fn payload_has_hardware(payload: &Value) -> bool {
    let (cpu, memory, temperature) = payload_hardware_fields(payload);
    cpu && memory && temperature
}

fn payload_hardware_fields(payload: &Value) -> (bool, bool, bool) {
    let map = payload_map(payload);
    (
        has_positive_metric(&map, &["cpu_utility", "cpu_usage", "cpu_percent", "cpu_rate", "cpu", "cpu_load"]),
        has_positive_metric(&map, &["mem_utility", "mem_usage", "mem_percent", "memory_rate", "memory", "mem_used_percent"]),
        has_positive_metric(&map, &["cpu_temp", "temperature", "temp", "ic_temp", "soc_temp", "modem_temp", "internal_temperature", "chip_temp", "device_temp"]),
    )
}

fn clean_qos_value(value: Option<&&Value>) -> Option<String> {
    let raw = match value? {
        Value::String(value) => value.trim().to_string(),
        Value::Number(value) => value.to_string(),
        _ => return None,
    };
    let clean = raw
        .trim_start_matches("QCI")
        .trim_start_matches("qci")
        .trim()
        .trim_start_matches(':')
        .trim();
    (!clean.is_empty() && clean != "0" && clean != "null").then(|| clean.to_string())
}

fn payload_has_qos(payload: &Value) -> bool {
    let (qci, downlink, uplink) = payload_qos_fields(payload);
    qci && downlink && uplink
}

fn payload_qos_fields(payload: &Value) -> (bool, bool, bool) {
    let map = payload_map(payload);
    (
        clean_qos_value(map.get("qci").or_else(|| map.get("qci_val")).or_else(|| map.get("qos_qci"))).is_some(),
        clean_qos_value(map.get("qos_dl").or_else(|| map.get("qos_downlink"))).is_some(),
        clean_qos_value(map.get("qos_ul").or_else(|| map.get("qos_uplink"))).is_some(),
    )
}

fn merge_payload_qos(status: &mut F50Status, payload: &Value) {
    let map = payload_map(payload);
    if let Some(value) = clean_qos_value(map.get("qci").or_else(|| map.get("qci_val")).or_else(|| map.get("qos_qci"))) {
        status.qci = value;
    }
    if let Some(value) = clean_qos_value(map.get("qos_dl").or_else(|| map.get("qos_downlink"))) {
        status.qos_dl = value;
    }
    if let Some(value) = clean_qos_value(map.get("qos_ul").or_else(|| map.get("qos_uplink"))) {
        status.qos_ul = value;
    }
}

fn first_valid_signal_value(map: &HashMap<String, &Value>, keys: &[&str]) -> Option<f64> {
    for k in keys {
        if let Some(val) = map.get(*k) {
            if let Some(num) = parse_f64(val) {
                if num != 0.0 {
                    return Some(num);
                }
            }
        }
    }
    None
}

fn parse_current_bands(map: &HashMap<String, &Value>, network_type: &str) -> String {
    let lte_band = first_band(map, &["lte_ca_pcell_band", "wan_active_band", "lte_band"], "B");
    let nr_band = first_band(
        map,
        &["nr5g_action_band", "nr5g_action_nsa_band", "zcellinfo_band", "z5g_cellinfo_band", "nr_ca_pcell_band", "nr_bands"],
        "n",
    );

    if network_type == "5G NSA" {
        match (lte_band, nr_band) {
            (Some(lte), Some(nr)) => format!("{} + {}", lte, nr),
            (Some(lte), None) => lte,
            (None, Some(nr)) => nr,
            (None, None) => String::new(),
        }
    } else if network_type.starts_with("5G") {
        nr_band.or(lte_band).unwrap_or_default()
    } else {
        lte_band.unwrap_or_default()
    }
}

fn first_band(map: &HashMap<String, &Value>, keys: &[&str], prefix: &str) -> Option<String> {
    let re = Regex::new(r"\d+").ok()?;
    for k in keys {
        if let Some(val) = map.get(*k) {
            let s = match val {
                Value::String(s) => s.trim(),
                Value::Number(n) => return Some(format!("{}{}", prefix, n)),
                _ => continue,
            };
            if !s.is_empty() && s != "0" {
                if let Some(m) = re.find(s) {
                    return Some(format!("{}{}", prefix, m.as_str()));
                }
            }
        }
    }
    None
}

fn parse_qos_response(raw: &str) -> Option<(String, String, String)> {
    let clean = raw.replace('*', "");
    let parts: Vec<&str> = clean.split(',').map(|s| s.trim()).collect();
    if parts.len() >= 8 && parts[0].contains("+CGEQOSRDP:") {
        let qci_raw = parts[1].trim();
        let qci = qci_raw.trim_start_matches("QCI").trim_start_matches("qci").trim().trim_start_matches(':').trim().to_string();
        let dl_raw = parts[6];
        let ul_raw = parts[7].split_whitespace().next().unwrap_or("");
        let dl_kbps = dl_raw.parse::<f64>().ok()?;
        let ul_kbps = ul_raw.parse::<f64>().ok()?;

        let format_rate = |kbps: f64| -> String {
            if kbps >= 1000.0 {
                format!("{:.0}Mbps", kbps / 1000.0)
            } else {
                format!("{:.0}Kbps", kbps)
            }
        };

        return Some((qci, format_rate(dl_kbps), format_rate(ul_kbps)));
    }
    None
}

fn parse_i32(v: &Value) -> Option<i32> {
    if let Some(i) = v.as_i64() { return Some(i as i32); }
    if let Some(s) = v.as_str() {
        let clean: String = s.chars().filter(|c| c.is_ascii_digit() || *c == '-').collect();
        return clean.parse::<i32>().ok();
    }
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
        let digits: String = clean.chars().filter(|c| c.is_ascii_digit()).collect();
        return digits.parse::<u64>().ok();
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
        let digits: String = trimmed.chars().filter(|c| c.is_ascii_digit()).collect();
        if let Ok(d) = digits.parse::<i32>() {
            if (1..=31).contains(&d) { return Some(d); }
        }
    }
    None
}

fn parse_traffic_limit(size_val: Option<&Value>, unit_val: Option<&Value>) -> u64 {
    let size_str = match size_val {
        Some(Value::String(s)) => s.trim().to_string(),
        Some(Value::Number(n)) => n.to_string(),
        _ => return 0,
    };
    if size_str.is_empty() || size_str == "0" || size_str == "null" || size_str == "undefined" {
        return 0;
    }

    // 1. Check if size string contains underscore separators e.g. "1536_1", "100_1024" or "500_1"
    let parts: Vec<f64> = size_str.split('_').filter_map(|p| p.parse::<f64>().ok()).collect();
    if parts.len() >= 2 {
        let value = parts[0];
        if value > 0.0 {
            let sub_multiplier = if parts[1] > 0.0 { parts[1] } else { 1.0 };
            let bytes = value * sub_multiplier * 1024.0 * 1024.0;
            if bytes.is_finite() && bytes > 0.0 {
                return bytes as u64;
            }
        }
    }

    // 2. Single numeric size value with unit
    let unit_str = unit_val.and_then(|v| v.as_str()).unwrap_or("").trim().to_lowercase();
    let clean_size: String = size_str.chars().filter(|c| c.is_ascii_digit() || *c == '.').collect();
    let num_val: f64 = clean_size.parse().unwrap_or(0.0);
    if num_val <= 0.0 { return 0; }

    let multiplier: f64 = match unit_str.as_str() {
        "gb" | "1" | "g" => 1024.0 * 1024.0 * 1024.0,
        "mb" | "0" | "m" => 1024.0 * 1024.0,
        "tb" | "2" | "t" => 1024.0 * 1024.0 * 1024.0 * 1024.0,
        "kb" | "k" => 1024.0,
        "data" | "data_volume" | "size" => {
            if num_val < 1000.0 { 1024.0 * 1024.0 * 1024.0 } else { 1024.0 * 1024.0 }
        }
        _ if num_val > 1_000_000_000.0 => 1.0,
        _ if num_val > 100_000.0 => 1024.0,
        _ => 1024.0 * 1024.0 * 1024.0,
    };

    let total = num_val * multiplier;
    if total.is_finite() && total > 0.0 {
        total as u64
    } else {
        0
    }
}

fn format_sms_date(raw: &str) -> String {
    let parts: Vec<&str> = raw.split(',').collect();
    if parts.len() >= 6 {
        let year = parts[0];
        let month = parts[1];
        let day = parts[2];
        let hour = parts[3];
        let minute = parts[4];
        let second_raw = parts[5];
        let second = second_raw.split(|c| c == '+' || c == '-').next().unwrap_or(second_raw);

        let full_year = if year.len() == 2 { format!("20{}", year) } else { year.to_string() };
        let pad_month = if month.len() == 1 { format!("0{}", month) } else { month.to_string() };
        let pad_day = if day.len() == 1 { format!("0{}", day) } else { day.to_string() };
        let pad_hour = if hour.len() == 1 { format!("0{}", hour) } else { hour.to_string() };
        let pad_minute = if minute.len() == 1 { format!("0{}", minute) } else { minute.to_string() };
        let pad_second = if second.len() == 1 { format!("0{}", second) } else { second.to_string() };

        format!("{}-{}-{} {}:{}:{}", full_year, pad_month, pad_day, pad_hour, pad_minute, pad_second)
    } else {
        raw.to_string()
    }
}

fn decode_sms_content(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    // 1. Base64 解码（中兴 F50 / UFI 默认短信编码格式）
    if let Some(bytes) = base64_decode(trimmed) {
        if !bytes.is_empty() {
            if let Ok(utf8_str) = String::from_utf8(bytes.clone()) {
                if !utf8_str.is_empty() && utf8_str.chars().any(|c| !c.is_control()) {
                    return utf8_str;
                }
            }
            // UTF-16BE 解码备用
            if bytes.len() >= 2 && bytes.len() % 2 == 0 {
                let u16_units: Vec<u16> = bytes.chunks_exact(2)
                    .map(|chunk| ((chunk[0] as u16) << 8) | (chunk[1] as u16))
                    .collect();
                if let Ok(utf16_str) = String::from_utf16(&u16_units) {
                    if !utf16_str.is_empty() {
                        return utf16_str;
                    }
                }
            }
        }
    }

    // 2. Hex 解码备用（部分较旧固件可能以 hex 输出）
    if let Ok(bytes) = hex::decode(trimmed) {
        if let Ok(utf8_str) = String::from_utf8(bytes.clone()) {
            if !utf8_str.is_empty() {
                return utf8_str;
            }
        }
        if bytes.len() >= 2 && bytes.len() % 2 == 0 {
            let u16_units: Vec<u16> = bytes.chunks_exact(2)
                .map(|chunk| ((chunk[0] as u16) << 8) | (chunk[1] as u16))
                .collect();
            if let Ok(utf16_str) = String::from_utf16(&u16_units) {
                if !utf16_str.is_empty() {
                    return utf16_str;
                }
            }
        }
    }

    // 3. 原始字符串回退
    trimmed.to_string()
}
