import { LightsToggle } from '@workouts/plugin-map'
import { useEffect, useState } from 'react'
import { useSimpleStore } from '../store'

export function MapOverlays() {
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const colorMode = useSimpleStore((s) => s.colorMode)
  const setColorMode = useSimpleStore((s) => s.setColorMode)
  const years = useSimpleStore((s) => s.years)
  const showLabels = useSimpleStore((s) => s.showLabels)
  const setShowLabels = useSimpleStore((s) => s.setShowLabels)

  const [fullscreen, setFullscreen] = useState(false)

  useEffect(() => {
    function onChange() {
      setFullscreen(!!document.fullscreenElement)
    }
    document.addEventListener('fullscreenchange', onChange)
    return () => document.removeEventListener('fullscreenchange', onChange)
  }, [])

  const fsSupported = !!document.documentElement.requestFullscreen

  function toggleFullscreen() {
    if (document.fullscreenElement) {
      document.exitFullscreen()
    } else {
      document.documentElement.requestFullscreen()
    }
  }

  return (
    <>
      <div className="map-overlays">
        <div className="year-pills">
          <button type="button" className={`year-pill${selectedYear === null ? ' active' : ''}`} onClick={() => setSelectedYear(null)}>
            All
          </button>
          {years.map((y) => (
            <button
              key={y}
              type="button"
              className={`year-pill${selectedYear === y ? ' active' : ''}`}
              onClick={() => setSelectedYear(selectedYear === y ? null : y)}
            >
              {y}
            </button>
          ))}
        </div>
        <div className="legend-area">
          <div className="legend-toggle">
            <button type="button" className={`legend-btn${colorMode === 'type' ? ' active' : ''}`} onClick={() => setColorMode('type')}>
              类型
            </button>
            <button type="button" className={`legend-btn${colorMode === 'speed' ? ' active' : ''}`} onClick={() => setColorMode('speed')}>
              速度
            </button>
          </div>
          <div className="speed-legend">
            <span className="sl-blue" />
            <span className="sl-green" />
            <span className="sl-yellow" />
            <span className="sl-red" />
          </div>
        </div>
      </div>
      <div className="map-actions">
        <LightsToggle showLabels={showLabels} onToggle={() => setShowLabels(!showLabels)} />
        {fsSupported && (
          <button
            type="button"
            className="control-btn"
            onClick={toggleFullscreen}
            aria-label="Fullscreen"
            title={fullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
          >
            {fullscreen ? '✕' : '⛶'}
          </button>
        )}
      </div>
    </>
  )
}
