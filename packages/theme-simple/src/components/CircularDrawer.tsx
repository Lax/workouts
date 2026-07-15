/** CircularDrawer — draws a circular year activity poster.
 *  Maps to upstream CircularDrawer / --type circular / year_YYYY.svg.
 *  Renders monthly polar area sectors in 200x200 viewBox.
 *  Month labels at 12 o'clock start, concentric reference arcs. */

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

export function CircularDrawer({ year, activities }: CircularDrawerProps) {
  const segments = useMemo(() => {
    const monthData = Array.from({ length: 12 }, (_, i) => ({
      month: i + 1,
      totalDist: 0,
      count: 0,
    }))
    for (const a of activities) {
      if (!a.start_date || new Date(a.start_date).getFullYear() !== year) continue
      const m = new Date(a.start_date).getMonth()
      monthData[m].totalDist += a.distance ?? 0
      monthData[m].count++
    }
    const maxDist = Math.max(...monthData.map((m) => m.totalDist), 1)
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    const anglePerMonth = 360 / 12
    let startAngle = -90
    return monthData.map((m) => {
      const endAngle = startAngle + anglePerMonth
      const ratio = m.totalDist / maxDist
      const outerR = 25 + 52 * ratio
      const color =
        m.totalDist === 0
          ? 'var(--color-border, #333)'
          : ratio > 0.7
            ? 'var(--svg-special-color2, #f56c6c)'
            : ratio > 0.4
              ? 'var(--svg-special-color, #f7d02c)'
              : ratio > 0.15
                ? 'var(--svg-color-active-cell, #4dd2ff)'
                : 'var(--color-text-dim, #666)'
      const seg = { ...m, label: monthNames[m.month - 1], startAngle, endAngle, outerR, color }
      startAngle = endAngle
      return seg
    })
  }, [year, activities])

  const cx = 100,
    cy = 100
  const innerR = 20

  function sectorPath(startAngle: number, endAngle: number, outerR: number) {
    const s = polarToCartesian(cx, cy, innerR, startAngle)
    const e = polarToCartesian(cx, cy, outerR, endAngle)
    const large = endAngle - startAngle > 180 ? 1 : 0
    return `M ${s.x} ${s.y} L ${e.x} ${e.y} A ${outerR} ${outerR} 0 ${large} 1 ${polarToCartesian(cx, cy, outerR, startAngle).x} ${polarToCartesian(cx, cy, outerR, startAngle).y} A ${innerR} ${innerR} 0 ${large} 0 ${s.x} ${s.y} Z`
  }

  return (
    <svg
      viewBox="0 0 200 200"
      xmlns="http://www.w3.org/2000/svg"
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Circular activity poster for ${year}`}
    >
      <title>{`Circular activity poster for ${year}`}</title>
      <rect width={200} height={200} fill="var(--color-bg, #171717)" />
      {segments.map(
        (s) => s.totalDist > 0 && <path key={s.month} d={sectorPath(s.startAngle, s.endAngle, s.outerR)} fill={s.color} opacity={0.85} />,
      )}
      {[0.25, 0.5, 0.75].map((r) => (
        <circle
          key={r}
          cx={cx}
          cy={cy}
          r={innerR + 52 * r}
          fill="none"
          stroke="var(--color-border, #333)"
          strokeWidth={0.5}
          opacity={0.3}
        />
      ))}
      {segments.map((s) => {
        const midAngle = (s.startAngle + s.endAngle) / 2
        const labelR = 82
        const p = polarToCartesian(cx, cy, labelR, midAngle)
        return (
          <text
            key={`l${s.month}`}
            x={p.x}
            y={p.y}
            textAnchor="middle"
            dominantBaseline="central"
            fill="var(--color-text-secondary, #d4d4d4)"
            fontSize={5}
            fontFamily="Arial"
          >
            {s.label}
          </text>
        )
      })}
      <text
        x={cx}
        y={cy}
        textAnchor="middle"
        dominantBaseline="central"
        fill="var(--color-brand, #e0ed5e)"
        fontSize={14}
        fontWeight="bold"
        fontFamily="Arial"
      >
        {year}
      </text>
    </svg>
  )
}
