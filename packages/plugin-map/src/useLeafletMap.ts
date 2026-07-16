import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { useCallback, useEffect, useRef } from 'react'
import { resolveLabeledTileUrl, resolveTileUrl, type TileConfig } from './tiles'

export type ZoomPosition = 'topleft' | 'topright' | 'bottomleft' | 'bottomright'

export interface LeafletMapOptions {
  colorScheme: 'light' | 'dark'
  tileConfig?: TileConfig
  lightsOn?: boolean
  showLabels?: boolean
  zoomControl?: boolean
  zoomPosition?: ZoomPosition
  attributionControl?: boolean
  attributionPosition?: ZoomPosition
  initialScrollDisabled?: boolean
}

export interface MapInstance {
  current: L.Map | null
}

export function useLeafletMap(elRef: React.RefObject<HTMLDivElement | null>, options: LeafletMapOptions): MapInstance {
  const mapRef = useRef<L.Map | null>(null)
  const tileLayerRef = useRef<L.TileLayer | null>(null)
  const prevTileKeyRef = useRef<string>('')

  const lightsOn = options.lightsOn ?? true
  const showLabels = options.showLabels ?? false

  const tileUrl = useCallback(() => {
    if (!lightsOn) return ''
    const tc = options.tileConfig ?? { vendor: 'carto' }
    if (showLabels) return resolveLabeledTileUrl(tc, options.colorScheme)
    return resolveTileUrl(tc, options.colorScheme)
  }, [options.colorScheme, options.tileConfig, lightsOn, showLabels])

  // biome-ignore lint/correctness/useExhaustiveDependencies: one-time init
  useEffect(() => {
    if (mapRef.current || !elRef.current) return
    const zoomCtrl = options.zoomControl !== false
    const attrCtrl = options.attributionControl !== false
    const m = L.map(elRef.current, {
      zoomControl: false,
      attributionControl: attrCtrl,
      scrollWheelZoom: !options.initialScrollDisabled,
    }).setView([30, 110], 4)
    if (zoomCtrl) L.control.zoom({ position: options.zoomPosition ?? 'topright' }).addTo(m)
    if (options.attributionPosition && m.attributionControl) {
      m.attributionControl.setPosition(options.attributionPosition)
    }
    mapRef.current = m

    if (options.initialScrollDisabled) {
      const el = elRef.current
      const enable = () => {
        m.scrollWheelZoom.enable()
        el.removeEventListener('pointerdown', enable)
        el.removeEventListener('focus', enable)
      }
      el.addEventListener('pointerdown', enable)
      el.addEventListener('focus', enable)
      return () => {
        el.removeEventListener('pointerdown', enable)
        el.removeEventListener('focus', enable)
        m.remove()
        mapRef.current = null
      }
    }

    return () => {
      m.remove()
      mapRef.current = null
    }
  }, [])

  useEffect(() => {
    const m = mapRef.current
    if (!m) return
    const url = tileUrl()
    const key = `${options.colorScheme}|${url}|${String(lightsOn)}|${String(showLabels)}`
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
  }, [tileUrl, options.colorScheme, lightsOn, showLabels])

  return mapRef
}
