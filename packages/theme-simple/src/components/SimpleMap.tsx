import { PanelMap, type TileConfig } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface SimpleMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  tileConfig?: TileConfig
  privacyMode?: boolean
  lightsOn?: boolean
  showLabels?: boolean
  animate?: boolean
  initialScrollDisabled?: boolean
  attributionPosition?: 'topleft' | 'topright' | 'bottomleft' | 'bottomright'
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function SimpleMap({
  activities,
  colorScheme,
  colorMode,
  hoveredActivityId,
  privacyMode,
  lightsOn,
  showLabels,
  animate,
  initialScrollDisabled,
  tileConfig,
  attributionPosition,
  onActivityClick,
  onActivityHover,
}: SimpleMapProps) {
  return (
    <PanelMap
      activities={activities}
      colorScheme={colorScheme}
      colorMode={colorMode}
      hoveredActivityId={hoveredActivityId}
      tileConfig={tileConfig}
      dashLines={true}
      privacyMode={privacyMode}
      lightsOn={lightsOn}
      showLabels={showLabels}
      animate={animate}
      initialScrollDisabled={initialScrollDisabled}
      attributionPosition={attributionPosition}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
