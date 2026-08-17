<template>
  <div class="mirror-view-container">
    <!-- Sub Header -->
    <div class="sub-header">
      <button class="btn-icon back-btn" @click="emit('close')">
        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
        <span>返回</span>
      </button>

      <span class="sub-title">无线屏幕镜像 (scrcpy)</span>

      <div style="width: 48px"></div>
    </div>

    <div class="mirror-content">
      <!-- Feature Poster Card -->
      <div class="mirror-info-card">
        <span class="info-icon">📺</span>
        <div class="info-texts">
          <span class="info-title">无线 ADB 投屏</span>
          <span class="info-desc">将 F50 随身 WiFi 的屏幕与操作无延迟镜像到 Windows 桌面</span>
        </div>
      </div>

      <!-- Dependencies Status Card -->
      <div class="dep-card">
        <div class="dep-row">
          <span class="dep-label">ADB 调试工具</span>
          <span class="badge-pill" :class="state.scrcpy.hasAdb ? 'badge-green' : 'badge-orange'">
            {{ state.scrcpy.hasAdb ? '已就绪' : '未检测到' }}
          </span>
        </div>
        <div class="dep-row">
          <span class="dep-label">scrcpy 镜像组件</span>
          <span class="badge-pill" :class="state.scrcpy.hasScrcpy ? 'badge-green' : 'badge-orange'">
            {{ state.scrcpy.hasScrcpy ? '已就绪' : '未检测到' }}
          </span>
        </div>
      </div>

      <!-- Status or Progress hint -->
      <div v-if="state.scrcpy.statusMessage" class="status-box">
        <span>{{ state.scrcpy.statusMessage }}</span>
      </div>

      <!-- Action Buttons -->
      <div class="action-footer">
        <button 
          v-if="!state.scrcpy.isInstalled" 
          class="btn-primary full-btn" 
          :disabled="state.scrcpy.isDownloading"
          @click="downloadScrcpy"
        >
          <span v-if="state.scrcpy.isDownloading" class="loading-spinner-sm"></span>
          <span>{{ state.scrcpy.isDownloading ? '正在自动下载组件...' : '一键下载并配置 scrcpy 组件' }}</span>
        </button>

        <button 
          v-else 
          class="btn-primary full-btn" 
          :disabled="state.scrcpy.isConnecting || !state.status.isOnline"
          @click="launchMirroring"
        >
          <span v-if="state.scrcpy.isConnecting" class="loading-spinner-sm"></span>
          <span>{{ state.scrcpy.isConnecting ? '正在连接设备...' : '启动无线投屏' }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted } from 'vue';
import { state, checkScrcpy, downloadScrcpy, launchMirroring } from '../stores/f50Store.js';

const emit = defineEmits(['close']);

onMounted(() => {
  checkScrcpy();
});
</script>

<style scoped>
.mirror-view-container {
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

.mirror-content {
  flex: 1;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.mirror-info-card {
  background: var(--bg-card);
  border: 1px solid var(--border-card);
  border-radius: 8px;
  padding: 14px;
  display: flex;
  align-items: center;
  gap: 12px;
}

.info-icon {
  font-size: 28px;
}

.info-texts {
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.info-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--text-primary);
}

.info-desc {
  font-size: 11px;
  color: var(--text-secondary);
  line-height: 1.4;
}

.dep-card {
  background: var(--bg-card);
  border: 1px solid var(--border-card);
  border-radius: 8px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.dep-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.dep-label {
  font-size: 12px;
  font-weight: 500;
  color: var(--text-primary);
}

.status-box {
  background: rgba(56, 128, 235, 0.1);
  border: 1px solid rgba(56, 128, 235, 0.2);
  color: var(--color-blue);
  font-size: 11px;
  padding: 8px 12px;
  border-radius: 6px;
}

.action-footer {
  margin-top: auto;
}

.full-btn {
  width: 100%;
  padding: 10px;
  font-size: 13px;
}

.loading-spinner-sm {
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #FFF;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  100% { transform: rotate(360deg); }
}
</style>
