<template>
  <div class="compose-view-container">
    <!-- Sub Header -->
    <div class="sub-header">
      <button class="btn-icon back-btn" @click="emit('close')" :disabled="state.sms.isSending">
        <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
        <span>返回</span>
      </button>

      <span class="sub-title">写短信</span>

      <div style="width: 48px"></div>
    </div>

    <!-- Form Area -->
    <div class="form-content">
      <div class="form-group">
        <label class="form-label">接收号码</label>
        <input 
          v-model="number" 
          type="text" 
          placeholder="例如 10086 或 13800138000" 
          :disabled="state.sms.isSending"
        />
      </div>

      <div class="form-group">
        <div class="label-row">
          <label class="form-label">短信内容</label>
          <span class="char-count">{{ content.length }} 字</span>
        </div>
        <textarea 
          v-model="content" 
          rows="6" 
          placeholder="输入要发送的短信内容..." 
          :disabled="state.sms.isSending"
        ></textarea>
      </div>

      <!-- Error hint -->
      <div v-if="state.sms.sendErrorMessage" class="error-hint">
        <span>⚠️ {{ state.sms.sendErrorMessage }}</span>
      </div>

      <!-- Success hint -->
      <div v-if="state.sms.sendSuccess" class="success-hint">
        <span>✅ 短信发送成功！</span>
      </div>

      <div class="form-actions">
        <button class="btn-primary send-btn" :disabled="!canSend" @click="handleSend">
          <span v-if="state.sms.isSending" class="loading-spinner-sm"></span>
          <span>{{ state.sms.isSending ? '正在发送...' : '发送短信' }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue';
import { state, sendSMS } from '../stores/f50Store.js';

const emit = defineEmits(['close', 'sent']);

const number = ref('');
const content = ref('');

const canSend = computed(() => {
  return number.value.trim().length > 0 
    && content.value.trim().length > 0 
    && !state.sms.isSending;
});

async function handleSend() {
  if (!canSend.value) return;
  const success = await sendSMS(number.value.trim(), content.value.trim());
  if (success) {
    number.value = '';
    content.value = '';
    setTimeout(() => {
      emit('sent');
    }, 1200);
  }
}
</script>

<style scoped>
.compose-view-container {
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

.form-content {
  flex: 1;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
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

.char-count {
  font-size: 10px;
  color: var(--text-muted);
  font-family: var(--font-mono);
}

textarea {
  resize: none;
  line-height: 1.4;
}

.error-hint {
  font-size: 11px;
  color: var(--color-red);
  background: rgba(224, 82, 82, 0.1);
  padding: 6px 10px;
  border-radius: 6px;
}

.success-hint {
  font-size: 11px;
  color: var(--color-green);
  background: rgba(46, 173, 115, 0.1);
  padding: 6px 10px;
  border-radius: 6px;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: auto;
}

.send-btn {
  width: 130px;
  padding: 8px 14px;
}

.loading-spinner-sm {
  width: 12px;
  height: 12px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #FFF;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  100% { transform: rotate(360deg); }
}
</style>
