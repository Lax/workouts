import { describe, it, expect } from 'vitest'
import { decodePolyline } from '@workouts/plugin-map'

describe('decodePolyline', () => {
  it('returns [] for null', () => {
    expect(decodePolyline(null as any)).toEqual([])
  })

  it('returns [] for empty string', () => {
    expect(decodePolyline('')).toEqual([])
  })

  it('decodes known polyline', () => {
    const pts = decodePolyline('_p~iF~ps|U_ulLnnqC')
    expect(pts).toHaveLength(2)
    expect(pts[0][0]).toBeCloseTo(38.5, 1)
    expect(pts[0][1]).toBeCloseTo(-120.2, 1)
    expect(pts[1][0]).toBeCloseTo(40.7, 1)
    expect(pts[1][1]).toBeCloseTo(-121.0, 1)
  })
})
