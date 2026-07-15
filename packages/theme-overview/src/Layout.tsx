import { useTheme } from '@workouts/core'
import { useActivities } from '@workouts/plugin-data-source'
import { useEffect } from 'react'
import { ChartOverlay } from './components/ChartOverlay'
import { DetailPanel } from './components/DetailPanel'
import { Drawer } from './components/Drawer'
import { OverviewMap } from './components/OverviewMap'
import { useOverviewStore } from './store'
import './overview.css'

export function OverviewLayout() {
  const { activities, loading: _loading, error: _error } = useActivities()
  const { config } = useTheme()
  const siteConfig = config?.site as Record<string, unknown> | undefined

  const setActivities = useOverviewStore((s) => s.setActivities)
  const colorMode = useOverviewStore((s) => s.colorMode)
  const colorScheme = useOverviewStore((s) => s.colorScheme)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const selectedMonth = useOverviewStore((s) => s.selectedMonth)
  const filteredActivities = useOverviewStore((s) => s.filteredActivities)
  const mapHoveredId = useOverviewStore((s) => s.mapHoveredId)
  const setSelectedYear = useOverviewStore((s) => s.setSelectedYear)
  const setColorMode = useOverviewStore((s) => s.setColorMode)
  const toggleTheme = useOverviewStore((s) => s.toggleTheme)
  const setMapHoveredId = useOverviewStore((s) => s.setMapHoveredId)
  const openDetail = useOverviewStore((s) => s.openDetail)
  const years = useOverviewStore((s) => s.years)

  useEffect(() => {
    setActivities(activities)
  }, [activities, setActivities])

  return (
    <>
      <OverviewMap
        activities={filteredActivities}
        colorScheme={colorScheme}
        colorMode={colorMode}
        hoveredActivityId={mapHoveredId}
        dashLines={siteConfig?.dashLines as boolean | undefined}
        privacyMode={siteConfig?.privacyMode as boolean | undefined}
        lightsOn={true}
        showLabels={siteConfig?.showLabels === true}
        onActivityClick={openDetail}
        onActivityHover={setMapHoveredId}
      />

      <div className="map-overlays">
        <div className="ol-tl">
          <span className="brand">
            <strong>Workouts</strong> {years.length > 0 ? `${Math.min(...years)}–${Math.max(...years)}` : '?'}
          </span>
        </div>

        <div className="ol-lc">
          <div className="year-pills">
            <button type="button" className={`year-pill${selectedYear === null ? ' active' : ''}`} onClick={() => setSelectedYear(null)}>
              All
            </button>
            {years.map((y) => (
              <button
                type="button"
                key={y}
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
              <button type="button" onClick={() => useOverviewStore.getState().setSelectedMonth(null)}>
                ×
              </button>
            </div>
          )}
        </div>

        <div className="ol-bl">
          <div className="legend-toggle">
            <button type="button" className={`legend-btn${colorMode === 'type' ? ' active' : ''}`} onClick={() => setColorMode('type')}>
              类型
            </button>
            <button type="button" className={`legend-btn${colorMode === 'speed' ? ' active' : ''}`} onClick={() => setColorMode('speed')}>
              速度
            </button>
          </div>
          <div className="speed-legend">
            <span className="sl-blue"></span>
            <span className="sl-green"></span>
            <span className="sl-yellow"></span>
            <span className="sl-red"></span>
          </div>
          <button type="button" className="icon-btn" onClick={toggleTheme} aria-label="Toggle theme">
            {colorScheme === 'dark' ? '☀️' : '🌙'}
          </button>
        </div>
      </div>

      <Drawer />
      <DetailPanel />
      <ChartOverlay />
    </>
  )
}
