import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

const CELL_SIZE = 10
const CELL_GAP = 2
const ROWS = 7
const WEEKDAYS = ['Mon', 'Wed', 'Fri']
const WEEKDAY_ROWS = [0, 2, 4]
const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

interface YearGridSVGProps {
  year: number
  activities: Activity[]
}

export function YearGridSVG({ year, activities }: YearGridSVGProps) {
  const grid = useMemo(() => {
    const dayCount = new Map<string, number>()
    for (const a of activities) {
      if (!a.start_date) continue
      const d = new Date(a.start_date)
      if (d.getFullYear() !== year) continue
      const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
      dayCount.set(key, (dayCount.get(key) || 0) + 1)
    }

    const start = new Date(year, 0, 1)
    const end = new Date(year, 11, 31)
    const startDow = start.getDay()
    const cols = Math.ceil((end.getTime() - start.getTime()) / (86400000 * 7)) + 1

    const cells: { x: number; y: number; count: number; date: string }[] = []

    for (let w = 0; w < cols; w++) {
      for (let d = 0; d < ROWS; d++) {
        const dayOffset = w * 7 + d - startDow
        const dt = new Date(year, 0, 1 + dayOffset)
        if (dt.getFullYear() !== year) continue
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

    return { cells, maxCount, width, height, cols }
  }, [year, activities])

  function colorIntensity(count: number): string {
    if (count === 0) return 'var(--color-border, #333)'
    const ratio = count / grid.maxCount
    if (ratio < 0.25) return 'var(--color-accent, #4dd2ff)'
    if (ratio < 0.5) return 'var(--color-accent, #4dd2ff)'
    if (ratio < 0.75) return 'var(--color-accent, #4dd2ff)'
    return '#fff'
  }

  return (
    <svg
      viewBox={`0 0 ${grid.width + 30} ${grid.height + 20}`}
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Activity grid for ${year}`}
    >
      <title>{`Activity grid for ${year}`}</title>
      {WEEKDAY_ROWS.map((r, i) => (
        <text key={r} x={0} y={r * (CELL_SIZE + CELL_GAP) + CELL_SIZE - 1} fill="var(--color-text-dim)" fontSize={8}>
          {WEEKDAYS[i]}
        </text>
      ))}
      {(() => {
        const labels: React.ReactNode[] = []
        for (let i = 0; i < grid.cols; i++) {
          const dt = new Date(year, 0, 1 + i * 7)
          const m = dt.getMonth()
          const prevM = i > 0 ? new Date(year, 0, 1 + (i - 1) * 7).getMonth() : -1
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
          fill={colorIntensity(c.count)}
          opacity={c.count > 0 ? 0.6 + (c.count / grid.maxCount) * 0.4 : 0.15}
        />
      ))}
    </svg>
  )
}
