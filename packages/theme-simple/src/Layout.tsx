import { useTheme } from '@workouts/core'
import { useActivities } from '@workouts/plugin-data-source'
import { formatPace } from '@workouts/shared'
import { useEffect, useMemo, useRef, useState } from 'react'
import { ActivityCardGrid } from './components/ActivityCardGrid'
import { CircularDrawer } from './components/CircularDrawer'
import { GithubDrawer } from './components/GithubDrawer'
import { Header } from './components/Header'
import { MapOverlays } from './components/MapOverlays'
import { RunTable } from './components/RunTable'
import { SimpleMap } from './components/SimpleMap'
import { intComma, Stat } from './components/Stat'
import { SummaryView } from './components/SummaryView'
import { SVGStat } from './components/SVGStat'
import { YearSelector } from './components/YearSelector'
import { LocationStats } from './LocationStats'
import { useSimpleStore } from './store'
import { getRunIdFromHash } from './utils'
import './simple.css'

export function SimpleLayout() {
  const { activities } = useActivities()
  const { config } = useTheme()
  const siteConfig = config?.site as Record<string, unknown> | undefined

  const SITE = useMemo(
    () => ({
      title: (siteConfig?.title as string) || 'Workouts',
      url: (siteConfig?.url as string) || '/',
      logo: (siteConfig?.logo as string | null) || null,
      navLinks: (siteConfig?.navLinks as { name: string; url: string }[]) || [],
    }),
    [siteConfig],
  )

  useEffect(() => {
    const link = document.createElement('link')
    link.href = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,600;0,700;1,700&family=IBM+Plex+Mono&display=swap'
    link.rel = 'stylesheet'
    document.head.appendChild(link)
  }, [])

  const setActivities = useSimpleStore((s) => s.setActivities)
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const colorMode = useSimpleStore((s) => s.colorMode)
  const colorScheme = useSimpleStore((s) => s.colorScheme)
  const filteredActivities = useSimpleStore((s) => s.filteredActivities)
  const years = useSimpleStore((s) => s.years)
  const showLabels = useSimpleStore((s) => s.showLabels)
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const cityFilter = useSimpleStore((s) => s.cityFilter)
  const periodFilter = useSimpleStore((s) => s.periodFilter)
  const viewMode = useSimpleStore((s) => s.viewMode)
  const setViewMode = useSimpleStore((s) => s.setViewMode)
  const view = useSimpleStore((s) => s.view)
  const selectedActivity = useSimpleStore((s) => s.selectedActivity)
  const openDetail = useSimpleStore((s) => s.openDetail)
  const selectByHash = useSimpleStore((s) => s.selectByHash)

  const [showSvgYear, setShowSvgYear] = useState<number | null>(null)
  const hoverTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const tableRef = useRef<HTMLDivElement>(null)
  const mapActivities = useMemo(() => (selectedActivity ? [selectedActivity] : filteredActivities), [filteredActivities, selectedActivity])

  useEffect(() => {
    if (!selectedActivity || !tableRef.current) return
    const row = tableRef.current.querySelector(`[data-run-id="${selectedActivity.run_id}"]`)
    if (row) row.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selectedActivity])

  useEffect(() => {
    setActivities(activities)
  }, [activities, setActivities])

  useEffect(() => {
    function onHashChange() {
      const id = getRunIdFromHash()
      if (!id || activities.length === 0) return
      const act = activities.find((a) => a.run_id === id)
      if (act) selectByHash(act)
    }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [activities, selectByHash])

  const totalKm = useMemo(() => intComma(Math.round(activities.reduce((s, a) => s + (a.distance ?? 0), 0) / 1000)), [activities])

  const yearRange = useMemo(() => {
    if (years.length === 0) return null
    return `${Math.min(...years)}–${Math.max(...years)}`
  }, [years])

  if (view === 'summary') return <SummaryView />

  return (
    <div className="page-container">
      <Header config={SITE} />
      <div className="layout">
        <aside className="left-panel">
          <a className="site-title" href={SITE.url}>
            {SITE.title}
          </a>
          <section className="info-message">
            <p>
              记录自己跑<span style={{ fontWeight: 700 }}>{years.length > 0 ? ` ${years.length} ` : ' '}</span>年了， 累计跑了
              <span style={{ fontWeight: 700 }}> {totalKm} </span>公里
              {yearRange ? `（${yearRange}）` : ''}
              {cityFilter && <span> · 城市: {cityFilter}</span>}
              {periodFilter && <span> · 时段: {periodFilter}</span>}
            </p>
          </section>
          <LocationStats activities={activities} />
          <hr className="section-divider" />
          <div className={`year-block${selectedYear === null ? ' active' : ''}`} onClick={() => setSelectedYear(null)}>
            <div className="year-label">Total</div>
            <YearStats year={null} />
          </div>
          {/* Selected year first, then other years descending */}
          {selectedYear !== null && (
            <div key={selectedYear} className="year-block" onClick={() => setSelectedYear(null)}>
              <div className="year-label">{selectedYear}</div>
              <YearStats year={selectedYear} />
            </div>
          )}
          {years
            .filter((y) => y !== selectedYear)
            .map((y) => (
              <div
                key={y}
                className="year-block"
                onClick={() => setSelectedYear(selectedYear === y ? null : y)}
                onMouseEnter={() => {
                  if (hoverTimerRef.current) clearTimeout(hoverTimerRef.current)
                  hoverTimerRef.current = setTimeout(() => setShowSvgYear(y), 1000)
                }}
                onMouseLeave={() => {
                  if (hoverTimerRef.current) clearTimeout(hoverTimerRef.current)
                  setShowSvgYear(null)
                }}
              >
                <div className="year-label">{y}</div>
                <YearStats year={y} />
                {showSvgYear === y && (
                  <div className="year-hover-svgs">
                    <CircularDrawer year={y} activities={activities} />
                    <GithubDrawer year={y} activities={activities} />
                  </div>
                )}
              </div>
            ))}
        </aside>
        <main className="right-panel">
          <div className="map-wrapper">
            <SimpleMap
              activities={mapActivities}
              colorScheme={colorScheme}
              colorMode={colorMode}
              hoveredActivityId={useSimpleStore.getState().mapHoveredId}
              privacyMode={siteConfig?.privacyMode as boolean | undefined}
              showLabels={showLabels}
              animate={!!selectedActivity}
              onActivityHover={setMapHoveredId}
              onActivityClick={openDetail}
            />
            <YearSelector />
            <MapOverlays />
            <div className="map-run-title">
              {selectedActivity
                ? `${selectedActivity.start_date?.slice(0, 10)} ${((selectedActivity.distance ?? 0) / 1000).toFixed(2)}km ${selectedActivity.name || selectedActivity.sport_category}`
                : selectedYear !== null
                  ? `${selectedYear} Running Heatmap`
                  : 'Total Running Heatmap'}
            </div>
          </div>
          {selectedYear !== null && (
            <div
              className="svg-stat-container"
              style={{ borderTop: '1px solid var(--color-border)', marginTop: 8, overflowX: 'hidden', maxWidth: '100%' }}
            >
              <GithubDrawer year={selectedYear} activities={activities} />
            </div>
          )}
          {selectedYear !== null && (
            <div className="table-area" ref={tableRef}>
              <div className="view-toggle">
                <button type="button" className={viewMode === 'table' ? 'active' : ''} onClick={() => setViewMode('table')}>
                  表格
                </button>
                <button type="button" className={viewMode === 'grid' ? 'active' : ''} onClick={() => setViewMode('grid')}>
                  卡片
                </button>
              </div>
              {viewMode === 'grid' ? <ActivityCardGrid /> : <RunTable />}
            </div>
          )}
          {selectedYear === null && <SVGStat activities={filteredActivities} />}
        </main>
      </div>
    </div>
  )
}

function YearStats({ year }: { year: number | null }) {
  const activities = useSimpleStore((s) => s.activities)
  const acts = useMemo(
    () => (year === null ? activities : activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)),
    [activities, year],
  )

  const stats = useMemo(() => {
    let totalDist = 0,
      hrTotal = 0,
      hrCount = 0,
      totalElev = 0,
      totalPaceDist = 0,
      totalPaceTime = 0
    const daySet = new Set<string>()
    const dates: string[] = []
    for (const a of acts) {
      totalDist += a.distance ?? 0
      totalElev += a.elevation_gain ?? 0
      if (a.average_heartrate) {
        hrTotal += a.average_heartrate
        hrCount++
      }
      if (a.average_speed && a.average_speed > 0) {
        totalPaceDist += a.distance ?? 0
        totalPaceTime += (a.distance ?? 0) / a.average_speed
      }
      const dayKey = a.start_date?.slice(0, 10)
      if (dayKey && !daySet.has(dayKey)) {
        daySet.add(dayKey)
        dates.push(dayKey)
      }
    }
    dates.sort()
    let streak = dates.length > 0 ? 1 : 0,
      current = 1
    for (let i = 1; i < dates.length; i++) {
      const diff = (new Date(dates[i]).getTime() - new Date(dates[i - 1]).getTime()) / 86400000
      if (Math.round(diff) === 1) {
        current++
        if (current > streak) streak = current
      } else current = 1
    }
    const avgPace = totalPaceTime > 0 ? totalPaceDist / totalPaceTime : 0
    return {
      count: acts.length,
      distance: totalDist,
      elev: totalElev,
      avgHr: hrCount > 0 ? Math.round(hrTotal / hrCount) : 0,
      avgPace,
      streak,
    }
  }, [acts])

  const paceStr = formatPace(stats.avgPace > 0 ? stats.avgPace : null)

  return (
    <div className="year-stats">
      <Stat value={stats.count} description=" Runs" />
      <Stat value={(stats.distance / 1000).toFixed(1)} description=" km" />
      {stats.elev > 0 && <Stat value={Math.round(stats.elev)} description=" Elevation Gain" />}
      <span className="stat-item">
        <strong>{paceStr}</strong>
        <span className="stat-desc"> Avg Pace</span>
      </span>
      <Stat value={`${stats.streak} day`} description=" Streak" />
      {stats.avgHr > 0 && <Stat value={stats.avgHr} description=" Avg Heart Rate" />}
    </div>
  )
}
