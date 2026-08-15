import type { Stats } from '@lax/plugin-data-source'
import { useMemo } from 'react'
import { buildYearlySeries, linearScale, niceMax } from '../charts'
import { formatCount, formatDistance, formatHours } from '../format'
import { DEFAULT_T } from '../labels'

const W = 960
const PLOT_LEFT = 46
const PLOT_RIGHT = W - 14
const PLOT_WIDTH = PLOT_RIGHT - PLOT_LEFT
const PLOT_TOP = 14
const PLOT_H = 170
const PLOT_BOTTOM = PLOT_TOP + PLOT_H

export interface YearlyChartProps {
  stats: Stats
  selectedYear: number | null
  onSelectYear: (year: number) => void
  hoveredYear: number | null
  onHoverYear: (year: number | null) => void
}

export function YearlyChart({ stats, selectedYear, onSelectYear, hoveredYear, onHoverYear }: YearlyChartProps) {
  const t = DEFAULT_T
  const years = useMemo(() => buildYearlySeries(stats), [stats])
  const n = years.length
  const xAt = (i: number): number => (n > 1 ? PLOT_LEFT + (PLOT_WIDTH * i) / (n - 1) : PLOT_LEFT + PLOT_WIDTH / 2)
  const y = linearScale([0, niceMax(years.map((y) => y.distance_km))], [PLOT_BOTTOM, PLOT_TOP])
  const barW = Math.max(2, (PLOT_WIDTH / n) * 0.6)
  const maxStreak = Math.max(1, ...years.map((y) => y.streak))
  const streakY = linearScale([0, maxStreak], [PLOT_BOTTOM, PLOT_TOP])
  const hovered = years.find((y) => y.year === hoveredYear)

  return (
    <div className="yc">
      <svg viewBox={`0 0 ${W} ${PLOT_BOTTOM + 28}`} className="yc-svg">
        {years.map((yr, i) => {
          const selected = yr.year === selectedYear
          const hover = yr.year === hoveredYear
          const cx = xAt(i)
          return (
            <g key={yr.year}>
              <rect
                x={cx - barW / 2}
                y={y(yr.distance_km)}
                width={barW}
                height={Math.max(1, PLOT_BOTTOM - y(yr.distance_km))}
                className={`yc-bar ${selected ? 'selected' : ''} ${hover ? 'hover' : ''}`}
                onClick={() => onSelectYear(yr.year)}
                onMouseEnter={() => onHoverYear(yr.year)}
                onMouseLeave={() => onHoverYear(null)}
              />
              <circle
                cx={cx}
                cy={streakY(yr.streak)}
                r={3}
                className="yc-streak-dot"
                onClick={() => onSelectYear(yr.year)}
                onMouseEnter={() => onHoverYear(yr.year)}
                onMouseLeave={() => onHoverYear(null)}
              />
              <text x={cx} y={PLOT_BOTTOM + 18} textAnchor="middle" className="yc-year">
                {yr.year}
              </text>
            </g>
          )
        })}
        <line x1={PLOT_LEFT} y1={PLOT_BOTTOM} x2={PLOT_RIGHT} y2={PLOT_BOTTOM} className="pane-axis" />
      </svg>
      {hovered ? (
        <div className="yc-tooltip">
          <div className="yc-tooltip-title">{hovered.year}</div>
          <div>
            {t('metric.distance')}: {formatDistance(hovered.distance_km)}
          </div>
          <div>
            {t('overview.activities')}: {formatCount(hovered.count)}
          </div>
          <div>
            {t('overview.totalTime')}: {formatHours(hovered.moving_time_h)}
          </div>
          <div>
            {t('yearly.longest')}: {formatDistance(hovered.longest_km)}
          </div>
          <div>
            {t('consistency.yearly')}: {hovered.streak} {t('overview.days')}
          </div>
        </div>
      ) : null}
      <p className="yc-hint">{t('yearly.detail')} → {t('monthly.title')}</p>
    </div>
  )
}
