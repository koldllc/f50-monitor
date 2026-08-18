<template>
  <div class="f50-card speed-card">
    <div class="speed-row">
      <!-- Download Speed -->
      <div class="speed-item">
        <div class="speed-header">
          <span class="speed-arrow dl-arrow">⬇</span>
          <span class="speed-label">实时下载</span>
        </div>
        <div class="speed-value dl-value">
          {{ formatSpeed(state.status.dlSpeed) }}
        </div>
        <div class="wave-container">
          <svg class="sparkline-svg" viewBox="0 0 140 28" preserveAspectRatio="none">
            <path :d="dlPath.fill" class="sparkline-fill dl-fill" />
            <path :d="dlPath.stroke" class="sparkline-stroke dl-stroke" />
          </svg>
        </div>
      </div>

      <div class="divider-vertical"></div>

      <!-- Upload Speed -->
      <div class="speed-item">
        <div class="speed-header">
          <span class="speed-arrow ul-arrow">⬆</span>
          <span class="speed-label">实时上传</span>
        </div>
        <div class="speed-value ul-value">
          {{ formatSpeed(state.status.ulSpeed) }}
        </div>
        <div class="wave-container">
          <svg class="sparkline-svg" viewBox="0 0 140 28" preserveAspectRatio="none">
            <path :d="ulPath.fill" class="sparkline-fill ul-fill" />
            <path :d="ulPath.stroke" class="sparkline-stroke ul-stroke" />
          </svg>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { state, formatSpeed } from '../stores/f50Store.js';

function generateWavePaths(history, currentSpeed, width = 140, height = 28) {
  let points = [];
  if (history && history.length >= 3) {
    const maxVal = Math.max(1024 * 1024, ...history);
    points = history.map(v => Math.min(0.9, Math.max(0.1, v / maxVal)));
  } else {
    // Resting wave
    points = currentSpeed > 0 
      ? [0.25, 0.45, 0.28, 0.60, 0.35, 0.68, 0.32, 0.52, 0.30] 
      : [0.15, 0.20, 0.16, 0.22, 0.18, 0.21, 0.17, 0.19, 0.15];
  }

  const stepX = width / (points.length - 1);
  const coords = points.map((p, i) => ({
    x: i * stepX,
    y: height * (1 - p)
  }));

  if (coords.length < 2) return { stroke: '', fill: '' };

  let strokePath = `M ${coords[0].x} ${coords[0].y}`;
  for (let i = 0; i < coords.length - 1; i++) {
    const p0 = i > 0 ? coords[i - 1] : coords[i];
    const p1 = coords[i];
    const p2 = coords[i + 1];
    const p3 = i + 2 < coords.length ? coords[i + 2] : p2;

    const cp1x = p1.x + (p2.x - p0.x) / 5.5;
    const cp1y = p1.y + (p2.y - p0.y) / 5.5;
    const cp2x = p2.x - (p3.x - p1.x) / 5.5;
    const cp2y = p2.y - (p3.y - p1.y) / 5.5;

    strokePath += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
  }

  const fillPath = `${strokePath} L ${coords[coords.length - 1].x} ${height} L ${coords[0].x} ${height} Z`;

  return { stroke: strokePath, fill: fillPath };
}

const dlPath = computed(() => generateWavePaths(state.status.dlHistory, state.status.dlSpeed));
const ulPath = computed(() => generateWavePaths(state.status.ulHistory, state.status.ulSpeed));
</script>

<style scoped>
.speed-card {
  padding: 10px 14px;
}

.speed-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.speed-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.speed-header {
  display: flex;
  align-items: center;
  gap: 4px;
}

.speed-arrow {
  font-size: 11px;
  font-weight: 700;
}
.dl-arrow { color: var(--color-green); }
.ul-arrow { color: var(--color-blue); }

.speed-label {
  font-size: 11px;
  color: var(--text-secondary);
  font-weight: 500;
}

.speed-value {
  font-size: 16px;
  font-weight: 700;
  font-family: var(--font-mono);
  letter-spacing: -0.5px;
}
.dl-value { color: var(--color-green); }
.ul-value { color: var(--color-blue); }

.divider-vertical {
  width: 1px;
  height: 48px;
  background: var(--border-card);
  margin: 0 12px;
}

.wave-container {
  width: 100%;
  height: 24px;
  margin-top: 2px;
}

.sparkline-svg {
  width: 100%;
  height: 100%;
  overflow: visible;
}

.sparkline-stroke {
  fill: none;
  stroke-width: 1.8;
  stroke-linecap: round;
}
.dl-stroke { stroke: var(--color-green); }
.ul-stroke { stroke: var(--color-blue); }

.sparkline-fill {
  opacity: 0.15;
}
.dl-fill { fill: var(--color-green); }
.ul-fill { fill: var(--color-blue); }
</style>
