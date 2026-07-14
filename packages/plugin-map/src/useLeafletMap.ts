import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useCallback, useEffect, useRef } from 'react'
import { type TileConfig, resolveTileUrl, resolveLabeledTileUrl } from './tiles'

export interface LeafletMapOptions {
  colorScheme: 'light' | 'dark'
  tileConfig?: TileConfig
  showLabels?: boolean
  zoomControl?: boolean
  attributionControl?: boolean
}

export interface MapInstance {
  current: L.Map | null
}

export function useLeafletMap(elRef: React.RefObject<HTMLDivElement | null>, options: LeafletMapOptions): MapInstance {
  const mapRef = useRef<L.Map | null>(null)
  const tileLayerRef = useRef<L.TileLayer | null>(null)
  const prevTileKeyRef = useRef<string>('')

  const tileUrl = useCallback(() => {
    const tc = options.tileConfig ?? { vendor: 'carto' }
    return options.showLabels ? resolveLabeledTileUrl(tc, options.colorScheme) : resolveTileUrl(tc, options.colorScheme)
  }, [options.colorScheme, options.tileConfig, options.showLabels])

  // biome-ignore lint/correctness/useExhaustiveDependencies: one-time init
  useEffect(() => {
    if (mapRef.current || !elRef.current) return
    const zoomCtrl = options.zoomControl !== false
    const attrCtrl = options.attributionControl !== false
    const m = L.map(elRef.current, { zoomControl: zoomCtrl, attributionControl: attrCtrl }).setView([30, 110], 4)
    if (zoomCtrl) L.control.zoom({ position: 'topright' }).addTo(m)
    mapRef.current = m
    return () => {
      m.remove()
      mapRef.current = null
    }
  }, [])

  useEffect(() => {
    const m = mapRef.current
    if (!m) return
    const url = tileUrl()
    const key = `${options.colorScheme}|${url}|${String(!!options.showLabels)}`
    if (prevTileKeyRef.current === key) return
    prevTileKeyRef.current = key
    if (tileLayerRef.current) {
      m.removeLayer(tileLayerRef.current)
    }
    if (url) {
      const layer = L.tileLayer(url, { maxZoom: 19, attribution: '' })
      layer.addTo(m)
      tileLayerRef.current = layer
    }
  }, [tileUrl, options.colorScheme, options.showLabels])

  return mapRef
}
