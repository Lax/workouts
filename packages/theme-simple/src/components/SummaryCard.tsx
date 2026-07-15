import type { Activity } from '@workouts/shared'
import { formatDistance, formatDuration, formatPace } from '@workouts/shared'
import { useMemo, useState } from 'react'
import { RoutePreviewSVG } from './RoutePreviewSVG'
import { Stat } from './Stat'

interface SummaryCardProps {
  periodLabel: string
  activities: Activity[]
  interval: string
}

export function SummaryCard({ periodLabel, activities, interval }: SummaryCardProps) {
  const [flipped, setFlipped] = useState(false)

  const stats = useMemo(() => {
    let totalDist = 0
    let totalTime = 0
    let totalHr = 0
    let hrCount = 0
    let totalPaceDist = 0
    let totalPaceTime = 0
    for (const a of activities) {
      totalDist += a.distance ?? 0
      totalTime += a.moving_time ?? 0
      if (a.average_heartrate) {
        totalHr += a.average_heartrate
        hrCount++
      }
      if (a.average_speed && a.average_speed > 0) {
        totalPaceDist += a.distance ?? 0
        totalPaceTime += (a.distance ?? 0) / a.average_speed
      }
    }
    const avgPace = totalPaceTime > 0 ? totalPaceDist / totalPaceTime : 0
    return {
      count: activities.length,
      distance: totalDist,
      time: totalTime,
      avgHr: hrCount > 0 ? totalHr / hrCount : 0,
      avgPace,
    }
  }, [activities])

  const routePolyline = useMemo(() => {
    const withPolyline = activities.find((a) => a.summary_polyline)
    return withPolyline?.summary_polyline || null
  }, [activities])

  const paceStr = formatPace(stats.avgPace > 0 ? stats.avgPace : null)

  return (
    <div className="summary-card" onClick={() => setFlipped(!flipped)}>
      <div className={`card-inner${flipped ? ' flipped' : ''}`}>
        <div className="card-front">
          <div className="card-period">{periodLabel}</div>
          <div className="card-stats">
            <Stat value={stats.count} description={stats.count === 1 ? 'run' : 'runs'} />
            <Stat value={formatDistance(stats.distance)} description="distance" />
            <Stat value={paceStr} description="pace" />
            {stats.avgHr > 0 && <Stat value={Math.round(stats.avgHr)} description="avg HR" />}
            <Stat value={formatDuration(stats.time)} description="time" />
          </div>
          {interval === 'year' && <div className="card-chart-hint">Flip for route →</div>}
        </div>
        <div className="card-back">
          <RoutePreviewSVG polyline={routePolyline} />
        </div>
      </div>
    </div>
  )
}
