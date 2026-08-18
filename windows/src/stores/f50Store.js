import { reactive, computed } from 'vue';

// Tauri API wrapper with browser fallback for dev/preview
const isTauri = typeof window !== 'undefined' && Boolean(window.__TAURI_INTERNALS__);

async function invokeTauri(cmd, args = {}) {
  if (isTauri) {
    const { invoke } = await import('@tauri-apps/api/core');
    return await invoke(cmd, args);
  }
  console.warn(`[Browser Mode] Simulated invoke: ${cmd}`, args);
  return mockInvoke(cmd, args);
}

// Mock fallback for browser preview
let mockDl = 1024 * 1024 * 3.5;
let mockUl = 1024 * 512;
function mockInvoke(cmd, args) {
  switch (cmd) {
    case 'get_status':
      mockDl = Math.max(1024 * 100, mockDl + (Math.random() - 0.48) * 1024 * 800);
      mockUl = Math.max(1024 * 50, mockUl + (Math.random() - 0.48) * 1024 * 200);
      return {
        isOnline: true,
        errorMessage: null,
        networkType: '5G SA',
        signalBar: 4,
        rsrp: '-82 dBm',
        rsrq: '-8 dB',
        snr: '18 dB',
        carrier: '中国移动',
        currentBands: 'n78 + B3',
        pppStatus: '已连接',
        qci: '9',
        qosDl: '1000Mbps',
        qosUl: '150Mbps',
        dlSpeed: mockDl,
        ulSpeed: mockUl,
        dlHistory: Array.from({ length: 16 }, () => Math.random() * 1024 * 1024 * 5),
        ulHistory: Array.from({ length: 16 }, () => Math.random() * 1024 * 1024 * 1),
        connectedDevices: 3,
        smsUnreadCount: 1,
        cpuUsage: 18.5,
        memUsage: 42.0,
        temperature: 41.2,
        batteryValue: -1,
        isCharging: false,
        monthlyRx: 45 * 1024 * 1024 * 1024,
        monthlyTx: 8 * 1024 * 1024 * 1024,
        dailyRx: 1.8 * 1024 * 1024 * 1024,
        dailyTx: 400 * 1024 * 1024,
        packageRx: 53 * 1024 * 1024 * 1024,
        packageTx: 10 * 1024 * 1024 * 1024,
        packageTotal: 63 * 1024 * 1024 * 1024,
        ufiDailyUsage: 2.2 * 1024 * 1024 * 1024,
        ufiMonthlyUsage: 63 * 1024 * 1024 * 1024,
        trafficLimit: 100 * 1024 * 1024 * 1024,
        trafficResetDay: 1,
        daysUntilReset: 14,
      };
    case 'get_config':
      return {
        baseURL: 'http://192.168.0.1:2333',
        password: 'admin',
        ufiToken: 'admin',
        refreshInterval: 2.0,
        displayMode: '图标 + 速率',
        screenMirroringPort: 5555,
        launchAtLogin: true
      };
    case 'get_sms_messages':
      return [
        {
          id: '1',
          number: '10086',
          content: '【中国移动】尊敬的客户，您的验证码是 839210，有效期 5 分钟。如非本人操作请忽略。',
          dateText: '2026-08-17 21:30:15',
          tag: '1',
          isUnread: true,
          isOutgoing: false
        },
        {
          id: '2',
          number: '10086',
          content: '【中国移动】截至 08 月 17 日 20 时，您本月已使用通用流量 63.00GB，剩余可用流量 37.00GB。',
          dateText: '2026-08-17 20:00:00',
          tag: '0',
          isUnread: false,
          isOutgoing: false
        }
      ];
    case 'get_scrcpy_status':
      return {
        hasAdb: true,
        hasScrcpy: true,
        isInstalled: true,
        adbPath: 'AppData/Local/F50Monitor/Tools/adb.exe',
        scrcpyPath: 'AppData/Local/F50Monitor/Tools/scrcpy.exe'
      };
    default:
      return { success: true };
  }
}

export const state = reactive({
  status: {
    isOnline: false,
    errorMessage: null,
    networkType: '5G SA',
    signalBar: 0,
    rsrp: 'N/A',
    rsrq: 'N/A',
    snr: 'N/A',
    carrier: '未知',
    currentBands: '',
    pppStatus: '未连接',
    qci: '',
    qosDl: '',
    qosUl: '',
    dlSpeed: 0,
    ulSpeed: 0,
    dlHistory: [],
    ulHistory: [],
    connectedDevices: 0,
    smsUnreadCount: 0,
    cpuUsage: 0,
    memUsage: 0,
    temperature: 0,
    batteryValue: -1,
    isCharging: false,
    monthlyRx: 0,
    monthlyTx: 0,
    dailyRx: 0,
    dailyTx: 0,
    packageRx: 0,
    packageTx: 0,
    packageTotal: 0,
    ufiDailyUsage: 0,
    ufiMonthlyUsage: 0,
    trafficLimit: 0,
    trafficResetDay: 0,
    daysUntilReset: null
  },
  config: {
    baseURL: 'http://192.168.0.1:2333',
    password: 'admin',
    ufiToken: 'admin',
    refreshInterval: 2.0,
    displayMode: '图标 + 速率',
    screenMirroringPort: 5555,
    launchAtLogin: false
  },
  sms: {
    messages: [],
    isFetching: false,
    isSending: false,
    errorMessage: null,
    sendErrorMessage: null,
    sendSuccess: false
  },
  scrcpy: {
    hasAdb: false,
    hasScrcpy: false,
    isInstalled: false,
    isDownloading: false,
    isConnecting: false,
    statusMessage: null,
    downloadProgress: 0
  },
  isFetchingStatus: false,
  isManualRefreshing: false,
  activeView: 'main', // 'main' | 'sms' | 'compose' | 'settings' | 'mirror'
  timer: null
});

