<script lang="ts">
  import { getContext } from 'svelte'
  import { formatDistance, formatDuration, formatDate } from '@workouts/shared'
  import { activityColor } from '../colorMode'
  import { decodePolyline } from '../polyline'
  const { state: store, toggleSort, openDetail } = getContext('overview-store') as any

  interface SvgPathData {
    points: string
    sx: number; sy: number
    ex: number; ey: number
    hasPath: boolean
  }

  function normalizeSvg(pts: [number, number][]): SvgPathData {
    let minLat = Infinity, maxLat = -Infinity
    let minLng = Infinity, maxLng = -Infinity
    for (const [lat, lng] of pts) {
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
      if (lng < minLng) minLng = lng
      if (lng > maxLng) maxLng = lng
    }
    const rLng = maxLng - minLng || 1
    const rLat = maxLat - minLat || 1
    const W = 60, H = 24, pad = 3
    const scale = Math.min((W - pad * 2) / rLng, (H - pad * 2) / rLat)
    const ox = (W - rLng * scale) / 2
    const oy = (H - rLat * scale) / 2
    const coords = pts.map(([lat, lng]) => ({
      x: ox + (lng - minLng) * scale,
      y: oy + (maxLat - lat) * scale,
    }))
    return {
      points: coords.map(c => `${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' '),
      sx: coords[0].x, sy: coords[0].y,
      ex: coords[coords.length - 1].x, ey: coords[coords.length - 1].y,
      hasPath: true,
    }
  }

  const decodeCache = new Map<string, SvgPathData>()

  let pathCache = $derived.by(() => {
    const map = new Map<string, SvgPathData>()
    for (const a of store.filteredActivities) {
      const encoded = a.summary_polyline || a.polyline
      if (!encoded) { map.set(a.run_id, { points: '', sx: 0, sy: 0, ex: 0, ey: 0, hasPath: false }); continue }
      if (decodeCache.has(encoded)) {
        map.set(a.run_id, decodeCache.get(encoded)!)
      } else {
        const pts = decodePolyline(encoded)
        if (pts.length < 2) { map.set(a.run_id, { points: '', sx: 0, sy: 0, ex: 0, ey: 0, hasPath: false }); continue }
        const data = normalizeSvg(pts)
        decodeCache.set(encoded, data)
        map.set(a.run_id, data)
      }
    }
    return map
  })

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
  <span class="count">{store.filteredActivities.length} activities</span>
  <div class="sort-group">
    <button
      class="sort-btn"
      class:active={store.sortField === 'date'}
      onclick={() => toggleSort('date')}
    >
      Date {store.sortField === 'date' ? (store.sortDesc ? '↓' : '↑') : ''}
    </button>
    <button
      class="sort-btn"
      class:active={store.sortField === 'distance'}
      onclick={() => toggleSort('distance')}
    >
      Dist {store.sortField === 'distance' ? (store.sortDesc ? '↓' : '↑') : ''}
    </button>
    <button
      class="sort-btn"
      class:active={store.sortField === 'time'}
      onclick={() => toggleSort('time')}
    >
      Time {store.sortField === 'time' ? (store.sortDesc ? '↓' : '↑') : ''}
    </button>
  </div>
</div>

<div class="list">
  {#each store.filteredActivities as act (act.run_id)}
    {@const col = activityColor({ average_speed: act.average_speed, type: act.sport_category }, store.colorMode)}
    {@const svg = pathCache.get(act.run_id)}
    <div
      class="activity-row"
      class:hovered={store.mapHoveredId === act.run_id}
      onclick={() => openDetail(act)}
      onmouseenter={() => { store.mapHoveredId = act.run_id }}
      onmouseleave={() => { store.mapHoveredId = null }}
    >
      {#if svg?.hasPath}
        <svg viewBox="0 0 60 24" width="60" height="24" class="mini-svg">
          <polyline points={svg.points} stroke={col} class="mini-path" />
          <circle cx={svg.sx} cy={svg.sy} r="2" fill={col} class="mini-endpoint" />
          <circle cx={svg.ex} cy={svg.ey} r="2" fill={col} class="mini-endpoint" />
        </svg>
      {:else}
        <svg viewBox="0 0 60 24" width="60" height="24" class="mini-svg">
          <circle cx="30" cy="12" r="6" fill={col} />
        </svg>
      {/if}
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
    grid-template-columns: 60px 1fr auto;
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

  .mini-svg {
    display: block;
    flex-shrink: 0;
  }

  .mini-path {
    fill: none;
    stroke-width: 2;
    stroke-opacity: 0.7;
    stroke-linecap: round;
    stroke-linejoin: round;
    transition: stroke-opacity 0.1s, stroke-width 0.1s;
  }

  .mini-endpoint {
    opacity: 0;
    transition: opacity 0.1s;
  }

  .activity-row:hover .mini-path {
    stroke-opacity: 1;
    stroke-width: 2.5;
  }

  .activity-row:hover .mini-endpoint {
    opacity: 0.8;
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
