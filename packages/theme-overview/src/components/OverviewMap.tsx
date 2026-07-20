import { HeroMap, type TileConfig } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface OverviewMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  tileConfig?: TileConfig
  dashLines?: boolean
  privacyMode?: boolean
  lightsOn?: boolean
  showLabels?: boolean
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function OverviewMap({
  activities,
  colorScheme,
  colorMode,
  hoveredActivityId,
  tileConfig,
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
      tileConfig={tileConfig}
      dashLines={dashLines}
      privacyMode={privacyMode}
      lightsOn={lightsOn}
      showLabels={showLabels}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
