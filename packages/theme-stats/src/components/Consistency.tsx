import type { Stats } from '@lax/plugin-data-source'
import { useMemo } from 'react'
import { linearScale } from '../charts'
import { DEFAULT_T } from '../labels'

const W = 640
const PLOT_LEFT = 8
const PLOT_RIGHT = W - 8
const PLOT_WIDTH = PLOT_RIGHT - PLOT_LEFT
const PLOT_TOP = 14
const PLOT_H = 90
const PLOT_BOTTOM = PLOT_TOP + PLOT_H

export function Consistency({ stats }: { stats: Stats }) {
  const t = DEFAULT_T
  const years = useMemo(() => stats.yearly, [stats])
  const maxStreak = Math.max(1, ...years.map((y) => y.streak))
  const y = linearScale([0, maxStreak], [PLOT_BOTTOM, PLOT_TOP])
  const n = years.length
  const xAt = (i: number): number => (n > 1 ? PLOT_LEFT + (PLOT_WIDTH * i) / (n - 1) : PLOT_LEFT + PLOT_WIDTH / 2)

  return (
    <div className="cs">
      <div className="cs-cards">
        <div className="cs-card">
          <span className="cs-label">{t('consistency.current')}</span>
          <span className="cs-value">{stats.streaks.current}</span>
          <span className="cs-unit">{t('overview.days')}</span>
        </div>
        <div className="cs-card">
          <span className="cs-label">{t('consistency.allTime')}</span>
          <span className="cs-value">{stats.streaks.all_time}</span>
          <span className="cs-unit">{t('overview.days')}</span>
        </div>
      </div>
      <div className="cs-yearly">
        <span className="cs-yearly-label">{t('consistency.yearly')}</span>
        <svg viewBox={`0 0 ${W} ${PLOT_BOTTOM + 24}`} className="cs-svg">
          {years.map((yr, i) => {
            const cx = xAt(i)
            return (
              <g key={yr.year}>
                <rect
                  x={cx - 3}
                  y={y(yr.streak)}
                  width={6}
                  height={Math.max(1, PLOT_BOTTOM - y(yr.streak))}
                  className="cs-bar"
                />
                <text x={cx} y={PLOT_BOTTOM + 16} textAnchor="middle" className="cs-year">
                  {String(yr.year).slice(2)}
                </text>
              </g>
            )
          })}
          <line x1={PLOT_LEFT} y1={PLOT_BOTTOM} x2={PLOT_RIGHT} y2={PLOT_BOTTOM} className="pane-axis" />
        </svg>
      </div>
    </div>
  )
}
