<script lang="ts">
  import { app } from './state.svelte'

  let totalDist = $derived(app.filteredActivities.reduce((s, a) => s + (a.distance ?? 0), 0))
  let totalTime = $derived(app.filteredActivities.reduce((s, a) => s + (a.moving_time ?? 0), 0))
  let totalElev = $derived(app.filteredActivities.reduce((s, a) => s + (a.elevation_gain ?? 0), 0))
  let count = $derived(app.filteredActivities.length)

  function fmtDist(m: number): string {
    return (m / 1000).toFixed(1)
  }

  function fmtTime(s: number): string {
    const h = s / 3600
    return h.toFixed(1)
  }
</script>

<div class="stats-bar">
  <span class="pill">{count}次</span>
  <span class="pill">{fmtDist(totalDist)}km</span>
  <span class="pill">{fmtTime(totalTime)}h</span>
  <span class="pill">{Math.round(totalElev)}m</span>
</div>

<style>
  .stats-bar {
    display: flex;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
  }

  .pill {
    background: var(--color-surface, #16213e);
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 999px;
    padding: 0.2rem 0.6rem;
    font-size: 0.8rem;
    color: var(--color-text, #e0e0e0);
    white-space: nowrap;
  }
</style>
