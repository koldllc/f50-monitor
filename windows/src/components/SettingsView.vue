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
      <div class="settings-section">
        <div class="setting-row">
          <div class="setting-text">
            <span class="setting-title">开机自启动</span>
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
        <span class="section-title">设备连接参数</span>

        <div class="form-group">
          <label class="form-label">后台主机地址 / IP</label>
          <input 
            v-model="form.baseURL" 
            type="text" 
            placeholder="http://192.168.0.1:2333" 
          />
          <span class="input-hint">中兴 F50 默认地址为 192.168.0.1</span>
        </div>

        <div class="form-group">
          <div class="label-row">
            <label class="form-label">中兴路由后台密码 (Port 80)</label>
            <button class="text-btn" @click="showRouterPwd = !showRouterPwd">
              {{ showRouterPwd ? '隐藏' : '显示' }}
            </button>
          </div>
          <input 
            v-model="form.password" 
            :type="showRouterPwd ? 'text' : 'password'" 
            placeholder="默认 admin" 
          />
        </div>

        <div class="form-group">
          <div class="label-row">
            <label class="form-label">UFI 高级后台口令 (Port 2333)</label>
            <button class="text-btn" @click="showUfiToken = !showUfiToken">
              {{ showUfiToken ? '隐藏' : '显示' }}
            </button>
          </div>
          <input 
            v-model="form.ufiToken" 
            :type="showUfiToken ? 'text' : 'password'" 
            placeholder="默认 admin" 
          />
        </div>
      </div>

      <!-- App Preferences -->
      <div class="settings-section">
        <span class="section-title">监控与显示偏好</span>

        <div class="form-group">
          <label class="form-label">数据刷新频率</label>
          <select v-model.number="form.refreshInterval">
            <option :value="1.0">1.0 秒 (高频实时)</option>
            <option :value="2.0">2.0 秒 (推荐默认)</option>
            <option :value="3.0">3.0 秒 (均衡)</option>
            <option :value="5.0">5.0 秒 (省电)</option>
            <option :value="10.0">10.0 秒 (低频)</option>
          </select>
        </div>

        <div class="form-group">
          <label class="form-label">任务栏托盘提示模式</label>
          <select v-model="form.displayMode">
            <option value="仅图标">仅图标</option>
            <option value="图标 + 速率">图标 + 实时速率 (默认)</option>
            <option value="图标 + 套餐用量">图标 + 套餐用量</option>
            <option value="图标 + CPU/内存">图标 + CPU/内存占用</option>
            <option value="图标 + 温度">图标 + 芯片温度</option>
            <option value="图标 + Wi-Fi 设备数">图标 + Wi-Fi 设备数</option>
          </select>
        </div>

        <div class="form-group">
          <label class="form-label">无线投屏 ADB 端口</label>
          <input 
            v-model.number="form.screenMirroringPort" 
            type="number" 
            placeholder="5555" 
          />
        </div>
      </div>

      <!-- Save Button -->
      <div class="save-actions">
        <button class="btn-primary save-btn" @click="handleSave">
          保存并应用
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive } from 'vue';
import { state, saveConfig } from '../stores/f50Store.js';

const emit = defineEmits(['close']);

const showRouterPwd = ref(false);
const showUfiToken = ref(false);

const form = reactive({
  baseURL: state.config.baseURL,
  password: state.config.password,
  ufiToken: state.config.ufiToken,
  refreshInterval: state.config.refreshInterval,
  displayMode: state.config.displayMode,
  screenMirroringPort: state.config.screenMirroringPort,
  launchAtLogin: state.config.launchAtLogin
});

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
  gap: 14px;
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
  text-transform: uppercase;
  letter-spacing: 0.5px;
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

.save-actions {
  margin-top: 6px;
  display: flex;
  justify-content: flex-end;
}

.save-btn {
  width: 100%;
  padding: 8px 14px;
}
</style>
