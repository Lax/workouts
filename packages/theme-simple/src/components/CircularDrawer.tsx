/**
 * CircularDrawer — ring chart showing individual activity arcs.
 * Matches upstream year_YYYY.svg: each activity is a colored arc on the ring.
 * Angle = day of year, extent = distance, color = intensity gradient from red to green.
 */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface CircularDrawerProps {
  year: number
  activities: Activity[]
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
const INNER_R = 52
const OUTER_R = 86
const ARC_DEG = 0.12
const CX = 100
const CY = 100

function colorForDist(ratio: number): string {
  if (ratio <= 0) return '#333'
  const r = Math.round(255 * Math.max(0, 1 - ratio * 1.2))
  const g = Math.round(140 + 115 * Math.min(1, ratio * 1.2))
  const b = Math.round(8 * Math.max(0, 1 - ratio * 1.5))
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
}

function polarToCartesian(r: number, deg: number) {
  const rad = ((deg - 90) * Math.PI) / 180
  return { x: CX + r * Math.cos(rad), y: CY + r * Math.sin(rad) }
}

export function CircularDrawer({ year, activities }: CircularDrawerProps) {
  const arcs = useMemo(() => {
    const yearActs = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
    if (yearActs.length === 0) return []

    const maxDist = Math.max(...yearActs.map((a) => a.distance ?? 0), 1)
    const startMs = new Date(year, 0, 1).getTime()
    const yearMs = new Date(year, 11, 31).getTime() - startMs

    return yearActs.map((a) => {
      const dayMs = new Date(a.start_date!).getTime() - startMs
      const angle = (dayMs / yearMs) * 360 - 90
      const ratio = (a.distance ?? 0) / maxDist
      const extent = INNER_R + (OUTER_R - INNER_R) * ratio ** 0.4
      return { angle, extent, ratio, key: a.run_id }
    })
  }, [year, activities])

  function arcPath(angle: number, extent: number) {
    const innerA = polarToCartesian(INNER_R, angle)
    const innerB = polarToCartesian(INNER_R, angle + ARC_DEG)
    const outerA = polarToCartesian(extent, angle)
    const outerB = polarToCartesian(extent, angle + ARC_DEG)
    return `M ${innerA.x} ${innerA.y} L ${outerA.x} ${outerA.y} A ${extent} ${extent} 0 0 0 ${outerB.x} ${outerB.y} L ${innerB.x} ${innerB.y} A ${INNER_R} ${INNER_R} 0 0 1 ${innerA.x} ${innerA.y} Z`
  }

  return (
    <svg
      viewBox="0 0 200 200"
      xmlns="http://www.w3.org/2000/svg"
      style={{ width: '100%', height: 'auto' }}
      role="img"
      aria-label={`Activity ring for ${year}`}
    >
      <title>{`Activity ring for ${year}`}</title>
      <rect width={200} height={200} fill="var(--color-bg, #171717)" />
      <circle cx={CX} cy={CY} r={INNER_R} fill="none" stroke="var(--color-border, #333)" strokeWidth={0.5} opacity={0.3} />
      <circle cx={CX} cy={CY} r={OUTER_R} fill="none" stroke="var(--color-border, #333)" strokeWidth={0.5} opacity={0.3} />
      {[...arcs]
        .sort((a, b) => b.extent - a.extent)
        .map((a) => (
          <path key={a.key} d={arcPath(a.angle, a.extent)} fill={colorForDist(a.ratio)} opacity={0.85} />
        ))}
      {MONTH_NAMES.map((name, i) => {
        const p = polarToCartesian(95, -90 + (i + 0.5) * 30)
        return (
          <text
            key={name}
            x={p.x}
            y={p.y}
            textAnchor="middle"
            dominantBaseline="central"
            fill="var(--color-text-secondary, #d4d4d4)"
            fontSize={4.5}
            fontFamily="Arial"
          >
            {name.slice(0, 3)}
          </text>
        )
      })}
      <text
        x={CX}
        y={CY}
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
