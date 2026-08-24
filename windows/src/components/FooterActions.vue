<template>
  <footer class="footer-container">
    <!-- Web Admin Dual Entrance & Screen Mirroring Grid -->
    <div class="actions-grid" :class="{ 'android-grid': isAndroidPlatform }">
      <!-- Screen Mirroring Button -->
      <button v-if="!isAndroidPlatform" class="action-card-btn" @click="emit('openMirror')" title="无线 ADB + scrcpy 设备屏幕镜像">
        <span class="action-icon">📺</span>
        <div class="action-texts">
          <span class="action-title">无线投屏</span>
          <span class="action-desc">scrcpy 镜像</span>
        </div>
      </button>

      <!-- UFI Tools Web Admin (Port 2333) -->
      <button class="action-card-btn" @click="openWebAdmin('ufi')" title="打开 UFI 高级后台 (Port 2333)">
        <span class="action-icon">⚡</span>
        <div class="action-texts">
          <span class="action-title">UFI 后台</span>
          <span class="action-desc">2333 端口</span>
        </div>
      </button>

      <!-- ZTE Router Admin (Port 80) -->
      <button class="action-card-btn" @click="openWebAdmin('router')" title="打开中兴官方路由器管理后台 (Port 80)">
        <span class="action-icon">🌐</span>
        <div class="action-texts">
          <span class="action-title">中兴后台</span>
          <span class="action-desc">80 端口</span>
        </div>
      </button>
    </div>
  </footer>
</template>

<script setup>
import { openWebAdmin, isAndroidPlatform } from '../stores/f50Store.js';

const emit = defineEmits(['openMirror']);
</script>

<style scoped>
.footer-container {
  padding: 10px 14px;
  background: var(--bg-card);
  border-top: 1px solid var(--border-card);
}

.actions-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.actions-grid.android-grid {
  grid-template-columns: repeat(2, 1fr);
}

.action-card-btn {
  background: var(--bg-card-subtle);
  border: 1px solid var(--border-card);
  border-radius: 8px;
  padding: 8px 10px;
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  color: var(--text-primary);
  text-align: left;
  transition: all 0.15s ease;
}

.action-card-btn:hover {
  background: var(--bg-control-hover);
  border-color: rgba(56, 128, 235, 0.3);
  transform: translateY(-1px);
}

.action-card-btn:active {
  transform: translateY(0);
}

.action-icon {
  font-size: 16px;
}

.action-texts {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.action-title {
  font-size: 11px;
  font-weight: 600;
}

.action-desc {
  font-size: 9px;
  color: var(--text-muted);
}
</style>
