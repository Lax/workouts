import L from 'leaflet'
import { useEffect } from 'react'
import { useOverviewStore } from '../store'
import '../overview.css'

export function DetailPanel() {
  const detailOpen = useOverviewStore((s) => s.detailOpen)
  const act = useOverviewStore((s) => s.selectedActivity)
  const closeDetail = useOverviewStore((s) => s.closeDetail)
  const colorScheme = useOverviewStore((s) => s.colorScheme)

  useEffect(() => {
    if (!detailOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') closeDetail()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [detailOpen, closeDetail])

  if (!detailOpen || !act) return null

  return (
    <div className="detail-panel">
      <button type="button" className="detail-backdrop" onClick={closeDetail} aria-label="Close" />
      <div className="detail-content">
        <div className="detail-card">
          <div className="panel-header">
            <h2>{act.name || 'Untitled'}</h2>
            <button type="button" className="close-btn" onClick={closeDetail}>
              ×
            </button>
          </div>
          <div className="detail-meta">
            {(act.start_date || act.source) && `${act.start_date?.slice(0, 10) ?? ''}${act.source ? ` · ${act.source}` : ''}`}
          </div>
          <div className="detail-grid">
            <Stat label="Distance" value={act.distance ? `${(act.distance / 1000).toFixed(2)} km` : '—'} />
            <Stat label="Moving Time" value={act.moving_time ? `${Math.floor(act.moving_time / 60)}m` : '—'} />
            <Stat label="Avg Pace" value={act.average_speed ? `${(1000 / (act.average_speed * 60)).toFixed(1)} /km` : '—'} />
            <Stat label="Elevation" value={act.elevation_gain ? `${Math.round(act.elevation_gain)} m` : '—'} />
            <Stat label="Avg HR" value={act.average_heartrate ? `${Math.round(act.average_heartrate)} bpm` : '—'} />
            <Stat label="Avg Power" value={act.average_power ? `${Math.round(act.average_power)} W` : '—'} />
            <Stat label="Avg Cadence" value={act.average_cadence ? `${Math.round(act.average_cadence)} rpm` : '—'} />
            <Stat label="Calories" value={act.calories ? `${act.calories} kcal` : '—'} />
          </div>
          {act.summary_polyline && (
            <div className="detail-mini-map">
              <MiniMap polyline={act.summary_polyline} colorScheme={colorScheme} />
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="detail-stat">
      <span className="label">{label}</span>
      <span className="value">{value}</span>
    </div>
  )
}

function MiniMap({ polyline, colorScheme }: { polyline: string; colorScheme: string }) {
  useEffect(() => {
    const el = document.getElementById('mini-map')
    if (!el) return
    const map = L.map(el, { zoomControl: false, attributionControl: false }).setView([30, 110], 4)
    const tiles = colorScheme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
    L.tileLayer(`https://{s}.basemaps.cartocdn.com/${tiles}/{z}/{x}/{y}{r}.png`, { maxZoom: 19, attribution: '' }).addTo(map)
    const points = decodePolyline(polyline)
    if (points.length > 1) {
      L.polyline(points, { color: '#4DD2FF', weight: 3 }).addTo(map)
      map.fitBounds(L.latLngBounds(points.map((p) => L.latLng(p[0], p[1]))).pad(0.1))
    }
    return () => {
      map.remove()
    }
  }, [polyline, colorScheme])

  return <div id="mini-map" style={{ height: '100%' }} />
}

function decodePolyline(encoded: string): [number, number][] {
  if (!encoded) return []
  const points: [number, number][] = []
  let index = 0,
    lat = 0,
    lng = 0
  while (index < encoded.length) {
    let b: number,
      shift = 0,
      result = 0
    do {
      b = encoded.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    lat += result & 1 ? ~(result >> 1) : result >> 1
    shift = 0
    result = 0
    do {
      b = encoded.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    lng += result & 1 ? ~(result >> 1) : result >> 1
    points.push([lat * 1e-5, lng * 1e-5])
  }
  return points
}
