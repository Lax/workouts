/** SVGStat — combined Total view with summary header, per-year
 *  calendar heatmaps, and all-year route grid.
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

  const totals = useMemo(() => {
    let dist = 0,
      runs = 0
    for (const a of activities) {
      dist += a.distance ?? 0
      if (a.start_date) runs++
    }
    return { distance: (dist / 1000).toFixed(1), runs }
  }, [activities])

  return (
    <div className="svg-stat-container">
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
          padding: '0.5rem 0',
          borderBottom: '1px solid var(--color-border)',
          marginBottom: '1rem',
        }}
      >
        <div>
          <div style={{ fontSize: 10, color: 'var(--color-text-dim)' }}>ATHLETE</div>
          <div style={{ fontSize: 14, fontWeight: 700, color: 'var(--color-brand)' }}>Workouts</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: 10, color: 'var(--color-text-dim)' }}>STATISTICS</div>
          <div style={{ fontSize: 11, color: 'var(--color-text-secondary)', lineHeight: 1.4 }}>
            Runs: {totals.runs}
            <br />
            Total: {totals.distance} km
          </div>
        </div>
      </div>
      {years.map((y) => (
        <GithubDrawer key={y} year={y} activities={activities} />
      ))}
      <GridDrawer year={null} activities={activities} />
    </div>
  )
}
