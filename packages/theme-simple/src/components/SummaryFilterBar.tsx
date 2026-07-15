import { useMemo } from 'react'
import { useSimpleStore } from '../store'

const INTERVALS = ['year', 'month', 'week', 'day', 'life'] as const

export function SummaryFilterBar() {
  const setView = useSimpleStore((s) => s.setView)
  const summaryInterval = useSimpleStore((s) => s.summaryInterval)
  const setSummaryInterval = useSimpleStore((s) => s.setSummaryInterval)
  const summarySportType = useSimpleStore((s) => s.summarySportType)
  const setSummarySportType = useSimpleStore((s) => s.setSummarySportType)
  const activities = useSimpleStore((s) => s.activities)

  const sportTypes = useMemo(() => {
    const s = new Set<string>()
    for (const a of activities) {
      const t = a.sport_category || a.type
      if (t) s.add(t)
    }
    return Array.from(s).sort()
  }, [activities])

  return (
    <div className="filter-bar">
      <button type="button" className="back-btn" onClick={() => setView('main')}>
        ← Back
      </button>
      <div className="filter-group">
        <label htmlFor="summary-type-select">Type</label>
        <select
          id="summary-type-select"
          className="filter-select"
          value={summarySportType}
          onChange={(e) => setSummarySportType(e.target.value)}
        >
          <option value="">All</option>
          {sportTypes.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </div>
      <div className="interval-pills">
        {INTERVALS.map((interval) => (
          <button
            key={interval}
            type="button"
            className={`interval-pill${summaryInterval === interval ? ' active' : ''}`}
            onClick={() => setSummaryInterval(interval)}
          >
            {interval.charAt(0).toUpperCase() + interval.slice(1)}
          </button>
        ))}
      </div>
    </div>
  )
}
