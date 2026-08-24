<template>
  <div class="feedback-modal-overlay" v-if="isOpen">
    <div class="feedback-modal-card">
      <div class="modal-header">
        <span class="modal-title">📋 问题反馈与设备适配</span>
        <button class="close-btn" @click="handleClose">✕</button>
      </div>

      <div class="modal-body">
        <div class="form-group">
          <label class="form-label">反馈类型</label>
          <select v-model="category" :disabled="isSubmitting">
            <option value="新设备适配">➕ 新设备适配</option>
            <option value="无法连接 / 频繁断连">📶 无法连接 / 频繁断连</option>
            <option value="数据缺失 / 显示不全">❓ 数据缺失 / 显示不全</option>
            <option value="数据不准 / 速率或流量偏差">⚡ 数据不准 / 速率或流量偏差</option>
            <option value="短信读取 / 发送异常">✉️ 短信读取 / 发送异常</option>
            <option value="无线投屏 (scrcpy) 异常">📺 无线投屏 (scrcpy) 异常</option>
            <option value="功能建议 / 体验优化">💡 功能建议 / 体验优化</option>
            <option value="软件崩溃 / 其他程序 Bug">🐞 软件崩溃 / 其他程序 Bug</option>
          </select>
        </div>

        <div class="form-group">
          <label class="form-label">设备品牌与型号 (选填)</label>
          <input
            v-model="deviceModel"
            type="text"
            placeholder="例如：中兴 F50 / F30 Pro / 华为 5G CPE"
            :disabled="isSubmitting"
          />
        </div>

        <div class="form-group">
          <label class="form-label">您的联系方式 (选填)</label>
          <input
            v-model="contact"
            type="text"
            placeholder="微信 / QQ / 邮箱"
            :disabled="isSubmitting"
          />
        </div>

        <div class="form-group">
          <label class="form-label">详细问题描述 (必填，至少 4 字)</label>
          <textarea
            v-model="userNotes"
            rows="3"
            placeholder="请详细描述触发问题的操作步骤、提示信息或异常现象..."
            :disabled="isSubmitting"
          ></textarea>
        </div>

        <div class="status-box error" v-if="errorMessage">
          ⚠️ {{ errorMessage }}
        </div>

        <div class="status-box success" v-if="successMessage">
          ✅ {{ successMessage }}
          <a v-if="issueUrl" :href="issueUrl" target="_blank" rel="noopener noreferrer" class="feedback-link">
            查看反馈处理进度 ↗
          </a>
        </div>
      </div>

      <div class="modal-footer">
        <button class="btn-cancel" @click="handleClose" :disabled="isSubmitting">取消</button>
        <button class="btn-submit" @click="handleSubmit" :disabled="isSubmitting || userNotes.trim().length < 4">
          {{ isSubmitting ? '正在抓取诊断并提交...' : '一键抓取并发送反馈' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { invokePlatform } from '../stores/f50Store.js';

const props = defineProps({
  isOpen: Boolean
});

const emit = defineEmits(['close']);

const category = ref('新设备适配');
const deviceModel = ref('');
const contact = ref('');
const userNotes = ref('');
const isSubmitting = ref(false);
const errorMessage = ref('');
const successMessage = ref('');
const issueUrl = ref('');

function handleClose() {
  errorMessage.value = '';
  successMessage.value = '';
  issueUrl.value = '';
  emit('close');
}

async function handleSubmit() {
  if (userNotes.value.trim().length < 4) {
    errorMessage.value = '请在「详细问题描述」中至少输入 4 个字符以提供复现说明。';
    return;
  }

  isSubmitting.value = true;
  errorMessage.value = '';
  successMessage.value = '';
  issueUrl.value = '';

  try {
    const res = await invokePlatform('submit_feedback', {
      category: category.value,
      deviceModel: deviceModel.value,
      userNotes: userNotes.value,
      contact: contact.value
    });
    successMessage.value = res?.message || '反馈提交成功！开发者将尽快跟进处理。';
    issueUrl.value = res?.issueUrl || '';
  } catch (err) {
    errorMessage.value = String(err);
  } finally {
    isSubmitting.value = false;
  }
}
</script>

<style scoped>
.feedback-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.feedback-modal-card {
  width: 90%;
  max-width: 440px;
  background: var(--bg-card, #ffffff);
  border-radius: 12px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border-card, #e5e5e5);
}

.modal-title {
  font-weight: bold;
  font-size: 14px;
}

.close-btn {
  background: none;
  border: none;
  font-size: 14px;
  cursor: pointer;
  color: #888;
}

.modal-body {
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.form-label {
  font-size: 11px;
  font-weight: 600;
  color: #666;
}

input[type="text"], select, textarea {
  width: 100%;
  padding: 6px 8px;
  border-radius: 6px;
  border: 1px solid #ddd;
  font-size: 12px;
  box-sizing: border-box;
}

.status-box {
  padding: 8px;
  border-radius: 6px;
  font-size: 11px;
}

.status-box.error {
  background: rgba(255, 149, 0, 0.1);
  color: #d97706;
}

.status-box.success {
  background: rgba(52, 199, 89, 0.1);
  color: #15803d;
}

.feedback-link {
  display: block;
  width: fit-content;
  margin-top: 6px;
  color: #007aff;
  font-weight: 600;
  text-decoration: none;
}

.feedback-link:hover {
  text-decoration: underline;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 10px 16px;
  border-top: 1px solid var(--border-card, #e5e5e5);
  background: var(--bg-panel, #f9f9f9);
}

.btn-cancel {
  padding: 5px 12px;
  border-radius: 6px;
  border: 1px solid #ccc;
  background: white;
  font-size: 12px;
  cursor: pointer;
}

.btn-submit {
  padding: 5px 12px;
  border-radius: 6px;
  border: none;
  background: #007aff;
  color: white;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.btn-submit:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
