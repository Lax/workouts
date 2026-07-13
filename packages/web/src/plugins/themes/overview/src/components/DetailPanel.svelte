<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import L from 'leaflet'
  import 'leaflet/dist/leaflet.css'
  import { getContext } from 'svelte'
  import { decodePolyline } from '$lib/polyline'
  const { state: store, closeDetail } = getContext('overview-store') as any
  const ctx = getContext('theme') as any
  import { formatDistance, formatDuration } from '@workouts/shared'

  let el: HTMLDivElement
  let miniMap: L.Map | null = null

  $effect(() => {
    if (!store.detailOpen || !store.selectedActivity) return

    requestAnimationFrame(() => {
      if (!el || miniMap) return
      miniMap = L.map(el, {
        zoomControl: false,
        attributionControl: false,
        scrollWheelZoom: false,
      }).setView([30, 110], 4)

      const carto = ctx.theme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
      L.tileLayer(
        `https://{s}.basemaps.cartocdn.com/${carto}/{z}/{x}/{y}{r}.png`,
        { maxZoom: 19 },
      ).addTo(miniMap)

      const encoded = store.selectedActivity.summary_polyline
      if (encoded) {
        const points = decodePolyline(encoded)
        if (points.length > 1) {
          const line = L.polyline(points, {
            color: '#4DD2FF',
            weight: 3,
            opacity: 0.8,
          }).addTo(miniMap)
          miniMap.invalidateSize()
          miniMap.fitBounds(line.getBounds().pad(0.2))
        }
      }
    })
  })

  function handleBgClick(e: MouseEvent) {
    if (e.target === e.currentTarget) closeDetail()
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === 'Escape') closeDetail()
  }

  onMount(() => document.addEventListener('keydown', handleKey))
  onDestroy(() => {
    document.removeEventListener('keydown', handleKey)
    miniMap?.remove()
    miniMap = null
  })

  function fmtPace(act: typeof store.selectedActivity): string {
    if (!act?.distance || !act.moving_time || act.distance <= 0) return '—'
    const pace = act.moving_time / (act.distance / 1000)
    const min = Math.floor(pace / 60)
    const sec = Math.round(pace % 60)
    return `${min}:${sec.toString().padStart(2, '0')} /km`
  }

  function fmtSpeed(act: typeof store.selectedActivity): string {
    if (act?.average_speed === null || act?.average_speed === undefined) return '—'
    return (act.average_speed * 3.6).toFixed(1)
  }
</script>

{#if store.detailOpen && store.selectedActivity}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="overlay" onclick={handleBgClick}>
    <div class="panel" role="dialog">
      <div class="panel-header">
        <h2>{store.selectedActivity.name || 'Untitled'}</h2>
        <button class="close-btn" onclick={closeDetail}>×</button>
      </div>

      <div class="meta">
        {store.selectedActivity.start_date?.slice(0, 10) || ''}
        · {store.selectedActivity.sport_category || 'other'}
      </div>

      <div class="grid">
        <div class="stat">
          <span class="label">Distance</span>
          <span class="value">{formatDistance(store.selectedActivity.distance)}</span>
        </div>
        <div class="stat">
          <span class="label">Pace</span>
          <span class="value">{fmtPace(store.selectedActivity)}</span>
        </div>
        <div class="stat">
          <span class="label">Moving Time</span>
          <span class="value">{formatDuration(store.selectedActivity.moving_time)}</span>
        </div>
        <div class="stat">
          <span class="label">Speed</span>
          <span class="value">{fmtSpeed(store.selectedActivity)} km/h</span>
        </div>
        <div class="stat">
          <span class="label">Avg HR</span>
          <span class="value">{store.selectedActivity.average_heartrate ? `${Math.round(store.selectedActivity.average_heartrate)} bpm` : '—'}</span>
        </div>
        <div class="stat">
          <span class="label">Elevation</span>
          <span class="value">{store.selectedActivity.elevation_gain ? `${Math.round(store.selectedActivity.elevation_gain)} m` : '—'}</span>
        </div>
        {#if store.selectedActivity.average_cadence}
          <div class="stat">
            <span class="label">Cadence</span>
            <span class="value">{Math.round(store.selectedActivity.average_cadence)} rpm</span>
          </div>
        {/if}
        {#if store.selectedActivity.average_power}
          <div class="stat">
            <span class="label">Avg Power</span>
            <span class="value">{Math.round(store.selectedActivity.average_power)} W</span>
          </div>
        {/if}
        {#if store.selectedActivity.calories}
          <div class="stat">
            <span class="label">Calories</span>
            <span class="value">{store.selectedActivity.calories} kcal</span>
          </div>
        {/if}
      </div>

      <div bind:this={el} class="mini-map"></div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 3;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }

  .panel {
    background: var(--color-surface, #16213e);
    border-radius: 12px 12px 0 0;
    width: 100%;
    max-width: 600px;
    max-height: 80vh;
    overflow-y: auto;
    padding: 1rem;
    animation: slideUp 0.2s ease-out;
  }

  @keyframes slideUp {
    from { transform: translateY(100%); }
    to { transform: translateY(0); }
  }

  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
  }

  h2 {
    font-size: 1.1rem;
    color: var(--color-text, #e0e0e0);
    margin: 0;
  }

  .close-btn {
    background: none;
    border: none;
    color: var(--color-text, #e0e0e0);
    font-size: 1.5rem;
    cursor: pointer;
    padding: 0;
    line-height: 1;
  }

  .meta {
    font-size: 0.8rem;
    color: var(--color-text-secondary, #888);
    margin-bottom: 1rem;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.75rem;
    margin-bottom: 1rem;
  }

  .stat {
    text-align: center;
  }

  .label {
    display: block;
    font-size: 0.7rem;
    color: var(--color-text-dim, #666);
  }

  .value {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-text, #e0e0e0);
  }

  .mini-map {
    height: 200px;
    border-radius: 8px;
    overflow: hidden;
  }

  @media (max-width: 640px) {
    .grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }
</style>
