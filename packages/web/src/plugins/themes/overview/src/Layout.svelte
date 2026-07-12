<script lang="ts">
  import { setContext, onMount } from 'svelte'
  import type { ThemeContext } from '@workouts/shared'
  import MapView from './components/MapView.svelte'
  import YearPicker from './components/YearPicker.svelte'
  import Drawer from './components/Drawer.svelte'
  import DetailPanel from './components/DetailPanel.svelte'
  import ChartOverlay from './components/ChartOverlay.svelte'
  import { createOverviewStore } from './store'

  let { ctx }: { ctx: ThemeContext } = $props()

  const { state: store, openDetail, closeDetail, openCharts, closeCharts, toggleSort, resetFilters } = createOverviewStore(ctx)
  setContext('overview-store', { state: store, openDetail, closeDetail, openCharts, closeCharts, toggleSort, resetFilters })

  onMount(() => {
    store.activities = ctx.data.activities ?? []
    store.stats = ctx.data.stats ?? null
  })

  function toggleTheme() {
    const next = ctx.theme === 'light' ? 'dark' : 'light'
    document.documentElement.setAttribute('data-theme', next)
    localStorage.setItem('theme', next)
  }
</script>

<MapView />

<div class="map-overlays">
  <div class="ol-tl">
    <div class="brand"><strong>Workouts</strong> {store.years.at(-1) ?? '?'}–{store.years[0] ?? '?'}</div>
  </div>
  <div class="ol-lc">
    <YearPicker />
  </div>
  <div class="ol-bl">
    <div class="legend-toggle">
      <button class="legend-btn" class:active={store.colorMode === 'speed'} onclick={() => { store.colorMode = 'speed' }}>
        速度
      </button>
      <button class="legend-btn" class:active={store.colorMode === 'type'} onclick={() => { store.colorMode = 'type' }}>
        类型
      </button>
    </div>
    <div class="speed-legend">
      <span class="sl-blue"></span>
      <span class="sl-green"></span>
      <span class="sl-yellow"></span>
      <span class="sl-red"></span>
    </div>
    <button class="icon-btn" onclick={toggleTheme} aria-label="Toggle theme">
      {ctx.theme === 'dark' ? '☀️' : '🌙'}
    </button>
  </div>
</div>

<Drawer />
<DetailPanel />
<ChartOverlay />

<style>
  .map-overlays {
    position: fixed;
    inset: 0;
    z-index: 1;
    pointer-events: none;
  }
  .map-overlays > * {
    position: absolute;
    pointer-events: auto;
    touch-action: manipulation;
  }
  .ol-tl { top: 10px; left: 10px; }
  .brand { font-size: 0.85rem; color: var(--color-text-secondary, #888); text-shadow: 0 1px 3px rgba(0,0,0,0.5); }
  .brand strong { color: var(--color-accent, #4dd2ff); font-weight: 700; }
  .ol-lc { left: 6px; top: 50%; transform: translateY(-50%); background: rgba(var(--color-surface-rgb), 0.85); border-radius: 10px; padding: 6px 4px; backdrop-filter: blur(4px); }
  .ol-bl { bottom: 72px; left: 10px; display: flex; flex-direction: column; gap: 4px; align-items: flex-start; }
  .legend-toggle { display: flex; background: rgba(var(--color-surface-rgb), 0.85); border-radius: 8px; border: 1px solid var(--color-border, #2a2a4a); overflow: hidden; backdrop-filter: blur(4px); }
  .legend-btn { padding: 4px 12px; font-size: 0.7rem; color: var(--color-text-secondary, #888); cursor: pointer; border: none; background: transparent; transition: all 0.15s; }
  .legend-btn:first-child { border-right: 1px solid var(--color-border, #2a2a4a); }
  .legend-btn.active { background: var(--color-accent, #4dd2ff); color: #000; font-weight: 600; }
  .speed-legend { display: flex; gap: 0; border-radius: 6px; overflow: hidden; height: 8px; margin-top: 4px; align-self: stretch; }
  .speed-legend span { flex: 1; }
  .sl-blue { background: #4A90D9; }
  .sl-green { background: #50C878; }
  .sl-yellow { background: #FFD700; }
  .sl-red { background: #FF4500; }
  .icon-btn { background: rgba(var(--color-surface-rgb), 0.85); border: 1px solid var(--color-border, #2a2a4a); color: var(--color-text-secondary, #888); border-radius: 6px; padding: 4px 8px; font-size: 0.85rem; cursor: pointer; transition: all 0.15s; line-height: 1; backdrop-filter: blur(4px); }
  .icon-btn:hover { border-color: var(--color-accent, #4dd2ff); color: var(--color-accent, #4dd2ff); }
  @media (max-width: 1023px) {
    .ol-lc { left: 10px; top: 10px; bottom: auto; transform: none; }
    .ol-bl { bottom: 62px; }
  }
</style>
