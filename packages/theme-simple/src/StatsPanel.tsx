import { computePeriods3, computeTypeBreakdown } from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { useSimpleStore } from './store'
import './stats-panel.css'

interface StatsPanelProps {
  activities: Activity[]
  loading?: boolean
}

interface RegionStat {
  name: string
  distance: number
  count: number
}

function computeRegionStats(activities: Activity[]): RegionStat[] {
  const regionDist = new Map<string, number>()
  const regionCount = new Map<string, number>()
  for (const a of activities) {
    const regions = a.divisions
    if (!regions || regions.length === 0) {
      // Fallback: try text-based province from location_country
      if (a.location_country) {
        const province = extractProvince(a.location_country)
        if (province) {
          regionDist.set(province, (regionDist.get(province) ?? 0) + (a.distance ?? 0))
          regionCount.set(province, (regionCount.get(province) ?? 0) + 1)
        }
      }
      continue
    }
    const dist = a.distance ?? 0
    for (const r of regions) {
      const province = r.p
      const weight = r.w ?? 1 / regions.length
      regionDist.set(province, (regionDist.get(province) ?? 0) + dist * weight)
    }
    regionCount.set(regions[0].p, (regionCount.get(regions[0].p) ?? 0) + 1)
  }
  return [...regionDist.entries()]
    .map(([name, distance]) => ({ name, distance, count: regionCount.get(name) ?? 0 }))
    .sort((a, b) => b.distance - a.distance)
}

function extractProvince(loc: string): string | null {
  const known = ['北京', '天津', '上海', '重庆'] as const
  for (const k of known) {
    if (loc.includes(k)) return k
  }
  const m = loc.match(/(.{2,4}?(?:省|自治区|特别行政区))/)
  return m?.[1] ?? null
}

export function StatsPanel({ activities, loading }: StatsPanelProps) {
  const regionFilter = useSimpleStore((s) => s.regionFilter)
  const period3Filter = useSimpleStore((s) => s.period3Filter)
  const typeFilter = useSimpleStore((s) => s.typeFilter)
  const setRegionFilter = useSimpleStore((s) => s.setRegionFilter)
  const setPeriod3Filter = useSimpleStore((s) => s.setPeriod3Filter)
  const setTypeFilter = useSimpleStore((s) => s.setTypeFilter)

  const regionStats = useMemo(() => computeRegionStats(activities), [activities])
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
                key={r.name}
                className={`sp-region-row${regionFilter === r.name ? ' active' : ''}`}
                onClick={() => setRegionFilter(r.name)}
              >
                <span className="sp-region-name">{r.name}</span>
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
