/**
 * F50 Monitor - 设备适配与问题诊断反馈接收网关 (Cloudflare Worker)
 *
 * 包含：
 * 1. 强类型/Schema 校验与 512KB 请求体大小限制
 * 2. 服务端二次深度脱敏 (保护 SNR、准确掩码 IMEI/IMSI/MAC/Phone/IP)
 * 3. 隐私保护隔离：敏感数据/联系方式隔离存储，GitHub Issue 仅保留脱敏摘要
 * 4. 0 静默丢单保障：必须成功写入 KV 或成功创建 GitHub Issue 后才返回 success: true
 */

const MAX_PAYLOAD_BYTES = 512 * 1024; // 512 KB
const MAX_PUBLIC_TEXT = 2_000;
const DEFAULT_CLIENT_KEY = "f50-feedback-v1";
const rateWindowMs = 60 * 60 * 1000;
const rateLimit = 20;
const recentRequests = new Map();
const seenRequestIds = new Map();

export default {
  async fetch(request, env, ctx) {
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, User-Agent, X-F50-Feedback-Key, X-F50-Feedback-Timestamp, X-F50-Feedback-Request-Id",
      "Content-Type": "application/json; charset=utf-8"
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== "POST") {
      return new Response(JSON.stringify({ success: false, error: "仅支持 POST 请求" }), {
        status: 405,
        headers: corsHeaders
      });
    }

    // 客户端契约：所有端发送同一个版本化共享密钥和请求时间戳。密钥可由 Worker Secret 覆盖。
    const clientKey = request.headers.get("x-f50-feedback-key") || "";
    const expectedKey = env.FEEDBACK_SHARED_KEY || DEFAULT_CLIENT_KEY;
    if (clientKey !== expectedKey) {
      return jsonResponse({ success: false, error: "反馈请求未通过鉴权" }, 401, corsHeaders);
    }
    const requestTimestamp = Number(request.headers.get("x-f50-feedback-timestamp") || "0");
    if (!Number.isFinite(requestTimestamp) || Math.abs(Date.now() - requestTimestamp) > 10 * 60 * 1000) {
      return jsonResponse({ success: false, error: "反馈请求已过期，请重试" }, 401, corsHeaders);
    }
    const requestId = request.headers.get("x-f50-feedback-request-id") || "";
    if (!/^[A-Za-z0-9._-]{8,100}$/.test(requestId)) {
      return jsonResponse({ success: false, error: "无效的反馈请求编号" }, 400, corsHeaders);
    }
    const seenAt = seenRequestIds.get(requestId);
    if (seenAt && Date.now() - seenAt < 10 * 60 * 1000) {
      return jsonResponse({ success: false, error: "该反馈请求已处理，请勿重复提交" }, 409, corsHeaders);
    }
    seenRequestIds.set(requestId, Date.now());
    const source = request.headers.get("cf-connecting-ip") || "unknown";
    const now = Date.now();
    const previous = recentRequests.get(source) || { started: now, count: 0 };
    if (now - previous.started > rateWindowMs) {
      recentRequests.set(source, { started: now, count: 1 });
    } else if (previous.count >= rateLimit) {
      return jsonResponse({ success: false, error: "提交过于频繁，请稍后再试" }, 429, corsHeaders);
    } else {
      previous.count += 1;
      recentRequests.set(source, previous);
    }

    // 1. 请求体大小检查
    const contentLength = parseInt(request.headers.get("content-length") || "0", 10);
    if (contentLength > MAX_PAYLOAD_BYTES) {
      return new Response(JSON.stringify({
        success: false,
        error: `请求体过大 (${(contentLength / 1024).toFixed(1)}KB)，超出 512KB 限制`
      }), {
        status: 413,
        headers: corsHeaders
      });
    }

    let rawText = "";
    try {
      rawText = await request.text();
    } catch (e) {
      return new Response(JSON.stringify({ success: false, error: "无法读取请求文本: " + e.message }), {
        status: 400,
        headers: corsHeaders
      });
    }

    if (rawText.length > MAX_PAYLOAD_BYTES) {
      return new Response(JSON.stringify({
        success: false,
        error: "请求体过大，超出 512KB 限制"
      }), {
        status: 413,
        headers: corsHeaders
      });
    }

    let rawPayload = null;
    try {
      rawPayload = JSON.parse(rawText);
    } catch (err) {
      return new Response(JSON.stringify({ success: false, error: "无效的 JSON 格式: " + err.message }), {
        status: 400,
        headers: corsHeaders
      });
    }

    // 2. Schema 与基础字段校验
    if (!rawPayload || typeof rawPayload !== "object" || Array.isArray(rawPayload)) {
      return new Response(JSON.stringify({ success: false, error: "无效的负载结构，必须为 JSON 对象" }), {
        status: 400,
        headers: corsHeaders
      });
    }

    const scalarFields = ["category", "deviceModel", "userNotes", "contact", "appVersion", "osVersion", "targetBaseURL"];
    for (const field of scalarFields) {
      const value = rawPayload[field];
      if (value !== undefined && value !== null && !["string", "number", "boolean"].includes(typeof value)) {
        return jsonResponse({ success: false, error: `字段 ${field} 必须是文本或标量值` }, 400, corsHeaders);
      }
    }
    if (rawPayload.endpoints !== undefined && (!Array.isArray(rawPayload.endpoints) || rawPayload.endpoints.some(item => !item || typeof item !== "object" || Array.isArray(item)))) {
      return jsonResponse({ success: false, error: "endpoints 必须是对象数组" }, 400, corsHeaders);
    }
    if (rawPayload.discoveredScriptAPIs !== undefined && rawPayload.discoveredScriptAPIs !== null && (!Array.isArray(rawPayload.discoveredScriptAPIs) || rawPayload.discoveredScriptAPIs.some(item => typeof item !== "string"))) {
      return jsonResponse({ success: false, error: "discoveredScriptAPIs 必须是字符串数组" }, 400, corsHeaders);
    }
    if (rawPayload.scriptCallSignatures !== undefined && rawPayload.scriptCallSignatures !== null && !isValidScriptCallSignatures(rawPayload.scriptCallSignatures)) {
      return jsonResponse({ success: false, error: "scriptCallSignatures 格式无效" }, 400, corsHeaders);
    }
    if (rawPayload.appState !== undefined && rawPayload.appState !== null && (typeof rawPayload.appState !== "object" || Array.isArray(rawPayload.appState))) {
      return jsonResponse({ success: false, error: "appState 必须是对象或 null" }, 400, corsHeaders);
    }
    if (rawPayload.screenshotBase64 !== undefined && rawPayload.screenshotBase64 !== null && typeof rawPayload.screenshotBase64 !== "string") {
      return jsonResponse({ success: false, error: "screenshotBase64 必须是字符串或 null" }, 400, corsHeaders);
    }

    // 3. 服务端深度二次脱敏
    const sanitizedPayload = sanitizeServerSide(rawPayload);

    const {
      category = "用户反馈",
      deviceModel = "未指定设备",
      userNotes = "无说明",
      contact = "",
      appVersion = "dev",
      osVersion = "macOS",
      targetBaseURL = "",
      appState = null,
      screenshotBase64 = null,
      endpoints = [],
      discoveredScriptAPIs = [],
      scriptCallSignatures = []
    } = sanitizedPayload;

    // ID 只作为客户端幂等提示，不作为 KV 路径；服务端始终生成规范化 ID，避免覆盖任意记录。
    const id = `diag_${Date.now().toString(36)}_${crypto.randomUUID().replaceAll("-", "").slice(0, 12)}`;
    const safeCategory = publicText(category, 80) || "用户反馈";
    const safeDeviceModel = publicText(deviceModel, 120) || "未指定设备";
    const safeAppVersion = publicText(appVersion, 40) || "未知";
    const safeOSVersion = publicText(osVersion, 80) || "未知";
    const publicNotes = maskPublicText(publicText(userNotes, MAX_PUBLIC_TEXT)) || "（用户未提供详细说明）";
    const publicTarget = maskPublicText(maskIPorHost(publicText(targetBaseURL, 300)));
    sanitizedPayload.id = id;

    const successfulProbes = Array.isArray(endpoints) ? endpoints.filter(e => e.isSuccess).length : 0;
    const totalProbes = Array.isArray(endpoints) ? endpoints.length : 0;

    // 4. 组装 Cloudflare KV 私有持久化数据
    let storedInKV = false;
    let kvError = null;

    if (env.FEEDBACK_KV) {
      try {
        const kvKey = `report:${id}`;
        await env.FEEDBACK_KV.put(kvKey, JSON.stringify(sanitizedPayload), {
          metadata: {
            id,
            category,
            deviceModel,
            timestamp: new Date().toISOString(),
            appVersion
          },
          expirationTtl: 60 * 60 * 24 * 180 // 自动保留 180 天
        });
        storedInKV = true;
      } catch (e) {
        kvError = e.message;
        console.error("Cloudflare KV 写入失败:", e);
      }
    }

    // 5. 组装 GitHub Issue 内容（严格防隐私泄露）
    const maskedContact = contact ? maskContactString(publicText(contact, 160)) : "";
    const publicEndpointSummary = Array.isArray(endpoints) ? endpoints.slice(0, 40).map(endpoint => ({
      name: publicText(endpoint.name, 100),
      vendor: publicText(endpoint.vendor, 80),
      statusCode: Number(endpoint.statusCode) || 0,
      statusText: publicText(endpoint.statusText, 80),
      latencyMs: Number(endpoint.latencyMs) || 0,
      contentType: publicText(endpoint.contentType, 100),
      isSuccess: Boolean(endpoint.isSuccess),
      authUsed: publicText(endpoint.authUsed, 80)
    })) : [];
    const noteSummary = publicNotes.replace(/\s+/g, " ").substring(0, 35);
    const title = `[${escapeMarkdown(safeCategory)}] ${escapeMarkdown(safeDeviceModel)} - ${escapeMarkdown(noteSummary)}`;

    let issueBody = `### 📋 问题与诊断脱敏报告
- **反馈类别**: \`${escapeMarkdown(safeCategory)}\`
- **设备型号**: **${escapeMarkdown(safeDeviceModel)}**
- **目标网关**: \`${escapeMarkdown(publicTarget || "未记录")}\`
- **联系方式**: ${maskedContact ? `\`${maskedContact}\` *(已掩码)*` : "未提供"}
- **客户端环境**: F50 Monitor v${escapeMarkdown(safeAppVersion)} (${escapeMarkdown(safeOSVersion)})
- **有效接口探测**: ${successfulProbes} / ${totalProbes}
- **诊断编号**: \`${id}\`
${storedInKV ? `- **私有存储**: 🟢 已保存至 KV (\`report:${id}\`)\n` : ''}
### 📝 详细问题描述
${escapeMarkdown(publicNotes)}
`;

    if (appState) {
      issueBody += `
