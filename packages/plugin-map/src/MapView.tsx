import L from 'leaflet'
import { useCallback, useEffect, useRef } from 'react'
import 'leaflet/dist/leaflet.css'
import type { Activity } from '@workouts/shared'
import { activityColor } from '@workouts/shared'
import { decodePolyline } from './polyline'

export interface MapViewProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'speed' | 'type'
  hoveredActivityId?: string | null
  maxLines?: number
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function MapView({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  onActivityClick,
  onActivityHover,
}: MapViewProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useRef<L.Map | null>(null)
  const polylinesRef = useRef<Map<string, L.Polyline>>(new Map())
  const fittedRef = useRef<number>(0)

  const tileUrl = useCallback(
    () => `https://{s}.basemaps.cartocdn.com/${colorScheme === 'dark' ? 'dark_nolabels' : 'light_nolabels'}/{z}/{x}/{y}{r}.png`,
    [colorScheme],
  )

  useEffect(() => {
    const el = elRef.current
    if (!el || mapRef.current) return

    const map = L.map(el, { zoomControl: false, attributionControl: false }).setView([30, 110], 4)
    L.control.zoom({ position: 'topright' }).addTo(map)
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)
    mapRef.current = map

    return () => {
      map.remove()
      mapRef.current = null
    }
  }, [tileUrl])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    map.eachLayer((layer) => {
      if (layer instanceof L.TileLayer) map.removeLayer(layer)
    })
    L.tileLayer(tileUrl(), { maxZoom: 19, attribution: '' }).addTo(map)
  }, [tileUrl])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    for (const [, line] of polylinesRef.current) map.removeLayer(line)
    polylinesRef.current.clear()

    const currentYear = new Date().getFullYear()
    const allPoints: [number, number][] = []

    for (let i = 0; i < Math.min(activities.length, maxLines); i++) {
      const a = activities[i]
      const encoded = a.summary_polyline
      if (!encoded) continue

      const points = decodePolyline(encoded)
      if (points.length < 2) continue
      allPoints.push(...points)

      const yearsAgo = currentYear - (a.start_date ? new Date(a.start_date).getFullYear() : currentYear)
      const opacity = Math.max(0.35, 1.0 - yearsAgo * 0.06)

      const line = L.polyline(points, {
        color: activityColor({ average_speed: a.average_speed, type: a.sport_category }, colorMode),
        weight: 5,
        opacity,
        smoothFactor: 1,
        interactive: true,
      }).addTo(map)

      line.on('click', () => onActivityClick?.(a))
      line.on('mouseover', () => onActivityHover?.(a.run_id))
      line.on('mouseout', () => onActivityHover?.(null))

      line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
        sticky: true,
      })

      polylinesRef.current.set(a.run_id, line)
    }

    if (allPoints.length > 0) {
      // Fit bounds only on first load or when activity count changes
      const actKey = activities.length
      if (!fittedRef.current || fittedRef.current !== actKey) {
        const bounds = L.latLngBounds(allPoints.map((p) => L.latLng(p[0], p[1])))
        if (bounds.isValid()) {
          map.fitBounds(bounds.pad(0.05))
          fittedRef.current = actKey as any
        }
      }
    }
  }, [activities, colorMode, maxLines, onActivityClick, onActivityHover])

  useEffect(() => {
    const map = mapRef.current
    if (!map) return

    for (const [id, line] of polylinesRef.current) {
      if (hoveredActivityId === id) {
        line.setStyle({ weight: 7, color: 'var(--color-accent, #4DD2FF)', opacity: 1 })
        line.bringToFront()
      } else {
        const a = activities.find((act) => act.run_id === id)
        if (a) {
          const yearsAgo = new Date().getFullYear() - (a.start_date ? new Date(a.start_date).getFullYear() : new Date().getFullYear())
          line.setStyle({
            weight: 5,
            color: activityColor({ average_speed: a.average_speed, type: a.sport_category }, colorMode),
            opacity: Math.max(0.35, 1.0 - yearsAgo * 0.06),
          })
        }
      }
    }
  }, [hoveredActivityId, activities, colorMode])

  return <div ref={elRef} style={{ position: 'fixed', inset: 0, zIndex: 0, background: 'var(--color-bg)' }} />
}
