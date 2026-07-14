import {
  computeAvailableSources,
  computeAvailableTypes,
  computeCities,
  computeFilteredActivities,
  computeLocationSummary,
  computePeriods,
  computeYears,
} from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { describe, expect, it } from 'vitest'

function act(overrides: Partial<Activity> = {}): Activity {
  return {
    run_id: '',
    name: '',
    distance: 5000,
    moving_time: 1800,
    elapsed_time: 2000,
    sport_category: 'run',
    start_date: '2024-06-01T00:00:00Z',
    start_date_local: '2024-06-01T00:00:00',
    location_country: null,
    source: 'garmin',
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
    ...overrides,
  }
}

const defaultFilters = { type: '', source: '', distanceMin: null, distanceMax: null, search: '' }

describe('computeYears', () => {
  it('returns unique years sorted desc', () => {
    expect(
      computeYears([
        act({ start_date: '2024-01-01T00:00:00Z' }),
        act({ start_date: '2025-06-15T00:00:00Z' }),
        act({ start_date: '2024-07-20T00:00:00Z' }),
      ]),
    ).toEqual([2025, 2024])
  })

  it('returns empty for empty list', () => {
    expect(computeYears([])).toEqual([])
  })

  it('handles null start_date', () => {
    expect(computeYears([act({ start_date: undefined as any })])).toEqual([])
  })
})

describe('computeAvailableTypes', () => {
  it('counts sorted by count desc', () => {
    expect(
      computeAvailableTypes([act({ sport_category: 'run' }), act({ sport_category: 'ride' }), act({ sport_category: 'run' })]),
    ).toEqual([
      ['run', 2],
      ['ride', 1],
    ])
  })

  it('classifies empty category as other via fallback', () => {
    expect(computeAvailableTypes([act({ sport_category: undefined as any })])).toEqual([['other', 1]])
  })
})

describe('computeAvailableSources', () => {
  it('counts sorted by count desc', () => {
    expect(computeAvailableSources([act({ source: 'garmin' }), act({ source: 'strava' }), act({ source: 'garmin' })])).toEqual([
      ['garmin', 2],
      ['strava', 1],
    ])
  })

  it('classifies null source as unknown', () => {
    expect(computeAvailableSources([act({ source: null as any })])).toEqual([['unknown', 1]])
  })
})

describe('computeFilteredActivities', () => {
  const activities = [
    act({ run_id: 'a', sport_category: 'run', distance: 5000, moving_time: 1800, start_date: '2024-01-01T00:00:00Z' }),
    act({ run_id: 'b', sport_category: 'ride', distance: 20000, moving_time: 3600, start_date: '2024-06-15T00:00:00Z' }),
    act({ run_id: 'c', sport_category: 'run', distance: 10000, moving_time: 3000, start_date: '2025-03-01T00:00:00Z' }),
  ]

  it('filters by sport_category', () => {
    const r = computeFilteredActivities(activities, { ...defaultFilters, type: 'run' }, 'date', true, null, null)
    expect(r).toHaveLength(2)
    expect(r.every((a) => a.sport_category === 'run')).toBe(true)
  })

  it('filters by source', () => {
    const r = computeFilteredActivities(activities, { ...defaultFilters, source: 'garmin' }, 'date', true, null, null)
    expect(r.every((a) => a.source === 'garmin')).toBe(true)
  })

  it('filters by distance range', () => {
    const r = computeFilteredActivities(activities, { ...defaultFilters, distanceMin: 8, distanceMax: 15 }, 'date', true, null, null)
    expect(r).toHaveLength(1)
    expect(r[0].distance).toBe(10000)
  })

  it('filters by search term in name', () => {
    const acts = [act({ run_id: '1', name: 'Morning Run' }), act({ run_id: '2', name: 'Evening Ride' })]
    const r = computeFilteredActivities(acts, { ...defaultFilters, search: 'morning' }, 'date', true, null, null)
    expect(r).toHaveLength(1)
    expect(r[0].run_id).toBe('1')
  })

  it('sorts by distance desc', () => {
    const r = computeFilteredActivities(activities, defaultFilters, 'distance', true, null, null)
    expect(r.map((a) => a.distance)).toEqual([20000, 10000, 5000])
  })

  it('sorts by distance asc', () => {
    const r = computeFilteredActivities(activities, defaultFilters, 'distance', false, null, null)
    expect(r.map((a) => a.distance)).toEqual([5000, 10000, 20000])
  })

  it('sorts by time desc', () => {
    const r = computeFilteredActivities(activities, defaultFilters, 'time', true, null, null)
    expect(r.map((a) => a.moving_time)).toEqual([3600, 3000, 1800])
  })

  it('filters by year', () => {
    const r = computeFilteredActivities(activities, defaultFilters, 'date', true, 2024, null)
    expect(r).toHaveLength(2)
  })

  it('filters by year + month', () => {
    const r = computeFilteredActivities(activities, defaultFilters, 'date', true, 2024, 1)
    expect(r).toHaveLength(1)
    expect(r[0].run_id).toBe('a')
  })
})

