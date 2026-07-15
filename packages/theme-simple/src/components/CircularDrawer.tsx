/** CircularDrawer — ring chart showing monthly activity.
 *  Matches upstream year_YYYY.svg style: ring arcs on a circle,
 *  year number in center, month labels along outer edge. */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface CircularDrawerProps {
  year: number
  activities: Activity[]
}

function polarToCartesian(cx: number, cy: number, r: number, deg: number) {
  const rad = ((deg - 90) * Math.PI) / 180
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) }
}

const MONTH_NAMES = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
]
const OUTER_R = 86

export function CircularDrawer({ year, activities }: CircularDrawerProps) {
  const segments = useMemo(() => {
    const monthData = Array.from({ length: 12 }, (_, i) => ({ month: i + 1, totalDist: 0 }))
    for (const a of activities) {
      if (!a.start_date || new Date(a.start_date).getFullYear() !== year) continue
      const m = new Date(a.start_date).getMonth()
      monthData[m].totalDist += a.distance ?? 0
    }
    const maxDist = Math.max(...monthData.map((m) => m.totalDist), 1)
    const arcWidth = 34
    const anglePerMonth = 360 / 12

    const sorted = [...monthData].sort((a, b) => b.totalDist - a.totalDist)
    const colors = [
      '#94ff23',
      '#adff20',
      '#c8e01e',
      '#e0c01c',
      '#ffb210',
      '#e8a012',
      '#d09014',
      '#b88016',
      '#a07018',
      '#88601a',
      '#70501c',
      '#58401e',
    ]
    const colorMap = new Map<number, string>()
    sorted.forEach((m, i) => {
      colorMap.set(m.month, colors[i] || '#58401e')
    })

    return monthData.map((m, i) => {
      const aStart = -90 + i * anglePerMonth
      const aEnd = aStart + anglePerMonth
      const ratio = m.totalDist / maxDist
      const bandWidth = Math.max(2, arcWidth * ratio)
      const rInner = OUTER_R - bandWidth
      const color = m.totalDist === 0 ? 'var(--color-border, #333)' : colorMap.get(m.month) || '#58401e'
      return {
        month: m.month,
        label: MONTH_NAMES[m.month - 1],
        totalDist: m.totalDist,
        aStart,
        aEnd,
        rInner,
        outerR: OUTER_R,
        color,
        ratio,
      }
    })
  }, [year, activities])

  const cx = 100
  const cy = 100
  const innerRefR = 52

  function ringPath(s: (typeof segments)[number]) {
    const s1 = polarToCartesian(cx, cy, s.outerR, s.aStart)
    const e1 = polarToCartesian(cx, cy, s.outerR, s.aEnd)
    const s2 = polarToCartesian(cx, cy, s.rInner, s.aEnd)
    const e2 = polarToCartesian(cx, cy, s.rInner, s.aStart)
    const large = s.aEnd - s.aStart > 180 ? 1 : 0
    return `M ${s1.x} ${s1.y} A ${s.outerR} ${s.outerR} 0 ${large} 1 ${e1.x} ${e1.y} L ${s2.x} ${s2.y} A ${s.rInner} ${s.rInner} 0 ${large} 0 ${e2.x} ${e2.y} Z`
  }

  return (
    <svg
      viewBox="0 0 200 200"
      xmlns="http://www.w3.org/2000/svg"
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Circular activity chart for ${year}`}
    >
      <title>{`Circular activity chart for ${year}`}</title>
      <rect width={200} height={200} fill="var(--color-bg, #171717)" />

      {/* Reference circles */}
      <circle cx={cx} cy={cy} r={innerRefR} fill="none" stroke="var(--color-border, #333)" strokeWidth={0.5} opacity={0.3} />
      <circle cx={cx} cy={cy} r={OUTER_R} fill="none" stroke="var(--color-border, #333)" strokeWidth={0.5} opacity={0.3} />

      {/* Ring arc segments */}
      {segments.map((s) => (s.totalDist > 0 ? <path key={s.month} d={ringPath(s)} fill={s.color} opacity={0.85} /> : null))}

      {/* Month labels on outer ring */}
      {segments.map((s) => {
        const midAngle = (s.aStart + s.aEnd) / 2
        const p = polarToCartesian(cx, cy, 95, midAngle)
        return (
          <text
            key={`l${s.month}`}
            x={p.x}
            y={p.y}
            textAnchor="middle"
            dominantBaseline="central"
            fill="var(--color-text-secondary, #d4d4d4)"
            fontSize={4.5}
            fontFamily="Arial"
          >
            {s.label.slice(0, 3)}
          </text>
        )
      })}

      {/* Year number in center */}
      <text
        x={cx}
        y={cy}
        textAnchor="middle"
        dominantBaseline="central"
        fill="var(--color-brand, #e0ed5e)"
        fontSize={16}
        fontWeight="bold"
        fontFamily="Arial"
      >
        {year}
      </text>
    </svg>
  )
}
