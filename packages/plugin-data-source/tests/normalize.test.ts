import { describe, expect, it } from 'vitest'
import { normalize, normalizeAll } from '../src/normalize'

describe('normalize', () => {
  it('prefers sport_category over type', () => {
    const a = normalize({ sport_category: 'walk', type: 'Walking' })
    expect(a.sport_category).toBe('walk')
  })

  it('falls back to type when sport_category absent', () => {
    const a = normalize({ type: 'Ride' })
    expect(a.sport_category).toBe('Ride')
  })

  it('returns other when neither sport_category nor type', () => {
    expect(normalize({}).sport_category).toBe('other')
  })

  it('returns other when type is empty string', () => {
    expect(normalize({ sport_category: '', type: '' }).sport_category).toBe('other')
  })

  it('handles null input', () => {
    const a = normalize(null as any)
    expect(a.sport_category).toBe('other')
    expect(a.run_id).toBe('')
    expect(a.name).toBeNull()
    expect(a.distance).toBeNull()
  })

  it('prefers summary_polyline over polyline', () => {
    const a = normalize({ summary_polyline: 'abc', polyline: 'xyz' })
    expect(a.summary_polyline).toBe('abc')
  })

  it('falls back to polyline when summary_polyline absent', () => {
    const a = normalize({ polyline: '_p~iF~ps|U' })
    expect(a.summary_polyline).toBe('_p~iF~ps|U')
  })

  it('returns null for missing numeric fields', () => {
    const a = normalize({ run_id: 'test' })
    expect(a.average_heartrate).toBeNull()
    expect(a.average_speed).toBeNull()
    expect(a.calories).toBeNull()
  })
})

describe('normalizeAll', () => {
  it('returns empty array for null', () => {
    expect(normalizeAll(null as any)).toEqual([])
  })

  it('returns empty array for undefined', () => {
    expect(normalizeAll(undefined as any)).toEqual([])
  })

  it('handles empty array', () => {
    expect(normalizeAll([])).toEqual([])
  })

  it('normalizes array of activities', () => {
    const result = normalizeAll([{ sport_category: 'run' }, { type: 'Ride' }, {}])
    expect(result).toHaveLength(3)
    expect(result[0].sport_category).toBe('run')
    expect(result[1].sport_category).toBe('Ride')
    expect(result[2].sport_category).toBe('other')
  })
})
