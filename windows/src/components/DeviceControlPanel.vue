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
        <h3>Wi-Fi 设置</h3>
        <label class="row"><span>Wi-Fi 开关</span><select v-model="controls.wifi.radioMode" :disabled="busy"><option value="1">仅 2.4 GHz</option><option value="2">仅 5 GHz</option><option value="0">关闭</option></select></label>
        <fieldset :disabled="busy || controls.wifi.radioMode === '0'">
          <label class="row"><span>网络名称（SSID）</span><input v-model.trim="controls.wifi.ssid" maxlength="32" /></label>
          <label class="row"><span>广播网络名称（SSID）</span><input type="checkbox" v-model="controls.wifi.broadcastsSSID" /></label>
          <label class="row"><span>安全模式</span><select v-model="controls.wifi.securityMode"><option value="WPA2PSK">WPA2 (AES)-PSK</option><option value="WPAPSKWPA2PSK">WPA / WPA2-PSK</option><option value="OPEN">开放网络</option></select></label>
          <template v-if="controls.wifi.securityMode !== 'OPEN'">
            <label class="row"><span>密码</span><input v-model="controls.wifi.password" :type="showWifiPassword ? 'text' : 'password'" /></label>
            <label class="row"><span>显示密码</span><input type="checkbox" v-model="showWifiPassword" /></label>
          </template>
          <label class="row"><span>最大接入数</span><input v-model.number="controls.wifi.maximumClients" type="number" min="1" max="32" /></label>
        </fieldset>
        <button :disabled="busy || !canSaveWifi" @click="saveWifi">保存并应用</button>
        <small>修改频段、网络名称或密码会中断当前连接。</small>
      </section>

      <section>
        <h3>APN</h3>
        <label class="row"><span>自动 APN</span><input type="checkbox" v-model="controls.apn.isAutomatic" /></label>
        <template v-if="!controls.apn.isAutomatic">
          <select v-model="controls.apn.pdpType"><option value="IP">IPv4</option><option value="IPv6">IPv6</option><option value="IPv4v6">IPv4 / IPv6</option></select>
          <input v-model.trim="controls.apn.profileName" placeholder="配置文件名称" /><input v-model.trim="controls.apn.apn" placeholder="APN" />
          <select v-model="controls.apn.authentication"><option value="none">无鉴权</option><option value="chap">CHAP</option><option value="pap">PAP</option></select>
          <input v-model.trim="controls.apn.username" placeholder="用户名" /><input v-model="controls.apn.password" type="password" placeholder="密码" />
        </template>
        <button :disabled="busy || !canSaveApn" @click="saveApn">保存并应用</button>
      </section>

      <section>
        <h3>Wi-Fi 客户端</h3><div v-if="!controls.clients.length" class="empty">暂无客户端</div>
        <div v-for="client in controls.clients" :key="`${client.macAddress}-${client.isBlocked}`" class="client"><div><b>{{ client.name || '未知设备' }}</b><small>{{ client.ipAddress }} {{ client.macAddress }}</small></div><button :class="{ danger: !client.isBlocked }" :disabled="busy" @click="toggleClient(client)">{{ client.isBlocked ? '解除' : '踢出' }}</button></div>
      </section>

      <section><h3>频段锁定</h3><div><small>4G 常用频段</small><div class="band-options"><label v-for="band in lteBandOptions" :key="`lte-${band}`"><input type="checkbox" :checked="selectedLTEBands.has(band)" :disabled="busy" @change="toggleBand('lte', band, $event.target.checked)" />B{{ band }}</label></div></div><div><small>5G 常用频段</small><div class="band-options"><label v-for="band in nrBandOptions" :key="`nr-${band}`"><input type="checkbox" :checked="selectedNRBands.has(band)" :disabled="busy" @change="toggleBand('nr', band, $event.target.checked)" />n{{ band }}</label></div></div><div class="actions"><button :disabled="busy || (!controls.lteBands && !controls.nrBands)" @click="setBands(false)">应用频段锁定</button><button class="danger" :disabled="busy" @click="setBands(true)">解除全部</button></div></section>
      <section><h3>基站锁定</h3><div class="two-columns"><select v-model="cell.is5G"><option :value="true">5G</option><option :value="false">4G</option></select><input v-model.number="cell.pci" type="number" placeholder="PCI" /></div><input v-model.number="cell.earfcn" type="number" placeholder="EARFCN / NR-ARFCN" /><div class="actions"><button :disabled="busy || cell.pci === '' || cell.earfcn === ''" @click="lockCell">应用基站锁定</button><button class="danger" :disabled="busy" @click="unlockCells">解除全部</button></div></section>
      <section><h3>设备电源</h3><button class="danger" :disabled="busy" @click="reboot">重启设备</button></section>

      <p v-if="message" :class="['message', messageType]">{{ message }}</p><p class="warning">Wi-Fi、网络模式、APN、锁频和锁站设置可能导致连接中断。请保留 USB 恢复路径。</p>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { invokePlatform } from '../stores/f50Store.js';
