<script lang="ts">
  import { onMount } from 'svelte'
  import { app, initTheme, toggleTheme } from './lib/state.svelte'
  import type { Activity } from '@workouts/shared'
  import type { StatsJson } from './lib/state.svelte'
  import MapView from './lib/MapView.svelte'
  import Drawer from './lib/Drawer.svelte'
  import DetailPanel from './lib/DetailPanel.svelte'
  import ChartOverlay from './lib/ChartOverlay.svelte'

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

<header>
  <h1>Workouts</h1>
  <div class="header-actions">
    <button class="theme-btn" onclick={toggleTheme} aria-label="Toggle theme">🌓</button>
  </div>
</header>

{#if app.loading}
  <div class="loading">Loading…</div>
{:else}
  <MapView />
  <Drawer />
  <DetailPanel />
  <ChartOverlay />
{/if}

<style>
  header {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 20;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 1rem;
    background: var(--color-surface, #16213e);
    border-bottom: 1px solid var(--color-border, #2a2a4a);
  }

  h1 {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-text, #e0e0e0);
    margin: 0;
  }

  .header-actions {
    display: flex;
    gap: 0.5rem;
  }

  .theme-btn {
    background: none;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 6px;
    padding: 0.2rem 0.45rem;
    cursor: pointer;
    font-size: 1rem;
  }

  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    color: var(--color-text-secondary, #888);
  }
</style>
