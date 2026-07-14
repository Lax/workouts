import { useRequiredComponent } from '@workouts/core'
import dsPlugin, { useActivities, useDerivedData } from '@workouts/plugin-data-source'
import mapPlugin from '@workouts/plugin-map'
import { useMemo, useState } from 'react'

function SimpleLayout() {
  const { activities } = useActivities()
  const { years } = useDerivedData()
  const [colorMode, setColorMode] = useState<'type' | 'speed'>('type')
  const [colorScheme, setColorScheme] = useState<'light' | 'dark'>(
    (document.documentElement.getAttribute('data-theme') as 'light' | 'dark') || 'dark',
  )

  const MapView = useRequiredComponent('map', 'MapView')
  const yearRange = useMemo(() => {
    if (years.length === 0) return '?–?'
    return `${Math.min(...years)}–${Math.max(...years)}`
  }, [years])

  function toggleTheme() {
    const next = colorScheme === 'light' ? 'dark' : 'light'
    document.documentElement.setAttribute('data-theme', next)
    localStorage.setItem('theme', next)
    setColorScheme(next)
  }

  return (
    <>
      {MapView && <MapView activities={activities} colorScheme={colorScheme} colorMode={colorMode} />}
      <div
        style={{
          position: 'fixed',
          inset: 0,
          zIndex: 1,
          pointerEvents: 'none',
        }}
      >
        <div style={{ position: 'absolute', top: 10, left: 10, pointerEvents: 'auto' }}>
          <span
            style={{
              fontSize: '0.85rem',
              color: 'var(--color-text-secondary, #888)',
              textShadow: '0 1px 3px rgba(0,0,0,0.5)',
            }}
          >
            <strong style={{ color: 'var(--color-accent, #4dd2ff)' }}>Workouts</strong> {yearRange}
          </span>
        </div>
        <div
          style={{
            position: 'absolute',
            bottom: 72,
            left: 10,
            pointerEvents: 'auto',
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
          }}
        >
          <div
            style={{
              display: 'flex',
              background: 'rgba(var(--color-surface-rgb), 0.85)',
              borderRadius: 8,
              border: '1px solid var(--color-border, #2a2a4a)',
              overflow: 'hidden',
              backdropFilter: 'blur(4px)',
            }}
          >
            <button
              type="button"
              onClick={() => setColorMode('type')}
              style={{
                padding: '4px 12px',
                fontSize: '0.7rem',
                color: colorMode === 'type' ? '#000' : 'var(--color-text-secondary, #888)',
                background: colorMode === 'type' ? 'var(--color-accent, #4dd2ff)' : 'transparent',
                fontWeight: colorMode === 'type' ? 600 : 400,
                border: 'none',
                cursor: 'pointer',
              }}
            >
              类型
            </button>
            <button
              type="button"
              onClick={() => setColorMode('speed')}
              style={{
                padding: '4px 12px',
                fontSize: '0.7rem',
                color: colorMode === 'speed' ? '#000' : 'var(--color-text-secondary, #888)',
                background: colorMode === 'speed' ? 'var(--color-accent, #4dd2ff)' : 'transparent',
                fontWeight: colorMode === 'speed' ? 600 : 400,
                border: 'none',
                cursor: 'pointer',
              }}
            >
              速度
            </button>
          </div>
          <div style={{ display: 'flex', borderRadius: 6, overflow: 'hidden', height: 8 }}>
            <span style={{ flex: 1, background: '#4A90D9' }} />
            <span style={{ flex: 1, background: '#50C878' }} />
            <span style={{ flex: 1, background: '#FFD700' }} />
            <span style={{ flex: 1, background: '#FF4500' }} />
          </div>
          <button
            type="button"
            onClick={toggleTheme}
            style={{
              background: 'rgba(var(--color-surface-rgb), 0.85)',
              border: '1px solid var(--color-border, #2a2a4a)',
              color: 'var(--color-text-secondary, #888)',
              borderRadius: 6,
              padding: '4px 8px',
              fontSize: '0.85rem',
              cursor: 'pointer',
              backdropFilter: 'blur(4px)',
            }}
          >
            {colorScheme === 'dark' ? '☀️' : '🌙'}
          </button>
        </div>
      </div>
      <div
        style={{
          position: 'fixed',
          bottom: 0,
          left: 0,
          right: 0,
          zIndex: 2,
          height: 80,
          overflow: 'auto',
          background: 'var(--color-surface)',
          borderTop: '1px solid var(--color-border)',
        }}
      >
        <div style={{ display: 'flex', gap: 8, padding: 8 }}>
          {activities.map((a) => (
            <div
              key={a.run_id}
              style={{
                flex: '0 0 160px',
                padding: 8,
                borderRadius: 6,
                background: 'var(--color-bg)',
                fontSize: '0.75rem',
              }}
            >
              <div
                style={{
                  fontWeight: 600,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {a.name || 'Untitled'}
              </div>
              <div style={{ color: 'var(--color-text-secondary)' }}>{((a.distance ?? 0) / 1000).toFixed(2)} km</div>
            </div>
          ))}
        </div>
      </div>
    </>
  )
}

const theme = {
  type: 'theme' as const,
  manifest: { id: 'simple', name: 'Simple', version: '0.1.0' },
  Layout: SimpleLayout,
  plugins: {
    'data-source': dsPlugin,
    map: mapPlugin,
  },
}

export default theme
