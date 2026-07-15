/** YearSummaryDrawer — draws a year summary dashboard.
 *  Maps to upstream YearSummaryDrawer / --type year_summary / year_summary_YYYY.svg.
 *  Calendar dot matrix (12 month columns with day rows) + stats panel. */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface YearSummaryDrawerProps {
  year: number
  activities: Activity[]
}

function dotColor(dist: number, maxDist: number): string {
  if (dist === 0) return 'var(--color-border, #444)'
  const ratio = dist / maxDist
  if (ratio > 0.7) return 'var(--svg-special-color2, #f56c6c)'
  if (ratio > 0.4) return 'var(--svg-special-color, #f7d02c)'
  if (ratio > 0.15) return 'var(--svg-color-active-cell, #4dd2ff)'
  return 'var(--color-text-dim, #666)'
}

const MONTH_LABELS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']

export function YearSummaryDrawer({ year, activities }: YearSummaryDrawerProps) {
  const stats = useMemo(() => {
    const acts = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
    let totalDist = 0,
      hrCount = 0,
      totalHr = 0,
      totalPaceDist = 0,
      totalPaceTime = 0
    for (const a of acts) {
      totalDist += a.distance ?? 0
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
    return { count: acts.length, distance: totalDist, avgHr: hrCount > 0 ? Math.round(totalHr / hrCount) : 0, pace: paceDisplay }
  }, [year, activities])

  // Group dots by month as column arrays
  const monthColumns = useMemo(() => {
    const map = new Map<string, number>()
    for (const a of activities) {
      if (!a.start_date || new Date(a.start_date).getFullYear() !== year) continue
      const d = new Date(a.start_date)
      const key = `${d.getMonth() + 1}-${d.getDate()}`
      map.set(key, (map.get(key) ?? 0) + (a.distance ?? 0))
    }
    const maxDist = Math.max(...map.values(), 1)
    return Array.from({ length: 12 }, (_, m) => {
      const daysInMonth = new Date(year, m + 1, 0).getDate()
      const days = Array.from({ length: daysInMonth }, (_, d) => {
        const dist = map.get(`${m + 1}-${d + 1}`) ?? 0
        return { day: d + 1, dist, color: dotColor(dist, maxDist) }
      })
      return { month: m, label: MONTH_LABELS[m], days }
    })
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
        <div style={{ display: 'flex', gap: 2 }}>
          {monthColumns.map((col) => (
            <div key={col.month} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1, flex: 1 }}>
              <div style={{ fontSize: 7, color: 'var(--color-text-dim, #666)' }}>{col.label}</div>
              {col.days.map((dot) => (
                <div
                  key={dot.day}
                  style={{ width: 6, height: 6, borderRadius: '50%', background: dot.color, flexShrink: 0 }}
                  title={`${col.month + 1}/${dot.day}: ${(dot.dist / 1000).toFixed(1)}km`}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
