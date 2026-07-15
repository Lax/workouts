import { LightsToggle } from '@workouts/plugin-map'
import { useSimpleStore } from '../store'
import { useFullscreenSync } from '../useFullscreenSync'

export function MapOverlays() {
  const lightsOn = useSimpleStore((s) => s.lightsOn)
  const setLightsOn = useSimpleStore((s) => s.setLightsOn)

  const isFullscreen = useFullscreenSync()

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
        <LightsToggle showLabels={lightsOn} onToggle={() => setLightsOn(!lightsOn)} />
      </div>
      {fsSupported && (
        <div className="map-fullscreen">
          <button
            type="button"
            className="control-btn"
            onClick={toggleFullscreen}
            aria-label="Fullscreen"
            title={isFullscreen ? 'Exit fullscreen' : 'Enter fullscreen'}
          >
            {isFullscreen ? '✕' : '⛶'}
          </button>
        </div>
      )}
    </>
  )
}
