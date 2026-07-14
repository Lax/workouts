import { useRequiredComponent } from '@workouts/core'
import { useActivities } from '@workouts/plugin-data-source'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Header } from './components/Header'
import { MapOverlays } from './components/MapOverlays'
import { YearBarSVG } from './components/YearBarSVG'
import { YearGridSVG } from './components/YearGridSVG'
import { useSimpleStore } from './store'
import './simple.css'

const SITE = { title: 'Workouts', url: '/', logo: null, navLinks: [] as { name: string; url: string }[] }

export function SimpleLayout() {
  const { activities } = useActivities()

  const setActivities = useSimpleStore((s) => s.setActivities)
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const colorMode = useSimpleStore((s) => s.colorMode)
  const colorScheme = useSimpleStore((s) => s.colorScheme)
  const filteredActivities = useSimpleStore((s) => s.filteredActivities)
  const years = useSimpleStore((s) => s.years)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)

  const [hoveredYear, setHoveredYear] = useState<number | null>(null)
  const tableRef = useRef<HTMLDivElement>(null)
  const selectedActivity = useSimpleStore((s) => s.selectedActivity)
  const openDetail = useSimpleStore((s) => s.openDetail)

  const MapView = useRequiredComponent('map', 'MapView')

  useEffect(() => {
    if (!selectedActivity || !tableRef.current) return
    const row = tableRef.current.querySelector(`[data-run-id="${selectedActivity.run_id}"]`)
    if (row) row.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selectedActivity])

  useEffect(() => {
    setActivities(activities)
  }, [activities, setActivities])

  useEffect(() => {
    const link = document.createElement('link')
    link.href = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,600;0,700;1,700&family=IBM+Plex+Mono&display=swap'
    link.rel = 'stylesheet'
    document.head.appendChild(link)
  }, [])

  const yearRange = useMemo(() => {
    if (years.length === 0) return null
    return `${Math.min(...years)}–${Math.max(...years)}`
  }, [years])

  return (
    <>
      <Header config={SITE} />
      <div className="layout">
        <aside className="left-panel">
          <a className="site-title" href={SITE.url}>
            {SITE.title}
          </a>
          <section className="info-message">
            <p>
              {years.length} years of running · {activities.length} activities · {yearRange ?? '–'}
            </p>
          </section>
          <hr className="section-divider" />
          {years.map((y) => (
            <div
              key={y}
              className={`year-block${selectedYear === y ? ' active' : ''}`}
              onClick={() => setSelectedYear(selectedYear === y ? null : y)}
              onMouseEnter={() => setHoveredYear(y)}
              onMouseLeave={() => setHoveredYear(null)}
            >
              <div className="year-label">{y}</div>
              <YearStats year={y} />
              {hoveredYear === y && (
                <div className="year-hover-svgs">
                  <YearGridSVG year={y} activities={activities} />
                  <YearBarSVG year={y} activities={activities} />
                </div>
              )}
              <hr className="section-divider" />
            </div>
          ))}
        </aside>
        <main className="right-panel">
          <div className="map-wrapper">
            {MapView && (
              <MapView
                variant="contained"
                activities={filteredActivities}
                colorScheme={colorScheme}
                colorMode={colorMode}
                hoveredActivityId={useSimpleStore.getState().mapHoveredId}
                onActivityHover={setMapHoveredId}
                onActivityClick={openDetail}
              />
            )}
            <MapOverlays />
          </div>
          <div className="table-area" ref={tableRef}>
            <RunTable />
          </div>
        </main>
      </div>
    </>
  )
}

function YearStats({ year }: { year: number }) {
  const activities = useSimpleStore((s) => s.activities)
  const acts = useMemo(() => activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year), [activities, year])

  const stats = useMemo(() => {
    let totalDist = 0
    let totalTime = 0
    let totalHr = 0
    let hrCount = 0
    let totalElev = 0
    let totalPaceDist = 0
    let totalPaceTime = 0
    for (const a of acts) {
      totalDist += a.distance ?? 0
      totalTime += a.moving_time ?? 0
      totalElev += a.elevation_gain ?? 0
      if (a.average_heartrate) {
        totalHr += a.average_heartrate
        hrCount++
      }
      if (a.average_speed && a.average_speed > 0) {
        totalPaceDist += a.distance ?? 0
        totalPaceTime += (a.distance ?? 0) / a.average_speed
      }
    }
    const avgPace = totalPaceTime > 0 ? totalPaceDist / totalPaceTime : 0
    return {
      count: acts.length,
      distance: totalDist,
      time: totalTime,
      elev: totalElev,
      avgHr: hrCount > 0 ? totalHr / hrCount : 0,
      avgPace,
    }
  }, [acts])

  const paceStr =
    stats.avgPace > 0
      ? `${Math.floor(1000 / (stats.avgPace * 60))}'${Math.round(
          (1000 / (stats.avgPace * 60) - Math.floor(1000 / (stats.avgPace * 60))) * 60,
        )
          .toString()
          .padStart(2, '0')}"`
      : '—'

  return (
    <div className="stats-row">
      <span className="stat-item">
        <strong>{stats.count}</strong> runs
      </span>
      <span className="stat-item">
        <strong>{(stats.distance / 1000).toFixed(1)}</strong> km
      </span>
      {stats.elev > 0 && (
        <span className="stat-item">
          <strong>{Math.round(stats.elev)}</strong> m
        </span>
      )}
      <span className="stat-item">
        <strong>{paceStr}</strong> /km
      </span>
      {stats.avgHr > 0 && (
        <span className="stat-item">
          <strong>{stats.avgHr.toFixed(0)}</strong> bpm
        </span>
      )}
    </div>
  )
}

function RunTable() {
  const filtered = useSimpleStore((s) => s.filteredActivities)
  const sortField = useSimpleStore((s) => s.sortField)
  const sortDesc = useSimpleStore((s) => s.sortDesc)
  const toggleSort = useSimpleStore((s) => s.toggleSort)
  const mapHoveredId = useSimpleStore((s) => s.mapHoveredId)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const openDetail = useSimpleStore((s) => s.openDetail)

  const hasElev = useMemo(() => filtered.some((a) => (a.elevation_gain ?? 0) > 0), [filtered])

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

  return (
    <div className="table-container">
      <table className="run-table">
        <thead>
          <tr>
            <th />
            <th className={sortField === 'distance' ? 'sorted' : ''} onClick={() => toggleSort('distance')}>
              km {sortField === 'distance' ? (sortDesc ? '↓' : '↑') : ''}
            </th>
            {hasElev && <th>m</th>}
            <th>Pace</th>
            <th>BPM</th>
            <th>Time</th>
            <th className={sortField === 'date' ? 'sorted' : ''} onClick={() => toggleSort('date')}>
              Date {sortField === 'date' ? (sortDesc ? '↓' : '↑') : ''}
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
              <td>{act.distance ? (act.distance / 1000).toFixed(2) : '—'}</td>
              {hasElev && <td>{act.elevation_gain ? Math.round(act.elevation_gain).toString() : '—'}</td>}
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
