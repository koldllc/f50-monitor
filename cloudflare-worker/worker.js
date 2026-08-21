/**
 * F50 Monitor - 设备适配与问题诊断反馈接收网关 (Cloudflare Worker)
 */

export default {
  async fetch(request, env, ctx) {
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, User-Agent",
      "Content-Type": "application/json; charset=utf-8"
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Only POST method is supported" }), {
        status: 405,
        headers: corsHeaders
      });
    }

    try {
      const payload = await request.json();
      const {
        id = `diag_${Date.now()}`,
        category = "用户反馈",
        deviceModel = "未指定设备",
        userNotes = "无说明",
        contact = "",
        appVersion = "2.1.1",
        osVersion = "macOS",
        targetBaseURL = "",
        appState = null,
        screenshotBase64 = null,
        endpoints = [],
        discoveredScriptAPIs = []
      } = payload;

      const successfulProbes = endpoints.filter(e => e.isSuccess).length;
      
      // 生成语义化 Issue 标题
      const noteSummary = userNotes ? userNotes.replace(/\s+/g, ' ').substring(0, 35) : "用户反馈";
      const title = `[${category}] ${deviceModel || "未知型号"} - ${noteSummary}`;

      // 组装结构化 Markdown 报告
      let issueBody = `### 📋 问题与反馈信息
- **反馈类别**: \`${category}\`
- **设备型号**: **${deviceModel || "未填写"}**
- **目标地址**: \`${targetBaseURL || "未记录"}\`
- **联系方式**: ${contact ? `\`${contact}\`` : "未提供"}
- **客户端环境**: F50 Monitor v${appVersion} (${osVersion})
- **有效接口探测**: ${successfulProbes} / ${endpoints.length}
- **反馈编号**: \`${id}\`

### 📝 详细问题描述
${userNotes || "（用户未提供详细说明）"}
`;

      // 附加 App 状态快照
      if (appState) {
        issueBody += `
### ⚡ 提交时应用状态快照
- **在线状态**: ${appState.isOnline ? "🟢 在线" : "🔴 离线"}
- **网络制式 / 运营商**: \`${appState.networkType || "未知"}\` / \`${appState.carrier || "未知"}\`
${appState.currentBands ? `- **活跃频段**: \`${appState.currentBands}\`\n` : ''}- **信号指标**: RSRP: \`${appState.rsrp || "--"}\` | SNR: \`${appState.snr || "--"}\` | RSRQ: \`${appState.rsrq || "--"}\` (信号格: ${appState.signalBar})
- **硬件负载**: 温度: \`${appState.temperature || "--"}℃\` | CPU: \`${appState.cpuUsage || "--"}%\` | 内存: \`${appState.memUsage || "--"}%\` | 连接设备: \`${appState.connectedDevices || 0} 台\`
${appState.localInterfaces ? `- **本机网络接口**: \`${appState.localInterfaces}\`\n` : ''}${appState.lastErrorMessage ? `- **最近连接错误**: \`${appState.lastErrorMessage}\`\n` : ''}${appState.lastSMSErrorMessage ? `- **短信模块错误**: \`${appState.lastSMSErrorMessage}\`\n` : ''}`;
      }

      // 附加前端发现的 API 路径
      if (discoveredScriptAPIs && discoveredScriptAPIs.length > 0) {
        issueBody += `
### 🌐 前端 JS 脚本中提取的 API 特征
${discoveredScriptAPIs.map(api => `- \`${api}\``).join('\n')}
`;
      }

      // 附加屏幕截图 (如有)
      if (screenshotBase64 && screenshotBase64.length > 50) {
        issueBody += `
### 🖼️ 附带屏幕截图
<details>
<summary><b>点击展开查看截图</b></summary>

<img src="data:image/jpeg;base64,${screenshotBase64}" width="480" alt="用户反馈截图" />

</details>
`;
      }

      // 附加接口探测明细
      if (endpoints && endpoints.length > 0) {
        issueBody += `
### 🔍 接口探测明细 (已脱敏)
<details>
<summary><b>点击展开查看全部 ${endpoints.length} 个接口探测记录</b></summary>

\`\`\`json
${JSON.stringify(endpoints, null, 2)}
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
            console.error("GitHub API error:", ghResp.status, errText);
          }
        } catch (e) {
          githubError = e.message;
          console.error("GitHub issue creation failed:", e);
        }
      } else {
        githubError = "GITHUB_TOKEN 未配置或未生效";
      }

      // 转发通知到群 Webhook (如有)
      if (env.NOTIFY_WEBHOOK) {
        try {
          await fetch(env.NOTIFY_WEBHOOK, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              msg_type: "text",
              text: {
                content: `【F50 Monitor 用户反馈】\n类型: ${category}\n设备: ${deviceModel}\n联系方式: ${contact || "未留"}\n说明: ${userNotes}\n${githubIssueUrl ? `Issue: ${githubIssueUrl}` : ""}`
              }
            })
          });
        } catch (e) {
          console.error("Webhook notification failed:", e);
        }
      }

      return new Response(JSON.stringify({
        success: true,
        message: "反馈提交成功，开发者将尽快跟进适配与排查！",
        id: id,
        issueUrl: githubIssueUrl,
        githubStatus: githubIssueUrl ? "Issue 创建成功" : (githubError || "未配置自动创建 Issue")
      }), {
        status: 200,
        headers: corsHeaders
      });

    } catch (err) {
      return new Response(JSON.stringify({
        success: false,
        error: "无效的请求数据: " + err.message
      }), {
        status: 400,
        headers: corsHeaders
      });
    }
  }
};
