<template>
  <div class="settings-view-container">
    <!-- Sub Header -->
    <div class="sub-header">
      <button class="btn-icon back-btn" @click="handleCancel">
        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
        <span>返回</span>
      </button>

      <span class="sub-title">设置</span>

      <div style="width: 48px"></div>
    </div>

    <!-- Settings Form Area -->
    <div class="settings-content">
      <!-- Windows Startup -->
      <div v-if="!isAndroidPlatform" class="settings-section">
        <div class="setting-row">
          <div class="setting-text">
            <span class="setting-title">登录时自动启动</span>
            <span class="setting-desc">Windows 登录时在后台启动并驻留托盘</span>
          </div>
          <label class="switch">
            <input type="checkbox" v-model="form.launchAtLogin" />
            <span class="slider"></span>
          </label>
        </div>
      </div>

      <!-- Device Connection -->
      <div class="settings-section">
        <span class="section-title">连接设置</span>

        <div class="form-group">
          <label class="form-label">设备 IP / 域名</label>
          <input 
            v-model="form.baseURL" 
            type="text" 
            placeholder="192.168.0.1 或域名" 
          />
          <span class="input-hint" v-if="!isIPValid">请输入正确的 IP 地址或域名（例如 192.168.0.1 或 f50.example.com）</span>
          <span class="input-hint" v-else>默认地址为 192.168.0.1，内网穿透可直接输入域名</span>
        </div>

        <div class="form-group">
          <div class="label-row">
            <label class="form-label">中兴后台口令</label>
            <button class="text-btn" @click="showRouterPwd = !showRouterPwd">
              {{ showRouterPwd ? '隐藏' : '显示' }}
            </button>
          </div>
          <input 
            v-model="form.password" 
            :type="showRouterPwd ? 'text' : 'password'" 
            placeholder="例如 admin" 
          />
        </div>

        <div class="form-group">
          <div class="label-row">
            <label class="form-label">UFI后台口令</label>
            <button class="text-btn" @click="showUfiToken = !showUfiToken">
              {{ showUfiToken ? '隐藏' : '显示' }}
            </button>
          </div>
          <input 
            v-model="form.ufiToken" 
            :type="showUfiToken ? 'text' : 'password'" 
            placeholder="例如 admin" 
          />
        </div>
      </div>

      <!-- Refresh Preferences -->
      <div class="settings-section">
        <span class="section-title">刷新与显示（节能优化）</span>

        <div class="form-group">
          <label class="form-label">自动刷新频率</label>
          <select v-model.number="form.refreshInterval">
            <option :value="1.0">1 秒</option>
            <option :value="2.0">2 秒（默认推荐）</option>
            <option :value="3.0">3 秒（推荐节能）</option>
            <option :value="5.0">5 秒（极简降温）</option>
            <option :value="10.0">10 秒（超低负载）</option>
          </select>
        </div>

        <div v-if="!isAndroidPlatform" class="form-group">
          <label class="form-label">无线投屏 ADB 端口</label>
          <input 
            v-model.number="form.screenMirroringPort" 
            type="number" 
            placeholder="5555" 
          />
        </div>
      </div>

      <!-- Troubleshooting & Feedback -->
      <div v-if="!isAndroidPlatform" class="settings-section">
        <span class="section-title">帮助与反馈</span>
        <div class="form-group">
          <button class="btn-icon feedback-btn" @click="showFeedbackModal = true">
            📋 问题反馈与新设备适配
          </button>
        </div>
      </div>

      <div v-if="isAndroidPlatform" class="settings-section">
        <span class="section-title">本机 Agent</span>
        <div class="form-group">
          <span class="form-label">LAN API 地址</span>
          <span class="input-hint">{{ agentInfo ? `http://${agentInfo.host || '设备网关IP'}:${agentInfo.port}` : '读取中…' }}</span>
        </div>
        <div class="form-group">
          <span class="form-label">Agent Key</span>
          <code class="agent-key">{{ agentInfo?.agentKey || '读取中…' }}</code>
          <span class="input-hint">仅用于局域网只读 API 配对，不会通过未鉴权接口返回。</span>
        </div>
        <button class="btn-icon feedback-btn" @click="requestBatteryOptimization">
          {{ agentInfo?.batteryOptimizationIgnored ? '已允许后台运行' : '允许后台长期运行' }}
        </button>
        <span v-if="batteryMessage" class="input-hint">{{ batteryMessage }}</span>
      </div>

      <!-- Footer Info & Actions -->
      <div class="footer-links">
        <span>© 2026 Kold. All rights reserved.</span>
        <a href="https://github.com/koldllc/f50-monitor" target="_blank" class="github-link">GitHub 项目链接</a>
      </div>

      <div class="save-actions">
        <button class="btn-icon default-btn" @click="handleRestoreDefault">
          使用默认值
        </button>
        <button class="btn-primary save-btn" @click="handleSave" :disabled="!isIPValid">
          保存并应用
        </button>
      </div>
    </div>

    <!-- Device Feedback Modal Component -->
    <DeviceFeedbackModal :isOpen="showFeedbackModal" @close="showFeedbackModal = false" />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { state, saveConfig, invokePlatform, isAndroidPlatform } from '../stores/f50Store.js';