describe('computeCities', () => {
  it('groups cities and sorts by distance desc', () => {
    const r = computeCities([
      act({ location_country: '北京市朝阳区', distance: 10000 }),
      act({ location_country: '上海', distance: 5000 }),
      act({ location_country: '北京市海淀区', distance: 8000 }),
    ])
    expect(r).toEqual([
      { city: '北京', distance: 18000 },
      { city: '上海', distance: 5000 },
    ])
  })

  it('returns empty for null location_country', () => {
    expect(computeCities([act({ location_country: null })])).toEqual([])
  })

  it('excludes non-Chinese locations', () => {
    expect(computeCities([act({ location_country: 'United States' }), act({ location_country: 'France' })])).toEqual([])
  })

  it('handles empty list', () => {
    expect(computeCities([])).toEqual([])
  })

  it('handles single activity', () => {
    const r = computeCities([act({ location_country: '深圳', distance: 15000 })])
    expect(r).toEqual([{ city: '深圳', distance: 15000 }])
  })
})

describe('computePeriods', () => {
  it('classifies activities into 5 periods', () => {
    const r = computePeriods([
      act({ start_date_local: '2024-06-01T08:00:00' }),
      act({ start_date_local: '2024-06-01T12:00:00' }),
      act({ start_date_local: '2024-06-01T15:00:00' }),
      act({ start_date_local: '2024-06-01T19:00:00' }),
      act({ start_date_local: '2024-06-01T22:00:00' }),
    ])
    expect(r).toHaveLength(5)
    expect(r.map((p) => p.period)).toEqual(['morning', 'noon', 'afternoon', 'evening', 'night'])
    expect(r.every((p) => p.count === 1)).toBe(true)
    expect(r.every((p) => p.pct === 20)).toBe(true)
  })

  it('returns empty for null start_date_local', () => {
    expect(computePeriods([act({ start_date_local: null as any })])).toEqual([])
  })

  it('returns empty for empty list', () => {
    expect(computePeriods([])).toEqual([])
  })

  it('handles garbage date string', () => {
    expect(computePeriods([act({ start_date_local: 'not-a-date' })])).toEqual([])
  })

  it('single period returns 100%', () => {
    const r = computePeriods([act({ start_date_local: '2024-06-01T07:00:00' })])
    expect(r).toHaveLength(1)
    expect(r[0].period).toBe('morning')
    expect(r[0].pct).toBe(100)
  })
})

describe('computeLocationSummary', () => {
  it('aggregates countries, provinces, cities', () => {
    const r = computeLocationSummary([
      act({ location_country: '北京市朝阳区' }),
      act({ location_country: '上海' }),
      act({ location_country: 'United States' }),
    ])
    expect(r.countries).toContain('China')
    expect(r.countries).toContain('United States')
    expect(r.provinces).toContain('北京')
    expect(r.provinces).toContain('上海')
    expect(r.cities).toContain('北京')
    expect(r.cities).toContain('上海')
  })

  it('returns empty for all null location_country', () => {
    const r = computeLocationSummary([act({ location_country: null }), act({ location_country: null })])
    expect(r).toEqual({ countries: [], provinces: [], cities: [] })
  })

  it('deduplicates countries', () => {
    const r = computeLocationSummary([
      act({ location_country: 'United States' }),
      act({ location_country: 'United States' }),
      act({ location_country: 'France' }),
    ])
    expect(r.countries).toEqual(['France', 'United States'])
  })
})
