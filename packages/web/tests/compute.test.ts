import {
  computeAvailableSources,
  computeAvailableTypes,
  computeFilteredActivities,
  computeLocationSummary,
  computePeriods,
  computePeriods3,
  computeProvinceStats,
  computeTypeBreakdown,
  computeYears,
} from '@workouts/plugin-data-source'
import type { Activity } from '@workouts/shared'
import { computeYearStats } from '@workouts/theme-simple'
import { describe, expect, it, vi } from 'vitest'

vi.mock('leaflet', () => ({
  default: { map: vi.fn(), tileLayer: vi.fn(), polyline: vi.fn(), control: { zoom: vi.fn() }, latLngBounds: vi.fn(), latLng: vi.fn() },
}))

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
  it('aggregates provinces from text fallback', () => {
    const r = computeLocationSummary([act({ location_country: '北京市朝阳区' }), act({ location_country: '上海' })])
    expect(r.countries).toContain('China')
    expect(r.provinces).toContain('北京')
    expect(r.provinces).toContain('上海')
  })

  it('returns empty for all null location_country', () => {
    const r = computeLocationSummary([act({ location_country: null }), act({ location_country: null })])
    expect(r).toEqual({ countries: [], provinces: [], cities: [] })
  })

  it('deduplicates countries', () => {
    const r = computeLocationSummary([act({ location_country: '北京市朝阳区' }), act({ location_country: '上海市浦东区' })])
    expect(r.countries).toEqual(['China'])
    expect(r.provinces.length).toBeGreaterThanOrEqual(1)
  })
})

describe('computeYearStats', () => {
  it('normal: 3 runs with known values', () => {
    const acts = [
      act({
        run_id: '1',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        start_date: '2024-01-01T00:00:00Z',
      }),
      act({
        run_id: '2',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        start_date: '2024-01-02T00:00:00Z',
      }),
      act({
        run_id: '3',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        start_date: '2024-01-03T00:00:00Z',
      }),
    ]
    const r = computeYearStats(acts)
    expect(r.count).toBe(3)
    expect(r.distance).toBe(30000)
    expect(r.movingTime).toBe(5400)
    expect(r.elevationGain).toBe(600)
    expect(r.avgHeartrate).toBe(150)
    expect(r.maxHeartrate).toBe(165)
    expect(r.avgCadence).toBeNull()
    expect(r.avgPower).toBeNull()
    expect(r.avgTemperature).toBeNull()
    expect(r.calories).toBe(0)
    expect(r.avgSpeed).toBe(4)
    expect(r.pace).toBe(4)
    expect(r.streak).toBe(3)
    expect(r.categoryBreakdown).toEqual([{ category: 'run', distanceKm: 30, count: 3 }])
  })

  it('null fields: all optional fields null', () => {
    const acts = [act({ distance: 5000, moving_time: 1800, start_date: '2024-06-01T00:00:00Z' })]
    const r = computeYearStats(acts)
    expect(r.count).toBe(1)
    expect(r.distance).toBe(5000)
    expect(r.movingTime).toBe(1800)
    expect(r.elevationGain).toBe(0)
    expect(r.avgHeartrate).toBeNull()
    expect(r.maxHeartrate).toBeNull()
    expect(r.avgCadence).toBeNull()
    expect(r.maxCadence).toBeNull()
    expect(r.avgPower).toBeNull()
    expect(r.maxPower).toBeNull()
    expect(r.avgTemperature).toBeNull()
    expect(r.calories).toBe(0)
    expect(r.avgSpeed).toBeNull()
    expect(r.pace).toBeNull()
    expect(r.streak).toBe(1)
    expect(r.categoryBreakdown).toEqual([{ category: 'run', distanceKm: 5, count: 1 }])
  })

  it('empty: empty array', () => {
    const r = computeYearStats([])
    expect(r.count).toBe(0)
    expect(r.distance).toBe(0)
    expect(r.movingTime).toBe(0)
    expect(r.avgHeartrate).toBeNull()
    expect(r.avgSpeed).toBeNull()
    expect(r.pace).toBeNull()
    expect(r.streak).toBe(0)
    expect(r.categoryBreakdown).toEqual([])
  })

  it('mixed categories: run + ride', () => {
    const acts = [
      act({
        run_id: '1',
        sport_category: 'ride',
        distance: 40000,
        moving_time: 3600,
        average_speed: 8,
        start_date: '2024-01-01T00:00:00Z',
      }),
      act({ run_id: '2', sport_category: 'run', distance: 10000, moving_time: 1800, average_speed: 4, start_date: '2024-01-02T00:00:00Z' }),
    ]
    const r = computeYearStats(acts)
    expect(r.count).toBe(2)
    expect(r.distance).toBe(50000)
    expect(r.avgSpeed).toBe(6)
    expect(r.pace).toBe(4)
    expect(r.categoryBreakdown).toEqual([
      { category: 'ride', distanceKm: 40, count: 1 },
      { category: 'run', distanceKm: 10, count: 1 },
    ])
  })

  it('single activity: streak=1', () => {
    const r = computeYearStats([act({ start_date: '2024-01-01T00:00:00Z' })])
    expect(r.streak).toBe(1)
  })

  it('pace guard: zero average_speed and valid speed', () => {
    const acts = [
      act({ run_id: '1', sport_category: 'run', distance: 10000, average_speed: 0, start_date: '2024-01-01T00:00:00Z' }),
      act({ run_id: '2', sport_category: 'run', distance: 10000, average_speed: 4, start_date: '2024-01-02T00:00:00Z' }),
    ]
    const r = computeYearStats(acts)
    expect(r.avgSpeed).toBe(4)
    expect(r.pace).toBe(4)

    const allZero = [
      act({ run_id: '1', sport_category: 'run', distance: 10000, average_speed: 0, start_date: '2024-01-01T00:00:00Z' }),
      act({ run_id: '2', sport_category: 'run', distance: 10000, average_speed: 0, start_date: '2024-01-02T00:00:00Z' }),
    ]
    const r2 = computeYearStats(allZero)
    expect(r2.pace).toBeNull()
    expect(r2.avgSpeed).toBeNull()
  })

  it('categoryBreakdown: multiple categories sorted by distance desc', () => {
    const acts = [
      act({ run_id: '1', sport_category: 'run', distance: 20000, start_date: '2024-01-01T00:00:00Z' }),
      act({ run_id: '2', sport_category: 'ride', distance: 50000, start_date: '2024-02-01T00:00:00Z' }),
      act({ run_id: '3', sport_category: 'run', distance: 10000, start_date: '2024-03-01T00:00:00Z' }),
      act({ run_id: '4', sport_category: 'swim', distance: 3000, start_date: '2024-04-01T00:00:00Z' }),
    ]
    const r = computeYearStats(acts)
    expect(r.categoryBreakdown).toEqual([
      { category: 'ride', distanceKm: 50, count: 1 },
      { category: 'run', distanceKm: 30, count: 2 },
      { category: 'swim', distanceKm: 3, count: 1 },
    ])
  })
})

