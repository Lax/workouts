import type { Activity } from '@workouts/shared'
import { formatDuration, formatPace } from '@workouts/shared'
import { colorIntensity, computeStreak, decodePolyline, useSimpleStore } from '@workouts/theme-simple'
import { describe, expect, it } from 'vitest'

function act(start_date: string): Activity {
  return {
    run_id: '',
    name: '',
    distance: 5000,
    moving_time: 1800,
    elapsed_time: 2000,
    sport_category: 'run',
    start_date,
    start_date_local: '',
    location_country: null,
    source: '',
    average_heartrate: null,
    max_heartrate: null,
    average_cadence: null,
    max_cadence: null,
    average_power: null,
    max_power: null,
    average_temperature: null,
    calories: null,
    average_speed: null,
    elevation_gain: null,
    summary_polyline: null,
  }
}

describe('formatPace — shared import from theme-simple context', () => {
  it('returns — for null', () => {
    expect(formatPace(null)).toBe('—')
  })

  it('returns — for zero', () => {
    expect(formatPace(0)).toBe('—')
  })

  it('formats pace from m/s', () => {
    expect(formatPace(5000 / 1500)).toBe('5:00 /km')
  })
})

describe('formatDuration — shared import from theme-simple context', () => {
  it('returns — for null', () => {
    expect(formatDuration(null)).toBe('—')
  })

  it('formats hours and minutes', () => {
    expect(formatDuration(5400)).toBe('1h 30m')
  })

  it('formats minutes only', () => {
    expect(formatDuration(1500)).toBe('25m')
  })
})

describe('computeStreak', () => {
  it('returns 0 for empty activities', () => {
    expect(computeStreak([])).toBe(0)
  })

  it('returns 1 for a single day', () => {
    expect(computeStreak([act('2024-06-01T00:00:00Z')])).toBe(1)
  })

  it('counts consecutive days', () => {
    const acts = [act('2024-06-01T00:00:00Z'), act('2024-06-02T00:00:00Z'), act('2024-06-03T00:00:00Z')]
    expect(computeStreak(acts)).toBe(3)
  })

  it('resets on gap', () => {
    const acts = [act('2024-06-01T00:00:00Z'), act('2024-06-02T00:00:00Z'), act('2024-06-04T00:00:00Z'), act('2024-06-05T00:00:00Z')]
    expect(computeStreak(acts)).toBe(2)
  })

  it('deduplicates same-day activities', () => {
    const acts = [act('2024-06-01T00:00:00Z'), act('2024-06-01T00:00:00Z'), act('2024-06-02T00:00:00Z')]
    expect(computeStreak(acts)).toBe(2)
  })
})

describe('colorIntensity — YearGridSVG', () => {
  it('returns border color for count 0', () => {
    expect(colorIntensity(0, 10)).toBe('var(--color-border, #333)')
  })

  it('returns cyan at low opacity for < 25%', () => {
    expect(colorIntensity(1, 10)).toBe('var(--svg-color-active-cell, #4dd2ff)')
  })

  it('returns cyan for 25-50%', () => {
    expect(colorIntensity(3, 10)).toBe('var(--svg-color-active-cell, #4dd2ff)')
  })

  it('returns gold for 50-75%', () => {
    expect(colorIntensity(6, 10)).toBe('var(--svg-special-color, #f7d02c)')
  })

  it('returns red for 75-100%', () => {
    expect(colorIntensity(9, 10)).toBe('var(--svg-special-color2, #f56c6c)')
  })

  it('handles maxCount 1 correctly', () => {
    expect(colorIntensity(0, 1)).toBe('var(--color-border, #333)')
    expect(colorIntensity(1, 1)).toBe('var(--svg-special-color2, #f56c6c)')
  })
})

describe('decodePolyline', () => {
  it('returns empty array for empty string', () => {
    expect(decodePolyline('')).toEqual([])
  })

  it('decodes a known polyline', () => {
    const result = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@')
    expect(result.length).toBe(3)
    expect(result[0][0]).toBeCloseTo(38.5, 1)
    expect(result[0][1]).toBeCloseTo(-120.2, 1)
  })

  it('decodes a single point', () => {
    const result = decodePolyline('_p~iF~ps|U')
    expect(result.length).toBe(1)
  })
})

describe('SummaryInterval store actions', () => {
  it('setView updates view state', () => {
    const store = useSimpleStore.getState()
    expect(store.view).toBe('main')
    store.setView('summary')
    expect(useSimpleStore.getState().view).toBe('summary')
    store.setView('main')
    expect(useSimpleStore.getState().view).toBe('main')
  })

  it('setSummaryInterval updates interval', () => {
    const store = useSimpleStore.getState()
    store.setSummaryInterval('year')
    expect(useSimpleStore.getState().summaryInterval).toBe('year')
    store.setSummaryInterval('life')
    expect(useSimpleStore.getState().summaryInterval).toBe('life')
  })

  it('setSummaryLifeYear updates life year', () => {
    const store = useSimpleStore.getState()
    expect(useSimpleStore.getState().summaryLifeYear).toBeNull()
    store.setSummaryLifeYear(2024)
    expect(useSimpleStore.getState().summaryLifeYear).toBe(2024)
    store.setSummaryLifeYear(null)
    expect(useSimpleStore.getState().summaryLifeYear).toBeNull()
  })
})
