import { useOverviewStore } from '../store'
import '../overview.css'

export function Filters() {
  const filters = useOverviewStore((s) => s.filters)
  const availableTypes = useOverviewStore((s) => s.availableTypes)
  const availableSources = useOverviewStore((s) => s.availableSources)
  const stats = useOverviewStore((s) => s.stats)
  const setFilter = useOverviewStore((s) => s.setFilter)
  const resetFilters = useOverviewStore((s) => s.resetFilters)

  return (
    <div className="filters">
      <h3>Filters</h3>

      <label>
        Type
        <select value={filters.type} onChange={(e) => setFilter({ type: e.target.value })}>
          <option value="">All</option>
          {availableTypes.map(([t, c]) => (
            <option key={t} value={t}>
              {t} ({c})
            </option>
          ))}
        </select>
      </label>

      <label>
        Source
        <select value={filters.source} onChange={(e) => setFilter({ source: e.target.value })}>
          <option value="">All</option>
          {availableSources.map(([s, c]) => (
            <option key={s} value={s}>
              {s} ({c})
            </option>
          ))}
        </select>
      </label>

      <label>
        Min distance (km)
        <input
          type="number"
          value={filters.distanceMin ?? ''}
          onChange={(e) => setFilter({ distanceMin: e.target.value ? parseFloat(e.target.value) : null })}
          step="0.5"
          min="0"
          placeholder="0"
        />
      </label>

      <label>
        Max distance (km)
        <input
          type="number"
          value={filters.distanceMax ?? ''}
          onChange={(e) => setFilter({ distanceMax: e.target.value ? parseFloat(e.target.value) : null })}
          step="0.5"
          min="0"
          placeholder="100"
        />
      </label>

      <label>
        Search name
        <input type="text" value={filters.search} onChange={(e) => setFilter({ search: e.target.value })} placeholder="Search…" />
      </label>

      <button type="button" className="reset-btn" onClick={() => resetFilters()}>
        Reset
      </button>

      {stats && (stats as any).streaks?.all_time > 7 && (
        <div className="insights">
          <p className="insight">Longest streak: {(stats as any).streaks.all_time} days</p>
        </div>
      )}
    </div>
  )
}
