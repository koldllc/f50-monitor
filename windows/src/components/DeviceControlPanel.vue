<template>
  <div class="control-page">
    <div class="control-header">
      <button class="back" @click="$emit('close')">‹ 返回</button>
      <strong>设备控制</strong>
      <button class="refresh" :disabled="busy" @click="load">刷新</button>
    </div>

    <div class="control-content">
      <section>
        <h3>蜂窝网络</h3>
        <label class="row"><span>移动数据</span><input type="checkbox" :checked="controls.mobileDataEnabled" :disabled="busy" @change="setMobileData($event.target.checked)" /></label>
        <label><span>网络模式</span><select v-model="controls.networkMode" :disabled="busy" @change="setNetworkMode(controls.networkMode)"><option v-for="mode in networkModes" :key="mode.value" :value="mode.value">{{ mode.label }}</option></select></label>
      </section>

      <section>
        <h3>APN 与 DNS</h3>
        <label class="row"><span>自动 APN</span><input type="checkbox" v-model="controls.apn.isAutomatic" /></label>
        <template v-if="!controls.apn.isAutomatic">
          <input v-model.trim="controls.apn.profileName" placeholder="配置名称" /><input v-model.trim="controls.apn.apn" placeholder="APN" />
          <input v-model.trim="controls.apn.username" placeholder="用户名（可选）" /><input v-model="controls.apn.password" type="password" placeholder="密码（可选）" />
          <div class="two-columns"><select v-model="controls.apn.authentication"><option value="none">无鉴权</option><option value="chap">CHAP</option><option value="pap">PAP</option></select><select v-model="controls.apn.pdpType"><option value="IP">IPv4</option><option value="IPv6">IPv6</option><option value="IPv4v6">IPv4 / IPv6</option></select></div>
          <input v-model.trim="controls.apn.primaryDNS" placeholder="首选 DNS，留空为自动" /><input v-model.trim="controls.apn.secondaryDNS" placeholder="备用 DNS，留空为自动" />
        </template>
        <button :disabled="busy || !canSaveApn" @click="saveApn">保存并应用</button><small>DNS 随蜂窝 APN 生效，不修改热点 DHCP 下发的 DNS。</small>
      </section>

      <section>
        <h3>Wi-Fi 客户端</h3><div v-if="!controls.clients.length" class="empty">暂无客户端</div>
        <div v-for="client in controls.clients" :key="`${client.macAddress}-${client.isBlocked}`" class="client"><div><b>{{ client.name || '未知设备' }}</b><small>{{ client.ipAddress }} {{ client.macAddress }}</small></div><button :class="{ danger: !client.isBlocked }" :disabled="busy" @click="toggleClient(client)">{{ client.isBlocked ? '解除' : '踢出' }}</button></div>
      </section>

      <section><h3>Band Lock</h3><input v-model.trim="controls.lteBands" placeholder="4G Band，例如 1,3,8" /><input v-model.trim="controls.nrBands" placeholder="5G Band，例如 41,78" /><div class="actions"><button :disabled="busy" @click="setBands(false)">应用锁频</button><button class="danger" :disabled="busy" @click="setBands(true)">解除全部</button></div></section>
      <section><h3>Cell Lock</h3><div class="two-columns"><select v-model="cell.is5G"><option :value="true">5G</option><option :value="false">4G</option></select><input v-model.number="cell.pci" type="number" placeholder="PCI" /></div><input v-model.number="cell.earfcn" type="number" placeholder="EARFCN / NR-ARFCN" /><div class="actions"><button :disabled="busy || cell.pci === '' || cell.earfcn === ''" @click="lockCell">应用锁站</button><button class="danger" :disabled="busy" @click="unlockCells">解除全部</button></div></section>
      <section><h3>设备电源</h3><button class="danger" :disabled="busy" @click="reboot">重启设备</button></section>

      <p v-if="message" :class="['message', messageType]">{{ message }}</p><p class="warning">网络模式、APN、锁频和锁站可能导致蜂窝连接中断。请保留本地 Wi-Fi 或 USB 恢复路径。</p>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { invokePlatform } from '../stores/f50Store.js';
