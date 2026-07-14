import { formatDuration, formatPace } from '@workouts/shared'
import { type SortField, useSimpleStore } from '../store'

export function RunTable() {
  const filtered = useSimpleStore((s) => s.filteredActivities)
  const sortField = useSimpleStore((s) => s.sortField)
  const sortDesc = useSimpleStore((s) => s.sortDesc)
  const toggleSort = useSimpleStore((s) => s.toggleSort)
  const mapHoveredId = useSimpleStore((s) => s.mapHoveredId)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const openDetail = useSimpleStore((s) => s.openDetail)

  function titleForRow(act: (typeof filtered)[0]): string {
    if (act.name && !act.name.startsWith('Running')) return act.name
    if (act.sport_category === 'run') return 'Run'
    return act.name || 'Untitled'
  }

  function sortArrow(field: SortField): string {
    if (sortField !== field) return ''
    return sortDesc ? ' ↓' : ' ↑'
  }

  return (
    <div className="table-container">
      <table className="run-table">
        <thead>
          <tr>
            <th />
            <th className={sortField === 'distance' ? 'sorted' : ''} onClick={() => toggleSort('distance')}>
              km{sortArrow('distance')}
            </th>
            <th className={sortField === 'elevation' ? 'sorted' : ''} onClick={() => toggleSort('elevation')}>
              m{sortArrow('elevation')}
            </th>
            <th>Pace</th>
            <th>BPM</th>
            <th>Time</th>
            <th className={sortField === 'date' ? 'sorted' : ''} onClick={() => toggleSort('date')}>
              Date{sortArrow('date')}
            </th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((act) => (
            <tr
              key={act.run_id}
              className={`run-row${mapHoveredId === act.run_id ? ' selected' : ''}`}
              data-run-id={act.run_id}
              onClick={() => openDetail(act)}
              onMouseEnter={() => setMapHoveredId(act.run_id)}
              onMouseLeave={() => setMapHoveredId(null)}
            >
              <td>{titleForRow(act)}</td>
              <td>{act.distance ? (Math.round(act.distance / 10) / 100).toLocaleString('en-US') : '—'}</td>
              <td className="elevation-col">{act.elevation_gain ? Math.round(act.elevation_gain).toString() : '—'}</td>
              <td>{formatPace(act.average_speed)}</td>
              <td>{act.average_heartrate ? act.average_heartrate.toFixed(0) : '—'}</td>
              <td>{formatDuration(act.moving_time)}</td>
              <td className="run-date">{act.start_date?.slice(0, 10) ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {filtered.length === 0 && (
        <div className="empty-state">
          <p>No activities match your filters</p>
        </div>
      )}
    </div>
  )
}
