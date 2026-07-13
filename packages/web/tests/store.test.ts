import { describe, it, expect } from 'vitest'
import { useOverviewStore } from '@workouts/theme-overview'
import type { Activity } from '@workouts/shared'

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

describe('useOverviewStore', () => {
  it('initializes with empty state', () => {
    const s = useOverviewStore.getState()
    expect(s.activities).toEqual([])
    expect(s.years).toEqual([])
    expect(s.availableTypes).toEqual([])
    expect(s.availableSources).toEqual([])
    expect(s.filteredActivities).toEqual([])
    expect(s.filters).toEqual({ type: '', source: '', distanceMin: null, distanceMax: null, search: '' })
  })

  it('setActivities computes derived data', () => {
    const { setActivities } = useOverviewStore.getState()
    setActivities([
      act({ start_date: '2024-01-01T00:00:00Z', sport_category: 'run', source: 'garmin' }),
      act({ start_date: '2025-06-15T00:00:00Z', sport_category: 'ride', source: 'strava' }),
    ])
    const s = useOverviewStore.getState()
    expect(s.years).toEqual([2025, 2024])
    expect(s.availableTypes).toEqual([['run', 1], ['ride', 1]])
    expect(s.availableSources).toEqual([['garmin', 1], ['strava', 1]])
    expect(s.filteredActivities).toHaveLength(2)
  })

  it('setFilter filters by type', () => {
    const { setActivities, setFilter } = useOverviewStore.getState()
    setActivities([
      act({ run_id: 'a', sport_category: 'run' }),
      act({ run_id: 'b', sport_category: 'ride' }),
    ])
    setFilter({ type: 'run' })
    expect(useOverviewStore.getState().filteredActivities).toHaveLength(1)
    expect(useOverviewStore.getState().filteredActivities[0].run_id).toBe('a')
  })

  it('setFilter clears type filter', () => {
    const { setFilter } = useOverviewStore.getState()
    setFilter({ type: '' })
    expect(useOverviewStore.getState().filteredActivities).toHaveLength(2)
  })

  it('setSelectedYear filters activities', () => {
    const { setActivities, setSelectedYear } = useOverviewStore.getState()
    setActivities([
      act({ run_id: 'a', start_date: '2024-01-01T00:00:00Z' }),
      act({ run_id: 'b', start_date: '2025-06-15T00:00:00Z' }),
    ])
    setSelectedYear(2024)
    expect(useOverviewStore.getState().filteredActivities).toHaveLength(1)
    expect(useOverviewStore.getState().filteredActivities[0].run_id).toBe('a')
  })

  it('toggleSort changes sort field', () => {
    const { setActivities, toggleSort } = useOverviewStore.getState()
    setActivities([
      act({ run_id: 'a', distance: 5000 }),
      act({ run_id: 'b', distance: 10000 }),
    ])
    toggleSort('distance')
    const s = useOverviewStore.getState()
    expect(s.sortField).toBe('distance')
    expect(s.sortDesc).toBe(true)
    expect(s.filteredActivities[0].run_id).toBe('b')
  })

  it('toggleSort same field toggles direction', () => {
    const { toggleSort } = useOverviewStore.getState()
    toggleSort('distance')
    const s = useOverviewStore.getState()
    expect(s.sortField).toBe('distance')
    expect(s.sortDesc).toBe(false)
  })

  it('openDetail sets selected activity', () => {
    const { openDetail } = useOverviewStore.getState()
    const a = act({ run_id: 'test-1' })
    openDetail(a)
    const s = useOverviewStore.getState()
    expect(s.selectedActivity?.run_id).toBe('test-1')
    expect(s.detailOpen).toBe(true)
    expect(s.drawerOpen).toBe(false)
  })

  it('closeDetail clears selection', () => {
    const { closeDetail } = useOverviewStore.getState()
    closeDetail()
    expect(useOverviewStore.getState().detailOpen).toBe(false)
    expect(useOverviewStore.getState().selectedActivity).toBeNull()
  })

  it('resetFilters clears filters and month', () => {
    const { setFilter, setSelectedMonth, resetFilters } = useOverviewStore.getState()
    setFilter({ search: 'test' })
    setSelectedMonth(3)
    resetFilters()
    const s = useOverviewStore.getState()
    expect(s.filters.search).toBe('')
    expect(s.selectedMonth).toBeNull()
  })

  it('toggleDrawer toggles drawer', () => {
    const { toggleDrawer, drawerOpen } = useOverviewStore.getState()
    expect(drawerOpen).toBe(false)
    toggleDrawer()
    expect(useOverviewStore.getState().drawerOpen).toBe(true)
    toggleDrawer()
    expect(useOverviewStore.getState().drawerOpen).toBe(false)
  })

  it('setColorMode changes color mode', () => {
    const { setColorMode } = useOverviewStore.getState()
    setColorMode('speed')
    expect(useOverviewStore.getState().colorMode).toBe('speed')
  })
})
