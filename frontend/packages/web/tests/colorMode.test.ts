import { speedColor, typeColor } from '@git-fit/shared'
import { describe, expect, it } from 'vitest'

describe('speedColor', () => {
  it('returns #888 for null', () => {
    expect(speedColor(null)).toBe('#888')
  })

  it('maps slow speed to the warm low band', () => {
    expect(speedColor(0)).toBe('#ffd166')
    // 0.8 m/s ≈ 2.88 km/h → < 3 band
    expect(speedColor(0.8)).toBe('#ffd166')
  })

  it('maps medium speed to the warm mid band', () => {
    // 1.5 m/s ≈ 5.4 km/h → < 6 band
    expect(speedColor(1.5)).toBe('#ff9f0a')
  })

  it('maps fast speed to the warm high band', () => {
    // 2.4 m/s ≈ 8.64 km/h → < 9 band
    expect(speedColor(2.4)).toBe('#ef5350')
  })
})

describe('typeColor', () => {
  it('returns warm run color by default', () => {
    expect(typeColor('run')).toBe('#e0ed5e')
  })

  it('returns warm ride color by default', () => {
    expect(typeColor('ride')).toBe('#ff9f0a')
  })

  it('returns #888 for unknown type', () => {
    expect(typeColor('unknown')).toBe('#888')
  })

  it('returns #888 for null', () => {
    expect(typeColor(null)).toBe('#888')
  })
})
