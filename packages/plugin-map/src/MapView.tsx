import type { Activity } from '@workouts/shared'
import { useRef } from 'react'
import { type LeafletMapOptions, useLeafletMap } from './useLeafletMap'
import { type PolylineOptions, useMapPolylines } from './useMapPolylines'

export type MapVariant = 'fullscreen' | 'contained'

export interface MapViewProps {
  activities: Activity[]
  colorScheme?: 'light' | 'dark'
  colorMode?: 'type' | 'speed'
  hoveredActivityId?: string | null
  maxLines?: number
  variant?: MapVariant
  tileProvider?: 'carto' | 'mapbox'
  mapboxToken?: string
  mapboxStyle?: string
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
  tileProvider = 'carto',
  mapboxToken = '',
  mapboxStyle = 'dark-v11',
  onActivityClick,
  onActivityHover,
}: MapViewProps) {
  const elRef = useRef<HTMLDivElement>(null)

  const leafletOptions: LeafletMapOptions = { colorScheme, tileProvider, mapboxToken, mapboxStyle }
  const mapRef = useLeafletMap(elRef, leafletOptions)

  const polylineOptions: PolylineOptions = { colorMode, hoveredActivityId, maxLines, fitOnChange: true, onActivityClick, onActivityHover }
  useMapPolylines(mapRef, activities, polylineOptions)

  const containerStyle: React.CSSProperties =
    variant === 'contained'
      ? { height: '100%', width: '100%', zIndex: 0, background: 'var(--color-bg)' }
      : { position: 'fixed', inset: 0, zIndex: 0, background: 'var(--color-bg)' }

  return <div ref={elRef} style={containerStyle} />
}
