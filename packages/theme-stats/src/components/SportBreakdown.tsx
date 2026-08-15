import type { Stats } from '@lax/plugin-data-source'
import { categoryColor } from '@lax/shared'
import { useMemo } from 'react'
import { formatCount, formatDistance, formatHours } from '../format'
import { DEFAULT_T } from '../labels'

export interface SportBreakdownProps {
  stats: Stats
  selected: string | null
  onSelect: (category: string | null) => void
}

export function SportBreakdown({ stats, selected, onSelect }: SportBreakdownProps) {
  const t = DEFAULT_T
  const rows = useMemo(() => [...stats.summary.sport_breakdown].sort((a, b) => b.distance_km - a.distance_km), [stats])
  const total = rows.reduce((acc, r) => acc + r.distance_km, 0)

  if (rows.length === 0) return null
  const active = selected ?? rows[0]!.category

  return (
    <div className="sb">
      <div className="sb-stacked">
        {rows.map((r) => (
          <div
            key={r.category}
            className="sb-seg"
            style={{
              width: `${total > 0 ? (r.distance_km / total) * 100 : 0}%`,
              backgroundColor: categoryColor(r.category),
            }}
            title={`${r.category}: ${formatDistance(r.distance_km)}`}
          />
        ))}
      </div>
      <div className="sb-legend">
        <div className="sb-row sb-head">
          <span>{t('overview.activities')}</span>
          <span>{t('metric.distance')}</span>
          <span>{t('composition.time')}</span>
        </div>
        {rows.map((r) => {
          const isActive = r.category === active
          const dimmed = selected !== null && !isActive
          return (
            <button
              key={r.category}
              type="button"
              className={`sb-row ${isActive ? 'active' : ''} ${dimmed ? 'dimmed' : ''}`}
              onClick={() => onSelect(isActive && selected ? null : r.category)}
            >
              <span className="sb-cat">
                <i className="sb-dot" style={{ backgroundColor: categoryColor(r.category) }} />
                {r.category}
              </span>
              <span>{formatCount(r.count)}</span>
              <span>{formatDistance(r.distance_km)}</span>
              <span>{formatHours(r.moving_time_h)}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
