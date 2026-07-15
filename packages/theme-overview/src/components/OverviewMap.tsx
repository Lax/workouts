import { HeroMap, type TileConfig, type Vendor } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface OverviewMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  dashLines?: boolean
  privacyMode?: boolean
  lightsOn?: boolean
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

export function OverviewMap({
  activities,
  colorScheme,
  colorMode,
  hoveredActivityId,
  dashLines,
  privacyMode,
  lightsOn,
  showLabels,
  onActivityClick,
  onActivityHover,
}: OverviewMapProps) {
  return (
    <HeroMap
      activities={activities}
      colorScheme={colorScheme}
      colorMode={colorMode}
      hoveredActivityId={hoveredActivityId}
      tileConfig={getTileConfig()}
      dashLines={dashLines}
      privacyMode={privacyMode}
      lightsOn={lightsOn}
      showLabels={showLabels}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
