import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useCallback, useEffect, useRef } from 'react'
import { carto, type TileUrlBuilder } from './tiles'

export interface LeafletMapOptions {
  colorScheme: 'light' | 'dark'
  tileUrl?: TileUrlBuilder
}

export interface MapInstance {
  current: L.Map | null
}

export function useLeafletMap(elRef: React.RefObject<HTMLDivElement | null>, options: LeafletMapOptions): MapInstance {
  const mapRef = useRef<L.Map | null>(null)

  const tileUrl = useCallback(() => {
    const builder = options.tileUrl ?? carto()
    return builder(options.colorScheme)
  }, [options.colorScheme, options.tileUrl])

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
