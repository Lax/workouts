import { HeroMap } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface OverviewMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

export function OverviewMap({ activities, colorScheme, colorMode, hoveredActivityId, onActivityClick, onActivityHover }: OverviewMapProps) {
  return (
    <HeroMap
      activities={activities}
      colorScheme={colorScheme}
      colorMode={colorMode}
      hoveredActivityId={hoveredActivityId}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