### ⚡ 提交时应用状态快照
- **在线状态**: ${appState.isOnline ? "🟢 在线" : "🔴 离线"}
- **网络制式 / 运营商**: \`${escapeMarkdown(publicText(appState.networkType || "未知", 80))}\` / \`${escapeMarkdown(publicText(appState.carrier || "未知", 80))}\`
${appState.currentBands ? `- **活跃频段**: \`${escapeMarkdown(publicText(appState.currentBands, 120))}\`\n` : ''}- **信号指标**: RSRP: \`${escapeMarkdown(String(appState.rsrp || "--"))}\` | SNR: \`${escapeMarkdown(String(appState.snr || "--"))}\` | RSRQ: \`${escapeMarkdown(String(appState.rsrq || "--"))}\` (信号格: ${escapeMarkdown(String(appState.signalBar ?? "--"))})
- **硬件负载**: 温度: \`${escapeMarkdown(String(appState.temperature || "--"))}℃\` | CPU: \`${escapeMarkdown(String(appState.cpuUsage || "--"))}%\` | 内存: \`${escapeMarkdown(String(appState.memUsage || "--"))}%\` | 连接设备: ${escapeMarkdown(String(appState.connectedDevices || 0))} 台
${appState.qci || appState.qosDl || appState.qosUl ? `- **签约状态**: QCI: \`${escapeMarkdown(publicText(appState.qci || "--", 40))}\` | 下行: \`${escapeMarkdown(publicText(appState.qosDl || "--", 40))}\` | 上行: \`${escapeMarkdown(publicText(appState.qosUl || "--", 40))}\`\n` : ''}
${appState.firmwareVersion ? `- **设备固件版本**: \`${escapeMarkdown(publicText(appState.firmwareVersion, 100))}\`\n` : ''}${appState.activeChannelMode ? `- **实际数据通道**: \`${escapeMarkdown(publicText(appState.activeChannelMode, 120))}\`\n` : ''}
${appState.lastErrorMessage ? `- **最近连接错误**: \`${escapeMarkdown(maskPublicText(publicText(appState.lastErrorMessage, 300)))}\`\n` : ''}${appState.lastSMSErrorMessage ? `- **短信模块错误**: \`${escapeMarkdown(maskPublicText(publicText(appState.lastSMSErrorMessage, 300)))}\`\n` : ''}`;
    }

    if (discoveredScriptAPIs && discoveredScriptAPIs.length > 0) {
      issueBody += `
