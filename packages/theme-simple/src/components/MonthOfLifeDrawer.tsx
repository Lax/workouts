/** MonthOfLifeDrawer — draws a month-of-life poster.
 *  Maps to upstream MonthOfLifeDrawer / --type monthoflife / mol.svg.
 *  Grid of months from birth to present, each cell = one month.
 *  Color intensity = monthly aggregate distance. */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'

interface MonthOfLifeDrawerProps {
  activities: Activity[]
  birthYear?: number
  birthMonth?: number
}

export function MonthOfLifeDrawer({ activities, birthYear = 1990, birthMonth = 1 }: MonthOfLifeDrawerProps) {
  const now = new Date()
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth() + 1
  const totalMonths = (currentYear - birthYear) * 12 + (currentMonth - birthMonth)
  const maxMonths = Math.min(totalMonths, 1200)

  const months = useMemo(() => {
    const map = new Map<string, number>()
    for (const a of activities) {
      if (!a.start_date) continue
      const d = new Date(a.start_date)
      const key = `${d.getFullYear()}-${d.getMonth() + 1}`
      map.set(key, (map.get(key) ?? 0) + (a.distance ?? 0))
    }
    const maxDist = Math.max(...map.values(), 1)
    const result: { age: string; dist: number; color: string; isFuture: boolean; key: string }[] = []
    for (let i = 0; i < Math.min(maxMonths, 1200); i++) {
      const y = birthYear + Math.floor((birthMonth - 1 + i) / 12)
      const m = ((birthMonth - 1 + i) % 12) + 1
      const key = `${y}-${m}`
      const dist = map.get(key) ?? 0
      const isFuture = y > currentYear || (y === currentYear && m > currentMonth)
      const age = y - birthYear + (m - birthMonth) / 12
      const ratio = dist / maxDist
      const color = isFuture
        ? '#333'
        : dist === 0
          ? '#444'
          : ratio > 0.7
            ? '#ff4500'
            : ratio > 0.4
              ? '#ff8c00'
              : ratio > 0.15
                ? '#4dd2ff'
                : '#555'
      result.push({ age: `${Math.floor(age)}y`, dist, color, isFuture, key })
    }
    return result
  }, [activities, birthYear, birthMonth, maxMonths, currentYear, currentMonth])

  const cols = Math.max(1, Math.round(Math.sqrt(maxMonths * 1.6)))
  const cellSize = 8,
    gap = 2

  return (
    <div style={{ padding: '0.5rem' }}>
      <div style={{ fontSize: 10, color: 'var(--color-text-dim, #666)', marginBottom: 4 }}>Month of Life</div>
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, ${cellSize}px)`, gap }}>
        {months.map((m) => (
          <div
            key={m.key}
            style={{ width: cellSize, height: cellSize, borderRadius: '50%', background: m.color }}
            title={`${m.age}: ${(m.dist / 1000).toFixed(1)}km`}
          />
        ))}
      </div>
    </div>
  )
}
