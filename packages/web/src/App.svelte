<script lang="ts">
  import { onMount } from 'svelte'
  import { app, initReactivity, initTheme, toggleTheme } from './lib/state.svelte'
  import type { Activity } from '@workouts/shared'
  import type { StatsJson } from './lib/state.svelte'
  import MapView from './lib/MapView.svelte'
  import YearPicker from './lib/YearPicker.svelte'
  import Drawer from './lib/Drawer.svelte'
  import DetailPanel from './lib/DetailPanel.svelte'
  import ChartOverlay from './lib/ChartOverlay.svelte'

  initReactivity()

  onMount(async () => {
    initTheme()
    try {
      const [actRes, statsRes] = await Promise.all([
        fetch('activities.json'),
        fetch('stats.json'),
      ])
      if (actRes.ok) {
        const data: Activity[] = await actRes.json()
        app.activities.splice(0, app.activities.length, ...data)
      }
      if (statsRes.ok) {
        const data: StatsJson = await statsRes.json()
        app.stats = data
      }
    } catch (e) {
      console.warn('Failed to load data', e)
    } finally {
      app.loading = false
    }
  })
</script>

{#if app.loading}
  <div class="loading">Loading…</div>
{:else}
  <MapView />

  <div class="map-overlay ol-tl">
    <div class="brand"><strong>Workouts</strong> {app.years.at(-1) ?? '?'}–{app.years[0] ?? '?'}</div>
  </div>

  <div class="map-overlay ol-lc">
    <YearPicker />
  </div>

  <div class="map-overlay ol-bl">
    <div class="legend-toggle">
      <button class="legend-btn" class:active={app.colorMode === 'speed'} onclick={() => { app.colorMode = 'speed' }}>
        速度
      </button>
      <button class="legend-btn" class:active={app.colorMode === 'type'} onclick={() => { app.colorMode = 'type' }}>
        类型
      </button>
    </div>
    <div class="speed-legend">
      <span class="sl-blue"></span>
      <span class="sl-green"></span>
      <span class="sl-yellow"></span>
      <span class="sl-red"></span>
    </div>
    <button class="icon-btn" onclick={toggleTheme} aria-label="Toggle theme">🌓</button>
  </div>

  <Drawer />
  <DetailPanel />
  <ChartOverlay />
{/if}

<style>
  .map-overlay {
    position: fixed;
    z-index: 1;
    pointer-events: none;
  }
  .map-overlay > * {
    pointer-events: auto;
  }

  .ol-tl {
    top: 10px;
    left: 10px;
  }

  .brand {
    font-size: 0.85rem;
    color: var(--color-text-secondary, #888);
    text-shadow: 0 1px 3px rgba(0,0,0,0.5);
  }
  .brand strong {
    color: var(--color-accent, #4dd2ff);
    font-weight: 700;
  }

  .ol-lc {
    left: 6px;
    top: 50%;
    transform: translateY(-50%);
    background: rgba(var(--color-surface-rgb), 0.85);
    border-radius: 10px;
    padding: 6px 4px;
    backdrop-filter: blur(4px);
  }

  .ol-bl {
    bottom: 72px;
    left: 10px;
    display: flex;
    flex-direction: column;
    gap: 4px;
    align-items: flex-start;
  }

  .legend-toggle {
    display: flex;
    background: rgba(var(--color-surface-rgb), 0.85);
    border-radius: 8px;
    border: 1px solid var(--color-border, #2a2a4a);
    overflow: hidden;
    backdrop-filter: blur(4px);
  }

  .legend-btn {
    padding: 4px 12px;
    font-size: 0.7rem;
    color: var(--color-text-secondary, #888);
    cursor: pointer;
    border: none;
    background: transparent;
    transition: all 0.15s;
  }
  .legend-btn:first-child {
    border-right: 1px solid var(--color-border, #2a2a4a);
  }

  .legend-btn.active {
    background: var(--color-accent, #4dd2ff);
    color: #000;
    font-weight: 600;
  }

  .speed-legend {
    display: flex;
    gap: 0;
    border-radius: 6px;
    overflow: hidden;
    height: 8px;
    margin-top: 4px;
    align-self: stretch;
  }
  .speed-legend span { flex: 1; }
  .sl-blue { background: #4A90D9; }
  .sl-green { background: #50C878; }
  .sl-yellow { background: #FFD700; }
  .sl-red { background: #FF4500; }

  .icon-btn {
    background: rgba(var(--color-surface-rgb), 0.85);
    border: 1px solid var(--color-border, #2a2a4a);
    color: var(--color-text-secondary, #888);
    border-radius: 6px;
    padding: 4px 8px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.15s;
    line-height: 1;
    backdrop-filter: blur(4px);
  }
  .icon-btn:hover {
    border-color: var(--color-accent, #4dd2ff);
    color: var(--color-accent, #4dd2ff);
  }

  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    color: var(--color-text-secondary, #888);
  }

  @media (max-width: 1023px) {
    .ol-lc {
      left: 10px;
      top: 10px;
      bottom: auto;
      transform: none;
    }

    .ol-bl {
      bottom: 62px;
    }
  }
</style>
