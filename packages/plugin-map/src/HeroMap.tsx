import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import type { TileConfig } from './tiles'
import { useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export interface HeroMapProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  tileConfig?: TileConfig
  lightsOn?: boolean
  showLabels?: boolean
  dashLines?: boolean
  privacyMode?: boolean
  animate?: boolean
  selectedActivityId?: string | null
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function HeroMap({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  tileConfig,
  lightsOn = true,
  showLabels = false,
  dashLines = false,
  privacyMode = false,
  animate = false,
  selectedActivityId = null,
  onActivityClick,
  onActivityHover,
}: HeroMapProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const mapRef = useLeafletMap(elRef, { colorScheme, tileConfig, lightsOn, showLabels })
  const opts: PolylineOptions = {
    colorMode,
    hoveredActivityId,
    maxLines,
    fitOnChange: true,
    dashLines,
    animate,
    selectedActivityId,
    onActivityClick,
    onActivityHover,
  }
  useMapPolylines(mapRef, activities, opts)
  const bg = privacyMode ? 'var(--color-bg, #000)' : 'var(--color-bg)'
  return <div ref={elRef} style={{ position: 'fixed', inset: 0, zIndex: 0, background: bg }} />
}
