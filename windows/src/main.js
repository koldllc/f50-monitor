import { createApp } from 'vue';
import App from './App.vue';
import './styles/theme.css';

const app = createApp(App);
app.mount('#app');

// Handle Tauri window behavior
if (typeof window !== 'undefined' && window.__TAURI_INTERNALS__) {
  import('@tauri-apps/api/window').then(({ getCurrentWindow }) => {
    const appWindow = getCurrentWindow();
    
    // Auto-hide when focus is lost (like macOS Popover)
    appWindow.listen('tauri://blur', () => {
      // Optional: hide window on blur
      // appWindow.hide();
    });
  }).catch(err => {
    console.warn('Tauri window API init failed:', err);
  });
}
