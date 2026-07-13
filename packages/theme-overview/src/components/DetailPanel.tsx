import { useEffect } from 'react'
import { useOverviewStore } from '../store'

export function DetailPanel() {
  const detailOpen = useOverviewStore((s) => s.detailOpen)
  const act = useOverviewStore((s) => s.selectedActivity)
  const closeDetail = useOverviewStore((s) => s.closeDetail)
  const colorScheme = useOverviewStore((s) => s.colorScheme)

  useEffect(() => {
    if (!detailOpen) return
    function onKey(e: KeyboardEvent) { if (e.key === 'Escape') closeDetail() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [detailOpen, closeDetail])

  if (!detailOpen || !act) return null

  return (
    <div
      onClick={(e) => { if (e.target === e.currentTarget) closeDetail() }}
      style={{
        position: 'fixed', inset: 0, zIndex: 3,
        background: 'rgba(0,0,0,0.5)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
    >
      <div
        style={{
          background: 'var(--color-surface)',
          borderRadius: 12, padding: 16, width: '90%', maxWidth: 400,
          animation: 'fadeIn 0.15s ease-out',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: '1rem' }}>{act.name || 'Untitled'}</h3>
          <button onClick={closeDetail} style={{ background: 'none', border: 'none', color: 'var(--color-text)', fontSize: '1.5rem', cursor: 'pointer' }}>×</button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, fontSize: '0.8rem' }}>
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
          <MiniMap polyline={act.summary_polyline} colorScheme={colorScheme} />
        )}
      </div>
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div style={{ color: 'var(--color-text-secondary)', fontSize: '0.65rem' }}>{label}</div>
      <div style={{ fontWeight: 600 }}>{value}</div>
    </div>
  )
}

function MiniMap({ polyline, colorScheme }: { polyline: string; colorScheme: string }) {
  useEffect(() => {
    let map: any = null
    import('leaflet').then((L) => {
      const el = document.getElementById('mini-map')
      if (!el) return
      map = L.map(el, { zoomControl: false, attributionControl: false }).setView([30, 110], 4)
      const tiles = colorScheme === 'dark' ? 'dark_nolabels' : 'light_nolabels'
      L.tileLayer(`https://{s}.basemaps.cartocdn.com/${tiles}/{z}/{x}/{y}{r}.png`, { maxZoom: 19, attribution: '' }).addTo(map)
      const points = decodePolyline(polyline)
      if (points.length > 1) {
        L.polyline(points, { color: '#4DD2FF', weight: 3 }).addTo(map)
        map.fitBounds(L.latLngBounds(points.map((p: [number, number]) => L.latLng(p[0], p[1]))).pad(0.1))
      }
    })
    return () => { map?.remove() }
  }, [polyline, colorScheme])

  return <div id="mini-map" style={{ height: 150, marginTop: 8, borderRadius: 8, overflow: 'hidden' }} />
}

function decodePolyline(encoded: string): [number, number][] {
  if (!encoded) return []
  const points: [number, number][] = []
  let index = 0, lat = 0, lng = 0
  while (index < encoded.length) {
    let b, shift = 0, result = 0
    do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lat += (result & 1 ? ~(result >> 1) : result >> 1)
    shift = 0; result = 0
    do { b = encoded.charCodeAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5 } while (b >= 0x20)
    lng += (result & 1 ? ~(result >> 1) : result >> 1)
    points.push([lat * 1e-5, lng * 1e-5])
  }
  return points
}