// Format utilities
export function formatSpeed(bytes) {
  if (!bytes || bytes <= 0) return '0 B/s';
  if (bytes < 1024) return `${bytes.toFixed(0)} B/s`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB/s`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB/s`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB/s`;
}

export function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  if (bytes < 1024 * 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  return `${(bytes / (1024 * 1024 * 1024 * 1024)).toFixed(2)} TB`;
}

export function parseSignalQuality(valueStr, metric) {
  if (!valueStr || valueStr === 'N/A') return { label: '-', color: 'var(--color-gray)', ratio: 0 };
  const val = parseFloat(valueStr.replace(/[^\d.-]/g, ''));
  if (isNaN(val)) return { label: '-', color: 'var(--color-gray)', ratio: 0 };

  if (metric === 'rsrp') {
    if (val >= -85) return { label: '极佳', color: 'var(--color-green)', ratio: 1.0 };
    if (val >= -95) return { label: '良好', color: 'var(--color-blue)', ratio: 0.75 };
    if (val >= -105) return { label: '一般', color: 'var(--color-orange)', ratio: 0.5 };
    return { label: '较差', color: 'var(--color-red)', ratio: 0.25 };
  } else if (metric === 'snr' || metric === 'sinr') {
    if (val >= 20) return { label: '极佳', color: 'var(--color-green)', ratio: 1.0 };
    if (val >= 13) return { label: '良好', color: 'var(--color-blue)', ratio: 0.75 };
    if (val >= 3) return { label: '一般', color: 'var(--color-orange)', ratio: 0.5 };
    return { label: '较差', color: 'var(--color-red)', ratio: 0.25 };
  } else if (metric === 'rsrq') {
    if (val >= -10) return { label: '极佳', color: 'var(--color-green)', ratio: 1.0 };
    if (val >= -15) return { label: '良好', color: 'var(--color-blue)', ratio: 0.75 };
    if (val >= -20) return { label: '一般', color: 'var(--color-orange)', ratio: 0.5 };
    return { label: '较差', color: 'var(--color-red)', ratio: 0.25 };
  }
  return { label: '-', color: 'var(--color-gray)', ratio: 0 };
}

export function extractVerifyCode(text) {
  if (!text) return null;
  // Match 4-8 digits near "验证码" or standalone
  const codeRegex = /(?:验证码|校验码|动态码|code|Code)[^\d]{0,8}(\d{4,8})/;
  const match = text.match(codeRegex);
  if (match && match[1]) return match[1];
  
  const digitMatch = text.match(/(?:\b|[^0-9])(\d{4,6})(?:\b|[^0-9])/);
  if (digitMatch && digitMatch[1]) return digitMatch[1];
  return null;
}

export const computedTraffic = computed(() => {
  const packageUsed = state.status.packageTotal > 0 ? state.status.packageTotal : state.status.monthlyRx + state.status.monthlyTx;
  const limit = state.status.trafficLimit;
  let ratio = limit > 0 ? Math.min(1.0, Math.max(0, packageUsed / limit)) : 0;
  
  let color = 'var(--color-cyan)';
  if (ratio >= 0.9) color = 'var(--color-red)';
  else if (ratio >= 0.75) color = 'var(--color-orange)';

  return {
    packageUsed,
    limit,
    ratio,
    color,
    todayUsed: state.status.ufiDailyUsage > 0 ? state.status.ufiDailyUsage : state.status.dailyRx + state.status.dailyTx,
    monthUsed: state.status.ufiMonthlyUsage > 0 ? state.status.ufiMonthlyUsage : state.status.monthlyRx + state.status.monthlyTx
  };
});

// Actions
export async function initApp() {
  try {
    const config = await invokeTauri('get_config');
    if (config) Object.assign(state.config, config);
    await fetchStatus();
    startTimer();
  } catch (err) {
    console.error('Init failed:', err);
  }
}

export async function fetchStatus(isManual = false) {
  if (state.isFetchingStatus) return;
  state.isFetchingStatus = true;
  if (isManual) {
    state.isManualRefreshing = true;
  }
  const minDuration = isManual ? 600 : 0;
  const startTime = Date.now();
  try {
    const data = await invokeTauri('get_status');
    if (data) {
      Object.assign(state.status, data);
    }
  } catch (err) {
    state.status.isOnline = false;
    state.status.errorMessage = String(err);
  } finally {
    if (isManual) {
      const elapsed = Date.now() - startTime;
      if (elapsed < minDuration) {
        await new Promise(resolve => setTimeout(resolve, minDuration - elapsed));
      }
      state.isManualRefreshing = false;
    }
    state.isFetchingStatus = false;
  }
}

export function startTimer() {
  if (state.timer) clearInterval(state.timer);
  const interval = Math.max(1, state.config.refreshInterval || 2.0) * 1000;
  state.timer = setInterval(fetchStatus, interval);
}

export async function saveConfig(newConfig) {
  Object.assign(state.config, newConfig);
  await invokeTauri('save_config', { config: state.config });
  startTimer();
}

export function decodeSmsContent(content) {
  if (!content) return '';
  const trimmed = content.trim();
  if (/[\u4e00-\u9fa5]/.test(trimmed)) {
    return trimmed;
  }
  try {
    if (/^[A-Za-z0-9+/=_-]+$/.test(trimmed) && trimmed.length >= 4) {
      const binary = atob(trimmed.replace(/-/g, '+').replace(/_/g, '/'));
      const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
      const decoded = new TextDecoder('utf-8').decode(bytes);
      if (decoded && !/[\x00-\x08\x0E-\x1F]/.test(decoded)) {
        return decoded;
      }
    }
  } catch (e) {
    // Ignore
  }
  return trimmed;
}

export async function fetchSMS() {
  state.sms.isFetching = true;
  state.sms.errorMessage = null;
  try {
    const msgs = await invokeTauri('get_sms_messages');
    const readIds = new Set(JSON.parse(localStorage.getItem('F50_LocallyReadSMSIds') || '[]'));
    state.sms.messages = (msgs || []).map(m => ({
      ...m,
      content: decodeSmsContent(m.content),
      isUnread: readIds.has(m.id) ? false : m.isUnread,
      isOutgoing: m.tag === '2' || m.tag === '3',
      didFailToSend: m.tag === '5' || String(m.tag).toLowerCase() === 'failed'
    }));
  } catch (err) {
    state.sms.errorMessage = String(err);
  } finally {
    state.sms.isFetching = false;
  }
}

export function startSMSPolling(interval = 4000) {
  stopSMSPolling();
  fetchSMS();
  state.smsTimer = setInterval(fetchSMS, interval);
}

export function stopSMSPolling() {
  if (state.smsTimer) {
    clearInterval(state.smsTimer);
    state.smsTimer = null;
  }
}

export function markSMSAsRead(ids) {
  if (!ids || !ids.length) return;
  const readIds = new Set(JSON.parse(localStorage.getItem('F50_LocallyReadSMSIds') || '[]'));
  ids.forEach(id => readIds.add(id));
  localStorage.setItem('F50_LocallyReadSMSIds', JSON.stringify([...readIds]));
  state.sms.messages = state.sms.messages.map(m => ({
    ...m,
    isUnread: readIds.has(m.id) ? false : m.isUnread
  }));
}

export function markAllSMSAsRead() {
  const unreadIds = state.sms.messages.filter(m => m.isUnread).map(m => m.id);
  markSMSAsRead(unreadIds);
}

export async function sendSMS(number, content) {
  state.sms.isSending = true;
  state.sms.sendErrorMessage = null;
  state.sms.sendSuccess = false;
  try {
    await invokeTauri('send_sms', { number, content });
    state.sms.sendSuccess = true;
    await fetchSMS();
    return true;
  } catch (err) {
    state.sms.sendErrorMessage = String(err);
    return false;
  } finally {
    state.sms.isSending = false;
  }
}

export async function checkScrcpy() {
  try {
    const res = await invokeTauri('get_scrcpy_status');
    if (res) Object.assign(state.scrcpy, res);
  } catch (err) {
    console.error('Check scrcpy error:', err);
  }
}

export async function downloadScrcpy() {
  state.scrcpy.isDownloading = true;
  state.scrcpy.statusMessage = '正在从 GitHub 下载 scrcpy Windows 组件包...';
  try {
    await invokeTauri('download_scrcpy');
    await checkScrcpy();
    state.scrcpy.statusMessage = 'scrcpy 投屏组件配置成功！';
  } catch (err) {
    state.scrcpy.statusMessage = `下载失败: ${err}`;
  } finally {
    state.scrcpy.isDownloading = false;
  }
}

export async function launchMirroring() {
  state.scrcpy.isConnecting = true;
  state.scrcpy.statusMessage = '正在连接设备并启动无线投屏...';
  try {
    await invokeTauri('launch_scrcpy', { 
      port: state.config.screenMirroringPort || 5555 
    });
    state.scrcpy.statusMessage = '投屏窗口已启动！';
  } catch (err) {
    state.scrcpy.statusMessage = `启动失败: ${err}`;
  } finally {
    state.scrcpy.isConnecting = false;
  }
}

export async function openWebAdmin(type = 'ufi') {
  const host = state.config.baseURL.replace(/https?:\/\//, '').split('/')[0].split(':')[0] || '192.168.0.1';
  const url = type === 'router' ? `http://${host}` : `http://${host}:2333`;
  await invokeTauri('open_url', { url });
}