defineEmits(['close']);
const busy = ref(false), message = ref(''), messageType = ref('success'), showWifiPassword = ref(false);
const controls = reactive({ mobileDataEnabled: false, networkMode: 'WL_AND_5G', wifi: { radioMode: '2', ssid: '', broadcastsSSID: true, securityMode: 'WPA2PSK', password: '', maximumClients: 10, usesEncodedPassword: false, noForwarding: '0', qrCodeDisplaySwitch: '1' }, lteBands: '', nrBands: '', clients: [], apn: { index: 0, isAutomatic: true, profileName: '', apn: '', username: '', password: '', authentication: 'none', pdpType: 'IPv4v6' } });
const cell = reactive({ is5G: true, pci: '', earfcn: '' });
const networkModes = [['自动（5G / 4G / 3G）','WL_AND_5G'],['5G NSA','LTE_AND_5G'],['5G SA','Only_5G'],['4G / 3G','WCDMA_AND_LTE'],['仅 4G','Only_LTE'],['仅 3G','Only_WCDMA']].map(([label,value])=>({label,value}));
const lteBandOptions = [1,3,5,8,34,38,39,40,41], nrBandOptions = [1,5,8,28,41,78];
const selectedLTEBands = computed(()=>new Set(controls.lteBands.split(',').map(Number).filter(Number.isFinite)));
const selectedNRBands = computed(()=>new Set(controls.nrBands.split(',').map(Number).filter(Number.isFinite)));
const canSaveApn = computed(()=>controls.apn.isAutomatic||(controls.apn.profileName&&controls.apn.apn));
const canSaveWifi = computed(()=>controls.wifi.radioMode==='0'||(controls.wifi.ssid.trim().length>0&&controls.wifi.ssid.length<=32&&controls.wifi.maximumClients>=1&&controls.wifi.maximumClients<=32&&(controls.wifi.securityMode==='OPEN'||(controls.wifi.password.length>=8&&controls.wifi.password.length<=63))));
async function run(action, success, refresh=true){if(busy.value)return;busy.value=true;message.value='';try{await action();messageType.value='success';message.value=success;if(refresh)await load(true);}catch(error){messageType.value='error';message.value=String(error?.message||error);}finally{busy.value=false;}}
async function load(nested=false){if(!nested)busy.value=true;try{Object.assign(controls,await invokePlatform('get_device_controls'));}catch(error){messageType.value='error';message.value=String(error?.message||error);}finally{if(!nested)busy.value=false;}}
const setMobileData=enabled=>run(()=>invokePlatform('set_mobile_data',{enabled}),enabled?'移动数据已开启':'移动数据已关闭');
const setNetworkMode=mode=>run(()=>invokePlatform('set_network_mode',{mode}),'网络模式已更新');
const saveWifi=()=>{if(!confirm('修改 Wi-Fi 设置可能立即断开当前连接，仍要保存？'))return;run(()=>invokePlatform('save_wifi',{wifi:controls.wifi}),'Wi-Fi 设置已保存',false);};
const toggleBand=(type,band,selected)=>{const values=new Set(type==='lte'?selectedLTEBands.value:selectedNRBands.value);selected?values.add(band):values.delete(band);controls[type==='lte'?'lteBands':'nrBands']=[...values].sort((a,b)=>a-b).join(',');};
const saveApn=()=>run(()=>controls.apn.isAutomatic?invokePlatform('set_apn_auto'):invokePlatform('save_apn',{apn:controls.apn}),controls.apn.isAutomatic?'已恢复自动 APN':'APN 已保存');
const toggleClient=client=>{if(!client.isBlocked&&!confirm(`踢出并拉黑 ${client.name||client.macAddress}？`))return;run(()=>invokePlatform('set_client_blocked',{...client,blocked:!client.isBlocked}),client.isBlocked?'已解除黑名单':'设备已踢出并拉黑');};
const setBands=unlock=>{if(!confirm(unlock?'确认解除全部频段锁定？':'错误频段可能导致无法入网，仍要应用？'))return;run(()=>invokePlatform('set_band_lock',{lteBands:controls.lteBands,nrBands:controls.nrBands,unlock}),unlock?'已解除频段锁定':'频段锁定已应用');};
const lockCell=()=>{if(confirm('错误基站参数可能导致无信号，仍要应用？'))run(()=>invokePlatform('lock_cell',{...cell}),'基站锁定已应用');};
const unlockCells=()=>run(()=>invokePlatform('unlock_cells'),'已解除基站锁定');
const reboot=()=>{if(confirm('确认重启 F50？当前连接会暂时中断。'))run(()=>invokePlatform('reboot_device'),'重启指令已发送',false);};
onMounted(load);
</script>

