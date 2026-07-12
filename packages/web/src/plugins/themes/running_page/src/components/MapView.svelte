<script lang="ts">
  import { onMount, onDestroy, getContext } from 'svelte'
  import L from 'leaflet'
  import 'leaflet/dist/leaflet.css'
  import { decodePolyline } from '../../../../../lib/polyline'
  import { activityColor } from '../colorMode'

  const api = getContext('running-store') as any
  const ctx = getContext('theme') as any

  let el: HTMLDivElement
  let map: L.Map | null = null
  let polylines: Map<string, L.Polyline> = new Map()

  function tileUrl(): string {
    const carto = ctx.theme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
    return `https://{s}.basemaps.cartocdn.com/${carto}/{z}/{x}/{y}{r}.png`
  }

  function updatePolylines() {
    if (!map) return
    for (const [, line] of polylines) map.removeLayer(line)
    polylines.clear()

    const acts = api.filteredRuns
    const allPoints: [number, number][] = []

    for (const a of acts) {
      const encoded = a.summary_polyline || a.polyline
      if (!encoded) continue
      const points = decodePolyline(encoded)
      if (points.length < 2) continue
      allPoints.push(...points)
      const color = activityColor(a.sport_category || a.type)
      const line = L.polyline(points, {
        color,
        weight: 4,
        opacity: 0.5,
        smoothFactor: 1,
      }).addTo(map)
      polylines.set(a.run_id, line)
    }

    if (allPoints.length > 0) {
      const bounds = L.latLngBounds(allPoints.map((p: [number, number]) => L.latLng(p[0], p[1])))
      if (bounds.isValid()) map.fitBounds(bounds.pad(0.05))
    }
  }

  onMount(() => {
    map = L.map(el, { zoomControl: false, attributionControl: false }).setView([30, 110], 4)
    L.control.zoom({ position: 'topright' }).addTo(map)
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)
  })

  $effect(() => {
    if (!map) return
    ctx.theme
    map.eachLayer((layer) => {
      if (layer instanceof L.TileLayer) map!.removeLayer(layer)
    })
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)
  })

  $effect(() => {
    if (!map) return
    api.filteredRuns
    updatePolylines()
  })

  onDestroy(() => { map?.remove() })
</script>

<div bind:this={el} class="rp-map"></div>

<style>
  .rp-map { height: 500px; border-radius: 8px; overflow: hidden; margin-bottom: 1rem; }
  :global(.leaflet-container) { background: var(--color-bg, #171717); }
</style>
