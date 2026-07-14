import { formatPace } from '@workouts/shared'
import { useSimpleStore } from '../store'

export function ActivityCardGrid() {
  const filtered = useSimpleStore((s) => s.filteredActivities)
  const mapHoveredId = useSimpleStore((s) => s.mapHoveredId)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const openDetail = useSimpleStore((s) => s.openDetail)

  if (filtered.length === 0) {
    return (
      <div className="empty-state">
        <p>No activities match your filters</p>
      </div>
    )
  }

  const maxDist = Math.max(...filtered.map((a) => a.distance ?? 0), 1)

  return (
    <div className="activity-grid">
      {filtered.map((act) => {
        const distKm = (act.distance ?? 0) / 1000
        const barPct = ((act.distance ?? 0) / maxDist) * 100

        return (
          <div
            key={act.run_id}
            className={`activity-card${mapHoveredId === act.run_id ? ' selected' : ''}`}
            onClick={() => openDetail(act)}
            onMouseEnter={() => setMapHoveredId(act.run_id)}
            onMouseLeave={() => setMapHoveredId(null)}
          >
            <div className="activity-card-row">
              <span className="activity-card-title">{act.name || (act.sport_category === 'run' ? 'Run' : act.sport_category)}</span>
              <span className="activity-card-badge">{act.sport_category}</span>
            </div>
            <div className="activity-card-row">
              <span className="activity-card-stat">
                <strong>{distKm.toFixed(2)}</strong> km
              </span>
              <span className="activity-card-stat">
                <strong>{formatPace(act.average_speed)}</strong> /km
              </span>
            </div>
            <div className="activity-card-row">
              <span className="activity-card-stat">{act.start_date?.slice(0, 10) ?? '—'}</span>
              <span className="activity-card-stat">
                {act.average_heartrate ? (
                  <>
                    <strong>{act.average_heartrate.toFixed(0)}</strong> bpm
                  </>
                ) : null}
              </span>
            </div>
            <div className="activity-card-bar">
              <div className="activity-card-fill" style={{ width: `${barPct}%` }} />
            </div>
          </div>
        )
      })}
    </div>
  )
}
