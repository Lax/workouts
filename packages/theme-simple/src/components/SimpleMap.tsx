import { PanelMap, type TileConfig, type Vendor } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface SimpleMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  dashLines?: boolean
  privacyMode?: boolean
  showLabels?: boolean
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

function getTileConfig(): TileConfig {
  const envVendor = import.meta.env.VITE__MAP_TILE_VENDOR
  const envStyle = import.meta.env.VITE__MAP_TILE_STYLE
  const envToken = import.meta.env.VITE__MAP_TILE_TOKEN || import.meta.env.VITE__MAPBOX__TOKEN
  return {
    vendor: (envVendor || 'carto') as Vendor,
    style: envStyle || undefined,
    token: envToken || undefined,
  }
}

export function SimpleMap({
  activities,
  colorScheme,
  colorMode,
  hoveredActivityId,
  dashLines,
  privacyMode,
  showLabels,
  onActivityClick,
  onActivityHover,
}: SimpleMapProps) {
  return (
    <PanelMap
      activities={activities}
      colorScheme={colorScheme}
      colorMode={colorMode}
      hoveredActivityId={hoveredActivityId}
      tileConfig={getTileConfig()}
      dashLines={dashLines}
      privacyMode={privacyMode}
      showLabels={showLabels}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
