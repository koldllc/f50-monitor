<template>
  <div class="f50-container">
    <!-- Main Monitor View -->
    <template v-if="state.activeView === 'main'">
      <Header 
        @openSMS="state.activeView = 'sms'" 
        @openSettings="state.activeView = 'settings'" 
      />

      <main class="panel-scroll-content">
        <SpeedCard />
        <SignalCard />
        <TrafficCard />
        <HardwareCard />
      </main>

      <FooterActions 
        @openMirror="state.activeView = 'mirror'" 
      />
    </template>

    <!-- SMS Inbox View -->
    <SMSView 
      v-else-if="state.activeView === 'sms'" 
      @close="state.activeView = 'main'" 
      @openCompose="state.activeView = 'compose'" 
    />

    <!-- Compose SMS View -->
    <ComposeSMSView 
      v-else-if="state.activeView === 'compose'" 
      @close="state.activeView = 'sms'" 
      @sent="state.activeView = 'sms'" 
    />

    <!-- Settings View -->
    <SettingsView 
      v-else-if="state.activeView === 'settings'" 
      @close="state.activeView = 'main'" 
      @openSMS="state.activeView = 'sms'"
    />

    <!-- Wireless Mirroring View -->
    <ScreenMirrorModal 
      v-else-if="state.activeView === 'mirror'" 
      @close="state.activeView = 'main'" 
    />
  </div>
</template>

<script setup>
import { onMounted } from 'vue';
import { state, initApp } from './stores/f50Store.js';
import Header from './components/Header.vue';
import SpeedCard from './components/SpeedCard.vue';
import SignalCard from './components/SignalCard.vue';
import TrafficCard from './components/TrafficCard.vue';
import HardwareCard from './components/HardwareCard.vue';
import FooterActions from './components/FooterActions.vue';
import SMSView from './components/SMSView.vue';
import ComposeSMSView from './components/ComposeSMSView.vue';
import SettingsView from './components/SettingsView.vue';
import ScreenMirrorModal from './components/ScreenMirrorModal.vue';

onMounted(() => {
  initApp();
});
</script>

<style scoped>
.panel-scroll-content {
  flex: 1;
  overflow-y: auto;
  padding: 10px 14px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
</style>
