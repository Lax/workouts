import { describe, it, expect } from 'vitest'
import { speedColor, typeColor } from '../src/lib/colorMode'

describe('speedColor', () => {
  it('returns #888 for null', () => {
    expect(speedColor(null)).toBe('#888')
  })

  it('maps slow speed to blue', () => {
    expect(speedColor(0)).toBe('#4A90D9')
    // 0.8 m/s ≈ 2.88 km/h → < 3 band
    expect(speedColor(0.8)).toBe('#4A90D9')
  })

  it('maps medium speed to green', () => {
    // 1.5 m/s ≈ 5.4 km/h → < 6 band
    expect(speedColor(1.5)).toBe('#50C878')
  })

  it('maps fast speed to yellow', () => {
    // 2.4 m/s ≈ 8.64 km/h → < 9 band
    expect(speedColor(2.4)).toBe('#FFD700')
  })
})

describe('typeColor', () => {
  it('returns known color for run', () => {
    expect(typeColor('run')).toBe('#4DD2FF')
  })

  it('returns known color for ride', () => {
    expect(typeColor('ride')).toBe('#FF6B6B')
  })

  it('returns #888 for unknown type', () => {
    expect(typeColor('unknown')).toBe('#888')
  })

  it('returns #888 for null', () => {
    expect(typeColor(null)).toBe('#888')
  })
})
