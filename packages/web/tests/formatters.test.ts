import { formatDate, formatDistance, formatDuration, formatPace } from '@workouts/shared'
import { describe, expect, it } from 'vitest'

describe('formatDistance', () => {
  it('returns — for null', () => {
    expect(formatDistance(null)).toBe('—')
  })

  it('formats meters when under 1 km', () => {
    expect(formatDistance(500)).toBe('500 m')
  })

  it('formats km with 2 decimals', () => {
    expect(formatDistance(5000)).toBe('5.00 km')
  })

  it('handles zero as 0 m', () => {
    expect(formatDistance(0)).toBe('0 m')
  })
})

describe('formatDuration', () => {
  it('returns — for null', () => {
    expect(formatDuration(null)).toBe('—')
  })

  it('formats minutes only', () => {
    expect(formatDuration(1500)).toBe('25m')
  })

  it('formats hours and minutes', () => {
    expect(formatDuration(5400)).toBe('1h 30m')
  })

  it('handles zero', () => {
    expect(formatDuration(0)).toBe('0m')
  })
})

describe('formatPace', () => {
  it('returns — for null', () => {
    expect(formatPace(null)).toBe('—')
  })

  it('returns — for zero speed', () => {
    expect(formatPace(0)).toBe('—')
  })

  it('formats pace from m/s', () => {
    // 5000m / 1500s = 3.33 m/s → 1000 / (3.33 * 60) ≈ 5:00 /km
    expect(formatPace(5000 / 1500)).toBe('5:00 /km')
  })
})

describe('formatDate', () => {
  it('returns — for null', () => {
    expect(formatDate(null)).toBe('—')
  })

  it('formats ISO date string', () => {
    const result = formatDate('2024-06-15T10:00:00Z')
    expect(result).toMatch(/Jun 15, 2024/)
  })
})
