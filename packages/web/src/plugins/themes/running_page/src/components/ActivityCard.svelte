<script lang="ts">
  import type { PeriodBucket } from '../store'
  import ActivityChart from './ActivityChart.svelte'
  import { formatDistance } from '@workouts/shared'

  let { bucket }: { bucket: PeriodBucket } = $props()
</script>

<div class="card">
  <h3 class="card-title">{bucket.label}</h3>
  <div class="card-stats">
    <span class="cs"><strong>{bucket.count}</strong> runs</span>
    <span class="cs"><strong>{formatDistance(bucket.totalDistance)}</strong></span>
    <span class="cs"><strong>{bucket.avgPace}</strong> /km</span>
    {#if bucket.avgHr}
      <span class="cs"><strong>{bucket.avgHr}</strong> bpm</span>
    {/if}
  </div>
  <ActivityChart dailyDistances={bucket.dailyDistances} />
</div>

<style>
  .card {
    background: var(--color-surface, #262626);
    border-radius: 8px;
    padding: 0.75rem;
    border: 1px solid var(--color-border, #333);
    transition: transform 0.15s;
    width: 260px;
    flex-shrink: 0;
  }
  .card:hover { transform: translateY(-3px); }
  .card-title { font-size: 1rem; color: var(--color-accent, #e0ed5e); margin: 0 0 0.5rem; }
  .card-stats { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.5rem; font-size: 0.75rem; color: var(--color-text-secondary, #888); }
  .cs strong { color: var(--color-text, #e0e0e0); }
</style>
