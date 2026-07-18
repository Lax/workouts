import { useTheme } from '@workouts/core'
import { useActivities } from '@workouts/plugin-data-source'
import { presetToTileConfig, TILE_PRESETS, TileSwitcher, vendorTokenEnvName } from '@workouts/plugin-map'
import { useEffect, useMemo, useRef, useState } from 'react'
import { ActivityCardGrid } from './components/ActivityCardGrid'
import { CircularDrawer } from './components/CircularDrawer'
import { GithubDrawer } from './components/GithubDrawer'
import { Header } from './components/Header'
import { MapOverlays } from './components/MapOverlays'
import { RunTable } from './components/RunTable'
import { SimpleMap } from './components/SimpleMap'
import { intComma } from './components/Stat'
import { SummaryView } from './components/SummaryView'
import { SVGStat } from './components/SVGStat'
import { YearSelector } from './components/YearSelector'
import { YearStats } from './components/YearStats'
import { StatsPanel } from './StatsPanel'
import { useSimpleStore } from './store'
import { useFullscreenSync } from './useFullscreenSync'
import { getRunIdFromHash } from './utils'
import './simple.css'

const DEFAULT_INFO = 'Tracking for {years} year(s), {distance} km total'

function formatInfoMessage(
  siteConfig: Record<string, unknown> | undefined,
  yearsCount: number,
  totalKm: string,
  yearRange: string | null,
): string {
  const template = (siteConfig?.infoMessage as string) || DEFAULT_INFO
  let msg = template
    .replace('{years}', String(yearsCount))
    .replace('{distance}', totalKm)
    .replace('{yearRange}', yearRange || '')
  msg = msg.replace(/\s+/g, ' ').trim()
  return msg
}

export function SimpleLayout() {
  const { activities, loading } = useActivities()
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
  const lightsOn = useSimpleStore((s) => s.lightsOn)
  const tilePresetId = useSimpleStore((s) => s.tilePresetId)
  const setTilePreset = useSimpleStore((s) => s.setTilePreset)
  const isFullscreen = useFullscreenSync()
  const showLabels = isFullscreen && lightsOn
  const setMapHoveredId = useSimpleStore((s) => s.setMapHoveredId)
  const viewMode = useSimpleStore((s) => s.viewMode)
  const setViewMode = useSimpleStore((s) => s.setViewMode)
  const view = useSimpleStore((s) => s.view)
  const selectedActivity = useSimpleStore((s) => s.selectedActivity)
  const mapCompact = useSimpleStore((s) => s.mapCompact)
  const openDetail = useSimpleStore((s) => s.openDetail)
  const selectByHash = useSimpleStore((s) => s.selectByHash)

  const [showSvgYear, setShowSvgYear] = useState<number | null>(null)
  const hoverTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const tableRef = useRef<HTMLDivElement>(null)
  const mapActivities = useMemo(() => (selectedActivity ? [selectedActivity] : filteredActivities), [filteredActivities, selectedActivity])

  const tileConfig = useMemo(() => {
    const preset = TILE_PRESETS.find((p) => p.id === tilePresetId) ?? TILE_PRESETS[0]
    const token = preset.requiresToken ? import.meta.env[vendorTokenEnvName(preset.vendor)] : undefined
    return presetToTileConfig(preset, token)
  }, [tilePresetId])

  const disabledTilePresets = useMemo(() => {
    const tokensOk = TILE_PRESETS.filter((p) => p.requiresToken).every((p) => import.meta.env[vendorTokenEnvName(p.vendor)])
    if (tokensOk) return []
    return TILE_PRESETS.filter((p) => p.requiresToken).map((p) => p.id)
  }, [])

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
            <p>{formatInfoMessage(siteConfig, years.length, totalKm, yearRange)}</p>
          </section>
          <StatsPanel activities={activities} loading={loading} />
          <hr className="section-divider" />
          {/* Selected year first, then other years descending, then Total */}
          {selectedYear !== null && (
            <div className="year-block year-block-selected" onClick={() => setSelectedYear(null)}>
              <YearStats year={selectedYear} />
              <hr className="section-divider" />
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
                <YearStats year={y} />
                {showSvgYear === y && (
                  <div className="year-hover-svgs">
                    <CircularDrawer year={y} activities={activities} />
                    <GithubDrawer year={y} activities={activities} />
                  </div>
                )}
                <hr className="section-divider" />
              </div>
            ))}
          <div className="year-block" onClick={() => setSelectedYear(null)}>
            <YearStats year={null} />
          </div>
        </aside>
        <main className="right-panel">
          <div className={`map-wrapper${mapCompact ? ' map-wrapper--compact' : ''}`}>
            <SimpleMap
              activities={mapActivities}
              colorScheme={colorScheme}
              colorMode={colorMode}
              hoveredActivityId={useSimpleStore.getState().mapHoveredId}
              tileConfig={tileConfig}
              privacyMode={siteConfig?.privacyMode as boolean | undefined}
              lightsOn={lightsOn}
              showLabels={showLabels}
              animate={!!selectedActivity}
              initialScrollDisabled={true}
              attributionPosition="bottomleft"
              onActivityHover={setMapHoveredId}
              onActivityClick={openDetail}
            />
            <YearSelector />
            <MapOverlays />
            <div className="map-tile-switcher">
              <TileSwitcher presets={TILE_PRESETS} activeId={tilePresetId} onSelect={setTilePreset} disabledIds={disabledTilePresets} />
            </div>
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
