import type { Stats } from '@lax/plugin-data-source'
import { useMemo, useState } from 'react'
import { buildYearMonths, linearScale, niceMax, type VolumeMetric } from '../charts'
import { formatDistance } from '../format'
import { DEFAULT_T } from '../labels'

const W = 960
const PLOT_LEFT = 46
const PLOT_RIGHT = W - 14
const PLOT_WIDTH = PLOT_RIGHT - PLOT_LEFT
const PLOT_TOP = 14
const PLOT_H = 140
const PLOT_BOTTOM = PLOT_TOP + PLOT_H

export function MonthlyChart({ stats, year, metric }: { stats: Stats; year: number; metric: VolumeMetric }) {
  const t = DEFAULT_T
  const months = useMemo(() => buildYearMonths(stats, year), [stats, year])
  const [hovered, setHovered] = useState<number | null>(null)
  const xAt = (i: number): number => PLOT_LEFT + (PLOT_WIDTH * i) / 11
  const y = linearScale([0, niceMax(months.map((m) => m[metric]))], [PLOT_BOTTOM, PLOT_TOP])
  const barW = Math.max(2, (PLOT_WIDTH / 12) * 0.62)
  const active = hovered !== null ? months[hovered] : null

  return (
    <div className="mc">
      <svg viewBox={`0 0 ${W} ${PLOT_BOTTOM + 28}`} className="mc-svg">
        {months.map((m, i) => {
          const v = m[metric]
          const cx = xAt(i)
          return (
            <g key={i}>
              <rect
                x={cx - barW / 2}
                y={y(v)}
                width={barW}
                height={Math.max(1, PLOT_BOTTOM - y(v))}
                className={`mc-bar ${i === hovered ? 'hover' : ''} ${v === 0 ? 'empty' : ''}`}
                onMouseEnter={() => setHovered(i)}
                onMouseLeave={() => setHovered(null)}
              />
              <text x={cx} y={PLOT_BOTTOM + 18} textAnchor="middle" className="mc-month">
                {m.month}
              </text>
            </g>
          )
        })}
        <line x1={PLOT_LEFT} y1={PLOT_BOTTOM} x2={PLOT_RIGHT} y2={PLOT_BOTTOM} className="pane-axis" />
      </svg>
      {active ? (
        <div className="mc-tooltip">
          <div className="mc-tooltip-title">
            {year}-{String(active.month).padStart(2, '0')}
          </div>
          <div>
            {t('metric.distance')}: {formatDistance(active.distance_km)}
          </div>
          <div>
            {t('overview.activities')}: {active.count}
          </div>
          <div>
            {t('trend.pace')}: {active.avg_pace ?? '—'}
          </div>
          {active.avg_hr !== null ? (
            <div>
              {t('trend.hr')}: {Math.round(active.avg_hr)} bpm
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