### 🌐 前端 JS 脚本中提取的 API 特征
${discoveredScriptAPIs.slice(0, 20).map(api => `- \`${escapeMarkdown(publicText(api, 160))}\``).join('\n')}
`;
    }

    if (Array.isArray(scriptCallSignatures) && scriptCallSignatures.length > 0) {
      issueBody += `
### 🧩 前端 API 调用特征（仅字段名，不含值）
${scriptCallSignatures.slice(0, 20).map(signature => {
  const endpoint = escapeMarkdown(publicText(signature.endpoint, 160));
  const source = escapeMarkdown(publicText(signature.sourceScript, 160));
  const methods = Array.isArray(signature.methodCandidates)
    ? signature.methodCandidates.slice(0, 5).map(item => escapeMarkdown(publicText(item, 12))).join("/")
    : "未知";
  const fields = Array.isArray(signature.nearbyFieldNames)
    ? signature.nearbyFieldNames.slice(0, 40).map(item => escapeMarkdown(publicText(item, 50))).join(", ")
    : "未识别";
  return `- \`${endpoint}\` · \`${methods || "未知"}\` · 来源 \`${source}\` · 邻近字段：\`${fields || "未识别"}\``;
}).join('\n')}
`;
    }

    // 截图只进入私有 KV，绝不写入公开 GitHub Issue。

    if (Array.isArray(endpoints) && endpoints.length > 0) {
      issueBody += `