<style scoped>
.control-page{position:absolute;inset:0;z-index:20;display:flex;flex-direction:column;background:var(--bg-panel)}.control-header{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;padding:10px 14px;border-bottom:1px solid var(--border-card);background:var(--bg-card)}.control-header button{background:none;border:0;color:var(--color-blue);padding:4px}.back{text-align:left}.refresh{text-align:right}.control-content{overflow-y:auto;padding:12px;display:grid;gap:10px}section{display:grid;gap:8px;padding:12px;border:1px solid var(--border-card);border-radius:10px;background:var(--bg-card)}fieldset{display:grid;gap:8px;margin:0;padding:0;border:0}h3{margin:0 0 2px;font-size:12px;color:var(--text-secondary)}label{display:grid;gap:5px;font-size:12px}.row{display:flex;justify-content:space-between;align-items:center}.row>input:not([type=checkbox]),.row>select{width:min(58%,220px)}input,select,button{box-sizing:border-box;min-height:34px;border:1px solid var(--border-card);border-radius:7px;background:var(--bg-panel);color:var(--text-primary);padding:7px 9px}button{cursor:pointer}.danger{color:var(--color-red)}.two-columns{display:grid;grid-template-columns:1fr 1fr;gap:8px}.actions{display:flex;gap:8px}.actions button{flex:1}.band-options{display:flex;flex-wrap:wrap;gap:6px;margin-top:5px}.band-options label{display:flex;align-items:center;gap:4px;border:1px solid var(--border-card);border-radius:7px;padding:5px 7px}.band-options input{min-height:auto;padding:0}.client{display:flex;align-items:center;justify-content:space-between;gap:8px}.client div{min-width:0}.client b,.client small{display:block;overflow:hidden;text-overflow:ellipsis}.client small,section>small,.empty{color:var(--text-secondary);font-size:10px}.message,.warning{margin:0;padding:10px;border-radius:8px;font-size:11px}.success{color:var(--color-green)}.error,.warning{color:var(--color-red);background:color-mix(in srgb,var(--color-red) 10%,transparent)}
</style>
