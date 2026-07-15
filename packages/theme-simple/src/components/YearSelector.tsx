/** YearSelector — vertical year pill filter on map.
 *  All + per-year buttons. Month-chip badge when month is selected.
 *  Position absolute center-left of map wrapper. */

import { useSimpleStore } from '../store'

export function YearSelector() {
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const selectedMonth = useSimpleStore((s) => s.selectedMonth)
  const setSelectedMonth = useSimpleStore((s) => s.setSelectedMonth)
  const years = useSimpleStore((s) => s.years)

  if (years.length === 0) return null

  return (
    <div className="map-year-selector">
      <div className="year-pills">
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
      </div>
      {selectedYear !== null && selectedMonth !== null && (
        <div className="month-chip">
          {selectedYear}-{String(selectedMonth).padStart(2, '0')}
          <button type="button" onClick={() => setSelectedMonth(null)}>
            ×
          </button>
        </div>
      )}
    </div>
  )
}
