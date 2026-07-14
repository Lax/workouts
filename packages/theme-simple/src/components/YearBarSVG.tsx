import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface YearBarSVGProps {
  year: number
  activities: Activity[]
}

export function YearBarSVG({ year, activities }: YearBarSVGProps) {
  const bars = useMemo(() => {
    const monthly = Array.from({ length: 12 }, () => 0)
    for (const a of activities) {
      if (!a.start_date) continue
      const d = new Date(a.start_date)
      if (d.getFullYear() !== year) continue
      monthly[d.getMonth()] += a.distance ?? 0
    }
    const max = Math.max(1, ...monthly)
    return monthly.map((d, i) => ({
      month: i,
      distance: d,
      height: (d / max) * 100,
    }))
  }, [year, activities])

  const MONTHS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D']
  const BAR_W = 18
  const GAP = 4
  const H = 120
  const W = bars.length * (BAR_W + GAP) + 10

  return (
    <svg
      viewBox={`0 0 ${W} ${H + 20}`}
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Monthly distance chart for ${year}`}
    >
      <title>{`Monthly distance for ${year}`}</title>
      {bars.map((b, i) => (
        <g key={b.month}>
          <rect
            x={i * (BAR_W + GAP) + 5}
            y={H - b.height}
            width={BAR_W}
            height={b.height}
            rx={2}
            fill="var(--color-accent, #4dd2ff)"
            opacity={0.7}
          />
          <text x={i * (BAR_W + GAP) + BAR_W / 2 + 5} y={H + 14} textAnchor="middle" fill="var(--color-text-dim)" fontSize={8}>
            {MONTHS[i]}
          </text>
        </g>
      ))}
    </svg>
  )
}
