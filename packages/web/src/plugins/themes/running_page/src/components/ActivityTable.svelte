<script lang="ts">
  import { getContext } from 'svelte'
  import { formatDistance, formatDuration } from '@workouts/shared'

  const api = getContext('running-store') as any
  const { state, filteredRuns } = api

  function sortBy(field: string) {
    if (state.sortField === field) { state.sortDesc = !state.sortDesc }
    else { state.sortField = field; state.sortDesc = true }
  }

  function locate(runId: string) {
    state.selectedActivity = filteredRuns.find((a: any) => a.run_id === runId) ?? null
  }

  const sorted = $derived(
    [...filteredRuns].sort((a: any, b: any) => {
      const dir = state.sortDesc ? -1 : 1
      switch (state.sortField) {
        case 'distance': return dir * ((a.distance ?? 0) - (b.distance ?? 0))
        case 'time': return dir * ((a.moving_time ?? 0) - (b.moving_time ?? 0))
        default: return dir * ((a.start_date ?? '').localeCompare(b.start_date ?? ''))
      }
    })
  )

  function pace(a: any): string {
    if (!a.distance || !a.moving_time || a.distance <= 0) return '—'
    const p = a.moving_time / (a.distance / 1000)
    return `${Math.floor(p / 60)}:${String(Math.round(p % 60)).padStart(2, '0')}`
  }

  function srcBadge(source: string | null): string {
    const m: Record<string, string> = { garmin: 'G', strava: 'S', keep: 'K', igpsport: 'iG', garmin_cn: 'GC', xoss: 'X', xingzhe: 'XZ' }
    return m[source ?? ''] ?? source?.charAt(0).toUpperCase() ?? '?'
  }
</script>

<div class="rp-table-wrap">
  <table class="rp-table">
    <thead>
      <tr>
        <th></th>
        <th class="sortable" class:active={state.sortField === 'distance'} onclick={() => sortBy('distance')}>Dist {state.sortField === 'distance' ? (state.sortDesc ? '↓' : '↑') : ''}</th>
        <th>Elev</th>
        <th>Pace</th>
        <th>BPM</th>
        <th class="sortable" class:active={state.sortField === 'time'} onclick={() => sortBy('time')}>Time {state.sortField === 'time' ? (state.sortDesc ? '↓' : '↑') : ''}</th>
        <th class="sortable" class:active={state.sortField === 'date'} onclick={() => sortBy('date')}>Date {state.sortField === 'date' ? (state.sortDesc ? '↓' : '↑') : ''}</th>
      </tr>
    </thead>
    <tbody>
      {#each sorted as act (act.run_id)}
        <tr
          class="rp-row"
          class:selected={state.selectedActivity?.run_id === act.run_id}
          onclick={() => locate(act.run_id)}
        >
          <td class="badge-cell"><span class="src-badge">{srcBadge(act.source)}</span></td>
          <td>{formatDistance(act.distance)}</td>
          <td>{act.elevation_gain ? `${Math.round(act.elevation_gain)}m` : '—'}</td>
          <td>{pace(act)}</td>
          <td>{act.average_heartrate ? Math.round(act.average_heartrate) : '—'}</td>
          <td>{formatDuration(act.moving_time)}</td>
          <td class="date-cell">{act.start_date?.slice(0, 10) ?? ''}</td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

<style>
  .rp-table-wrap { overflow-x: auto; }
  .rp-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; font-family: 'IBM Plex Mono', monospace; }
  th { text-align: left; padding: 0.5rem; color: var(--color-text-secondary, #888); border-bottom: 1px solid var(--color-border, #333); font-weight: 400; white-space: nowrap; }
  th.sortable { cursor: pointer; }
  th.sortable:hover, th.active { color: var(--color-accent, #e0ed5e); }
  .rp-row { cursor: pointer; transition: background 0.1s; }
  .rp-row:hover { background: var(--color-hover, #262626); }
  .rp-row.selected { color: var(--color-accent, #e0ed5e); }
  td { padding: 0.35rem 0.5rem; border-bottom: 1px solid var(--color-border, #222); }
  .badge-cell { width: 28px; }
  .src-badge { font-size: 0.65rem; padding: 1px 4px; border-radius: 3px; background: var(--color-border, #333); color: var(--color-text-dim, #666); }
  .date-cell { color: var(--color-text-dim, #666); font-size: 0.8rem; }
</style>
