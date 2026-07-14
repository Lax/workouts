import { useLeafletMap, useMapPolylines } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'
import { useRef } from 'react'

interface SimpleMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function SimpleMap({ activities, colorScheme, colorMode, hoveredActivityId, onActivityClick, onActivityHover }: SimpleMapProps) {
  const elRef = useRef<HTMLDivElement>(null)

  const mapRef = useLeafletMap(elRef, {
    colorScheme,
    tileProvider: 'mapbox',
    mapboxToken: import.meta.env.VITE__MAPBOX__TOKEN || '',
    mapboxStyle: 'dark-v11',
  })

  useMapPolylines(mapRef, activities, {
    colorMode,
    hoveredActivityId,
    fitOnChange: false,
    onActivityClick,
    onActivityHover,
  })

  return <div ref={elRef} style={{ height: '100%', width: '100%' }} />
}
