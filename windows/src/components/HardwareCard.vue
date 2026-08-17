<template>
  <div class="f50-card hardware-card">
    <div class="card-title-row">
      <div class="title-left">
        <span class="card-icon">⚡</span>
        <span class="card-title">硬件与连接状态</span>
      </div>

      <div class="title-right">
        <!-- Wi-Fi Connected Devices -->
        <span class="device-pill">
          <svg viewBox="0 0 24 24" width="12" height="12" stroke="currentColor" stroke-width="2" fill="none">
            <path d="M5 12.55a11 11 0 0 1 14.08 0"></path>
            <path d="M1.42 9a16 16 0 0 1 21.16 0"></path>
            <path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>
            <line x1="12" y1="20" x2="12.01" y2="20"></line>
          </svg>
          Wi-Fi: {{ state.status.connectedDevices }} 台
        </span>

        <!-- Battery if available -->
        <span v-if="state.status.batteryValue >= 0" class="battery-pill">
          🔋 {{ state.status.batteryValue }}% {{ state.status.isCharging ? '⚡' : '' }}
        </span>
      </div>
    </div>

    <div class="hw-grid">
      <!-- CPU -->
      <div class="hw-col">
        <div class="hw-head">
          <span class="hw-name">CPU</span>
          <span class="hw-val" :style="{ color: cpuColor }">{{ state.status.cpuUsage ? state.status.cpuUsage.toFixed(0) : 0 }}%</span>
        </div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${state.status.cpuUsage || 0}%`, backgroundColor: cpuColor }"></div>
        </div>
      </div>

      <!-- Memory -->
      <div class="hw-col">
        <div class="hw-head">
          <span class="hw-name">内存</span>
          <span class="hw-val" :style="{ color: memColor }">{{ state.status.memUsage ? state.status.memUsage.toFixed(0) : 0 }}%</span>
        </div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${state.status.memUsage || 0}%`, backgroundColor: memColor }"></div>
        </div>
      </div>

      <!-- Temperature -->
      <div class="hw-col">
        <div class="hw-head">
          <span class="hw-name">芯片温度</span>
          <span class="hw-val" :style="{ color: tempColor }">{{ state.status.temperature ? state.status.temperature.toFixed(1) : 0 }}℃</span>
        </div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${Math.min(100, (state.status.temperature || 0) * 1.2)}%`, backgroundColor: tempColor }"></div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { state } from '../stores/f50Store.js';

const cpuColor = computed(() => {
  const v = state.status.cpuUsage || 0;
  if (v < 50) return 'var(--color-green)';
  if (v < 80) return 'var(--color-orange)';
  return 'var(--color-red)';
});

const memColor = computed(() => {
  const v = state.status.memUsage || 0;
  if (v < 60) return 'var(--color-green)';
  if (v < 85) return 'var(--color-orange)';
  return 'var(--color-red)';
});

const tempColor = computed(() => {
  const v = state.status.temperature || 0;
  if (v < 45) return 'var(--color-green)';
  if (v < 60) return 'var(--color-orange)';
  return 'var(--color-red)';
});
</script>

<style scoped>
.hardware-card {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.card-title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.title-left {
  display: flex;
  align-items: center;
  gap: 6px;
}

.card-icon {
  font-size: 13px;
}

.card-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-primary);
}

.title-right {
  display: flex;
  align-items: center;
  gap: 6px;
}

.device-pill {
  font-size: 10px;
  font-weight: 600;
  color: var(--color-blue);
  background: rgba(56, 128, 235, 0.12);
  padding: 2px 6px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  gap: 4px;
}

.battery-pill {
  font-size: 10px;
  font-weight: 600;
  color: var(--color-green);
  background: rgba(46, 173, 115, 0.12);
  padding: 2px 6px;
  border-radius: 4px;
}

.hw-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
}

.hw-col {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.hw-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.hw-name {
  font-size: 10px;
  font-weight: 600;
  color: var(--text-secondary);
}

.hw-val {
  font-size: 11px;
  font-weight: 700;
  font-family: var(--font-mono);
}
</style>
