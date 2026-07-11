<script lang="ts">
  import { app, openCharts } from './state.svelte'
  import StatsBar from './StatsBar.svelte'
  import YearPicker from './YearPicker.svelte'
  import ActivityList from './ActivityList.svelte'
  import Filters from './Filters.svelte'

  let tab = $state<'list' | 'filters'>('list')

  $effect(() => {
    if (app.drawerOpen) tab = 'list'
  })
</script>

<!-- Handle bar to toggle drawer -->
<button
  class="handle"
  onclick={() => { app.drawerOpen = !app.drawerOpen }}
  aria-label="Toggle drawer"
>
  <div class="handle-bar">
    <StatsBar />
  </div>
</button>

<div class="drawer" class:open={app.drawerOpen}>
  <div class="drawer-header">
    <div class="tabs">
      <button class="tab" class:active={tab === 'list'} onclick={() => { tab = 'list' }}>
        Activities
      </button>
      <button class="tab" class:active={tab === 'filters'} onclick={() => { tab = 'filters' }}>
        Filters
      </button>
    </div>
    <button class="charts-btn" onclick={openCharts}>📊 Charts</button>
  </div>

  {#if tab === 'list'}
    <YearPicker />
    <ActivityList />
  {:else}
    <Filters />
  {/if}
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

  .charts-btn {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.25rem 0.6rem;
    font-size: 0.8rem;
    color: var(--color-text, #e0e0e0);
    cursor: pointer;
  }

  @media (min-width: 1024px) {
    .drawer {
      left: auto;
      right: 0;
      top: 0;
      bottom: 0;
      border-top: none;
      border-left: 1px solid var(--color-border, #2a2a4a);
      transform: translateX(calc(100% - 48px));
      max-height: none;
      width: 380px;
    }

    .drawer.open {
      transform: translateX(0);
    }
  }
</style>
