/** YearSelector — vertical year pill filter on map.
 *  All + per-year buttons, plus month pills when a year is selected.
 *  Position absolute center-left of map wrapper. */

import { useSimpleStore } from '../store'

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

export function YearSelector() {
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const selectedMonth = useSimpleStore((s) => s.selectedMonth)
  const setSelectedMonth = useSimpleStore((s) => s.setSelectedMonth)
  const years = useSimpleStore((s) => s.years)

  if (years.length === 0) return null

  return (
    <div className="map-year-selector">
      <div className={`year-pills${selectedYear !== null ? ' year-pills--month-view' : ''}`}>
        <button type="button" className={`year-pill${selectedYear === null ? ' active' : ''}`} onClick={() => setSelectedYear(null)}>
          All
        </button>
        {years.map((y) => (
          <button
            key={y}
            type="button"
            className={`year-pill${selectedYear === y ? ' active' : ''}`}
            onClick={() => setSelectedYear(selectedYear === y ? null : y)}
          >
            {y}
          </button>
        ))}
        {selectedYear !== null && (
          <div className="month-pills">
            {MONTH_NAMES.map((name, i) => {
              const m = i + 1
              const isActive = selectedMonth === m
              if (isActive) {
                return (
                  <span key={name} className="year-pill-label">
                    {name}
                  </span>
                )
              }
              return (
                <button key={name} type="button" className="year-pill" onClick={() => setSelectedMonth(m)}>
                  {name}
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
