import { buildMonthlyBarOption, Chart } from '@workouts/plugin-chart'
import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { useSimpleStore } from '../store'
import { SummaryCard } from './SummaryCard'

function getISOWeek(date: Date): string {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7))
  const year = d.getFullYear()
  const week = Math.floor(((+d - +new Date(year, 0, 4)) / 86400000 + ((new Date(year, 0, 4).getDay() + 6) % 7)) / 7)
  return `${year}-W${String(week).padStart(2, '0')}`
}

export function SummaryCardGrid() {
  const activities = useSimpleStore((s) => s.activities)
  const summaryInterval = useSimpleStore((s) => s.summaryInterval)
  const summarySportType = useSimpleStore((s) => s.summarySportType)

  const filtered = useMemo(
    () => (summarySportType ? activities.filter((a) => (a.sport_category || a.type) === summarySportType) : activities),
    [activities, summarySportType],
  )

  const groups = useMemo(() => {
    const map = new Map<string, Activity[]>()
    filtered.forEach((act) => {
      if (!act.start_date) return
      const d = new Date(act.start_date)
      let key: string
      switch (summaryInterval) {
        case 'year':
          key = String(d.getFullYear())
          break
        case 'month':
          key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
          break
        case 'week':
          key = getISOWeek(d)
          break
        case 'day':
          key = act.start_date.slice(0, 10)
          break
        default:
          return
      }
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(act)
    })
    return Array.from(map.entries())
      .sort(([a], [b]) => b.localeCompare(a))
      .map(([period, acts]) => ({ period, activities: acts }))
  }, [filtered, summaryInterval])

  if (groups.length === 0) {
    return <div className="empty-state">No activities match your filters</div>
  }

  return (
    <div className="summary-card-grid">
      {groups.map((g) => (
        <div key={g.period} className="summary-card-wrapper">
          <SummaryCard periodLabel={g.period} activities={g.activities} interval={summaryInterval} />
          {summaryInterval === 'year' && (
            <div className="card-chart">
              <Chart option={buildMonthlyBarOption(g.activities)} style={{ height: 100 }} />
            </div>
          )}
        </div>
      ))}
    </div>
  )
}
