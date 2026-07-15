/** YearSummaryDrawer — draws a year summary dashboard.
 *  Maps to upstream YearSummaryDrawer / --type year_summary / year_summary_YYYY.svg.
 *  Calendar dot matrix (12 cols × 31 rows) + stats panel. */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface YearSummaryDrawerProps {
  year: number
  activities: Activity[]
}

export function YearSummaryDrawer({ year, activities }: YearSummaryDrawerProps) {
  const stats = useMemo(() => {
    const acts = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
    let totalDist = 0,
      totalTime = 0,
      hrCount = 0,
      totalHr = 0,
      totalPaceDist = 0,
      totalPaceTime = 0
    for (const a of acts) {
      totalDist += a.distance ?? 0
      totalTime += a.moving_time ?? 0
      totalHr += a.average_heartrate ?? 0
      if (a.average_heartrate) hrCount++
      if (a.average_speed && a.average_speed > 0) {
        totalPaceDist += a.distance ?? 0
        totalPaceTime += (a.distance ?? 0) / a.average_speed
      }
    }
    let paceDisplay = '--'
    if (totalPaceTime > 0) {
      const avgSpeed = totalPaceDist / totalPaceTime
      const paceMinPerKm = 1000 / (avgSpeed * 60)
      const paceMin = Math.floor(paceMinPerKm)
      const paceSec = Math.round((paceMinPerKm - paceMin) * 60)
      paceDisplay = `${paceMin}m ${String(paceSec).padStart(2, '0')}s`
    }
    return {
      count: acts.length,
      distance: totalDist,
      time: totalTime,
      avgHr: hrCount > 0 ? Math.round(totalHr / hrCount) : 0,
      pace: paceDisplay,
    }
  }, [year, activities])

  // Compute dot matrix: month × day
  const dots = useMemo(() => {
    const map = new Map<string, number>()
    for (const a of activities) {
      if (!a.start_date || new Date(a.start_date).getFullYear() !== year) continue
      const d = new Date(a.start_date)
      const key = `${d.getMonth() + 1}-${d.getDate()}`
      map.set(key, (map.get(key) ?? 0) + (a.distance ?? 0))
    }
    const maxDist = Math.max(...map.values(), 1)
    const result: { month: number; day: number; dist: number; color: string }[] = []
    for (let m = 0; m < 12; m++) {
      const daysInMonth = new Date(year, m + 1, 0).getDate()
      for (let d = 1; d <= daysInMonth; d++) {
        const dist = map.get(`${m + 1}-${d}`) ?? 0
        const ratio = dist / maxDist
        const color =
          dist === 0
            ? 'var(--color-border, #444)'
            : ratio > 0.7
              ? 'var(--svg-special-color2, #f56c6c)'
              : ratio > 0.4
                ? 'var(--svg-special-color, #f7d02c)'
                : ratio > 0.15
                  ? 'var(--svg-color-active-cell, #4dd2ff)'
                  : 'var(--color-text-dim, #666)'
        result.push({ month: m + 1, day: d, dist, color })
      }
    }
    return result
  }, [year, activities])

  return (
    <div style={{ display: 'flex', gap: '1rem', padding: '0.5rem', fontFamily: 'IBM Plex Sans, sans-serif' }}>
      <div style={{ minWidth: 120 }}>
        <div style={{ fontSize: 10, color: 'var(--color-text-dim, #666)' }}>{year} Summary</div>
        <div style={{ marginTop: 8 }}>
          {[
            { label: 'Distance', value: `${(stats.distance / 1000).toFixed(0)} km` },
            { label: 'Runs', value: stats.count },
            { label: 'Avg Pace', value: stats.pace },
            { label: 'Avg HR', value: stats.avgHr > 0 ? `${stats.avgHr} bpm` : '--' },
          ].map((s) => (
            <div key={s.label} style={{ marginBottom: 6 }}>
              <div style={{ fontSize: 9, color: 'var(--color-text-dim, #666)' }}>{s.label}</div>
              <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--color-brand, #e0ed5e)' }}>{s.value}</div>
            </div>
          ))}
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(12, 1fr)', gap: 1 }}>
          {['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'].map((label) => (
            <div key={`mhl-${label}`} style={{ fontSize: 7, textAlign: 'center', color: 'var(--color-text-dim, #666)' }}>
              {label}
            </div>
          ))}
          {dots.map((dot) => (
            <div
              key={`${dot.month}-${dot.day}`}
              style={{ width: 6, height: 6, borderRadius: '50%', background: dot.color, margin: '0 auto' }}
              title={`${dot.month}/${dot.day}: ${(dot.dist / 1000).toFixed(1)}km`}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
