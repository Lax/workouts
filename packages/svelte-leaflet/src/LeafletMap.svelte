<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import L from 'leaflet'
  import 'leaflet/dist/leaflet.css'

  let { center = [39.9, 116.4], zoom = 12, tileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', polylines = [] } = $props<{
    center?: [number, number]
    zoom?: number
    tileUrl?: string
    polylines?: { points: [number, number][]; color?: string }[]
  }>()

  let el: HTMLDivElement
  let map: L.Map | null = null
  let polylineLayers: L.Polyline[] = []

  onMount(() => {
    map = L.map(el).setView(center, zoom)
    L.tileLayer(tileUrl, { maxZoom: 19 }).addTo(map)

    for (const pl of polylines) {
      const layer = L.polyline(pl.points, {
        color: pl.color ?? '#4DD2FF',
        weight: 3,
        opacity: 0.8,
      }).addTo(map)
      polylineLayers.push(layer)
    }

    if (polylines.length > 0) map.fitBounds(polylineLayers[0].getBounds().pad(0.1))
  })

  $effect(() => {
    if (!map) return
    tileUrl // track dependency
    map.eachLayer((layer) => {
      if (layer instanceof L.TileLayer) {
        map!.removeLayer(layer)
      }
    })
    L.tileLayer(tileUrl, { maxZoom: 19 }).addTo(map)
  })

  $effect(() => {
    if (!map) return
    // clear old polylines
    for (const layer of polylineLayers) map.removeLayer(layer)
    polylineLayers = []

    for (const pl of polylines) {
      const layer = L.polyline(pl.points, {
        color: pl.color ?? '#4DD2FF',
        weight: 3,
        opacity: 0.8,
      }).addTo(map)
      polylineLayers.push(layer)
    }
  })

  onDestroy(() => {
    map?.remove()
  })
</script>

<div bind:this={el} style="width:100%;height:400px"></div>
