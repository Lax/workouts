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
  animate?: boolean
  selectedActivityId?: string | null
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

interface AnimState {
  ghost: L.Polyline | null
  sweep: L.Polyline | null
  dot: L.CircleMarker | null
  tail: L.Polyline[]
  fid: number | null
  runId: string | null
}

function clearAnimState(state: AnimState, mapInst: L.Map): void {
  if (state.fid !== null) cancelAnimationFrame(state.fid)
  if (state.ghost) {
    mapInst.removeLayer(state.ghost)
    state.ghost = null
  }
  if (state.sweep) {
    mapInst.removeLayer(state.sweep)
    state.sweep = null
  }
  if (state.dot) {
    mapInst.removeLayer(state.dot)
    state.dot = null
  }
  // eslint-disable-next-line prefer-const
  for (const tl of state.tail) mapInst.removeLayer(tl)
  state.tail = []
  state.fid = null
  state.runId = null
}

export function useMapPolylines(mapRef: MapInstance, activities: Activity[], options: PolylineOptions): void {
  const polylinesRef = useRef<Map<string, L.Polyline>>(new Map())
  const markersRef = useRef<L.CircleMarker[]>([])
  const fittedRef = useRef<string>('')
  const animFramesRef = useRef<Map<string, number>>(new Map())
  const animStateRef = useRef<AnimState | null>(null)

  const {
    colorMode,
    hoveredActivityId = null,
    maxLines = 500,
    fitOnChange = true,
    dashLines = false,
    showMarkers = false,
    animate = false,
    selectedActivityId = null,
    onActivityClick,
    onActivityHover,
  } = options

  useEffect(() => {
    const mapInst = mapRef.current
    if (!mapInst) return

    // Cleanup existing layers and frame refs
    for (const [, line] of polylinesRef.current) mapInst.removeLayer(line)
    polylinesRef.current.clear()
    for (const m of markersRef.current) mapInst.removeLayer(m)
    markersRef.current = []
    for (const [, fid] of animFramesRef.current) cancelAnimationFrame(fid)
    animFramesRef.current.clear()

    // Cleanup existing animation state
    if (animStateRef.current) {
      clearAnimState(animStateRef.current, mapInst)
      animStateRef.current = null
    }

    const allPoints: [number, number][] = []

    const hasSelection = selectedActivityId !== null && selectedActivityId !== undefined
    const shouldAnimateSimple = !hasSelection && animate && activities.length === 1

    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)')?.matches === true

    for (let i = 0; i < Math.min(activities.length, maxLines); i++) {
      const a = activities[i]
      const encoded = a.summary_polyline
      if (!encoded) continue

      const points = decodePolyline(encoded)
      if (points.length < 2) continue
      allPoints.push(...points)

      const baseColor = activityColor({ average_speed: a.average_speed, type: a.sport_category }, colorMode)

      if (hasSelection && a.run_id === selectedActivityId) {
        // Selected activity: ghost + sweep + dot + tail animation
        const color = baseColor

        if (prefersReducedMotion || points.length < 3) {
          // Reduced motion or too few points: render solid highlight directly
          const line = L.polyline(points, {
            color,
            weight: 6,
            opacity: 0.8,
            smoothFactor: 1,
            interactive: true,
            dashArray: dashLines ? [2, 2] : undefined,
          }).addTo(mapInst)

          line.on('click', () => onActivityClick?.(a))
          line.on('mouseover', () => onActivityHover?.(a.run_id))
          line.on('mouseout', () => onActivityHover?.(null))

          line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
            sticky: true,
          })

          polylinesRef.current.set(a.run_id, line)
        } else {
          // 1. Ghost: full path, low opacity
          const ghost = L.polyline(points, {
            color,
            weight: 3,
            opacity: 0.1,
            smoothFactor: 1,
            interactive: false,
          }).addTo(mapInst)

          // 2. Sweep: starts empty (just first point), interactive line
          const sweep = L.polyline([points[0]], {
            color,
            weight: 6,
            opacity: 0.9,
            smoothFactor: 1,
            interactive: true,
            dashArray: dashLines ? [2, 2] : undefined,
          }).addTo(mapInst)

          sweep.on('click', () => onActivityClick?.(a))
          sweep.on('mouseover', () => onActivityHover?.(a.run_id))
          sweep.on('mouseout', () => onActivityHover?.(null))

          sweep.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
            sticky: true,
          })

          polylinesRef.current.set(a.run_id, sweep)

          // 3. Dot: circle marker at start
          const dot = L.circleMarker(points[0], {
            radius: 5,
            color,
            fillColor: '#fff',
            fillOpacity: 1,
            weight: 2,
            interactive: false,
          }).addTo(mapInst)

          // Setup animation state
          const state: AnimState = {
            ghost,
            sweep,
            dot,
            tail: [],
            fid: null,
            runId: a.run_id,
          }
          animStateRef.current = state

          // 4. Animation loop
          const duration = Math.min(3000, Math.max(800, points.length * 15))
          const startTime = performance.now()

          function step(timestamp: number): void {
            const s = animStateRef.current
            if (!s || s.runId !== a.run_id) return

            const t = Math.min((timestamp - startTime) / duration, 1)
            // Ease function: cubic-bezier(0.16, 1, 0.3, 1) ≈ ease-in-out quad
            const eased = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2
            const traversed = Math.max(1, Math.floor(points.length * eased))

            // Update sweep points
            s.sweep?.setLatLngs(points.slice(0, traversed))

            // Update dot position
            s.dot?.setLatLng(points[Math.min(traversed, points.length - 1)])

            // Update tail: last 25% of traversed, split into 4 segments
            const m = mapInst!
            for (const tl of s.tail) m.removeLayer(tl)
            s.tail = []

            if (traversed >= 12) {
              const trailLen = Math.floor(traversed * 0.25)
              const trailStart = traversed - trailLen
              const segments = [
                { start: 0, end: 0.4, op: 0.7, w: 5 },
                { start: 0.4, end: 0.7, op: 0.5, w: 4 },
                { start: 0.7, end: 0.9, op: 0.3, w: 3 },
                { start: 0.9, end: 1.0, op: 0.15, w: 2 },
              ]
              for (const seg of segments) {
                const segStartIdx = trailStart + Math.floor(trailLen * seg.start)
                const segEndIdx = trailStart + Math.floor(trailLen * seg.end)
                if (segStartIdx < segEndIdx) {
                  const tline = L.polyline(points.slice(segStartIdx, segEndIdx), {
                    color,
                    weight: seg.w,
                    opacity: seg.op,
                    smoothFactor: 1,
                    interactive: false,
                  }).addTo(m)
                  s.tail.push(tline)
                }
              }
            }

            if (t >= 1) {
              // Animation complete: fade out ghost, pulse dot, remove tail
              let ghostFadeFrames = 3
              function fadeGhost(): void {
                const fs = animStateRef.current
                if (!fs || fs.runId !== a.run_id) return
                if (ghostFadeFrames <= 0) {
                  if (fs.ghost) {
                    m.removeLayer(fs.ghost)
                    fs.ghost = null
                  }
                  // Pulse dot
                  if (fs.dot) {
                    fs.dot.setStyle({ radius: 8 })
                    setTimeout(() => {
                      const ds = animStateRef.current
                      if (!ds || ds.runId !== a.run_id) return
                      if (ds.dot) {
                        ds.dot.setStyle({ radius: 5 })
                        setTimeout(() => {
                          const dds = animStateRef.current
                          if (!dds || dds.runId !== a.run_id) return
                          if (dds.dot) {
                            m.removeLayer(dds.dot)
                            dds.dot = null
                          }
                        }, 200)
                      }
                    }, 200)
                  }
                  // Remove tail
                  for (const tl of fs.tail) m.removeLayer(tl)
                  fs.tail = []
                  // Sweep becomes highlight
                  if (fs.sweep) {
                    fs.sweep.setStyle({ opacity: 0.8, weight: 6 })
                  }
                  fs.fid = null
                  return
                }
                ghostFadeFrames--
                if (fs.ghost) fs.ghost.setStyle({ opacity: ghostFadeFrames * 0.033 })
                fs.fid = requestAnimationFrame(fadeGhost)
              }
              state.fid = requestAnimationFrame(fadeGhost)
              return
            }

            s.fid = requestAnimationFrame(step)
          }

          state.fid = requestAnimationFrame(step)
        }

        if (showMarkers) {
          const startC = L.circleMarker(points[0], {
            radius: 4,
            color: '#22c55e',
            fillColor: '#22c55e',
            fillOpacity: 1,
            weight: 2,
          }).addTo(mapInst)
          const endC = L.circleMarker(points[points.length - 1], {
            radius: 4,
            color: '#ef4444',
            fillColor: '#ef4444',
            fillOpacity: 1,
            weight: 2,
          }).addTo(mapInst)
          markersRef.current.push(startC, endC)
        }
      } else if (hasSelection) {
        // Other activities (when one is selected): dimmed, non-interactive
        const line = L.polyline(points, {
          color: baseColor,
          weight: 3,
          opacity: 0.15,
          smoothFactor: 1,
          interactive: false,
        }).addTo(mapInst)

        polylinesRef.current.set(a.run_id, line)
      } else if (shouldAnimateSimple && points.length > 2) {
        // Existing animation: single activity, draw effect
        const lineStyle: L.PolylineOptions = {
          color: baseColor,
          weight: 5,
          opacity: 0.4,
          smoothFactor: 1,
          interactive: true,
          dashArray: dashLines ? [2, 2] : undefined,
        }

        const initial = [points[0], points[1]]
        const line = L.polyline(initial, lineStyle).addTo(mapInst)

        line.on('click', () => onActivityClick?.(a))
        line.on('mouseover', () => onActivityHover?.(a.run_id))
        line.on('mouseout', () => onActivityHover?.(null))

        line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
          sticky: true,
        })

        polylinesRef.current.set(a.run_id, line)

        const duration = Math.min(4000, Math.max(1000, points.length * 25))
        const startTime = performance.now()

        function stepSimple(timestamp: number): void {
          const elapsed = timestamp - startTime
          const progress = Math.min(elapsed / duration, 1)
          const count = Math.max(2, Math.floor(points.length * progress))
          line.setLatLngs(points.slice(0, count))
          if (progress < 1) {
            const fid = requestAnimationFrame(stepSimple)
            animFramesRef.current.set(a.run_id, fid)
          } else {
            animFramesRef.current.delete(a.run_id)
          }
        }

        const fid = requestAnimationFrame(stepSimple)
        animFramesRef.current.set(a.run_id, fid)
      } else {
        // Static rendering
        const lineStyle: L.PolylineOptions = {
          color: baseColor,
          weight: 5,
          opacity: 0.4,
          smoothFactor: 1,
          interactive: true,
          dashArray: dashLines ? [2, 2] : undefined,
        }

        const line = L.polyline(points, lineStyle).addTo(mapInst)

        line.on('click', () => onActivityClick?.(a))
        line.on('mouseover', () => onActivityHover?.(a.run_id))
        line.on('mouseout', () => onActivityHover?.(null))

        line.bindTooltip(`${a.name || 'Untitled'} — ${((a.distance ?? 0) / 1000).toFixed(2)} km`, {
          sticky: true,
        })

        polylinesRef.current.set(a.run_id, line)
      }

      if (showMarkers && !(hasSelection && a.run_id === selectedActivityId)) {
        // Markers already added above for selected activity; add for others
        const startC = L.circleMarker(points[0], {
          radius: 4,
          color: '#22c55e',
          fillColor: '#22c55e',
          fillOpacity: 1,
          weight: 2,
        }).addTo(mapInst)
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    mapRef.current,
    activities,
    colorMode,
    maxLines,
    dashLines,
    showMarkers,
    animate,
    selectedActivityId,
    onActivityClick,
    onActivityHover,
    fitOnChange,
  ])

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
          line.setStyle({
            weight: 5,
            color: activityColor({ average_speed: a.average_speed, type: a.sport_category }, colorMode),
            opacity: 0.4,
          })
        }
      }
    }
  }, [mapRef.current, hoveredActivityId, activities, colorMode])
}
