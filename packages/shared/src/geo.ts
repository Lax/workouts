export interface Boundary {
  type: 'Polygon' | 'MultiPolygon'
  coordinates: number[][][]
}

export interface CityBoundary extends Boundary {
  province: string
}

export function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000
  const toRad = (d: number) => (d * Math.PI) / 180
  const dLat = toRad(lat2 - lat1)
  const dLng = toRad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

function pointInRing(lat: number, lng: number, ring: number[][]): boolean {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][1],
      yi = ring[i][0]
    const xj = ring[j][1],
      yj = ring[j][0]
    if (yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) {
      inside = !inside
    }
  }
  return inside
}

export function pointInPolygon(lat: number, lng: number, boundary: Boundary): boolean {
  if (boundary.type === 'Polygon') {
    return pointInRing(lat, lng, boundary.coordinates[0])
  }
  for (const ring of boundary.coordinates) {
    if (pointInRing(lat, lng, ring)) return true
  }
  return false
}

export function matchPolygons(lat: number, lng: number, polygons: Record<string, Boundary>): string | null {
  for (const [name, boundary] of Object.entries(polygons)) {
    if (pointInPolygon(lat, lng, boundary)) return name
  }
  return null
}

export function decodePolyline(encoded: string | null | undefined): [number, number][] {
  if (!encoded) return []
  const points: [number, number][] = []
  let index = 0
  const len = encoded.length
  let lat = 0
  let lng = 0
  while (index < len) {
    let b: number
    let shift = 0
    let result = 0
    do {
      b = encoded.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    const dlat = result & 1 ? ~(result >> 1) : result >> 1
    lat += dlat
    shift = 0
    result = 0
    do {
      b = encoded.charCodeAt(index++) - 63
      result |= (b & 0x1f) << shift
      shift += 5
    } while (b >= 0x20)
    const dlng = result & 1 ? ~(result >> 1) : result >> 1
    lng += dlng
    points.push([lat / 1e5, lng / 1e5])
  }
  return points
}

export function getStartCoords(polyline: string | null | undefined): [number, number] | null {
  const pts = decodePolyline(polyline)
  if (pts.length === 0) return null
  return pts[0]
}

export function classifyPeriod3(hour: number): 'morning' | 'afternoon' | 'evening' | null {
  if (hour >= 3 && hour <= 9) return 'morning'
  if (hour >= 10 && hour <= 17) return 'afternoon'
  if (hour >= 18 || hour <= 2) return 'evening'
  return null
}

export const PERIOD3_LABELS: Record<string, string> = {
  morning: '早',
  afternoon: '中',
  evening: '晚',
}

export interface GeoLocation {
  type: 'province' | 'continent' | 'ocean' | 'text_fallback' | 'unknown'
  name: string
}
