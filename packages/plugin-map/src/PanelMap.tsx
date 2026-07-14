import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import type { TileUrlBuilder } from './tiles'
import { useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export interface PanelMapProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  tileUrl?: TileUrlBuilder
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function PanelMap({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  tileUrl,
  onActivityClick,
  onActivityHover,
}: PanelMapProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useLeafletMap(elRef, { colorScheme, tileUrl })
  const opts: PolylineOptions = { colorMode, hoveredActivityId, maxLines, fitOnChange: true, onActivityClick, onActivityHover }
  useMapPolylines(mapRef, activities, opts)
  return <div ref={elRef} style={{ height: '100%', width: '100%' }} />
}