defineEmits(['close']);
const busy = ref(false), message = ref(''), messageType = ref('success');
const controls = reactive({ mobileDataEnabled: false, networkMode: 'WL_AND_5G', lteBands: '', nrBands: '', clients: [], apn: { index: 0, isAutomatic: true, profileName: '', apn: '', username: '', password: '', authentication: 'none', pdpType: 'IPv4v6', primaryDNS: '', secondaryDNS: '' } });
const cell = reactive({ is5G: true, pci: '', earfcn: '' });
const networkModes = [['自动（5G / 4G / 3G）','WL_AND_5G'],['5G NSA','LTE_AND_5G'],['5G SA','Only_5G'],['4G / 3G','WCDMA_AND_LTE'],['仅 4G','Only_LTE'],['仅 3G','Only_WCDMA']].map(([label,value])=>({label,value}));
const canSaveApn = computed(()=>controls.apn.isAutomatic||(controls.apn.profileName&&controls.apn.apn));
async function run(action, success, refresh=true){if(busy.value)return;busy.value=true;message.value='';try{await action();messageType.value='success';message.value=success;if(refresh)await load(true);}catch(error){messageType.value='error';message.value=String(error?.message||error);}finally{busy.value=false;}}
async function load(nested=false){if(!nested)busy.value=true;try{Object.assign(controls,await invokePlatform('get_device_controls'));}catch(error){messageType.value='error';message.value=String(error?.message||error);}finally{if(!nested)busy.value=false;}}
const setMobileData=enabled=>run(()=>invokePlatform('set_mobile_data',{enabled}),enabled?'移动数据已开启':'移动数据已关闭');
const setNetworkMode=mode=>run(()=>invokePlatform('set_network_mode',{mode}),'网络模式已更新');
const saveApn=()=>run(()=>controls.apn.isAutomatic?invokePlatform('set_apn_auto'):invokePlatform('save_apn',{apn:controls.apn}),controls.apn.isAutomatic?'已恢复自动 APN':'APN 与 DNS 已保存');
const toggleClient=client=>{if(!client.isBlocked&&!confirm(`踢出并拉黑 ${client.name||client.macAddress}？`))return;run(()=>invokePlatform('set_client_blocked',{...client,blocked:!client.isBlocked}),client.isBlocked?'已解除黑名单':'设备已踢出并拉黑');};
const setBands=unlock=>{if(!confirm(unlock?'确认解除全部 Band Lock？':'错误频段可能导致无法入网，仍要应用？'))return;run(()=>invokePlatform('set_band_lock',{lteBands:controls.lteBands,nrBands:controls.nrBands,unlock}),unlock?'已解除 Band Lock':'Band Lock 已应用');};
const lockCell=()=>{if(confirm('错误小区参数可能导致无信号，仍要应用？'))run(()=>invokePlatform('lock_cell',{...cell}),'Cell Lock 已应用');};
const unlockCells=()=>run(()=>invokePlatform('unlock_cells'),'已解除 Cell Lock');
const reboot=()=>{if(confirm('确认重启 F50？当前连接会暂时中断。'))run(()=>invokePlatform('reboot_device'),'重启指令已发送',false);};
onMounted(load);
</script>

<style scoped>
.control-page{position:absolute;inset:0;z-index:20;display:flex;flex-direction:column;background:var(--bg-panel)}.control-header{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;padding:10px 14px;border-bottom:1px solid var(--border-card);background:var(--bg-card)}.control-header button{background:none;border:0;color:var(--color-blue);padding:4px}.back{text-align:left}.refresh{text-align:right}.control-content{overflow-y:auto;padding:12px;display:grid;gap:10px}section{display:grid;gap:8px;padding:12px;border:1px solid var(--border-card);border-radius:10px;background:var(--bg-card)}h3{margin:0 0 2px;font-size:12px;color:var(--text-secondary)}label{display:grid;gap:5px;font-size:12px}.row{display:flex;justify-content:space-between;align-items:center}input,select,button{box-sizing:border-box;min-height:34px;border:1px solid var(--border-card);border-radius:7px;background:var(--bg-panel);color:var(--text-primary);padding:7px 9px}button{cursor:pointer}.danger{color:var(--color-red)}.two-columns{display:grid;grid-template-columns:1fr 1fr;gap:8px}.actions{display:flex;gap:8px}.actions button{flex:1}.client{display:flex;align-items:center;justify-content:space-between;gap:8px}.client div{min-width:0}.client b,.client small{display:block;overflow:hidden;text-overflow:ellipsis}.client small,section>small,.empty{color:var(--text-secondary);font-size:10px}.message,.warning{margin:0;padding:10px;border-radius:8px;font-size:11px}.success{color:var(--color-green)}.error,.warning{color:var(--color-red);background:color-mix(in srgb,var(--color-red) 10%,transparent)}
</style>
