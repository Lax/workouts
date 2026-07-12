<script lang="ts">
  import { setContext } from 'svelte'
  import type { ThemeContext } from '@workouts/shared'
  import { createRunningStore } from './store'
  import Sidebar from './components/Sidebar.svelte'
  import MapView from './components/MapView.svelte'
  import ActivityTable from './components/ActivityTable.svelte'
  import FilterBar from './components/FilterBar.svelte'
  import VirtualGrid from './components/VirtualGrid.svelte'

  let { ctx }: { ctx: ThemeContext } = $props()
  setContext('theme', ctx)

  const api = createRunningStore(ctx)
  setContext('running-store', api)

  function toggleTheme() {
    const next = ctx.theme === 'light' ? 'dark' : 'light'
    document.documentElement.setAttribute('data-theme', next)
  }
</script>

<div class="rp-layout">
  <header class="rp-header">
    <div class="rp-header-left">
      <h1 class="rp-title">Workouts</h1>
    </div>
    <nav class="rp-nav">
      <a href="/">Home</a>
      <a href="/summary" onclick={(e) => { e.preventDefault(); api.state.view = 'summary' }}>Summary</a>
    </nav>
    <button class="rp-theme-btn" onclick={toggleTheme}>
      {ctx.theme === 'dark' ? '☀️' : '🌙'}
    </button>
  </header>

  <div class="rp-main">
    <aside class="rp-sidebar">
      <Sidebar />
    </aside>
    <section class="rp-content">
      {#if api.state.view === 'summary'}
        <FilterBar />
        <VirtualGrid buckets={api.summaryBuckets} />
      {:else}
        <MapView />
        <ActivityTable />
      {/if}
    </section>
  </div>
</div>

<style>
  .rp-layout {
    min-height: 100vh;
    background: var(--color-bg, #171717);
    color: var(--color-text, #e0e0e0);
    font-family: 'IBM Plex Sans', sans-serif;
  }
  .rp-header {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 1rem 2rem;
    border-bottom: 1px solid var(--color-border, #333);
  }
  .rp-header-left { flex: 1; }
  .rp-title {
    font-size: 1.5rem;
    font-weight: 700;
    font-style: italic;
    color: var(--color-accent, #e0ed5e);
    margin: 0;
  }
  .rp-nav { display: flex; gap: 1rem; }
  .rp-nav a {
    color: var(--color-text-secondary, #888);
    text-decoration: none;
    font-size: 0.9rem;
  }
  .rp-nav a:hover { color: var(--color-accent, #e0ed5e); }
  .rp-theme-btn {
    background: transparent;
    border: 1px solid var(--color-border, #333);
    border-radius: 50%;
    width: 36px; height: 36px;
    cursor: pointer;
    font-size: 1rem;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .rp-main {
    display: flex;
    gap: 0;
    min-height: calc(100vh - 60px);
  }
  .rp-sidebar {
    width: 33.333%;
    max-width: 380px;
    padding: 1.5rem;
    border-right: 1px solid var(--color-border, #333);
    overflow-y: auto;
  }
  .rp-content {
    flex: 1;
    padding: 1rem;
    overflow-y: auto;
  }
  .rp-summary-placeholder {
    padding: 2rem;
    text-align: center;
    color: var(--color-text-dim, #666);
  }

  @media (max-width: 768px) {
    .rp-main { flex-direction: column; }
    .rp-sidebar { width: 100%; max-width: none; border-right: none; border-bottom: 1px solid var(--color-border, #333); }
  }
</style>
