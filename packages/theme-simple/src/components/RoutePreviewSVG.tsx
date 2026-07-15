interface Props {
  polyline: string | null
  width?: number
  height?: number
}

function decodePolyline(str: string): [number, number][] {
  if (!str) return []
  let index = 0
  const len = str.length
  let lat = 0
  let lng = 0
  const coordinates: [number, number][] = []
  while (index < len) {
    let b: number
    let shift = 0
    let result = 0
    do {
      b = str.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    const dlat = result & 1 ? ~(result >> 1) : result >> 1
    lat += dlat
    shift = 0
    result = 0
    do {
      b = str.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    const dlng = result & 1 ? ~(result >> 1) : result >> 1
    lng += dlng
    coordinates.push([lat * 1e-5, lng * 1e-5])
  }
  return coordinates
}

export { decodePolyline }
export function RoutePreviewSVG({ polyline, width = 250, height = 150 }: Props) {
  const points = polyline ? decodePolyline(polyline) : []

  if (points.length === 0) {
    return (
      <svg
        viewBox={`0 0 ${width} ${height}`}
        width={width}
        height={height}
        className="route-preview-svg"
        role="img"
        aria-label="No route data"
      >
        <text x="50%" y="50%" textAnchor="middle" fill="var(--color-text-dim, #666)" fontSize={12}>
          No route data
        </text>
      </svg>
    )
  }

  const lats = points.map((p) => p[0])
  const lngs = points.map((p) => p[1])
  const minLat = Math.min(...lats)
  const maxLat = Math.max(...lats)
  const minLng = Math.min(...lngs)
  const maxLng = Math.max(...lngs)
  const padX = (maxLng - minLng) * 0.1 || 0.001
  const padY = (maxLat - minLat) * 0.1 || 0.001
  const rangeX = maxLng - minLng + 2 * padX
  const rangeY = maxLat - minLat + 2 * padY

  const toSvg = (lat: number, lng: number): [number, number] => [
    ((lng - minLng + padX) / rangeX) * width,
    ((maxLat - lat + padY) / rangeY) * height,
  ]

  const svgPoints = points.map((p) => toSvg(p[0], p[1]))
  const pathD = svgPoints.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ')
  const start = svgPoints[0]
  const end = svgPoints[svgPoints.length - 1]

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      width={width}
      height={height}
      className="route-preview-svg"
      role="img"
      aria-label="Route preview"
    >
      <path d={pathD} fill="none" stroke="var(--color-brand, #e0ed5e)" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={start[0]} cy={start[1]} r={4} fill="#4ade80" />
      <circle cx={end[0]} cy={end[1]} r={4} fill="#f87171" />
    </svg>
  )
}
