<script lang="ts">
  import { getContext } from 'svelte'
  const { yearStats, state } = getContext('running-store') as any

  function selectYear(y: string) { state.selectedYear = y }
</script>

<div class="sidebar">
  <h2 class="site-title">Workouts</h2>
  <p class="site-desc">Running Journey</p>

  <div class="year-list">
    <div class="year-block total" class:active={state.selectedYear === 'all'} onclick={() => selectYear('all')}>
      <span class="year-label">Total</span>
    </div>
    {#each yearStats as ys}
      <div
        class="year-block"
        class:active={state.selectedYear === String(ys.year)}
        onclick={() => selectYear(String(ys.year))}
      >
        <span class="year-label">{ys.year}</span>
        <div class="year-stats">
          <span class="stat"><strong>{ys.count}</strong> runs</span>
          <span class="stat"><strong>{(ys.totalDistance / 1000).toFixed(0)}</strong> km</span>
          <span class="stat"><strong>{ys.avgPace}</strong> /km</span>
          {#if ys.avgHr}
            <span class="stat"><strong>{ys.avgHr}</strong> bpm</span>
          {/if}
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .sidebar { padding: 0.5rem 0; }
  .site-title {
    font-size: 2rem;
    font-weight: 700;
    font-style: italic;
    color: var(--color-accent, #e0ed5e);
    margin: 0 0 0.25rem;
  }
  .site-desc { font-size: 0.85rem; color: var(--color-text-dim, #666); margin-bottom: 1.5rem; }
  .year-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .year-block {
    padding: 0.75rem;
    border-radius: 8px;
    cursor: pointer;
    transition: background 0.15s;
    border: 1px solid transparent;
  }
  .year-block:hover { background: var(--color-hover, #262626); }
  .year-block.active { border-color: var(--color-accent, #e0ed5e); }
  .year-label { font-weight: 600; font-size: 1rem; color: var(--color-text, #e0e0e0); }
  .year-stats { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.35rem; }
  .stat { font-size: 0.75rem; color: var(--color-text-secondary, #888); }
  .stat strong { color: var(--color-text, #e0e0e0); }
</style>
