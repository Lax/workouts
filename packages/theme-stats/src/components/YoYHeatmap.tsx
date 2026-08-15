import type { Stats } from '@lax/plugin-data-source'
import { useMemo, useState } from 'react'
import { buildMonthYearMatrix, linearScale } from '../charts'
import { formatCount, formatDelta, formatDistance } from '../format'
import { DEFAULT_T } from '../labels'

const CELL_W = 56
const CELL_H = 22
const ROW_LABEL_W = 40
const COL_LABEL_H = 20
const W = ROW_LABEL_W + 12 * CELL_W + 12
const H = COL_LABEL_H + 12 * CELL_H + 8

export function YoYHeatmap({ stats }: { stats: Stats }) {
  const t = DEFAULT_T
  const matrix = useMemo(() => buildMonthYearMatrix(stats), [stats])
  const [hovered, setHovered] = useState<string | null>(null)
  const colorScale = linearScale([0, matrix.maxDistance || 1], [0.12, 1])

  const hoveredCell = hovered ? matrix.cells.find((c) => `${c.year}-${c.month}` === hovered) : null
  const delta =
    hoveredCell &&
    hoveredCell.prev &&
    hoveredCell.prev.distance_km !== null &&
    hoveredCell.distance_km !== null &&
    hoveredCell.prev.distance_km > 0
      ? ((hoveredCell.distance_km - hoveredCell.prev.distance_km) / hoveredCell.prev.distance_km) * 100
      : null

  return (
    <div className="yoy">
      <svg viewBox={`0 0 ${W} ${H}`} className="yoy-svg">
        {matrix.years.map((year, ci) => (
          <text key={year} x={ROW_LABEL_W + ci * CELL_W + CELL_W / 2} y={COL_LABEL_H - 6} textAnchor="middle" className="yoy-year">
            {year}
          </text>
        ))}
        {matrix.cells.map((cell) => {
          const ci = matrix.years.indexOf(cell.year)
          const key = `${cell.year}-${cell.month}`
          const active = hovered === key
          const has = cell.distance_km !== null
          const opacity = has ? colorScale(cell.distance_km!) : 0.06
          return (
            <rect
              key={key}
              x={ROW_LABEL_W + ci * CELL_W}
              y={COL_LABEL_H + (cell.month - 1) * CELL_H}
              width={CELL_W - 2}
              height={CELL_H - 2}
              rx={3}
              className={`yoy-cell ${has ? 'has' : 'empty'} ${active ? 'active' : ''}`}
              opacity={active && has ? 1 : opacity}
              onMouseEnter={() => setHovered(key)}
              onMouseLeave={() => setHovered(null)}
            />
          )
        })}
        {Array.from({ length: 12 }, (_, r) => (
          <text key={r} x={ROW_LABEL_W - 8} y={COL_LABEL_H + r * CELL_H + CELL_H / 2 + 1} textAnchor="end" className="yoy-month">
            {r + 1}月
          </text>
        ))}
      </svg>
      {hoveredCell ? (
        <div className="yoy-tooltip">
          <div className="yoy-tooltip-title">
            {hoveredCell.year}-{String(hoveredCell.month).padStart(2, '0')}
          </div>
          <div>
            {t('metric.distance')}: {hoveredCell.distance_km !== null ? formatDistance(hoveredCell.distance_km) : '—'}
          </div>
          <div>
            {t('overview.activities')}: {hoveredCell.count !== null ? formatCount(hoveredCell.count) : '—'}
          </div>
          <div>
            {t('period.sameMonthLastYear')}: {delta !== null ? formatDelta(delta) : '—'}
          </div>
        </div>
      ) : null}
    </div>
  )
}
