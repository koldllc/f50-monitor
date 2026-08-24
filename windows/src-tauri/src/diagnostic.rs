use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use tokio::task::JoinSet;
use tokio::time::Duration;

use crate::crypto::{kano_sign, KANO_SIGN_KEY};
use crate::fetcher::F50Fetcher;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackSubmissionResult {
    message: String,
    issue_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointProbeResult {
    pub name: String,
    pub vendor: String,
    pub url: String,
    pub method: String,
    pub statusCode: u16,
    pub statusText: String,
    pub latencyMs: u128,
    pub contentType: String,
    pub serverHeader: String,
    pub responseSnippet: String,
    pub isSuccess: bool,
    pub authUsed: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScriptCallSignature {
    endpoint: String,
    source_script: String,
    method_candidates: Vec<String>,
    nearby_field_names: Vec<String>,
}

async fn probe_one(
    client: &reqwest::Client,
    probe: ProbeDef,
    url: String,
    tokens: &[String],
    cookie: Option<&str>,
) -> (EndpointProbeResult, String) {
    let mut builder = client.get(&url).header("Accept", "application/json, text/plain, */*");
    if let Some(cookie) = cookie.filter(|v| !v.is_empty()) {
        builder = builder.header("Cookie", cookie);
    }
    let first = builder.send().await;
    let mut auth_used = None;
    let mut response = first;
    if response.as_ref().ok().map(|r| r.status().as_u16()).is_some_and(|s| s == 401 || s == 403)
        && probe.vendor.contains("UFI") {
        for token in tokens.iter().filter(|t| !t.is_empty()) {
            let timestamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_millis().to_string();
            let path = reqwest::Url::parse(&url).map(|u| u.path().to_string()).unwrap_or_else(|_| probe.path.to_string());
            let sign = kano_sign(KANO_SIGN_KEY, &format!("minikanoGET{}{}", path, timestamp));
            let mut request = client.get(&url)
                .header("Authorization", token)
                .header("token", token)
                .header("user", "admin")
                .header("kano-t", &timestamp)
                .header("kano-sign", sign);
            if let Some(cookie) = cookie.filter(|v| !v.is_empty()) { request = request.header("Cookie", cookie); }
            let candidate = request.send().await;
            let accepted = candidate.as_ref().ok().map(|r| r.status().is_success()).unwrap_or(false);
            response = candidate;
            if accepted {
                auth_used = Some("Candidate Token + KanoSign".to_string());
                break;
            }
        }
    }

    let start = std::time::Instant::now();
    match response {
        Ok(resp) => {
            let status_code = resp.status().as_u16();
            let status_text = resp.status().canonical_reason().unwrap_or("").to_string();
            let content_type = resp.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
            let server = resp.headers().get("server").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
            let text = resp.text().await.unwrap_or_default();
            let snippet = sanitize_text_snippet(&text);
            let result = EndpointProbeResult {
                name: probe.name.to_string(), vendor: probe.vendor.to_string(), url, method: "GET".to_string(),
                statusCode: status_code, statusText: status_text, latencyMs: start.elapsed().as_millis(),
                contentType: content_type, serverHeader: server, responseSnippet: snippet.clone(),
                isSuccess: (200..300).contains(&status_code) && !snippet.is_empty(), authUsed: auth_used,
            };
            (result, text)
        }
        Err(error) => (EndpointProbeResult {
            name: probe.name.to_string(), vendor: probe.vendor.to_string(), url, method: "GET".to_string(),
            statusCode: 0, statusText: error.to_string(), latencyMs: start.elapsed().as_millis(),
            contentType: String::new(), serverHeader: String::new(), responseSnippet: String::new(),
            isSuccess: false, authUsed: auth_used,
        }, String::new()),
    }
}

#[derive(Clone, Copy)]
struct ProbeDef {
    name: &'static str,
    vendor: &'static str,
    path: &'static str,
    port_override: Option<u16>,
}

const DEFAULT_PROBE_DEFS: &[ProbeDef] = &[
    ProbeDef { name: "Web UI 首页 (/)", vendor: "通用/基础", path: "/", port_override: None },
    ProbeDef { name: "Web UI 登录页", vendor: "通用/基础", path: "/index.html", port_override: None },
    ProbeDef { name: "ZTE 状态接口", vendor: "中兴 (ZTE)", path: "/goform/goform_get_cmd_process?cmd=Language,cr_version,wa_inner_version,network_type,network_provider,signalbar,lte_rsrp,rscp,Nr_bands,battery_value,realtime_rx_thrpt,realtime_tx_thrpt,monthly_rx_bytes,day_rx_bytes&multi_data=1", port_override: None },
    ProbeDef { name: "ZTE 频段/网络详情", vendor: "中兴 (ZTE)", path: "/goform/goform_get_cmd_process?cmd=network_information&multi_data=1", port_override: None },
    ProbeDef { name: "UFI 设备信息 (:2333)", vendor: "UFI-TOOLS", path: "/api/baseDeviceInfo", port_override: Some(2333) },
    ProbeDef { name: "UFI 信号指标 (:2333)", vendor: "UFI-TOOLS", path: "/api/signalDeviceInfo", port_override: Some(2333) },
    ProbeDef { name: "UFI 蜂窝用量 (:2333)", vendor: "UFI-TOOLS", path: "/api/cellularUsage", port_override: Some(2333) },
    ProbeDef { name: "Huawei 状态接口", vendor: "华为 (HiLink)", path: "/api/monitoring/status", port_override: None },
    ProbeDef { name: "Huawei 设备信息", vendor: "华为 (HiLink)", path: "/api/device/information", port_override: None },
    ProbeDef { name: "Unisoc 综合状态", vendor: "展锐/翱捷 (Unisoc/ASR)", path: "/reqproc/proc_get?cmd=get_network_info,get_device_info,get_sim_status,get_wan_traffic", port_override: None },
    ProbeDef { name: "Qualcomm 状态接口", vendor: "高通 (Qualcomm)", path: "/cgi-bin/te_web_cgi?cmd=get_device_info", port_override: None },
    ProbeDef { name: "MTK Goform 网络接口", vendor: "联发科 (MTK)", path: "/goform/get_network_info", port_override: None },
    ProbeDef { name: "OPPO 5G CPE 设备状态", vendor: "OPPO (CPE)", path: "/api/v1/device/status", port_override: None },
    ProbeDef { name: "通用 5G CPE 状态", vendor: "通用 5G CPE", path: "/api/status", port_override: None },
];

pub async fn execute_and_submit_feedback(
    fetcher: Arc<F50Fetcher>,
    category: String,
    device_model: String,
    user_notes: String,
    contact: String,
) -> Result<FeedbackSubmissionResult, String> {
    if user_notes.trim().len() < 4 {
        return Err("请在「详细问题描述」中至少输入 4 个字符以提供复现说明。".to_string());
    }

    let config = fetcher.config.read().await.clone();
    let current_status = fetcher.fetch_status().await;
    let base_url = config.base_url.trim_matches('/').to_string();

    // 局域网设备常使用自签名证书；仅探测客户端允许该行为。公网提交必须严格校验证书。
    let probe_client = reqwest::Client::builder()
        .timeout(Duration::from_millis(3000))
        .danger_accept_invalid_certs(true)
        .build()
        .map_err(|e| e.to_string())?;
    let public_client = reqwest::Client::builder()
        .timeout(Duration::from_millis(15000))
        .build()
        .map_err(|e| e.to_string())?;

    let tokens = fetcher.diagnostic_candidate_tokens(&config.ufi_token, &config.password);
    let session_cookie = fetcher.diagnostic_session_cookie().await;

    let mut probe_results: Vec<EndpointProbeResult> = Vec::new();
    let mut discovered_apis: Vec<String> = Vec::new();
    let mut script_call_signatures: Vec<ScriptCallSignature> = Vec::new();

    let host = base_url
        .replace("http://", "")
        .replace("https://", "")
        .split('/')
        .next()
        .unwrap_or("192.168.0.1")
        .split(':')
        .next()
        .unwrap_or("192.168.0.1")
        .to_string();

    // 有限并发，避免新设备在诊断期间被打满，同时复用正式链路的 Cookie/Token/Kano 鉴权。
    for chunk in DEFAULT_PROBE_DEFS.chunks(4) {
        let mut tasks = JoinSet::new();
        for probe in chunk.iter().copied() {
            let client = probe_client.clone();
            let probe_tokens = tokens.clone();
            let cookie = session_cookie.clone();
            let url_str = if let Some(port) = probe.port_override {
                format!("http://{}:{}{}", host, port, probe.path)
            } else {
                format!("http://{}{}", host, probe.path)
            };
            tasks.spawn(async move { probe_one(&client, probe, url_str, &probe_tokens, cookie.as_deref()).await });
        }
        while let Some(result) = tasks.join_next().await {
            if let Ok((probe_result, raw_text)) = result {
                if probe_result.statusCode == 200 && (probe_result.url.ends_with('/') || probe_result.url.contains("index.html")) {
                    for api in extract_apis_from_html(&raw_text) {
                        if !discovered_apis.contains(&api) { discovered_apis.push(api); }
                    }
                    for script_url in extract_script_urls(&raw_text, &probe_result.url).into_iter().take(3) {
                        if let Ok(resp) = probe_client.get(&script_url).send().await {
                            if resp.status().is_success()
                                && resp.content_length().unwrap_or(0) <= 1_500 * 1024 {
                                let body = resp.text().await.unwrap_or_default();
                                if body.len() <= 1_500 * 1024 {
                                    for api in extract_apis_from_html(&body) {
                                        if !discovered_apis.contains(&api) { discovered_apis.push(api); }
                                    }
                                    let source_script = reqwest::Url::parse(&script_url)
                                        .map(|url| url.path().to_string())
                                        .unwrap_or(script_url);
                                    merge_call_signatures(
                                        &mut script_call_signatures,
                                        extract_call_signatures(&body, &source_script),
                                    );
                                }
                            }
                        }
                    }
                }
                probe_results.push(probe_result);
            }
        }
    }

    let payload = json!({
        "id": format!("diag_win_{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis()),
        "category": category,
        "deviceModel": if device_model.is_empty() { "未指定 (Windows客户端)" } else { &device_model },
        "userNotes": user_notes,
        "contact": contact,
        "appVersion": env!("CARGO_PKG_VERSION"),
        "osVersion": format!("Windows OS ({})", std::env::consts::ARCH),
        "targetBaseURL": base_url,
        "appState": {
            "isOnline": current_status.is_online,
            "networkType": current_status.network_type,
            "carrier": current_status.carrier,
            "currentBands": current_status.current_bands,
            "signalBar": current_status.signal_bar,
            "rsrp": current_status.rsrp,
            "snr": current_status.snr,
            "rsrq": current_status.rsrq,
            "dlSpeed": current_status.dl_speed,
            "ulSpeed": current_status.ul_speed,
            "cpuUsage": current_status.cpu_usage,
            "memUsage": current_status.mem_usage,
            "temperature": current_status.temperature,
            "connectedDevices": current_status.connected_devices,
            "lastErrorMessage": current_status.error_message,
            "activeChannelMode": active_channel_mode(&probe_results),
            "firmwareVersion": extract_firmware_version(&probe_results)
        },
        "endpoints": probe_results,
        "discoveredScriptAPIs": if discovered_apis.is_empty() { None } else { Some(discovered_apis) },
        "scriptCallSignatures": if script_call_signatures.is_empty() { None } else { Some(script_call_signatures) }
    });
    let payload_bytes = serde_json::to_vec(&payload).map_err(|e| format!("诊断数据序列化失败: {}", e))?;
    if payload_bytes.len() > 512 * 1024 {
        return Err("诊断数据超过 512 KB 限制，请减少接口明细后重试。".to_string());
    }

    let webhook_url = "https://feedback-api.koldllc.com";
    let timestamp = chrono::Utc::now().timestamp_millis().to_string();
    let request_id = format!("win_{}_{}", timestamp, std::process::id());
    let post_resp = public_client.post(webhook_url)
        .header("Content-Type", "application/json")
        .header("User-Agent", format!("F50Monitor-Windows/{}", env!("CARGO_PKG_VERSION")))
        .header("X-F50-Feedback-Key", "f50-feedback-v1")
        .header("X-F50-Feedback-Timestamp", timestamp)
        .header("X-F50-Feedback-Request-Id", request_id)
        .body(payload_bytes)
        .send()
        .await
        .map_err(|e| format!("网络提交失败: {}", e))?;

    if post_resp.status().is_success() {
        let resp_json: serde_json::Value = post_resp.json().await.unwrap_or(json!({}));
        let msg = resp_json.get("message").and_then(|v| v.as_str()).unwrap_or("提交成功");
        let issue_url = resp_json.get("issueUrl").and_then(|v| v.as_str()).map(str::to_string);
        Ok(FeedbackSubmissionResult {
            message: msg.to_string(),
            issue_url,
        })
    } else {
        let err_text = post_resp.text().await.unwrap_or_default();
        Err(format!("服务端退回: {}", err_text))
    }
}

fn extract_apis_from_html(html: &str) -> Vec<String> {
    let mut found = Vec::new();
    let re_patterns = [
        r"/(?:api|goform|reqproc|cgi-bin|ajax)/[a-zA-Z0-9_\-\./]+",
    ];
    for pat in re_patterns {
        if let Ok(re) = regex::Regex::new(pat) {
            for cap in re.find_iter(html) {
                let path = cap.as_str().to_string();
                if !found.contains(&path) && path.len() < 80 {
                    found.push(path);
                }
            }
        }
    }
    found
}

fn extract_call_signatures(script: &str, source_script: &str) -> Vec<ScriptCallSignature> {
    let Ok(endpoint_re) = regex::Regex::new(r"/(?:api|goform|reqproc|cgi-bin|ajax)/[a-zA-Z0-9_\-\./]+") else {
        return Vec::new();
    };
    let method_re = regex::Regex::new(
        r#"(?i)(?:method|type)\s*:\s*["'](GET|POST|PUT|DELETE|PATCH)["']|\.(get|post|put|delete|patch)\s*\("#,
    ).ok();
    let field_re = regex::Regex::new(
        r#"(?:["']([A-Za-z_][A-Za-z0-9_.-]{1,40})["']|([A-Za-z_][A-Za-z0-9_]{1,40}))\s*:"#,
    ).ok();
    let ignored: BTreeSet<&str> = ["url", "method", "type", "headers", "data", "params", "timeout", "baseURL"]
        .into_iter().collect();
    let mut collected: BTreeMap<String, (BTreeSet<String>, BTreeSet<String>)> = BTreeMap::new();

    for endpoint_match in endpoint_re.find_iter(script) {
        let mut start = endpoint_match.start().saturating_sub(900);
        let mut end = (endpoint_match.end() + 900).min(script.len());
        while start < endpoint_match.start() && !script.is_char_boundary(start) { start += 1; }
        while end > endpoint_match.end() && !script.is_char_boundary(end) { end -= 1; }
        let context = &script[start..end];
        let entry = collected.entry(endpoint_match.as_str().to_string()).or_default();

        if let Some(re) = &method_re {
            for captures in re.captures_iter(context) {
                for index in 1..captures.len() {
                    if let Some(value) = captures.get(index) {
                        entry.0.insert(value.as_str().to_ascii_uppercase());
                    }
                }
            }
        }
        if let Some(re) = &field_re {
            for captures in re.captures_iter(context) {
                let field = captures.get(1).or_else(|| captures.get(2)).map(|m| m.as_str());
                if let Some(field) = field.filter(|field| !ignored.contains(*field)) {
                    entry.1.insert(field.to_string());
                }
            }
        }
    }

    collected.into_iter().take(30).map(|(endpoint, (methods, fields))| ScriptCallSignature {
        endpoint,
        source_script: source_script.to_string(),
        method_candidates: methods.into_iter().collect(),
        nearby_field_names: fields.into_iter().take(40).collect(),
    }).collect()
}

fn merge_call_signatures(existing: &mut Vec<ScriptCallSignature>, incoming: Vec<ScriptCallSignature>) {
    for signature in incoming {
        if let Some(current) = existing.iter_mut().find(|current| {
            current.endpoint == signature.endpoint && current.source_script == signature.source_script
        }) {
            current.method_candidates.extend(signature.method_candidates);
            current.method_candidates.sort();
            current.method_candidates.dedup();
            current.nearby_field_names.extend(signature.nearby_field_names);
            current.nearby_field_names.sort();
            current.nearby_field_names.dedup();
            current.nearby_field_names.truncate(40);
        } else if existing.len() < 30 {
            existing.push(signature);
        }
    }
}

fn active_channel_mode(results: &[EndpointProbeResult]) -> &'static str {
    let router = results.iter().any(|probe| probe.isSuccess && !probe.url.contains(":2333"));
    let ufi = results.iter().any(|probe| probe.isSuccess && probe.url.contains(":2333"));
    match (router, ufi) {
        (true, true) => "80 Router + 2333 UFI",
        (true, false) => "80 Router",
        (false, true) => "2333 UFI",
        (false, false) => "未知",
    }
}

fn extract_script_urls(html: &str, page_url: &str) -> Vec<String> {
    let Ok(base) = reqwest::Url::parse(page_url) else { return Vec::new() };
    let Ok(re) = regex::Regex::new(r#"<script[^>]+src=[\"']([^\"']+)[\"']"#) else { return Vec::new() };
    re.captures_iter(html).filter_map(|cap| {
        let joined = base.join(cap.get(1)?.as_str()).ok()?;
        if joined.host_str() == base.host_str() { Some(joined.to_string()) } else { None }
    }).take(3).collect()
}

fn extract_firmware_version(results: &[EndpointProbeResult]) -> String {
    let Ok(re) = regex::Regex::new(r#"(?:wa_inner_version|wa_version|cr_version)[^A-Za-z0-9._-]{1,4}([A-Za-z0-9._-]{2,40})"#) else { return String::new() };
    results.iter().find_map(|result| re.captures(&result.responseSnippet).and_then(|c| c.get(1).map(|m| m.as_str().to_string()))).unwrap_or_default()
}

fn sanitize_text_snippet(raw: &str) -> String {
    let mut text = raw.trim().to_string();
    if text.chars().count() > 3072 {
        text = text.chars().take(3072).collect();
        text.push_str("\n... [截取前 3KB]");
    }
    // 脱敏密码与 Token
    if let Ok(re) = regex::Regex::new(r#"(?i)"(password|pwd|token|wpa_key|psk|secret)"\s*:\s*"[^"]*""#) {
        text = re.replace_all(&text, r#""$1": "******""#).to_string();
    }
    // 脱敏 15 位 IMEI/IMSI
    if let Ok(re) = regex::Regex::new(r"\b(\d{4})\d{7}(\d{4})\b") {
        text = re.replace_all(&text, "$1*******$2").to_string();
    }
    text
}
