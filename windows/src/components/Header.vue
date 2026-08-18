<template>
  <header class="header-container">
    <div class="header-left">
      <!-- Carrier Logo or Network Icon -->
      <div class="carrier-box">
        <img v-if="carrierLogo" :src="carrierLogo" class="carrier-logo" :alt="state.status.carrier" />
        <span v-else class="carrier-fallback-icon">📶</span>
      </div>

      <div class="header-info">
        <div class="title-row">
          <span class="device-name">F50 Monitor</span>
          <span :class="['badge-pill', networkBadgeClass]">
            {{ state.status.isOnline ? state.status.networkType : '离线' }}
          </span>
          <span v-if="state.status.isOnline && state.status.currentBands" class="badge-pill badge-gray">
            {{ state.status.currentBands }}
          </span>
        </div>
        <div class="subtitle-row">
          <span class="status-dot" :class="{ online: state.status.isOnline }"></span>
          <span class="carrier-name">{{ state.status.isOnline ? (state.status.carrier || '已连接') : (state.status.errorMessage || '未连接后台') }}</span>
          <span v-if="state.status.isOnline && state.status.qci" class="qci-tag">QCI {{ state.status.qci }}</span>
        </div>
      </div>
    </div>

    <div class="header-right">
      <!-- SMS Button with Unread Badge -->
      <button class="icon-btn" @click="emit('openSMS')" title="短信箱">
        <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path>
        </svg>
        <span v-if="state.status.smsUnreadCount > 0" class="unread-badge">
          {{ state.status.smsUnreadCount }}
        </span>
      </button>

      <!-- Refresh Button -->
      <button 
        class="icon-btn" 
        :class="{ spinning: state.isManualRefreshing }" 
        @click="handleRefresh" 
        :disabled="state.isManualRefreshing"
        title="刷新数据"
      >
        <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none">
          <polyline points="23 4 23 10 17 10"></polyline>
          <polyline points="1 20 1 14 7 14"></polyline>
          <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
        </svg>
      </button>

      <!-- Settings Button -->
      <button class="icon-btn" @click="emit('openSettings')" title="设置">
        <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" stroke-width="2" fill="none">
          <circle cx="12" cy="12" r="3"></circle>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
        </svg>
      </button>
    </div>
  </header>
</template>

<script setup>
import { computed } from 'vue';
import { state, fetchStatus } from '../stores/f50Store.js';
import mobileLogo from '../assets/ChinaMobileLogo.svg';
import unicomLogo from '../assets/ChinaUnicomLogo.svg';
import telecomLogo from '../assets/ChinaTelecomLogo.svg';
import broadnetLogo from '../assets/ChinaBroadnetLogo.png';

const emit = defineEmits(['openSMS', 'openSettings']);

const carrierLogo = computed(() => {
  const carrier = state.status.carrier || '';
  if (carrier.includes('移动')) return mobileLogo;
  if (carrier.includes('联通')) return unicomLogo;
  if (carrier.includes('电信')) return telecomLogo;
  if (carrier.includes('广电')) return broadnetLogo;
  return null;
});

const networkBadgeClass = computed(() => {
  if (!state.status.isOnline) return 'badge-gray';
  const type = state.status.networkType || '';
  if (type.includes('5G')) return 'badge-blue';
  if (type.includes('4G')) return 'badge-green';
  return 'badge-orange';
});

function handleRefresh() {
  fetchStatus(true);
}
</script>

<style scoped>
.header-container {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  background: var(--bg-card);
  border-bottom: 1px solid var(--border-card);
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.carrier-box {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: var(--bg-card-subtle);
  border: 1px solid var(--border-card);
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.carrier-logo {
  width: 22px;
  height: 22px;
  object-fit: contain;
}

.carrier-fallback-icon {
  font-size: 16px;
}

.header-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.title-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.device-name {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  letter-spacing: -0.2px;
}

.subtitle-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--text-secondary);
}

.status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--color-red);
  box-shadow: 0 0 6px var(--color-red);
}
.status-dot.online {
  background: var(--color-green);
  box-shadow: 0 0 6px var(--color-green);
}

.carrier-name {
  font-size: 11px;
  max-width: 140px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.qci-tag {
  font-size: 10px;
  font-family: var(--font-mono);
  background: rgba(56, 128, 235, 0.12);
  color: var(--color-blue);
  padding: 1px 4px;
  border-radius: 4px;
}

.header-right {
  display: flex;
  align-items: center;
  gap: 6px;
}

.icon-btn {
  background: var(--bg-control);
  border: 1px solid var(--border-card);
  color: var(--text-primary);
  border-radius: 8px;
  width: 30px;
  height: 30px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  position: relative;
  transition: all 0.15s ease;
}
.icon-btn:hover {
  background: var(--bg-control-hover);
  color: var(--color-blue);
}
.icon-btn:active {
  transform: scale(0.95);
}

.unread-badge {
  position: absolute;
  top: -3px;
  right: -3px;
  background: var(--color-red);
  color: #FFF;
  font-size: 9px;
  font-weight: 700;
  border-radius: 999px;
  min-width: 14px;
  height: 14px;
  padding: 0 3px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1.5px solid var(--bg-card);
}

.spinning svg {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  100% { transform: rotate(360deg); }
}
</style>
