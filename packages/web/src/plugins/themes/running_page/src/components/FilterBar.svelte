<script lang="ts">
  import { getContext } from 'svelte'
  const { state, availableTypes } = getContext('running-store') as any

  function goBack() { state.view = 'main' }
</script>

<div class="filter-bar">
  <button class="rp-btn" onclick={goBack}>← Back to Main</button>
  <select bind:value={state.summaryType}>
    <option value="all">All Types</option>
    {#each availableTypes as [type, _]}
      <option value={type}>{type}</option>
    {/each}
  </select>
  <select bind:value={state.summaryInterval}>
    <option value="monthly">Monthly</option>
    <option value="weekly">Weekly</option>
    <option value="daily">Daily</option>
    <option value="yearly">Yearly</option>
  </select>
</div>

<style>
  .filter-bar { display: flex; gap: 0.5rem; align-items: center; margin-bottom: 1rem; flex-wrap: wrap; }
  .rp-btn {
    padding: 0.35rem 0.75rem; font-size: 0.8rem;
    background: var(--color-surface, #262626); color: var(--color-text, #e0e0e0);
    border: 1px solid var(--color-border, #333); border-radius: 6px; cursor: pointer;
  }
  .rp-btn:hover { border-color: var(--color-accent, #e0ed5e); }
  select {
    padding: 0.35rem; font-size: 0.8rem;
    background: var(--color-surface, #262626); color: var(--color-text, #e0e0e0);
    border: 1px solid var(--color-border, #333); border-radius: 6px;
  }
</style>
