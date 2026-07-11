<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import L from 'leaflet'
  import 'leaflet/dist/leaflet.css'
  import { decodePolyline } from './polyline'
  import { activityColor } from './colorMode'
  import { app, openDetail } from './state.svelte'

  let el: HTMLDivElement
  let map: L.Map | null = null
  let polylines: Map<string, L.Polyline> = new Map()

  function tileUrl(): string {
    const carto = app.theme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
    return `https://{s}.basemaps.cartocdn.com/${carto}/{z}/{x}/{y}{r}.png`
  }

  function updatePolylines() {
    if (!map) return

    for (const [, line] of polylines) map.removeLayer(line)
    polylines.clear()

    const acts = app.filteredActivities
    const currentYear = new Date().getFullYear()
    const maxLines = 500

    const allPoints: [number, number][] = []

    for (let i = 0; i < Math.min(acts.length, maxLines); i++) {
      const a = acts[i]
      const encoded = a.summary_polyline || a.polyline
      if (!encoded) continue

      const points = decodePolyline(encoded)
      if (points.length < 2) continue

      allPoints.push(...points)

      const yearsAgo = currentYear - (a.start_date ? new Date(a.start_date).getFullYear() : currentYear)
      const opacity = Math.max(0.35, 1.0 - yearsAgo * 0.06)
      const color = activityColor(
        { average_speed: a.average_speed, type: a.sport_category },
        app.colorMode,
      )

      const line = L.polyline(points, {
        color,
        weight: 3,
        opacity,
        smoothFactor: 1,
        interactive: true,
      }).addTo(map)

      line.on('click', () => openDetail(a))
      line.on('mouseover', () => { app.mapHoveredId = a.run_id })
      line.on('mouseout', () => { app.mapHoveredId = null })

      line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
        sticky: true,
      })

      polylines.set(a.run_id, line)
    }

    if (allPoints.length > 0) {
      const lats = allPoints.map((p) => p[0]).sort((a, b) => a - b)
      const lngs = allPoints.map((p) => p[1]).sort((a, b) => a - b)

      const midLat = lats[Math.floor(lats.length / 2)]
      const midLng = lngs[Math.floor(lngs.length / 2)]
      const q1Lat = lats[Math.floor(lats.length * 0.25)]
      const q3Lat = lats[Math.floor(lats.length * 0.75)]
      const q1Lng = lngs[Math.floor(lngs.length * 0.25)]
      const q3Lng = lngs[Math.floor(lngs.length * 0.75)]

      const iqrLat = q3Lat - q1Lat
      const iqrLng = q3Lng - q1Lng

      const filtered = allPoints.filter(
        (p) =>
          Math.abs(p[0] - midLat) < iqrLat * 2 + 5 &&
          Math.abs(p[1] - midLng) < iqrLng * 2 + 5,
      )

      if (filtered.length > 0) {
        const bounds = L.latLngBounds(filtered.map((p) => L.latLng(p[0], p[1])))
        map.fitBounds(bounds.pad(0.1))
      }
    }
  }

  function updateTileLayer() {
    if (!map) return
    map.eachLayer((layer) => {
      if (layer instanceof L.TileLayer) map!.removeLayer(layer)
    })
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)
  }

  function updateHover() {
    for (const [id, line] of polylines) {
      if (app.mapHoveredId === id) {
        line.setStyle({ weight: 4, color: 'var(--color-accent, #4DD2FF)', opacity: 1 })
        line.bringToFront()
      } else {
        const a = app.filteredActivities.find((a) => a.run_id === id)
        if (a) {
          line.setStyle({
            weight: 3,
            color: activityColor(
              { average_speed: a.average_speed, type: a.sport_category },
              app.colorMode,
            ),
            opacity: Math.max(
              0.35,
              1.0 -
                (new Date().getFullYear() -
                  (a.start_date ? new Date(a.start_date).getFullYear() : new Date().getFullYear())) *
                  0.06,
            ),
          })
        }
      }
    }
  }

  onMount(() => {
    map = L.map(el, {
      zoomControl: false,
      attributionControl: false,
    }).setView([30, 110], 4)

    L.control.zoom({ position: 'topright' }).addTo(map)
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)

    updatePolylines()
  })

  $effect(() => {
    if (!map) return
    app.theme
    updateTileLayer()
  })

  $effect(() => {
    if (!map) return
    app.colorMode
    app.filteredActivities
    updatePolylines()
  })

  $effect(() => {
    updateHover()
  })

  onDestroy(() => {
    map?.remove()
  })
</script>

<div bind:this={el} class="map-container"></div>

<style>
  .map-container {
    position: fixed;
    inset: 0;
    z-index: 0;
  }
</style>