import DeviceFeedbackModal from './DeviceFeedbackModal.vue';

const emit = defineEmits(['close', 'openSMS']);

const showRouterPwd = ref(false);
const showUfiToken = ref(false);
const showFeedbackModal = ref(false);
const agentInfo = ref(null);
const batteryMessage = ref('');

const form = reactive({
  baseURL: state.config.baseURL,
  password: state.config.password,
  ufiToken: state.config.ufiToken,
  refreshInterval: state.config.refreshInterval || 2.0,
  displayMode: state.config.displayMode || '仅图标',
  screenMirroringPort: state.config.screenMirroringPort || 5555,
  launchAtLogin: state.config.launchAtLogin || false
});

const isIPValid = computed(() => {
  const raw = (form.baseURL || '').trim();
  if (!raw) return false;
  const clean = raw.replace(/^https?:\/\//, '').split('/')[0].trim();
  if (!clean) return false;
  const host = clean.split(':')[0].trim();
  if (!host) return false;

  const parts = host.split('.');
  const allNumeric = parts.length > 0 && parts.every(p => !isNaN(Number(p)) && p.trim() !== '');

  if (allNumeric) {
    return parts.length === 4 && parts.every(p => {
      const n = Number(p);
      return !isNaN(n) && n >= 0 && n <= 255 && p.trim() !== '';
    });
  }

  if (host.toLowerCase() === 'localhost') return true;

  return !host.includes(' ') && !host.includes('/') && host.includes('.') && !host.startsWith('.') && !host.endsWith('.');
});

function handleRestoreDefault() {
  form.baseURL = isAndroidPlatform ? 'http://192.168.0.1' : 'http://192.168.0.1:2333';
  form.password = 'admin';
  form.ufiToken = 'admin';
  form.refreshInterval = 2.0;
  form.displayMode = '仅图标';
  form.screenMirroringPort = 5555;
}

onMounted(async () => {
  if (isAndroidPlatform) {
    try {
      agentInfo.value = await invokePlatform('get_agent_info');
    } catch (error) {
      batteryMessage.value = String(error);
    }
  }
});

async function requestBatteryOptimization() {
  try {
    await invokePlatform('request_battery_optimization');
    batteryMessage.value = '请在系统页面确认后返回。';
    agentInfo.value = await invokePlatform('get_agent_info');
  } catch (error) {
    batteryMessage.value = String(error);
  }
}

function handleCancel() {
  emit('close');
}

async function handleSave() {
  await saveConfig(form);
  emit('close');
}
</script>

<style scoped>
.settings-view-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--bg-panel);
}

.sub-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 14px;
  background: var(--bg-card);
  border-bottom: 1px solid var(--border-card);
}

.back-btn {
  color: var(--color-blue);
}

.sub-title {
  font-size: 13px;
  font-weight: 700;
}

.settings-content {
  flex: 1;
  overflow-y: auto;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.settings-section {
  background: var(--bg-card);
  border: 1px solid var(--border-card);
  border-radius: 8px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.section-title {
  font-size: 11px;
  font-weight: 700;
  color: var(--text-secondary);
  letter-spacing: 0.2px;
}

.setting-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.setting-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.setting-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-primary);
}

.setting-desc {
  font-size: 10px;
  color: var(--text-muted);
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.label-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.form-label {
  font-size: 11px;
  font-weight: 600;
  color: var(--text-secondary);
}

.text-btn {
  background: none;
  border: none;
  color: var(--color-blue);
  font-size: 10px;
  cursor: pointer;
}

.input-hint {
  font-size: 9px;
  color: var(--text-muted);
}

.footer-links {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 10px;
  color: var(--text-muted);
  padding: 0 4px;
}

.github-link {
  color: var(--color-blue);
  text-decoration: none;
}
.github-link:hover {
  text-decoration: underline;
}

.save-actions {
  margin-top: 4px;
  display: flex;
  gap: 8px;
}

.default-btn {
  flex: 1;
  padding: 8px 12px;
}

.save-btn {
  flex: 1;
  padding: 8px 12px;
}
</style>