### 🔍 接口探测明细 (服务端二次脱敏)
<details>
<summary><b>点击展开查看 ${totalProbes} 个接口探测明细</b></summary>

\`\`\`json
${escapeMarkdown(JSON.stringify(publicEndpointSummary, null, 2))}
\`\`\`

</details>
`;
    }

    let githubIssueUrl = null;
    let githubError = null;

    const repo = env.GITHUB_REPO || "koldllc/f50-monitor";
    const token = env.GITHUB_TOKEN ? env.GITHUB_TOKEN.trim() : null;

    if (token && repo) {
      try {
        const ghResp = await fetch(`https://api.github.com/repos/${repo}/issues`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "User-Agent": "F50-Feedback-Worker",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            title: title,
            body: issueBody
          })
        });

        if (ghResp.ok) {
          const ghData = await ghResp.json();
          githubIssueUrl = ghData.html_url;
        } else {
          const errText = await ghResp.text();
          githubError = `GitHub API (${ghResp.status}): ${errText}`;
          console.error("GitHub API 提交失败:", ghResp.status, errText);
        }
      } catch (e) {
        githubError = e.message;
        console.error("GitHub Issue 创建异常:", e);
      }
    } else {
      githubError = "GITHUB_TOKEN 未配置";
    }

    // 转发群 Webhook
    if (env.NOTIFY_WEBHOOK) {
      try {
        await fetch(env.NOTIFY_WEBHOOK, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            msg_type: "text",
            text: {
              content: `【F50 Monitor 用户反馈】\n类型: ${safeCategory}\n设备: ${safeDeviceModel}\n联系方式: ${maskedContact || "未留"}\n说明: ${publicNotes.substring(0, 100)}\n${githubIssueUrl ? `Issue: ${githubIssueUrl}` : ""}${storedInKV ? `\nKV存储: report:${id}` : ""}`
            }
          })
        });
      } catch (e) {
        console.error("Webhook 通知推送失败:", e);
      }
    }

    // 6. 核心可靠性保护：若既未存入 KV 也未成功创建 Issue，绝对不假成功！
    const isSuccess = Boolean(githubIssueUrl || storedInKV);

    if (!isSuccess) {
      return new Response(JSON.stringify({
        success: false,
        error: "反馈提交失败：数据无法持久化存盘。请检查云端服务配置或联系开发者。",
        detail: githubError || kvError || "未配置有效存储通道",
        id: id
      }), {
        status: 503,
        headers: corsHeaders
      });
    }

    return new Response(JSON.stringify({
      success: true,
      message: "反馈提交成功，已完成安全存盘与诊断分配！",
      id: id,
      issueUrl: githubIssueUrl,
      storedInKV: storedInKV,
      githubStatus: githubIssueUrl ? "Issue 创建成功" : (githubError || "未配置 GitHub Issue")
    }), {
      status: 200,
      headers: corsHeaders
    });
  }
};

