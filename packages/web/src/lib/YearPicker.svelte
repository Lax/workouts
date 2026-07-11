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
    gap: 0.25rem;
    padding: 0.5rem;
  }

  .year-pill {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 999px;
    padding: 0.3rem 0.65rem;
    color: var(--color-text, #e0e0e0);
    cursor: pointer;
    font-size: 0.8rem;
    text-align: center;
    transition: background 0.15s;
  }

  .year-pill.active {
    background: var(--color-accent, #4dd2ff);
    border-color: var(--color-accent, #4dd2ff);
    color: #000;
  }

  .month-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    background: var(--color-accent, #4dd2ff);
    color: #000;
    border-radius: 999px;
    padding: 0.15rem 0.5rem;
    font-size: 0.75rem;
    margin: 0 0.5rem;
  }

  .chip-close {
    background: none;
    border: none;
    color: #000;
    cursor: pointer;
    font-size: 1rem;
    padding: 0;
    line-height: 1;
  }

  @media (max-width: 1023px) {
    .year-picker {
      flex-direction: row;
      overflow-x: auto;
    }
  }
</style>
