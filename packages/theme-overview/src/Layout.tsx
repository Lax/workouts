import { useRequiredComponent, useTheme } from '@workouts/core'
import { useEffect } from 'react'
import { ChartOverlay } from './components/ChartOverlay'
import { DetailPanel } from './components/DetailPanel'
import { Drawer } from './components/Drawer'
import { useOverviewStore } from './store'
import './overview.css'

export function OverviewLayout() {
  const { data } = useTheme()

  const activities = data.activities ?? []

  const setActivities = useOverviewStore((s) => s.setActivities)
  const colorMode = useOverviewStore((s) => s.colorMode)
  const colorScheme = useOverviewStore((s) => s.colorScheme)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const selectedMonth = useOverviewStore((s) => s.selectedMonth)
  const filteredActivities = useOverviewStore((s) => s.filteredActivities)
  const mapHoveredId = useOverviewStore((s) => s.mapHoveredId)
  const setSelectedYear = useOverviewStore((s) => s.setSelectedYear)
  const setSelectedMonth = useOverviewStore((s) => s.setSelectedMonth)
  const setColorMode = useOverviewStore((s) => s.setColorMode)
  const toggleTheme = useOverviewStore((s) => s.toggleTheme)
  const setMapHoveredId = useOverviewStore((s) => s.setMapHoveredId)
  const openDetail = useOverviewStore((s) => s.openDetail)
  const years = useOverviewStore((s) => s.years)

  const MapView = useRequiredComponent('map', 'MapView')

  useEffect(() => {
    setActivities(activities)
  }, [activities, setActivities])

  return (
    <>
      {MapView && (
        <MapView
          activities={filteredActivities}
          colorScheme={colorScheme}
          colorMode={colorMode}
          hoveredActivityId={mapHoveredId}
          onActivityClick={openDetail}
          onActivityHover={setMapHoveredId}
        />
      )}

      <div className="map-overlays">
        <div className="ol-tl">
          <span className="brand">
            <strong>Workouts</strong>{' '}
            {years.length > 0 ? `${Math.min(...years)}–${Math.max(...years)}` : '?'}
          </span>
        </div>

        <div className="ol-lc">
          {years.map((y) => (
            <button
              type="button"
              key={y}
              className={'year-pill' + (selectedYear === y ? ' active' : '')}
              onClick={() => setSelectedYear(selectedYear === y ? null : y)}
            >
              {y}
            </button>
          ))}
        </div>

        {selectedYear !== null && selectedMonth === null && (
          <div style={{ position: 'absolute', left: 10, top: 10, pointerEvents: 'auto' }}>
            <div style={{ display: 'flex', gap: 2, flexWrap: 'wrap', maxWidth: 120 }}>
              {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
                <button
                  type="button"
                  key={m}
                  onClick={() => setSelectedMonth(m)}
                  style={{
                    padding: '1px 4px', fontSize: '0.6rem', borderRadius: 3,
                    border: '1px solid var(--color-border)', cursor: 'pointer',
                    background: 'rgba(var(--color-surface-rgb), 0.85)', color: 'var(--color-text)',
                  }}
                >
                  {m}月
                </button>
              ))}
            </div>
          </div>
        )}
        {(selectedYear !== null || selectedMonth !== null) && (
          <div style={{ position: 'absolute', left: 10, top: 40, pointerEvents: 'auto' }}>
            <button
              type="button"
              onClick={() => { setSelectedYear(null); setSelectedMonth(null) }}
              style={{
                padding: '1px 6px', fontSize: '0.6rem', borderRadius: 3,
                border: '1px solid var(--color-border)', cursor: 'pointer',
                background: 'rgba(var(--color-surface-rgb), 0.85)', color: 'var(--color-accent)',
              }}
            >
              Clear
            </button>
          </div>
        )}

        <div className="ol-bl">
          <div className="legend-toggle">
            <button
              type="button"
              className={'legend-btn' + (colorMode === 'type' ? ' active' : '')}
              onClick={() => setColorMode('type')}
            >
              类型
            </button>
            <button
              type="button"
              className={'legend-btn' + (colorMode === 'speed' ? ' active' : '')}
              onClick={() => setColorMode('speed')}
            >
              速度
            </button>
          </div>
          <div className="speed-legend">
            <span className="sl-blue" />
            <span className="sl-green" />
            <span className="sl-yellow" />
            <span className="sl-red" />
          </div>
          <button type="button" className="icon-btn" onClick={toggleTheme}>
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
