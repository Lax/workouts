import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import type { TileConfig } from './tiles'
import { useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export interface PanelMapProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  tileConfig?: TileConfig
  lightsOn?: boolean
  dashLines?: boolean
  privacyMode?: boolean
  animate?: boolean
  initialScrollDisabled?: boolean
  attributionPosition?: 'topleft' | 'topright' | 'bottomleft' | 'bottomright'
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function PanelMap({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  tileConfig,
  lightsOn = true,
  dashLines = false,
  privacyMode = false,
  animate = false,
  initialScrollDisabled,
  attributionPosition,
  onActivityClick,
  onActivityHover,
}: PanelMapProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useLeafletMap(elRef, {
    colorScheme,
    tileConfig,
    lightsOn,
    zoomPosition: 'bottomright',
    attributionPosition,
    initialScrollDisabled,
  })
  const opts: PolylineOptions = {
    colorMode,
    hoveredActivityId,
    maxLines,
    fitOnChange: true,
    dashLines,
    animate,
    onActivityClick,
    onActivityHover,
  }
  useMapPolylines(mapRef, activities, opts)
  const bg = privacyMode ? 'var(--color-bg, #000)' : 'transparent'
  return <div ref={elRef} style={{ height: '100%', width: '100%', background: bg }} />
}
