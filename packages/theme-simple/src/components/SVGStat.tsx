/** SVGStat — combined Total view with calendar heatmap + route grid.
 *  Maps to upstream SVGStat (github.svg + grid.svg). */

import type { Activity } from '@workouts/shared'
import { GithubDrawer } from './GithubDrawer'
import { GridDrawer } from './GridDrawer'

interface SVGStatProps {
  activities: Activity[]
}

export function SVGStat({ activities }: SVGStatProps) {
  return (
    <div className="svg-stat-container">
      <GithubDrawer year={null} activities={activities} />
      <GridDrawer year={null} activities={activities} />
    </div>
  )
}