/**
 * 服务端深度递归脱敏
 */
function sanitizeServerSide(obj) {
  if (typeof obj === "string") {
    return sanitizeString(obj);
  }
  if (Array.isArray(obj)) {
    return obj.map(item => sanitizeServerSide(item));
  }
  if (obj && typeof obj === "object") {
    const res = {};
    for (const [key, value] of Object.entries(obj)) {
      const lowerKey = key.toLowerCase();

      // 敏感密码/密钥全屏蔽
      if (isSensitiveKey(lowerKey)) {
        res[key] = "******";
      }
      // 标识符精准屏蔽 (注意：排除 snr / rsnr，避免误打码)
      else if (isIdentifierKey(lowerKey)) {
        res[key] = maskIdentifier(String(value));
      }
      // MAC/BSSID 屏蔽
      else if (lowerKey.includes("mac") || lowerKey.includes("bssid")) {
        res[key] = maskMAC(String(value));
      }
      // 短信正文脱敏
      else if (lowerKey === "content" || lowerKey === "sms" || lowerKey === "message") {
        // 无论是字符串、对象还是嵌套数组，短信正文都不能进入公开摘要。
        res[key] = typeof value === "string" || value == null
          ? "[已脱敏过滤]"
          : sanitizeServerSide(value);
      }
      else {
        res[key] = sanitizeServerSide(value);
      }
    }
    return res;
  }
  return obj;
}

