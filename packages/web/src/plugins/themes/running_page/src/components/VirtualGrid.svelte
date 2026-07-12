<script lang="ts">
  import type { PeriodBucket } from '../store'
  import ActivityCard from './ActivityCard.svelte'

  let { buckets = [] as PeriodBucket[] }: { buckets: PeriodBucket[] } = $props()
</script>

<div class="grid">
  {#each buckets as bucket (bucket.key)}
    <ActivityCard {bucket} />
  {/each}
</div>

<style>
  .grid {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    padding-bottom: 2rem;
  }
</style>
