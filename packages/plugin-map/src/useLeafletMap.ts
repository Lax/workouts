import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useCallback, useEffect, useRef } from 'react'

export interface LeafletMapOptions {
  colorScheme: 'light' | 'dark'
  tileProvider?: 'carto' | 'mapbox'
  mapboxToken?: string
  mapboxStyle?: string
}

export interface MapInstance {
  current: L.Map | null
}

export function useLeafletMap(elRef: React.RefObject<HTMLDivElement | null>, options: LeafletMapOptions): MapInstance {
  const mapRef = useRef<L.Map | null>(null)

  const tileUrl = useCallback(() => {
    const scheme = options.colorScheme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
    if (options.tileProvider === 'mapbox' && options.mapboxToken) {
      const style = options.mapboxStyle || (options.colorScheme === 'dark' ? 'dark-v11' : 'light-v11')
      return `https://api.mapbox.com/styles/v1/mapbox/${style}/tiles/{z}/{x}/{y}@2x?access_token=${options.mapboxToken}`
    }
    return `https://{s}.basemaps.cartocdn.com/${scheme}/{z}/{x}/{y}{r}.png`
  }, [options.colorScheme, options.tileProvider, options.mapboxToken, options.mapboxStyle])

  // biome-ignore lint/correctness/useExhaustiveDependencies: one-time init
  useEffect(() => {
    if (mapRef.current || !elRef.current) return
    const m = L.map(elRef.current, { zoomControl: false, attributionControl: false }).setView([30, 110], 4)
    L.control.zoom({ position: 'topright' }).addTo(m)
    mapRef.current = m
    return () => {
      m.remove()
      mapRef.current = null
    }
  }, [])

  useEffect(() => {
    const m = mapRef.current
    if (!m) return
    m.eachLayer((layer) => {
      if (layer instanceof L.TileLayer) m.removeLayer(layer)
    })
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(m)
  }, [tileUrl])

  return mapRef
}
