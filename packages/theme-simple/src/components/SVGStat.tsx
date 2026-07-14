import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { YearBarSVG } from './YearBarSVG'
import { YearGridSVG } from './YearGridSVG'

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
        <div key={y}>
          <h3 style={{ fontSize: '0.85rem', color: 'var(--color-text-secondary)', marginBottom: '0.5rem' }}>{y}</h3>
          <YearGridSVG year={y} activities={activities} />
          <YearBarSVG year={y} activities={activities} />
        </div>
      ))}
    </div>
  )
}
