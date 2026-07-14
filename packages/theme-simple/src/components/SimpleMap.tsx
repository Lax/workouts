import { mapbox, PanelMap } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'

interface SimpleMapProps {
  activities: Activity[]
  colorScheme: 'light' | 'dark'
  colorMode: 'type' | 'speed'
  hoveredActivityId: string | null
  onActivityClick?: (activity: Activity) => void
  onActivityHover?: (activityId: string | null) => void
}

const MAPBOX_URL = mapbox(import.meta.env.VITE__MAPBOX__TOKEN || '', 'dark-v11')

export function SimpleMap({ activities, colorScheme, colorMode, hoveredActivityId, onActivityClick, onActivityHover }: SimpleMapProps) {
  return (
    <PanelMap
      activities={activities}
      colorScheme={colorScheme}
      colorMode={colorMode}
      hoveredActivityId={hoveredActivityId}
      tileUrl={MAPBOX_URL}
      onActivityClick={onActivityClick}
      onActivityHover={onActivityHover}
    />
  )
}
