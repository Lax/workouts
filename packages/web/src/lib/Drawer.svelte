<script lang="ts">
  import { app, openCharts } from './state.svelte'
  import StatsBar from './StatsBar.svelte'
  import ActivityList from './ActivityList.svelte'
  import Filters from './Filters.svelte'

  let tab = $state<'list' | 'filters'>('list')

  $effect(() => {
    if (app.drawerOpen) tab = 'list'
  })
</script>

<!-- Mobile handle (hidden on desktop) -->
<button
  class="handle"
  onclick={() => { app.drawerOpen = !app.drawerOpen }}
  onmousedown={(e) => e.stopPropagation()}
  ontouchstart={(e) => e.stopPropagation()}
  aria-label="Toggle drawer"
>
  <div class="handle-bar">
    <StatsBar />
  </div>
</button>

<div class="drawer" class:open={app.drawerOpen}>
  <!-- Collapsed strip (desktop only — click to toggle, shows stats) -->
  <div class="drawer-collapsed" onclick={() => { if (!app.drawerOpen) app.drawerOpen = true }} onmousedown={(e) => e.stopPropagation()}>
    <div class="collapsed-item">
      <strong>{app.filteredActivities.length}</strong>
      <span class="lbl">次</span>
    </div>
    <div class="collapsed-item">
      <strong>{(app.filteredActivities.reduce((s, a) => s + (a.distance ?? 0), 0) / 1000).toFixed(0)}</strong>
      <span class="lbl">km</span>
    </div>
    <div class="collapsed-item">
      <strong>{(app.filteredActivities.reduce((s, a) => s + (a.moving_time ?? 0), 0) / 3600).toFixed(1)}</strong>
      <span class="lbl">h</span>
    </div>
    <div class="collapsed-item">
      <strong>{Math.round(app.filteredActivities.reduce((s, a) => s + (a.elevation_gain ?? 0), 0))}</strong>
      <span class="lbl">m</span>
    </div>
    <span class="spacer"></span>
    <button class="collapsed-btn" onclick={(e) => { e.stopPropagation(); openCharts() }} onmousedown={(e) => e.stopPropagation()}>📊</button>
  </div>

  <!-- Full drawer body -->
  <div class="drawer-body">
    <div class="drawer-header">
      <div class="tabs">
        <button class="tab" class:active={tab === 'list'} onclick={() => { tab = 'list' }}>
          Activities
        </button>
        <button class="tab" class:active={tab === 'filters'} onclick={() => { tab = 'filters' }}>
          Filters
        </button>
      </div>
      <button class="charts-btn" onclick={openCharts}>📊</button>
      <button class="retract-btn" onclick={() => { app.drawerOpen = false }} onmousedown={(e) => e.stopPropagation()} aria-label="Close drawer">▶</button>
    </div>

    {#if tab === 'list'}
      <ActivityList />
    {:else}
      <Filters />
    {/if}
  </div>
</div>

<style>
  .handle {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    z-index: 10;
    background: transparent;
    border: none;
    cursor: pointer;
    padding: 0;
  }

  .handle-bar {
    background: var(--color-surface, #16213e);
    border-top: 1px solid var(--color-border, #2a2a4a);
    padding: 0.5rem;
  }

  .drawer {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    z-index: 9;
    background: var(--color-surface, #16213e);
    border-top: 1px solid var(--color-border, #2a2a4a);
    transform: translateY(calc(100% - 52px));
    transition: transform 0.3s ease;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
  }

  .drawer.open {
    transform: translateY(0);
  }

  .drawer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--color-border, #2a2a4a);
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

  .charts-btn, .retract-btn {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.25rem 0.6rem;
    font-size: 0.8rem;
    color: var(--color-text, #e0e0e0);
    cursor: pointer;
  }
  .retract-btn {
    margin-left: auto;
  }
  .retract-btn:hover {
    color: var(--color-accent, #4dd2ff);
    border-color: var(--color-accent, #4dd2ff);
  }

  .drawer-collapsed {
    display: none;
  }

  @media (min-width: 1024px) {
    .handle {
      display: none;
    }

    .drawer {
      flex-direction: row-reverse;
      left: auto;
      right: 0;
      top: 50%;
      bottom: auto;
      transform: translateY(-50%) translateX(calc(100% - 48px));
      width: auto;
      max-height: 80vh;
      height: auto;
      border-top: none;
      border-left: 1px solid var(--color-border, #2a2a4a);
      border-radius: 12px 0 0 12px;
    }

    .drawer.open {
      transform: translateY(-50%) translateX(0);
    }

    .drawer-collapsed {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
      padding: 12px 4px;
      width: 48px;
      flex-shrink: 0;
    }

    .drawer-body {
      display: none;
      width: 380px;
      max-height: 80vh;
      overflow-y: auto;
    }

    .drawer.open .drawer-body {
      display: flex;
      flex-direction: column;
    }

    .drawer.open .drawer-collapsed {
      display: none;
    }

    .collapsed-item {
      text-align: center;
      font-size: 0.65rem;
      color: var(--color-text-secondary, #888);
    }
    .collapsed-item strong {
      display: block;
      font-size: 0.8rem;
      color: var(--color-text, #e0e0e0);
    }
    .collapsed-item .lbl {
      font-size: 0.6rem;
    }

    .spacer {
      flex: 1;
    }

    .collapsed-btn {
      background: transparent;
      border: 1px solid var(--color-border, #2a2a4a);
      border-radius: 6px;
      padding: 4px 6px;
      font-size: 0.8rem;
      color: var(--color-text-secondary, #888);
      cursor: pointer;
      line-height: 1;
      width: 36px;
    }
    .collapsed-btn:hover {
      border-color: var(--color-accent, #4dd2ff);
      color: var(--color-accent, #4dd2ff);
    }
  }
</style>
