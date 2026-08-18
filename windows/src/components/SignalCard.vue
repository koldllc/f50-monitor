<template>
  <div class="f50-card signal-card">
    <div class="card-title-row">
      <div class="title-left">
        <span class="card-icon">📶</span>
        <span class="card-title">蜂窝信号质量</span>
      </div>
      <div class="signal-bars">
        <div 
          v-for="i in 5" 
          :key="i" 
          class="bar" 
          :class="{ active: i <= state.status.signalBar }"
          :style="{ height: `${i * 3 + 3}px` }"
        ></div>
      </div>
    </div>

    <!-- Subscription / QCI Status Banner if available -->
    <div v-if="state.status.qci || state.status.qosDl || state.status.qosUl" class="subscription-banner">
      <span class="banner-label">签约状态：</span>
      <span v-if="state.status.qci" class="qci-text">QCI: {{ state.status.qci }}</span>
      <span v-if="state.status.qosDl" class="rate-badge dl-badge">
        <span class="arrow">⬇</span> {{ state.status.qosDl }}
      </span>
      <span v-if="state.status.qosUl" class="rate-badge ul-badge">
        <span class="arrow">⬆</span> {{ state.status.qosUl }}
      </span>
    </div>

    <div class="metrics-grid">
      <!-- RSRP -->
      <div class="metric-col">
        <div class="metric-head">
          <span class="metric-name">RSRP</span>
          <span class="quality-badge" :style="{ color: rsrpInfo.color, background: rsrpInfo.color + '1A' }">
            {{ rsrpInfo.label }}
          </span>
        </div>
        <div class="metric-val">{{ state.status.rsrp || 'N/A' }}</div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${rsrpInfo.ratio * 100}%`, backgroundColor: rsrpInfo.color }"></div>
        </div>
      </div>

      <!-- SINR / SNR -->
      <div class="metric-col">
        <div class="metric-head">
          <span class="metric-name">SINR / SNR</span>
          <span class="quality-badge" :style="{ color: snrInfo.color, background: snrInfo.color + '1A' }">
            {{ snrInfo.label }}
          </span>
        </div>
        <div class="metric-val">{{ state.status.snr || 'N/A' }}</div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${snrInfo.ratio * 100}%`, backgroundColor: snrInfo.color }"></div>
        </div>
      </div>

      <!-- RSRQ -->
      <div class="metric-col">
        <div class="metric-head">
          <span class="metric-name">RSRQ</span>
          <span class="quality-badge" :style="{ color: rsrqInfo.color, background: rsrqInfo.color + '1A' }">
            {{ rsrqInfo.label }}
          </span>
        </div>
        <div class="metric-val">{{ state.status.rsrq || 'N/A' }}</div>
        <div class="progress-bar-track">
          <div class="progress-bar-fill" :style="{ width: `${rsrqInfo.ratio * 100}%`, backgroundColor: rsrqInfo.color }"></div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { state, parseSignalQuality } from '../stores/f50Store.js';

const rsrpInfo = computed(() => parseSignalQuality(state.status.rsrp, 'rsrp'));
const snrInfo = computed(() => parseSignalQuality(state.status.snr, 'snr'));
const rsrqInfo = computed(() => parseSignalQuality(state.status.rsrq, 'rsrq'));
</script>

<style scoped>
.signal-card {
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

.signal-bars {
  display: flex;
  align-items: flex-end;
  gap: 2.5px;
  height: 18px;
}

.bar {
  width: 3px;
  background: var(--bg-control);
  border-radius: 1px;
}
.bar.active {
  background: var(--color-green);
}

.subscription-banner {
  display: flex;
  align-items: center;
  gap: 6px;
  background: var(--bg-card-subtle);
  border: 1px solid var(--border-subtle);
  border-radius: 6px;
  padding: 4px 8px;
  font-size: 10px;
}

.banner-label {
  color: var(--text-muted);
}

.qci-text {
  font-weight: 700;
  font-family: var(--font-mono);
  color: var(--text-primary);
}

.rate-badge {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  font-weight: 700;
  font-family: var(--font-mono);
  color: var(--color-blue);
  background: rgba(56, 128, 235, 0.12);
  padding: 1px 4px;
  border-radius: 4px;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
}

.metric-col {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.metric-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.metric-name {
  font-size: 10px;
  font-weight: 600;
  color: var(--text-secondary);
}

.quality-badge {
  font-size: 9px;
  font-weight: 700;
  padding: 1px 4px;
  border-radius: 4px;
}

.metric-val {
  font-size: 12px;
  font-weight: 600;
  font-family: var(--font-mono);
  color: var(--text-primary);
}
</style>
