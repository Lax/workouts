import { formatDuration } from '@workouts/shared'
import { useMemo } from 'react'
import { computeYearStats } from '../compute'
import { useSimpleStore } from '../store'
import { Stat } from './Stat'

interface YearStatsProps {
  year: number | null
}

export function YearStats({ year }: YearStatsProps) {
  const activities = useSimpleStore((s) => s.activities)
  const acts = useMemo(
    () => (year === null ? activities : activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)),
    [activities, year],
  )
  const stats = useMemo(() => computeYearStats(acts), [acts])

  const movingTimeStr = formatDuration(stats.movingTime > 0 ? stats.movingTime : null)

  return (
    <div>
      <Stat variant="year-stat" value={year !== null ? String(year) : 'Total'} description="Journey" />
      {stats.categoryBreakdown.map((c) => (
        <div key={c.category} className="stat-line">
          <span className="stat-val">{c.count} {c.category}</span>
          <span className="stat-label">{c.distanceKm.toFixed(0)}km</span>
        </div>
      ))}
      <Stat variant="year-stat" value={`${stats.streak} day`} description="Streak" />
      {stats.movingTime > 0 && <Stat variant="year-stat" value={movingTimeStr} description="Moving Time" />}
      {stats.elevationGain > 0 && <Stat variant="year-stat" value={Math.round(stats.elevationGain)} description="Elevation Gain" />}
    </div>
  )
}


