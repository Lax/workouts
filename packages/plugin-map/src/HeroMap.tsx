import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import { useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export interface HeroMapProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function HeroMap({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  onActivityClick,
  onActivityHover,
}: HeroMapProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useLeafletMap(elRef, { colorScheme })
  const opts: PolylineOptions = { colorMode, hoveredActivityId, maxLines, fitOnChange: true, onActivityClick, onActivityHover }
  useMapPolylines(mapRef, activities, opts)
  return <div ref={elRef} style={{ position: 'fixed', inset: 0, zIndex: 0, background: 'var(--color-bg)' }} />
}
