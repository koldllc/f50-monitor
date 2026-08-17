<template>
  <div class="f50-card traffic-card">
    <div class="card-title-row">
      <div class="title-left">
        <span class="card-icon">📊</span>
        <span class="card-title">套餐流量信息</span>
      </div>

      <div class="title-right">
        <span v-if="state.status.daysUntilReset !== null && state.status.daysUntilReset !== undefined" class="reset-badge">
          {{ state.status.daysUntilReset }} 天后重置
        </span>
        <span v-if="state.status.qosDl && state.status.qosUl" class="qos-badge">
          签约 ⬇{{ state.status.qosDl }} ⬆{{ state.status.qosUl }}
        </span>
      </div>
    </div>

    <!-- Package Usage Progress -->
    <div class="package-section">
      <div class="usage-summary">
        <span class="usage-label">套餐已用</span>
        <span class="usage-amount">
          <strong :style="{ color: computedTraffic.color }">{{ formatBytes(computedTraffic.packageUsed) }}</strong>
          <span class="usage-total"> / {{ computedTraffic.limit > 0 ? formatBytes(computedTraffic.limit) : '不限量' }}</span>
        </span>
      </div>
      <div class="progress-bar-track">
        <div 
          class="progress-bar-fill" 
          :style="{ 
            width: `${computedTraffic.ratio * 100}%`, 
            backgroundColor: computedTraffic.color 
          }"
        ></div>
      </div>
    </div>

    <!-- Sub metrics: Today vs This Month -->
    <div class="sub-metrics-grid">
      <div class="sub-metric-item">
        <span class="sub-metric-label">当日累计</span>
        <span class="sub-metric-val">{{ formatBytes(computedTraffic.todayUsed) }}</span>
      </div>
      <div class="divider-sub"></div>
      <div class="sub-metric-item">
        <span class="sub-metric-label">本月累计</span>
        <span class="sub-metric-val">{{ formatBytes(computedTraffic.monthUsed) }}</span>
      </div>
      <div v-if="state.status.trafficResetDay > 0" class="divider-sub"></div>
      <div v-if="state.status.trafficResetDay > 0" class="sub-metric-item">
        <span class="sub-metric-label">账单重置日</span>
        <span class="sub-metric-val">每月 {{ state.status.trafficResetDay }} 日</span>
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

.reset-badge {
  font-size: 10px;
  font-weight: 600;
  color: var(--color-orange);
  background: rgba(240, 148, 51, 0.12);
  padding: 2px 6px;
  border-radius: 4px;
}

.qos-badge {
  font-size: 10px;
  font-family: var(--font-mono);
  color: var(--color-blue);
  background: rgba(56, 128, 235, 0.12);
  padding: 2px 6px;
  border-radius: 4px;
}

.package-section {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.usage-summary {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}

.usage-label {
  font-size: 11px;
  color: var(--text-secondary);
}

.usage-amount {
  font-size: 13px;
  font-family: var(--font-mono);
}

.usage-amount strong {
  font-size: 14px;
  font-weight: 700;
}

.usage-total {
  font-size: 11px;
  color: var(--text-secondary);
}

.sub-metrics-grid {
  display: flex;
  align-items: center;
  background: var(--bg-card-subtle);
  border-radius: 6px;
  padding: 6px 10px;
  border: 1px solid var(--border-subtle);
}

.sub-metric-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.sub-metric-label {
  font-size: 10px;
  color: var(--text-muted);
}

.sub-metric-val {
  font-size: 11px;
  font-weight: 600;
  font-family: var(--font-mono);
  color: var(--text-primary);
}

.divider-sub {
  width: 1px;
  height: 22px;
  background: var(--border-card);
  margin: 0 8px;
}
</style>
