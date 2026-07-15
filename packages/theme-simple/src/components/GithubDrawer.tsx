/** GithubDrawer — draws a year activity calendar grid.
 *  Maps to upstream GithubDrawer / --type github / github_YYYY.svg.
 *  7-row × N-column matrix of day cells; color intensity encodes daily distance.
 *  When year is null, renders ALL activities combined (Total view). */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

const CELL_SIZE = 10
const CELL_GAP = 2
const ROWS = 7
const WEEKDAYS = ['Mon', 'Wed', 'Fri']
const WEEKDAY_ROWS = [0, 2, 4]
const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

export function colorIntensity(count: number, maxCount: number): string {
  if (count === 0) return 'var(--color-border, #333)'
  const ratio = count / maxCount
  if (ratio < 0.25) return 'var(--svg-color-active-cell, #4dd2ff)'
  if (ratio < 0.5) return 'var(--svg-color-active-cell, #4dd2ff)'
  if (ratio < 0.75) return 'var(--svg-special-color, #f7d02c)'
  return 'var(--svg-special-color2, #f56c6c)'
}

interface GithubDrawerProps {
  year: number | null
  activities: Activity[]
}

export function GithubDrawer({ year, activities }: GithubDrawerProps) {
  const grid = useMemo(() => {
    const dayCount = new Map<string, number>()
    let minYear = Infinity
    let maxYear = -Infinity

    for (const a of activities) {
      if (!a.start_date) continue
      const d = new Date(a.start_date)
      const y = d.getFullYear()
      if (year !== null && y !== year) continue
      if (y < minYear) minYear = y
      if (y > maxYear) maxYear = y
      const key = `${y}-${d.getMonth() + 1}-${d.getDate()}`
      dayCount.set(key, (dayCount.get(key) || 0) + 1)
    }

    if (year === null && minYear === Infinity) return null
    const startYear = year ?? minYear
    const endYear = year ?? maxYear
    const start = new Date(startYear, 0, 1)
    const end = new Date(endYear, 11, 31)
    const startDow = start.getDay()
    const totalDays = Math.round((end.getTime() - start.getTime()) / 86400000) + 1
    const cols = Math.ceil(totalDays / 7) + 1

    const cells: { x: number; y: number; count: number; date: string }[] = []

    for (let w = 0; w < cols; w++) {
      for (let d = 0; d < ROWS; d++) {
        const dayOffset = w * 7 + d - startDow
        const dt = new Date(startYear, 0, 1 + dayOffset)
        if (dt.getFullYear() < startYear || dt.getFullYear() > endYear) continue
        if (year !== null && dt.getFullYear() !== year) continue
        const key = `${dt.getFullYear()}-${dt.getMonth() + 1}-${dt.getDate()}`
        const count = dayCount.get(key) || 0
        cells.push({
          x: w * (CELL_SIZE + CELL_GAP),
          y: d * (CELL_SIZE + CELL_GAP),
          count,
          date: key,
        })
      }
    }

    const maxCount = Math.max(1, ...cells.map((c) => c.count))
    const width = cols * (CELL_SIZE + CELL_GAP)
    const height = ROWS * (CELL_SIZE + CELL_GAP)

    return { cells, maxCount, width, height, cols, startYear, endYear }
  }, [year, activities])

  if (!grid) return <div className="empty-state">No activity data</div>

  const label = year !== null ? String(year) : `${grid.startYear}–${grid.endYear}`

  return (
    <svg
      viewBox={`0 0 ${grid.width + 30} ${grid.height + 20}`}
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Activity grid for ${label}`}
    >
      <title>{`Activity grid for ${label}`}</title>
      {WEEKDAY_ROWS.map((r, i) => (
        <text key={r} x={0} y={r * (CELL_SIZE + CELL_GAP) + CELL_SIZE - 1} fill="var(--color-text-dim)" fontSize={8}>
          {WEEKDAYS[i]}
        </text>
      ))}
      {(() => {
        const labels: React.ReactNode[] = []
        for (let i = 0; i < grid.cols; i++) {
          const dt = new Date(grid.startYear, 0, 1 + i * 7)
          if (dt.getFullYear() > grid.endYear) break
          const m = dt.getMonth()
          const prevM = i > 0 ? new Date(grid.startYear, 0, 1 + (i - 1) * 7).getMonth() : -1
          if (m !== prevM) {
            labels.push(
              <text key={`ml-${m}`} x={i * (CELL_SIZE + CELL_GAP) + 20} y={grid.height + 12} fill="var(--color-text-dim)" fontSize={8}>
                {MONTH_LABELS[m]}
              </text>,
            )
          }
        }
        return labels
      })()}
      {grid.cells.map((c) => (
        <rect
          key={c.date}
          x={c.x + 20}
          y={c.y}
          width={CELL_SIZE}
          height={CELL_SIZE}
          rx={2}
          fill={colorIntensity(c.count, grid.maxCount)}
          opacity={1}
        />
      ))}
    </svg>
  )
}
