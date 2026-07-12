<script lang="ts">
  import { getContext } from 'svelte'
  const { state: store, resetFilters } = getContext('overview-store') as any
</script>

<div class="filters">
  <h3>Filters</h3>

  <label>
    Type
    <select bind:value={store.filters.type}>
      <option value="">All</option>
      {#each store.availableTypes as [t, c]}
        <option value={t}>{t} ({c})</option>
      {/each}
    </select>
  </label>

  <label>
    Source
    <select bind:value={store.filters.source}>
      <option value="">All</option>
      {#each store.availableSources as [s, c]}
        <option value={s}>{s} ({c})</option>
      {/each}
    </select>
  </label>

  <label>
    Min distance (km)
    <input type="number" bind:value={store.filters.distanceMin} step="0.5" min="0" placeholder="0" />
  </label>

  <label>
    Max distance (km)
    <input type="number" bind:value={store.filters.distanceMax} step="0.5" min="0" placeholder="100" />
  </label>

  <label>
    Search name
    <input type="text" bind:value={store.filters.search} placeholder="Search…" />
  </label>

  <button class="reset-btn" onclick={resetFilters}>Reset</button>

  {#if store.stats}
    <div class="insights">
      {#if store.stats.streaks.all_time > 7}
        <p class="insight">Longest streak: {store.stats.streaks.all_time} days</p>
      {/if}
    </div>
  {/if}
</div>

<style>
  .filters {
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  h3 {
    font-size: 0.85rem;
    color: var(--color-text, #e0e0e0);
    margin: 0;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    font-size: 0.75rem;
    color: var(--color-text-secondary, #888);
  }

  select,
  input {
    background: var(--color-surface, #16213e);
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.3rem 0.5rem;
    color: var(--color-text, #e0e0e0);
    font-size: 0.8rem;
  }

  .reset-btn {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.3rem;
    color: var(--color-text, #e0e0e0);
    cursor: pointer;
    font-size: 0.8rem;
    margin-top: 0.25rem;
  }

  .insights {
    margin-top: 0.5rem;
  }

  .insight {
    font-size: 0.75rem;
    color: var(--color-text-insight, #aaa);
    padding: 0.3rem 0;
    border-top: 1px solid var(--color-border, #2a2a4a);
  }
</style>
