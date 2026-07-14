import type { Activity } from '@workouts/shared'
import { activityColor } from '@workouts/shared'
import L from 'leaflet'
import { useEffect, useRef } from 'react'
import { decodePolyline } from './polyline'
import type { MapInstance } from './useLeafletMap'

export interface PolylineOptions {
  colorMode: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  fitOnChange?: boolean
  dashLines?: boolean
  showMarkers?: boolean
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function useMapPolylines(mapRef: MapInstance, activities: Activity[], options: PolylineOptions): void {
  const polylinesRef = useRef<Map<string, L.Polyline>>(new Map())
  const markersRef = useRef<L.CircleMarker[]>([])
  const fittedRef = useRef<string>('')

  const {
    colorMode,
    hoveredActivityId = null,
    maxLines = 500,
    fitOnChange = true,
    dashLines = false,
    showMarkers = false,
    onActivityClick,
    onActivityHover,
  } = options

  useEffect(() => {
    const mapInst = mapRef.current
    if (!mapInst) return

    for (const [, line] of polylinesRef.current) mapInst.removeLayer(line)
    polylinesRef.current.clear()
    for (const m of markersRef.current) mapInst.removeLayer(m)
    markersRef.current = []

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
        dashArray: dashLines ? '10, 10' : undefined,
      }).addTo(mapInst)

      line.on('click', () => onActivityClick?.(a))
      line.on('mouseover', () => onActivityHover?.(a.run_id))
      line.on('mouseout', () => onActivityHover?.(null))

      line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
        sticky: true,
      })

      polylinesRef.current.set(a.run_id, line)

      if (showMarkers) {
        const startC = L.circleMarker(points[0], { radius: 4, color: '#22c55e', fillColor: '#22c55e', fillOpacity: 1, weight: 2 }).addTo(
          mapInst,
        )
        const endC = L.circleMarker(points[points.length - 1], {
          radius: 4,
          color: '#ef4444',
          fillColor: '#ef4444',
          fillOpacity: 1,
          weight: 2,
        }).addTo(mapInst)
        markersRef.current.push(startC, endC)
      }
    }

    if (fitOnChange && allPoints.length > 0) {
      const actKey = activities
        .map((a) => a.run_id)
        .sort()
        .join('|')
      if (fittedRef.current !== actKey) {
        const bounds = L.latLngBounds(allPoints.map((p) => L.latLng(p[0], p[1])))
        if (bounds.isValid()) {
          mapInst.fitBounds(bounds.pad(0.05))
          fittedRef.current = actKey
        }
      }
    }
  }, [mapRef.current, activities, colorMode, maxLines, dashLines, showMarkers, onActivityClick, onActivityHover, fitOnChange])

  useEffect(() => {
    const mapInst = mapRef.current
    if (!mapInst) return

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
  }, [mapRef.current, hoveredActivityId, activities, colorMode])
}
