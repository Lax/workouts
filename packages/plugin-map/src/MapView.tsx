import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import type { TileConfig } from './tiles'
import { useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export type MapVariant = 'fullscreen' | 'contained'

export interface MapViewProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  variant?: MapVariant
  tileConfig?: TileConfig
  lightsOn?: boolean
  showLabels?: boolean
  dashLines?: boolean
  privacyMode?: boolean
  animate?: boolean
  selectedActivityId?: string | null
  showZoomControl?: boolean
  showAttribution?: boolean
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function MapView({
  activities,
  colorScheme = 'dark',
  colorMode = 'type',
  hoveredActivityId = null,
  maxLines = 500,
  variant = 'fullscreen',
  tileConfig,
  lightsOn = true,
  showLabels = false,
  dashLines = false,
  privacyMode = false,
  animate = false,
  selectedActivityId = null,
  showZoomControl = true,
  showAttribution = false,
  onActivityClick,
  onActivityHover,
}: MapViewProps) {
  const elRef = useRef<HTMLDivElement>(null)

  const mapRef = useLeafletMap(elRef, {
    colorScheme,
    tileConfig,
    lightsOn,
    showLabels,
    zoomControl: showZoomControl,
    attributionControl: showAttribution,
  })

  const polylineOptions: PolylineOptions = {
    colorMode,
    colorScheme,
    hoveredActivityId,
    maxLines,
    fitOnChange: true,
    dashLines,
    animate,
    selectedActivityId,
    onActivityClick,
    onActivityHover,
  }
  useMapPolylines(mapRef, activities, polylineOptions)

  const bg = privacyMode ? 'var(--color-bg, #000)' : 'var(--color-bg)'
  const containerStyle: React.CSSProperties =
    variant === 'contained'
      ? { height: '100%', width: '100%', zIndex: 0, background: bg }
      : { position: 'fixed', inset: 0, zIndex: 0, background: bg }

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <div ref={elRef} style={containerStyle} />
      {privacyMode && <div style={{ position: 'absolute', inset: 0, background: bg, zIndex: -1 }} />}
    </div>
  )
}
