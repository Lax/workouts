<script lang="ts">
  import { app } from './state.svelte'
</script>

<div class="year-picker">
  <button
    class="year-pill"
    class:active={app.selectedYear === null}
    onclick={() => { app.selectedYear = null; app.selectedMonth = null }}
  >All</button>

  {#each app.years as year}
    <button
      class="year-pill"
      class:active={app.selectedYear === year}
      onclick={() => { app.selectedYear = year; app.selectedMonth = null }}
    >{year}</button>
  {/each}
</div>

{#if app.selectedMonth !== null}
  <span class="month-chip">
    {app.selectedYear}-{String(app.selectedMonth).padStart(2, '0')}
    <button class="chip-close" onclick={() => { app.selectedMonth = null }}>×</button>
  </span>
{/if}

<style>
  .year-picker {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .year-pill {
    background: rgba(var(--color-surface-rgb), 0.85);
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 12px;
    padding: 2px 8px;
    color: var(--color-text-secondary, #888);
    cursor: pointer;
    font-size: 0.7rem;
    text-align: center;
    transition: all 0.15s;
    backdrop-filter: blur(4px);
    line-height: 1.5;
  }

  .year-pill:hover {
    border-color: var(--color-accent, #4dd2ff);
    color: var(--color-accent, #4dd2ff);
  }

  .year-pill.active {
    background: var(--color-accent, #4dd2ff);
    border-color: var(--color-accent, #4dd2ff);
    color: var(--color-bg, #121212);
    font-weight: 600;
  }

  .month-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    background: rgba(var(--color-surface-rgb), 0.85);
    border: 1px solid var(--color-border, #2a2a4a);
    color: var(--color-accent, #4dd2ff);
    border-radius: 12px;
    padding: 2px 8px;
    font-size: 0.7rem;
    margin-top: 3px;
    backdrop-filter: blur(4px);
  }

  .chip-close {
    background: none;
    border: none;
    color: var(--color-accent, #4dd2ff);
    cursor: pointer;
    font-size: 1rem;
    padding: 0;
    line-height: 1;
    opacity: 0.7;
  }
  .chip-close:hover {
    opacity: 1;
  }

  @media (max-width: 1023px) {
    .year-picker {
      flex-direction: row;
      overflow-x: auto;
    }
  }
</style>
