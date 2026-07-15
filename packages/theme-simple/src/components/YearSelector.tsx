/** YearSelector — horizontal year filter on map.
 *  All + per-year buttons, position absolute top-left of map wrapper.
 *  Maps to running_page RunMapButtons behavior. */

import { useSimpleStore } from '../store'

export function YearSelector() {
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const years = useSimpleStore((s) => s.years)

  if (years.length === 0) return null

  return (
    <div className="map-year-selector">
      <ul>
        <li className={selectedYear === null ? 'selected' : ''} onClick={() => setSelectedYear(null)}>
          All
        </li>
        {years.map((y) => (
          <li key={y} className={selectedYear === y ? 'selected' : ''} onClick={() => setSelectedYear(selectedYear === y ? null : y)}>
            {y}
          </li>
        ))}
      </ul>
    </div>
  )
}
