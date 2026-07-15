/** SVGStat — combined Total view with per-year calendar heatmaps + all-year route grid.
 *  Maps to upstream SVGStat (github.svg + grid.svg). */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { GithubDrawer } from './GithubDrawer'
import { GridDrawer } from './GridDrawer'

interface SVGStatProps {
  activities: Activity[]
}

export function SVGStat({ activities }: SVGStatProps) {
  const years = useMemo(() => {
    const s = new Set<number>()
    for (const a of activities) {
      if (a.start_date) s.add(new Date(a.start_date).getFullYear())
    }
    return Array.from(s).sort((a, b) => b - a)
  }, [activities])

  return (
    <div className="svg-stat-container">
      {years.map((y) => (
        <GithubDrawer key={y} year={y} activities={activities} />
      ))}
      <GridDrawer year={null} activities={activities} />
    </div>
  )
}
