import { computePeriods3, computeProvinceStats, computeTypeBreakdown } from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { useSimpleStore } from './store'
import './stats-panel.css'

interface StatsPanelProps {
  activities: Activity[]
  loading?: boolean
}

export function StatsPanel({ activities, loading }: StatsPanelProps) {
  const regionFilter = useSimpleStore((s) => s.regionFilter)
  const period3Filter = useSimpleStore((s) => s.period3Filter)
  const typeFilter = useSimpleStore((s) => s.typeFilter)
  const setRegionFilter = useSimpleStore((s) => s.setRegionFilter)
  const setPeriod3Filter = useSimpleStore((s) => s.setPeriod3Filter)
  const setTypeFilter = useSimpleStore((s) => s.setTypeFilter)

  const regionStats = useMemo(() => computeProvinceStats(activities), [activities])
  const periods3 = useMemo(() => computePeriods3(activities), [activities])
  const typeBreakdown = useMemo(() => computeTypeBreakdown(activities), [activities])

  const showTypeSection = typeBreakdown.length >= 2

  if (loading) {
    return (
      <section className="stats-panel">
        <div className="sp-summary">
          <span className="sp-loading">Loading...</span>
        </div>
      </section>
    )
  }

  return (
    <section className="stats-panel">
      {regionStats.length > 0 && (
        <>
          <div className="sp-summary">
            <span className="sp-summary-text">{regionStats.length} 个地区</span>
          </div>
          <hr className="section-divider" />
          <div className="sp-regions">
            {regionStats.map((r) => (
              <div
                key={r.province}
                className={`sp-region-row${regionFilter === r.province ? ' active' : ''}`}
                onClick={() => setRegionFilter(r.province)}
              >
                <span className="sp-region-name">{r.province}</span>
                <span className="sp-region-bar">
                  <span
                    className="sp-region-fill"
                    style={{
                      width: `${regionStats.length > 1 ? Math.round((r.distance / regionStats[0].distance) * 100) : 100}%`,
                    }}
                  />
                </span>
                <span className="sp-region-dist">{(r.distance / 1000).toFixed(0)} km</span>
              </div>
            ))}
          </div>
        </>
      )}

      {regionStats.length === 0 && (
        <div className="sp-summary">
          <span className="sp-summary-text sp-empty">暂无位置数据</span>
        </div>
      )}

      {periods3.length > 0 && (
        <>
          <hr className="section-divider" />
          <div className="sp-periods">
            {periods3.map((p) => (
              <div
                key={p.period}
                className={`sp-period-row${period3Filter === p.period ? ' active' : ''}`}
                onClick={() => setPeriod3Filter(p.period)}
              >
                <span className="sp-period-label">{p.label}</span>
                <span className="sp-period-bar">
                  <span className="sp-period-fill" style={{ width: `${p.pct}%` }} />
                </span>
                <span className="sp-period-count">{p.count} 次</span>
                <span className="sp-period-pct">{p.pct}%</span>
              </div>
            ))}
          </div>
        </>
      )}

      {showTypeSection && (
        <>
          <hr className="section-divider" />
          <div className="sp-types">
            {typeBreakdown.map((t) => (
              <div key={t.type} className={`sp-type-row${typeFilter === t.type ? ' active' : ''}`} onClick={() => setTypeFilter(t.type)}>
                <span className="sp-type-label">{t.label}</span>
                <span className="sp-type-bar">
                  <span className="sp-type-fill" style={{ width: `${t.pct}%` }} />
                </span>
                <span className="sp-type-count">{t.count} 次</span>
                <span className="sp-type-dist">{(t.distance / 1000).toFixed(0)} km</span>
              </div>
            ))}
          </div>
        </>
      )}
    </section>
  )
}
