import type { Activity } from '@workouts/shared'
import { useSimpleStore, YearStats } from '@workouts/theme-simple'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

function baseAct(overrides: Partial<Activity> = {}): Activity {
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

describe('YearStats', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    useSimpleStore.setState({
      activities: [],
      selectedYear: null,
      selectedMonth: null,
      years: [],
      filteredActivities: [],
    })
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('empty: no activities renders Total label, 0 streak, no categories', () => {
    act(() => {
      root.render(<YearStats year={null} />)
    })
    expect(container.textContent).toContain('TotalJourney')
    expect(container.textContent).toContain('0 dayStreak')
    expect(container.textContent).not.toContain('Moving Time')
    expect(container.textContent).not.toContain('Elevation')
    expect(container.textContent).not.toContain('More')
    expect(container.textContent).not.toContain('Less')
  })

  it('empty with year filter shows year label', () => {
    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).toContain('2024Journey')
    expect(container.textContent).not.toContain('Runs')
    expect(container.textContent).not.toContain('km')
  })

  it('populated: renders stats for given year', () => {
    const acts = [
      baseAct({
        run_id: '1',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        elevation_gain: 200,
        start_date: '2024-01-01T00:00:00Z',
      }),
      baseAct({
        run_id: '2',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        elevation_gain: 200,
        start_date: '2024-01-02T00:00:00Z',
      }),
      baseAct({
        run_id: '3',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        elevation_gain: 200,
        start_date: '2024-01-03T00:00:00Z',
      }),
    ]
    useSimpleStore.setState({
      activities: acts,
      selectedYear: null,
      selectedMonth: null,
      years: [2024],
      filteredActivities: acts,
    })

    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).toContain('2024Journey')
    expect(container.textContent).toContain('×3 run')
    expect(container.textContent).toContain('30km')
    expect(container.textContent).toContain('3 dayStreak')
    expect(container.textContent).toContain('Moving Time')
    expect(container.textContent).toContain('Elevation')
    expect(container.textContent).toContain('600m')
    expect(container.textContent).not.toContain('Runs')
    expect(container.textContent).not.toContain('More')
    expect(container.textContent).not.toContain('Less')
  })

  it('null year (Total): aggregates all activities', () => {
    const acts = [
      baseAct({ run_id: '1', distance: 10000, moving_time: 1800, average_speed: 4, start_date: '2024-06-01T00:00:00Z' }),
      baseAct({ run_id: '2', distance: 5000, moving_time: 900, average_speed: 4, start_date: '2025-06-01T00:00:00Z' }),
    ]
    useSimpleStore.setState({
      activities: acts,
      selectedYear: null,
      selectedMonth: null,
      years: [2024, 2025],
      filteredActivities: acts,
    })

    act(() => {
      root.render(<YearStats year={null} />)
    })
    expect(container.textContent).toContain('TotalJourney')
    expect(container.textContent).toContain('×2 run')
    expect(container.textContent).toContain('15km')
  })

  it('category breakdown: multiple sport types', () => {
    const acts = [
      baseAct({ run_id: '1', sport_category: 'run', distance: 10000, start_date: '2024-01-01T00:00:00Z' }),
      baseAct({ run_id: '2', sport_category: 'ride', distance: 40000, start_date: '2024-01-02T00:00:00Z' }),
      baseAct({ run_id: '3', sport_category: 'run', distance: 20000, start_date: '2024-01-03T00:00:00Z' }),
    ]
    useSimpleStore.setState({
      activities: acts,
      selectedYear: null,
      selectedMonth: null,
      years: [2024],
      filteredActivities: acts,
    })

    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).toContain('×1 ride')
    expect(container.textContent).toContain('40km')
    expect(container.textContent).toContain('×2 run')
    expect(container.textContent).toContain('30km')
  })

  it('moving time hides when zero', () => {
    const acts = [baseAct({ run_id: '1', distance: 5000, moving_time: 0, start_date: '2024-01-01T00:00:00Z' })]
    useSimpleStore.setState({
      activities: acts,
      selectedYear: null,
      selectedMonth: null,
      years: [2024],
      filteredActivities: acts,
    })

    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).not.toContain('Moving Time')
  })

  it('elevation gain hides when zero', () => {
    const acts = [baseAct({ run_id: '1', distance: 5000, elevation_gain: 0, start_date: '2024-01-01T00:00:00Z' })]
    useSimpleStore.setState({
      activities: acts,
      selectedYear: null,
      selectedMonth: null,
      years: [2024],
      filteredActivities: acts,
    })

    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).not.toContain('Elevation')
  })
})
