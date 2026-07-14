import { useSimpleStore } from '../store'

export function MapOverlays() {
  const selectedYear = useSimpleStore((s) => s.selectedYear)
  const setSelectedYear = useSimpleStore((s) => s.setSelectedYear)
  const colorMode = useSimpleStore((s) => s.colorMode)
  const setColorMode = useSimpleStore((s) => s.setColorMode)
  const years = useSimpleStore((s) => s.years)

  return (
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
  )
}
