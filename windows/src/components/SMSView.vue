<template>
  <div class="sms-view-container">
    <!-- Sub Header -->
    <div class="sub-header">
      <button class="btn-icon back-btn" @click="emit('close')">
        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
        <span>返回</span>
      </button>

      <span class="sub-title">短信收件箱</span>

      <div class="sub-actions">
        <button class="btn-icon" @click="emit('openCompose')" title="写短信">
          <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
            <path d="M12 20h9"></path>
            <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
          </svg>
        </button>

        <button class="btn-icon" :class="{ spinning: state.sms.isFetching }" @click="fetchSMS" title="刷新短信">
          <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
            <polyline points="23 4 23 10 17 10"></polyline>
            <polyline points="1 20 1 14 7 14"></polyline>
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
          </svg>
        </button>
      </div>
    </div>

    <!-- Content List -->
    <div class="sms-content-area">
      <div v-if="state.sms.isFetching && state.sms.messages.length === 0" class="empty-state">
        <span class="loading-spinner"></span>
        <p>正在读取短信...</p>
      </div>

      <div v-else-if="state.sms.errorMessage && state.sms.messages.length === 0" class="empty-state error-state">
        <span class="empty-icon">⚠️</span>
        <p>{{ state.sms.errorMessage }}</p>
        <button class="btn-primary" @click="fetchSMS">重试</button>
      </div>

      <div v-else-if="state.sms.messages.length === 0" class="empty-state">
        <span class="empty-icon">📭</span>
        <p>暂无短信记录</p>
      </div>

      <div v-else class="sms-list">
        <div 
          v-for="msg in state.sms.messages" 
          :key="msg.id" 
          class="sms-card"
          :class="{ unread: msg.isUnread }"
        >
          <div class="sms-meta">
            <div class="sms-sender">
              <span v-if="msg.isUnread" class="unread-dot"></span>
              <strong>{{ msg.number }}</strong>
              <span v-if="msg.isOutgoing" class="badge-pill badge-gray">已发送</span>
            </div>
            <span class="sms-date">{{ msg.dateText }}</span>
          </div>

          <div class="sms-body">
            {{ msg.content }}
          </div>

          <!-- Quick Copy Verify Code Button -->
          <div v-if="extractVerifyCode(msg.content)" class="verify-action-row">
            <button class="copy-code-btn" @click="copyCode(extractVerifyCode(msg.content))">
              <svg viewBox="0 0 24 24" width="12" height="12" stroke="currentColor" stroke-width="2" fill="none">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
              </svg>
              <span>复制验证码 <strong>{{ extractVerifyCode(msg.content) }}</strong></span>
            </button>
            <span v-if="copiedCode === extractVerifyCode(msg.content)" class="copied-hint">已复制!</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { state, fetchSMS, extractVerifyCode } from '../stores/f50Store.js';

const emit = defineEmits(['close', 'openCompose']);
const copiedCode = ref(null);

onMounted(() => {
  if (state.sms.messages.length === 0) {
    fetchSMS();
  }
});

function copyCode(code) {
  if (!code) return;
  navigator.clipboard.writeText(code);
  copiedCode.value = code;
  setTimeout(() => {
    if (copiedCode.value === code) copiedCode.value = null;
  }, 2000);
}
</script>

<style scoped>
.sms-view-container {
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

.sub-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}

.sms-content-area {
  flex: 1;
  overflow-y: auto;
  padding: 12px;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 280px;
  gap: 10px;
  color: var(--text-secondary);
}

.empty-icon {
  font-size: 32px;
}

.loading-spinner {
  width: 24px;
  height: 24px;
  border: 2px solid var(--bg-control);
  border-top-color: var(--color-blue);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

.sms-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.sms-card {
  background: var(--bg-card);
  border: 1px solid var(--border-card);
  border-radius: 8px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  transition: border-color 0.2s ease;
}

.sms-card.unread {
  border-color: rgba(56, 128, 235, 0.4);
  background: var(--bg-card-subtle);
}

.sms-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.sms-sender {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
}

.unread-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--color-blue);
}

.sms-date {
  font-size: 10px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}

.sms-body {
  font-size: 12px;
  color: var(--text-primary);
  line-height: 1.45;
  user-select: text;
  -webkit-user-select: text;
  word-break: break-word;
}

.verify-action-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
}

.copy-code-btn {
  background: rgba(56, 128, 235, 0.12);
  border: 1px solid rgba(56, 128, 235, 0.25);
  color: var(--color-blue);
  border-radius: 6px;
  padding: 4px 8px;
  font-size: 11px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.copy-code-btn:hover {
  background: rgba(56, 128, 235, 0.2);
}

.copied-hint {
  font-size: 10px;
  font-weight: 600;
  color: var(--color-green);
}

.spinning svg {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  100% { transform: rotate(360deg); }
}
</style>