function isValidScriptCallSignatures(value) {
  if (!Array.isArray(value) || value.length > 30) return false;
  return value.every(signature => {
    if (!signature || typeof signature !== "object" || Array.isArray(signature)) return false;
    if (typeof signature.endpoint !== "string" || signature.endpoint.length > 160) return false;
    if (typeof signature.sourceScript !== "string" || signature.sourceScript.length > 160) return false;
    const methods = signature.methodCandidates;
    const fields = signature.nearbyFieldNames;
    return Array.isArray(methods) && methods.length <= 5 && methods.every(item => typeof item === "string" && /^(GET|POST|PUT|DELETE|PATCH)$/i.test(item))
      && Array.isArray(fields) && fields.length <= 40 && fields.every(item => typeof item === "string" && /^[A-Za-z_][A-Za-z0-9_.-]{1,40}$/.test(item));
  });
}

function isSensitiveKey(key) {
  const words = [
    "pass", "pwd", "token", "secret", "psk", "wpa_key", "key",
    "credential", "auth", "session", "cookie", "ad", "rd", "wa_inner_version_key"
  ];
  return words.some(w => key.includes(w));
}

function isIdentifierKey(key) {
  // 注意：snr, rsnr 包含 "sn"，但不是 serial number！
  if (key === "snr" || key === "rsnr" || key.endsWith("_snr")) {
    return false;
  }
  if (key.includes("imei") || key.includes("imsi") || key.includes("iccid")) {
    return true;
  }
  // 精确判断 serial number / sn
  return /\b(sn|serial_number|serialno)\b/.test(key) || key === "sn";
}

function maskIdentifier(val) {
  if (!val || val.length < 8) return "******";
  return `${val.substring(0, 3)}****${val.substring(val.length - 4)}`;
}

function maskMAC(val) {
  if (!val || typeof val !== "string") return "**:**:**:**:**:**";
  const parts = val.split(":");
  if (parts.length === 6) {
    return `${parts[0]}:${parts[1]}:**:**:${parts[4]}:${parts[5]}`;
  }
  return val.replace(/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/g, "$1:**:**:$4:$5");
}

function maskIPorHost(val) {
  if (!val || typeof val !== "string") return "";
  return val.replace(/\b(\d{1,3}\.\d{1,3})\.\d{1,3}\.\d{1,3}\b/g, "$1.*.*");
}

function maskContactString(val) {
  if (!val || typeof val !== "string") return "";
  // 手机号打码
  let masked = val.replace(/\b(1[3-9]\d)\d{4}(\d{4})\b/g, "$1****$2");
  // 邮箱打码
  masked = masked.replace(/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/g, (match, p1, p2) => {
    const prefix = p1.length > 2 ? p1.substring(0, 2) + "***" : "***";
    return `${prefix}@${p2}`;
  });
  return masked;
}

function maskPublicText(value) {
  let masked = publicText(value, MAX_PUBLIC_TEXT);
  masked = maskContactString(masked);
  masked = masked.replace(/\b(?:https?:\/\/)?(?:\d{1,3}\.){3}\d{1,3}\b/g, match => maskIPorHost(match));
  masked = masked.replace(/(["']?)(password|pwd|token|secret|psk|wpa_key|authorization)(\1)\s*[:=]\s*([^,\s}]+)/gi, "$1$2$3: ******");
  return masked;
}

function sanitizeString(str) {
  if (!str || typeof str !== "string") return str;
  let res = str;
  // 隐藏常见密码模式
  res = res.replace(/"(password|pwd|token|wpa_key|psk|secret)"\s*:\s*"[^"]*"/gi, '"$1": "******"');
  // 隐藏 15 位 IMEI/IMSI
  res = res.replace(/\b(\d{4})\d{7}(\d{4})\b/g, '$1*******$2');
  return res;
}

function publicText(value, maxLength = MAX_PUBLIC_TEXT) {
  if (value == null) return "";
  return String(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, maxLength);
}

function escapeMarkdown(value) {
  return publicText(value).replace(/[\\`*_{}\[\]()#+\-.!|>]/g, "\\$&");
}

function jsonResponse(body, status, headers) {
  return new Response(JSON.stringify(body), { status, headers });
}

export { sanitizeServerSide, sanitizeString, escapeMarkdown, publicText };
