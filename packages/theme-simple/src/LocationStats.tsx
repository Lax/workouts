import { computeCities, computeLocationSummary, computePeriods } from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { useSimpleStore } from './store'
import './location-stats.css'

interface LocationStatsProps {
  activities: Activity[]
}

export function LocationStats({ activities }: LocationStatsProps) {
  const cityFilter = useSimpleStore((s) => s.cityFilter)
  const periodFilter = useSimpleStore((s) => s.periodFilter)
  const setCityFilter = useSimpleStore((s) => s.setCityFilter)
  const setPeriodFilter = useSimpleStore((s) => s.setPeriodFilter)

  const cities = useMemo(() => computeCities(activities), [activities])
  const periods = useMemo(() => computePeriods(activities), [activities])
  const summary = useMemo(() => computeLocationSummary(activities), [activities])

  return (
    <section className="location-stats">
      <div className="loc-summary">
        {summary.countries.length > 0 || summary.provinces.length > 0 || summary.cities.length > 0 ? (
          <span className="loc-summary-text">
            {summary.countries.length} 个国家 / {summary.provinces.length} 个省份 / {summary.cities.length} 个城市
          </span>
        ) : (
          <span className="loc-summary-text loc-empty">暂无位置数据</span>
        )}
      </div>

      {cities.length > 0 && (
        <>
          <hr className="section-divider" />
          <div className="loc-cities">
            {cities.map((c) => (
              <div key={c.city} className={`loc-city-row${cityFilter === c.city ? ' active' : ''}`} onClick={() => setCityFilter(c.city)}>
                <span className="loc-city-name">{c.city}</span>
                <span className="loc-city-dist">{(c.distance / 1000).toFixed(0)} km</span>
              </div>
            ))}
          </div>
        </>
      )}

      {periods.length > 0 && (
        <>
          <hr className="section-divider" />
          <div className="loc-periods">
            {periods.map((p) => (
              <div
                key={p.period}
                className={`loc-period-row${periodFilter === p.period ? ' active' : ''}`}
                onClick={() => setPeriodFilter(p.period)}
              >
                <span className="loc-period-label">{p.label}</span>
                <span className="loc-period-bar">
                  <span className="loc-period-fill" style={{ width: `${p.pct}%` }} />
                </span>
                <span className="loc-period-count">{p.count} 次</span>
                <span className="loc-period-pct">{p.pct}%</span>
              </div>
            ))}
          </div>
        </>
      )}
    </section>
  )
}
