import { formatDuration, formatPace } from '@workouts/shared'
import { useMemo, useState } from 'react'
import { computeYearStats } from '../compute'
import { useSimpleStore } from '../store'
import { Stat } from './Stat'

interface YearStatsProps {
  year: number | null
  defaultCompact?: boolean
}

export function YearStats({ year, defaultCompact = true }: YearStatsProps) {
  const [showAll, setShowAll] = useState(false)
  const activities = useSimpleStore((s) => s.activities)
  const acts = useMemo(
    () => (year === null ? activities : activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)),
    [activities, year],
  )
  const stats = useMemo(() => computeYearStats(acts), [acts])

  const paceStr = formatPace(stats.pace)
  const movingTimeStr = formatDuration(stats.movingTime > 0 ? stats.movingTime : null)

  const catStr = stats.categoryBreakdown.map((c) => `${capitalize(c.category)} ${c.distanceKm.toFixed(0)}km`).join(' · ')
  const hasExtra =
    stats.movingTime > 0 ||
    stats.elevationGain > 0 ||
    stats.avgHeartrate !== null ||
    stats.maxHeartrate !== null ||
    stats.avgCadence !== null ||
    stats.avgPower !== null ||
    stats.avgTemperature !== null ||
    stats.calories > 0

  const expanded = !defaultCompact || showAll

  return (
    <div>
      <Stat variant="year-stat" value={year !== null ? String(year) : 'Total'} description="Journey" />
      <Stat variant="year-stat" value={stats.count} description="Runs" />
      <Stat variant="year-stat" value={(stats.distance / 1000).toFixed(1)} description="km" />
      {stats.pace !== null && <Stat variant="year-stat" value={paceStr} description="Avg Pace" />}
      <Stat variant="year-stat" value={`${stats.streak} day`} description="Streak" />
      {expanded && (
        <>
          {stats.movingTime > 0 && <Stat variant="year-stat" value={movingTimeStr} description="Moving Time" />}
          {stats.elevationGain > 0 && <Stat variant="year-stat" value={Math.round(stats.elevationGain)} description="Elevation Gain" />}
          {stats.avgHeartrate !== null && <Stat variant="year-stat" value={Math.round(stats.avgHeartrate)} description="Avg Heart Rate" />}
          {stats.maxHeartrate !== null && <Stat variant="year-stat" value={Math.round(stats.maxHeartrate)} description="Max Heart Rate" />}
          {stats.avgCadence !== null && <Stat variant="year-stat" value={Math.round(stats.avgCadence)} description="Avg Cadence" />}
          {stats.avgPower !== null && <Stat variant="year-stat" value={Math.round(stats.avgPower)} description="Avg Power" />}
          {stats.avgTemperature !== null && <Stat variant="year-stat" value={Math.round(stats.avgTemperature)} description="Avg Temp" />}
          {stats.calories > 0 && <Stat variant="year-stat" value={stats.calories} description="Calories" />}
          {catStr && (
            <div className="stat-line" style={{ fontSize: '0.85rem', opacity: 0.7 }}>
              <span className="stat-label">{catStr}</span>
            </div>
          )}
        </>
      )}
      {defaultCompact && hasExtra && (
        <button
          type="button"
          className="stats-toggle"
          onClick={(e) => {
            e.stopPropagation()
            setShowAll(!showAll)
          }}
        >
          {showAll ? 'Less' : 'More'}
        </button>
      )}
    </div>
  )
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}
