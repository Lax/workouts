import { decodePolyline } from '@workouts/plugin-map'
import { activityColor, formatDate, formatDistance, formatDuration } from '@workouts/shared'
import { useMemo } from 'react'
import { useOverviewStore } from '../store'
import '../overview.css'

interface SvgPathData {
  points: string
  sx: number
  sy: number
  ex: number
  ey: number
  hasPath: boolean
}

function normalizeSvg(pts: [number, number][]): SvgPathData {
  let minLat = Infinity,
    maxLat = -Infinity
  let minLng = Infinity,
    maxLng = -Infinity
  for (const [lat, lng] of pts) {
    if (lat < minLat) minLat = lat
    if (lat > maxLat) maxLat = lat
    if (lng < minLng) minLng = lng
    if (lng > maxLng) maxLng = lng
  }
  const rLng = maxLng - minLng || 1
  const rLat = maxLat - minLat || 1
  const W = 60,
    H = 24,
    pad = 3
  const scale = Math.min((W - pad * 2) / rLng, (H - pad * 2) / rLat)
  const ox = (W - rLng * scale) / 2
  const oy = (H - rLat * scale) / 2
  const coords = pts.map(([lat, lng]) => ({
    x: ox + (lng - minLng) * scale,
    y: oy + (maxLat - lat) * scale,
  }))
  return {
    points: coords.map((c) => `${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' '),
    sx: coords[0].x,
    sy: coords[0].y,
    ex: coords[coords.length - 1].x,
    ey: coords[coords.length - 1].y,
    hasPath: true,
  }
}

function srcBadge(source: string | null): string {
  const map: Record<string, string> = {
    garmin: 'G',
    garmin_cn: 'GC',
    strava: 'S',
    keep: 'K',
    igpsport: 'iG',
    xoss: 'X',
    xingzhe: 'XZ',
  }
  return map[source ?? ''] ?? source?.charAt(0).toUpperCase() ?? '?'
}

export function ActivityList() {
  const filtered = useOverviewStore((s) => s.filteredActivities)
  const sortField = useOverviewStore((s) => s.sortField)
  const sortDesc = useOverviewStore((s) => s.sortDesc)
  const toggleSort = useOverviewStore((s) => s.toggleSort)
  const openDetail = useOverviewStore((s) => s.openDetail)
  const mapHoveredId = useOverviewStore((s) => s.mapHoveredId)
  const setMapHoveredId = useOverviewStore((s) => s.setMapHoveredId)
  const colorMode = useOverviewStore((s) => s.colorMode)

  const pathCache = useMemo(() => {
    const cache = new Map<string, SvgPathData>()
    for (const a of filtered) {
      const encoded = a.summary_polyline
      if (!encoded) {
        cache.set(a.run_id, { points: '', sx: 0, sy: 0, ex: 0, ey: 0, hasPath: false })
        continue
      }
      const pts = decodePolyline(encoded)
      if (pts.length < 2) {
        cache.set(a.run_id, { points: '', sx: 0, sy: 0, ex: 0, ey: 0, hasPath: false })
        continue
      }
      cache.set(a.run_id, normalizeSvg(pts))
    }
    return cache
  }, [filtered])

  return (
    <>
      <div className="list-header">
        <span className="count">{filtered.length} activities</span>
        <div className="sort-group">
          <button type="button" className={`sort-btn${sortField === 'date' ? ' active' : ''}`} onClick={() => toggleSort('date')}>
            Date {sortField === 'date' ? (sortDesc ? '↓' : '↑') : ''}
          </button>
          <button type="button" className={`sort-btn${sortField === 'distance' ? ' active' : ''}`} onClick={() => toggleSort('distance')}>
            Dist {sortField === 'distance' ? (sortDesc ? '↓' : '↑') : ''}
          </button>
          <button type="button" className={`sort-btn${sortField === 'time' ? ' active' : ''}`} onClick={() => toggleSort('time')}>
            Time {sortField === 'time' ? (sortDesc ? '↓' : '↑') : ''}
          </button>
        </div>
      </div>
      <div className="list">
        {filtered.length === 0 ? (
          <div className="empty-state">
            <p>No activities match your filters</p>
          </div>
        ) : (
          filtered.map((act) => {
            const col = activityColor({ average_speed: act.average_speed, type: act.sport_category }, colorMode)
            const svg = pathCache.get(act.run_id)
            return (
              <button
                type="button"
                key={act.run_id}
                className={`activity-row${mapHoveredId === act.run_id ? ' hovered' : ''}`}
                onClick={() => openDetail(act)}
                onMouseEnter={() => setMapHoveredId(act.run_id)}
                onMouseLeave={() => setMapHoveredId(null)}
              >
                {svg?.hasPath ? (
                  <svg
                    viewBox="0 0 60 24"
                    width="60"
                    height="24"
                    className="mini-svg"
                    role="img"
                    aria-label={`Route for ${act.name || 'activity'}`}
                  >
                    <title>{`Route for ${act.name || 'activity'}`}</title>
                    <polyline points={svg.points} stroke={col} className="mini-path" />
                    <circle cx={svg.sx} cy={svg.sy} r="2" fill={col} className="mini-endpoint" />
                    <circle cx={svg.ex} cy={svg.ey} r="2" fill={col} className="mini-endpoint" />
                  </svg>
                ) : (
                  <svg
                    viewBox="0 0 60 24"
                    width="60"
                    height="24"
                    className="mini-svg"
                    role="img"
                    aria-label={`${act.sport_category || 'activity'} icon`}
                  >
                    <title>{`${act.sport_category || 'activity'} icon`}</title>
                    <circle cx="30" cy="12" r="6" fill={col} />
                  </svg>
                )}
                <div className="info">
                  <span className="name">
                    {act.name || 'Untitled'}
                    <span className="badge">{srcBadge(act.source)}</span>
                  </span>
                  <span className="date">{formatDate(act.start_date)}</span>
                </div>
                <div className="metrics">
                  <span className="dist">{formatDistance(act.distance)}</span>
                  <span className="time">{formatDuration(act.moving_time)}</span>
                </div>
              </button>
            )
          })
        )}
      </div>
    </>
  )
}
