import { type SortField, useSimpleStore } from '../store'

export function RunTable() {
  const filtered = useSimpleStore((s) => s.filteredActivities)
  const sortField = useSimpleStore((s) => s.sortField)
  const sortDesc = useSimpleStore((s) => s.sortDesc)
  const toggleSort = useSimpleStore((s) => s.toggleSort)
  const mapHoveredId = useSimpleStore((s) => s.mapHoveredId)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const openDetail = useSimpleStore((s) => s.openDetail)

  function formatTime(sec: number | null): string {
    if (sec === null || sec === undefined) return '—'
    const m = Math.floor(sec / 60)
    if (m < 60) return `${m}min`
    return `${Math.floor(m / 60)}h ${m % 60}min`
  }

  function formatPace(speed: number | null): string {
    if (speed === null || speed <= 0) return '—'
    const pace = 1000 / (speed * 60)
    const min = Math.floor(pace)
    const sec = Math.round((pace - min) * 60)
    return `${min}'${sec.toString().padStart(2, '0')}"`
  }

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
              <td>{act.distance ? intComma(Math.round(act.distance / 10) / 100) : '—'}</td>
              <td className="elevation-col">{act.elevation_gain ? Math.round(act.elevation_gain).toString() : '—'}</td>
              <td>{formatPace(act.average_speed)}</td>
              <td>{act.average_heartrate ? act.average_heartrate.toFixed(0) : '—'}</td>
              <td>{formatTime(act.moving_time)}</td>
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

function intComma(n: number): string {
  return n.toLocaleString('en-US')
}
