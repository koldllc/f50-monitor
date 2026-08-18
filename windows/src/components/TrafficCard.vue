<template>
  <div class="f50-card traffic-card">
    <div class="card-title-row">
      <div class="title-left">
        <span class="card-icon">📊</span>
        <span class="card-title">套餐流量</span>
      </div>

      <div class="title-right">
        <span v-if="state.status.daysUntilReset !== null && state.status.daysUntilReset !== undefined" class="reset-badge">
          {{ state.status.daysUntilReset === 0 ? '今天重置' : `${state.status.daysUntilReset}天后重置` }}
        </span>
      </div>
    </div>

    <!-- Package Usage Line -->
    <div class="traffic-header-line">
      <span class="usage-text">
        已用流量：<strong>{{ formatBytes(computedTraffic.packageUsed) }}</strong>
      </span>
      <span class="limit-text">
        总流量：{{ computedTraffic.limit > 0 ? formatBytes(computedTraffic.limit) : '不限' }}
      </span>
    </div>

    <!-- Package Usage Progress Bar -->
    <div class="progress-bar-track">
      <div 
        class="progress-bar-fill" 
        :style="{ 
          width: `${computedTraffic.ratio * 100}%`, 
          backgroundColor: computedTraffic.color 
        }"
      ></div>
    </div>

    <!-- Percentage badge & Reset day -->
    <div class="traffic-sub-row" v-if="computedTraffic.limit > 0 || state.status.trafficResetDay > 0">
      <span v-if="computedTraffic.limit > 0" class="percent-badge" :style="{ color: computedTraffic.color, background: computedTraffic.color + '26' }">
        {{ (computedTraffic.ratio * 100).toFixed(0) }}%
      </span>
      <span v-else></span>

      <span v-if="state.status.trafficResetDay > 0" class="reset-day-hint">
        每月 {{ state.status.trafficResetDay }} 日清零
      </span>
    </div>

    <div class="divider-line"></div>

    <!-- 2 Sub metrics: 当日流量 & 本月已用 -->
    <div class="sub-metrics-grid">
      <div class="sub-metric-item">
        <div class="sub-metric-head">
          <span class="sub-icon orange-icon">☀️</span>
          <span class="sub-metric-label">当日流量</span>
        </div>
        <span class="sub-metric-val">{{ formatBytes(computedTraffic.todayUsed) }}</span>
      </div>
      <div class="divider-sub"></div>
      <div class="sub-metric-item">
        <div class="sub-metric-head">
          <span class="sub-icon purple-icon">📅</span>
          <span class="sub-metric-label">本月已用</span>
        </div>
        <span class="sub-metric-val">{{ formatBytes(computedTraffic.monthUsed) }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { state, computedTraffic, formatBytes } from '../stores/f50Store.js';
</script>

<style scoped>
.traffic-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
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

.reset-badge {
  font-size: 10px;
  font-weight: 600;
  color: var(--color-orange);
  background: rgba(240, 148, 51, 0.12);
  padding: 1px 6px;
  border-radius: 4px;
}

.traffic-header-line {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 11px;
  color: var(--text-secondary);
}

.traffic-header-line strong {
  font-family: var(--font-mono);
  color: var(--text-primary);
  font-size: 12px;
}

.limit-text {
  font-family: var(--font-mono);
  font-size: 11px;
}

.traffic-sub-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 10px;
}

.percent-badge {
  font-size: 10px;
  font-weight: 700;
  font-family: var(--font-mono);
  padding: 1px 6px;
  border-radius: 999px;
}

.reset-day-hint {
  color: var(--text-muted);
  font-size: 10px;
}

.divider-line {
  height: 1px;
  background: var(--border-card);
  margin: 2px 0;
  opacity: 0.6;
}

.sub-metrics-grid {
  display: flex;
  align-items: center;
}

.sub-metric-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
}

.sub-metric-head {
  display: flex;
  align-items: center;
  gap: 4px;
}

.sub-icon {
  font-size: 11px;
}

.sub-metric-label {
  font-size: 10px;
  color: var(--text-secondary);
  font-weight: 500;
}

.sub-metric-val {
  font-size: 13px;
  font-weight: 700;
  font-family: var(--font-mono);
  color: var(--text-primary);
}

.divider-sub {
  width: 1px;
  height: 24px;
  background: var(--border-card);
  margin: 0 8px;
}
</style>