describe('computePeriods3', () => {
  it('classifies activities into 3 periods', () => {
    const r = computePeriods3([
      act({ start_date_local: '2024-06-01T06:00:00' }),
      act({ start_date_local: '2024-06-01T14:00:00' }),
      act({ start_date_local: '2024-06-01T20:00:00' }),
    ])
    expect(r).toHaveLength(3)
    expect(r.map((p) => p.period)).toEqual(['morning', 'afternoon', 'evening'])
    expect(r.every((p) => p.count === 1)).toBe(true)
    expect(r.every((p) => p.pct === 33)).toBe(true)
  })

  it('uses correct labels', () => {
    const r = computePeriods3([act({ start_date_local: '2024-06-01T06:00:00' })])
    expect(r[0].label).toBe('早')
  })

  it('returns empty for null start_date_local', () => {
    expect(computePeriods3([act({ start_date_local: null as any })])).toEqual([])
  })

  it('returns empty for empty list', () => {
    expect(computePeriods3([])).toEqual([])
  })

  it('handles garbage date string', () => {
    expect(computePeriods3([act({ start_date_local: 'not-a-date' })])).toEqual([])
  })

  it('single period returns 100%', () => {
    const r = computePeriods3([act({ start_date_local: '2024-06-01T06:00:00' })])
    expect(r).toHaveLength(1)
    expect(r[0].period).toBe('morning')
    expect(r[0].pct).toBe(100)
  })
})

describe('computeTypeBreakdown', () => {
  it('groups by sport_category with counts and distances', () => {
    const r = computeTypeBreakdown([
      act({ run_id: '1', sport_category: 'run', distance: 10000 }),
      act({ run_id: '2', sport_category: 'ride', distance: 40000 }),
      act({ run_id: '3', sport_category: 'run', distance: 5000 }),
    ])
    expect(r).toHaveLength(2)
    expect(r[0].type).toBe('ride')
    expect(r[0].count).toBe(1)
    expect(r[0].distance).toBe(40000)
    expect(r[0].label).toBe('Cycling')
    expect(r[0].pct).toBe(73) // 40/55 ≈ 73%
    expect(r[1].type).toBe('run')
    expect(r[1].count).toBe(2)
    expect(r[1].distance).toBe(15000)
    expect(r[1].label).toBe('Running')
    expect(r[1].pct).toBe(27) // 15/55 ≈ 27%
  })

  it('single type shows 100% and is the only entry', () => {
    const r = computeTypeBreakdown([act({ sport_category: 'run', distance: 5000 })])
    expect(r).toHaveLength(1)
    expect(r[0].pct).toBe(100)
    expect(r[0].type).toBe('run')
  })

  it('returns empty for empty list', () => {
    expect(computeTypeBreakdown([])).toEqual([])
  })

  it('handles null sport_category as other', () => {
    const r = computeTypeBreakdown([act({ sport_category: null as any })])
    expect(r).toHaveLength(1)
    expect(r[0].type).toBe('other')
  })
})

describe('computeProvinceStats', () => {
  it('groups provinces by text fallback', () => {
    const r = computeProvinceStats([
      act({ run_id: '1', location_country: '北京市朝阳区', distance: 10000 }),
      act({ run_id: '2', location_country: '上海', distance: 5000 }),
    ])
    expect(r.length).toBeGreaterThanOrEqual(1)
    expect(r[0].distance).toBeGreaterThan(0)
  })

  it('handles international text fallback', () => {
    const r = computeProvinceStats([act({ location_country: 'United States', distance: 5000 })])
    expect(r.length).toBe(1)
    expect(r[0].distance).toBe(5000)
  })

  it('returns empty for empty list', () => {
    expect(computeProvinceStats([])).toEqual([])
  })

  it('returns empty for null location_country', () => {
    expect(computeProvinceStats([act({ location_country: null })])).toEqual([])
  })
})
