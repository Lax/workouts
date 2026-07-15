import { LightsToggle } from '@workouts/plugin-map'
import { useEffect, useState } from 'react'
import { useSimpleStore } from '../store'

export function MapOverlays() {
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
      <div className="map-lights">
        <LightsToggle showLabels={showLabels} onToggle={() => setShowLabels(!showLabels)} />
      </div>
      {fsSupported && (
        <div className="map-fullscreen">
          <button
            type="button"
            className="control-btn"
            onClick={toggleFullscreen}
            aria-label="Fullscreen"
            title={fullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
          >
            {fullscreen ? '✕' : '⛶'}
          </button>
        </div>
      )}
    </>
  )
}
