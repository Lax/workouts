<script lang="ts">
  import { app, toggleSort, openDetail } from './state.svelte'
  import { formatDistance, formatDuration, formatDate } from '@workouts/shared'
  import { activityColor } from './colorMode'

  function srcBadge(source: string | null): string {
    const map: Record<string, string> = {
      garmin: 'G',
      garmin_cn: 'GC',
      strava: 'S',
      keep: 'K',
      igpsport: 'iG',
      xoss: 'X',
      xingzhe: 'XZ',
    }
    return map[source ?? ''] ?? source?.charAt(0).toUpperCase() ?? '?'
  }
</script>

<div class="list-header">
  <span class="count">{app.filteredActivities.length} activities</span>
  <div class="sort-group">
    <button
      class="sort-btn"
      class:active={app.sortField === 'date'}
      onclick={() => toggleSort('date')}
    >
      Date {app.sortField === 'date' ? (app.sortDesc ? '↓' : '↑') : ''}
    </button>
    <button
      class="sort-btn"
      class:active={app.sortField === 'distance'}
      onclick={() => toggleSort('distance')}
    >
      Dist {app.sortField === 'distance' ? (app.sortDesc ? '↓' : '↑') : ''}
    </button>
    <button
      class="sort-btn"
      class:active={app.sortField === 'time'}
      onclick={() => toggleSort('time')}
    >
      Time {app.sortField === 'time' ? (app.sortDesc ? '↓' : '↑') : ''}
    </button>
  </div>
</div>

<div class="list">
  {#each app.filteredActivities as act}
    <div
      class="activity-row"
      class:hovered={app.mapHoveredId === act.run_id}
      onclick={() => openDetail(act)}
      onmouseenter={() => { app.mapHoveredId = act.run_id }}
      onmouseleave={() => { app.mapHoveredId = null }}
    >
      <span
        class="dot"
        style="background:{activityColor(
          { average_speed: act.average_speed, type: act.sport_category },
          app.colorMode,
        )}"
      ></span>
      <div class="info">
        <span class="name">
          {act.name || 'Untitled'}
          <span class="badge">{srcBadge(act.source)}</span>
        </span>
        <span class="date">{formatDate(act.start_date)}</span>
      </div>
      <div class="metrics">
        <span class="dist">{formatDistance(act.distance)}</span>
        <span class="time">{formatDuration(act.moving_time)}</span>
      </div>
    </div>
  {/each}
</div>

<style>
  .list-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0.75rem;
    font-size: 0.8rem;
    color: var(--color-text-secondary, #888);
    border-bottom: 1px solid var(--color-border, #2a2a4a);
  }

  .sort-group {
    display: flex;
    gap: 0.25rem;
  }

  .sort-btn {
    background: transparent;
    border: 1px solid var(--color-border, #2a2a4a);
    border-radius: 4px;
    padding: 0.15rem 0.4rem;
    font-size: 0.75rem;
    color: var(--color-text-secondary, #888);
    cursor: pointer;
  }

  .sort-btn.active {
    color: var(--color-accent, #4dd2ff);
    border-color: var(--color-accent, #4dd2ff);
  }

  .list {
    overflow-y: auto;
    flex: 1;
  }

  .activity-row {
    display: grid;
    grid-template-columns: 8px 1fr auto;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    cursor: pointer;
    align-items: center;
    border-bottom: 1px solid var(--color-border, #2a2a4a);
    transition: background 0.1s;
  }

  .activity-row:hover,
  .activity-row.hovered {
    background: var(--color-hover, #0f3460);
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .info {
    min-width: 0;
  }

  .name {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.85rem;
    color: var(--color-text, #e0e0e0);
  }

  .badge {
    font-size: 0.65rem;
    padding: 0.05rem 0.3rem;
    border-radius: 3px;
    background: var(--color-border, #2a2a4a);
    color: var(--color-text-secondary, #888);
  }

  .date {
    font-size: 0.7rem;
    color: var(--color-text-dim, #666);
  }

  .metrics {
    text-align: right;
  }

  .dist {
    display: block;
    font-size: 0.85rem;
    color: var(--color-accent, #4dd2ff);
  }

  .time {
    font-size: 0.7rem;
    color: var(--color-text-dim, #666);
  }
</style>
