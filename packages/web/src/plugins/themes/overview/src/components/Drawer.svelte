<script lang="ts">
  import { getContext } from 'svelte'
  const { state: store, openCharts } = getContext('overview-store') as any
  import ActivityList from './ActivityList.svelte'
  import Filters from './Filters.svelte'

  let tab = $state<'list' | 'filters'>('list')

  $effect(() => {
    if (store.drawerOpen) tab = 'list'
  })

  let count = $derived(store.filteredActivities.length)
  let dist = $derived((store.filteredActivities.reduce((s, a) => s + (a.distance ?? 0), 0) / 1000).toFixed(0))
  let time = $derived((store.filteredActivities.reduce((s, a) => s + (a.moving_time ?? 0), 0) / 3600).toFixed(1))
  let elev = $derived(Math.round(store.filteredActivities.reduce((s, a) => s + (a.elevation_gain ?? 0), 0)).toString())

  function toggle() { store.drawerOpen = !store.drawerOpen }
</script>

<div class="drawer" class:open={store.drawerOpen}>
  <div class="drawer-handle" onclick={toggle} onmousedown={(e) => e.stopPropagation()}>
    <div class="bar"></div>
  </div>

  <div class="drawer-collapsed" onclick={toggle} onmousedown={(e) => e.stopPropagation()}>
    <span class="stat-pill"><strong>{count}</strong>次</span>
    <span class="stat-pill"><strong>{dist}</strong>km</span>
    <span class="stat-pill"><strong>{time}</strong>h</span>
    <span class="stat-pill"><strong>{elev}</strong>m</span>
    <span class="spacer"></span>
    <button class="icon-btn" onclick={(e) => { e.stopPropagation(); openCharts() }} onmousedown={(e) => e.stopPropagation()}>📊</button>
    <button class="icon-btn" onclick={(e) => { e.stopPropagation(); toggle() }} onmousedown={(e) => e.stopPropagation()}>▲</button>
  </div>

  <div class="drawer-body">
    <div class="drawer-header">
      <div class="tabs">
        <button class="tab" class:active={tab === 'list'} onclick={() => { tab = 'list' }}>Activities</button>
        <button class="tab" class:active={tab === 'filters'} onclick={() => { tab = 'filters' }}>Filters</button>
      </div>
      <button class="icon-btn" onclick={openCharts} onmousedown={(e) => e.stopPropagation()}>📊</button>
      <button class="icon-btn retract" onclick={(e) => { e.stopPropagation(); toggle() }} onmousedown={(e) => e.stopPropagation()} aria-label="Close drawer">✕</button>
    </div>
    {#if tab === 'list'}
      <ActivityList />
    {:else}
      <Filters />
    {/if}
  </div>
</div>

<style>
  .drawer {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    z-index: 2;
    background: var(--color-surface, #16213e);
    border-top: 1px solid var(--color-border, #2a2a4a);
    transform: translateY(calc(100% - 52px));
    transition: transform 0.3s ease;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    will-change: transform;
  }

  .drawer.open {
    transform: translateY(0);
  }

  .drawer-handle {
    height: 16px;
    display: flex;
    justify-content: center;
    align-items: center;
    cursor: pointer;
    background: var(--color-surface, #16213e);
    border-radius: 12px 12px 0 0;
    padding: 2px 0;
    flex-shrink: 0;
  }

  .drawer-handle .bar {
    width: 32px;
    height: 3px;
    border-radius: 2px;
    background: var(--color-text-dim, #444);
  }

  .drawer-collapsed {
    height: 34px;
    display: flex;
    align-items: center;
    padding: 0 10px;
    gap: 6px;
    background: var(--color-surface, #16213e);
    border-left: 1px solid var(--color-border, #2a2a4a);
    border-right: 1px solid var(--color-border, #2a2a4a);
    flex-shrink: 0;
  }

  .stat-pill {
    font-size: 0.72rem;
    color: var(--color-text-secondary, #888);
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 3px;
  }
  .stat-pill strong {
    color: var(--color-text, #e0e0e0);
    font-weight: 600;
  }

  .spacer {
    flex: 1;
  }

  .icon-btn {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    color: var(--color-text-secondary, #888);
    border-radius: 6px;
    padding: 4px 8px;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.15s;
    line-height: 1;
  }
  .icon-btn:hover {
    border-color: var(--color-accent, #4dd2ff);
    color: var(--color-accent, #4dd2ff);
  }

  .drawer-body {
    height: 45vh;
    max-height: 480px;
    background: var(--color-surface, #16213e);
    display: none;
    flex-direction: column;
    border-left: 1px solid var(--color-border, #2a2a4a);
    border-right: 1px solid var(--color-border, #2a2a4a);
  }

  .drawer.open .drawer-body {
    display: flex;
  }

  .drawer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--color-border, #2a2a4a);
    flex-shrink: 0;
  }

  .tabs {
    display: flex;
    gap: 0.25rem;
  }

  .tab {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.25rem 0.6rem;
    font-size: 0.8rem;
    color: var(--color-text-secondary, #888);
    cursor: pointer;
  }
  .tab.active {
    background: var(--color-accent, #4dd2ff);
    border-color: var(--color-accent, #4dd2ff);
    color: #000;
  }

  .retract {
    margin-left: auto;
  }

  @media (min-width: 1024px) {
    .drawer {
      left: auto;
      right: 0;
      bottom: auto;
      top: 50%;
      transform: translateY(-50%) translateX(calc(100% - 48px));
      width: auto;
      height: auto;
      max-height: 80vh;
      border-top: none;
      border-left: 1px solid var(--color-border, #2a2a4a);
      border-radius: 12px 0 0 12px;
      flex-direction: row-reverse;
    }

    .drawer.open {
      transform: translateY(-50%) translateX(0);
    }

    .drawer-handle {
      display: none;
    }

    .drawer-collapsed {
      flex-direction: column;
      width: 48px;
      height: auto;
      padding: 10px 4px;
      gap: 8px;
      border: none;
      border-radius: 12px 0 0 12px;
      flex-shrink: 0;
    }

    .drawer.open .drawer-collapsed {
      display: none;
    }

    .drawer-body {
      width: 380px;
      max-height: 80vh;
      height: auto;
      display: none;
      border: none;
    }

    .drawer.open .drawer-body {
      display: flex;
    }

    .stat-pill {
      flex-direction: column;
      gap: 0;
      text-align: center;
      font-size: 0.65rem;
    }
    .stat-pill strong {
      font-size: 0.8rem;
    }

    .spacer {
      display: none;
    }
  }

  @media (max-width: 640px) {
    .drawer-body {
      height: 55vh;
    }
  }
</style>
