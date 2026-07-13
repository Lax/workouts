import { useEffect } from 'react'
import { useRequiredComponent, useTheme } from '@workouts/core'
import { useOverviewStore } from './store'
import { Drawer } from './components/Drawer'
import { DetailPanel } from './components/DetailPanel'
import { ChartOverlay } from './components/ChartOverlay'

const styleId = 'overview-theme-styles'
const keyframesStyle = `
@keyframes fadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
`

if (typeof document !== 'undefined' && !document.getElementById(styleId)) {
  const style = document.createElement('style')
  style.id = styleId
  style.textContent = keyframesStyle
  document.head.appendChild(style)
}

export function OverviewLayout() {
  const { data } = useTheme()

  const activities = data.activities ?? []
  const stats = data.stats ?? null

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
  const toggleDrawer = useOverviewStore((s) => s.toggleDrawer)
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

      <div style={{
        position: 'fixed', inset: 0, zIndex: 1, pointerEvents: 'none',
      }}>
        <div style={{ position: 'absolute', top: 10, left: 10, pointerEvents: 'auto' }}>
          <span style={{
            fontSize: '0.85rem', color: 'var(--color-text-secondary, #888)',
            textShadow: '0 1px 3px rgba(0,0,0,0.5)',
          }}>
            <strong style={{ color: 'var(--color-accent, #4dd2ff)' }}>Workouts</strong>{' '}
            {years.length > 0 ? `${Math.min(...years)}–${Math.max(...years)}` : '?'}
          </span>
        </div>

        <div style={{ position: 'absolute', left: 6, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {years.map((y) => (
            <button
              key={y}
              onClick={() => setSelectedYear(selectedYear === y ? null : y)}
              style={{
                writingMode: 'vertical-lr', padding: '4px 2px', fontSize: '0.65rem',
                background: selectedYear === y ? 'var(--color-accent, #4dd2ff)' : 'rgba(var(--color-surface-rgb), 0.85)',
                color: selectedYear === y ? '#000' : 'var(--color-text-secondary, #888)',
                border: '1px solid var(--color-border, #2a2a4a)',
                borderRadius: 6, cursor: 'pointer', backdropFilter: 'blur(4px)',
                fontWeight: selectedYear === y ? 600 : 400,
              }}
            >{y}</button>
          ))}
        </div>

        {selectedYear !== null && selectedMonth === null && (
          <div style={{ position: 'absolute', left: 10, top: 10, pointerEvents: 'auto' }}>
            <div style={{ display: 'flex', gap: 2, flexWrap: 'wrap', maxWidth: 120 }}>
              {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
                <button
                  key={m}
                  onClick={() => setSelectedMonth(m)}
                  style={{
                    padding: '1px 4px', fontSize: '0.6rem', borderRadius: 3,
                    border: '1px solid var(--color-border)', cursor: 'pointer',
                    background: 'rgba(var(--color-surface-rgb), 0.85)',
                    color: 'var(--color-text)',
                  }}
                >{m}月</button>
              ))}
            </div>
          </div>
        )}
        {(selectedYear !== null || selectedMonth !== null) && (
          <div style={{ position: 'absolute', left: 10, top: 40, pointerEvents: 'auto' }}>
            <button
              onClick={() => { setSelectedYear(null); setSelectedMonth(null) }}
              style={{
                padding: '1px 6px', fontSize: '0.6rem', borderRadius: 3,
                border: '1px solid var(--color-border)', cursor: 'pointer',
                background: 'rgba(var(--color-surface-rgb), 0.85)',
                color: 'var(--color-accent)',
              }}
            >Clear</button>
          </div>
        )}

        <div style={{
          position: 'absolute', bottom: 72, left: 10, pointerEvents: 'auto',
          display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-start',
        }}>
          <div style={{
            display: 'flex',
            background: 'rgba(var(--color-surface-rgb), 0.85)',
            borderRadius: 8, border: '1px solid var(--color-border, #2a2a4a)',
            overflow: 'hidden', backdropFilter: 'blur(4px)',
          }}>
            <button
              onClick={() => setColorMode('type')}
              style={{
                padding: '4px 12px', fontSize: '0.7rem',
                color: colorMode === 'type' ? '#000' : 'var(--color-text-secondary, #888)',
                background: colorMode === 'type' ? 'var(--color-accent, #4dd2ff)' : 'transparent',
                fontWeight: colorMode === 'type' ? 600 : 400,
                border: 'none', cursor: 'pointer',
                borderRight: '1px solid var(--color-border, #2a2a4a)',
              }}
            >类型</button>
            <button
              onClick={() => setColorMode('speed')}
              style={{
                padding: '4px 12px', fontSize: '0.7rem',
                color: colorMode === 'speed' ? '#000' : 'var(--color-text-secondary, #888)',
                background: colorMode === 'speed' ? 'var(--color-accent, #4dd2ff)' : 'transparent',
                fontWeight: colorMode === 'speed' ? 600 : 400,
                border: 'none', cursor: 'pointer',
              }}
            >速度</button>
          </div>
          <div style={{ display: 'flex', borderRadius: 6, overflow: 'hidden', height: 8, alignSelf: 'stretch' }}>
            <span style={{ flex: 1, background: '#4A90D9' }} />
            <span style={{ flex: 1, background: '#50C878' }} />
            <span style={{ flex: 1, background: '#FFD700' }} />
            <span style={{ flex: 1, background: '#FF4500' }} />
          </div>
          <button
            onClick={toggleTheme}
            style={{
              background: 'rgba(var(--color-surface-rgb), 0.85)',
              border: '1px solid var(--color-border, #2a2a4a)',
              color: 'var(--color-text-secondary, #888)',
              borderRadius: 6, padding: '4px 8px', fontSize: '0.85rem',
              cursor: 'pointer', backdropFilter: 'blur(4px)',
            }}
          >{colorScheme === 'dark' ? '☀️' : '🌙'}</button>
        </div>
      </div>

      <Drawer />
      <DetailPanel />
      <ChartOverlay />
    </>
  )
}
