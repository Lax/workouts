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

  it('empty: no activities renders Total label, 0 Runs, 0 km, 0 day Streak, no category breakdown', () => {
    act(() => {
      root.render(<YearStats year={null} />)
    })
    expect(container.textContent).toContain('TotalJourney')
    expect(container.textContent).toContain('0Runs')
    expect(container.textContent).toContain('0.0km')
    expect(container.textContent).toContain('0 dayStreak')
    expect(container.textContent).not.toContain('Elevation Gain')
    expect(container.textContent).not.toContain('Avg Heart Rate')
    expect(container.textContent).not.toContain('Avg Pace')
    expect(container.textContent).not.toContain('Moving Time')
    expect(container.textContent).not.toContain('·')
  })

  it('empty with year filter shows year label', () => {
    act(() => {
      root.render(<YearStats year={2024} />)
    })
    expect(container.textContent).toContain('2024Journey')
    expect(container.textContent).toContain('0Runs')
    expect(container.textContent).toContain('0.0km')
  })

  it('populated: renders stats for given year', () => {
    const acts = [
      baseAct({
        run_id: '1',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        calories: 500,
        start_date: '2024-01-01T00:00:00Z',
      }),
      baseAct({
        run_id: '2',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        calories: 500,
        start_date: '2024-01-02T00:00:00Z',
      }),
      baseAct({
        run_id: '3',
        sport_category: 'run',
        distance: 10000,
        moving_time: 1800,
        average_speed: 4,
        average_heartrate: 150,
        max_heartrate: 165,
        elevation_gain: 200,
        calories: 500,
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
    expect(container.textContent).toContain('3Runs')
    expect(container.textContent).toContain('30.0km')
    expect(container.textContent).toContain('1h 30mMoving Time')
    expect(container.textContent).toContain('600Elevation Gain')
    expect(container.textContent).toContain('3 dayStreak')
    expect(container.textContent).toContain('150Avg Heart Rate')
    expect(container.textContent).toContain('165Max Heart Rate')
    expect(container.textContent).toContain('1,500Calories')
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
    expect(container.textContent).toContain('2Runs')
    expect(container.textContent).toContain('15.0km')
    expect(container.textContent).toContain('1 dayStreak')
  })

  it('conditional hiding: all HR/power/temp null — those lines not rendered', () => {
    const acts = [
      baseAct({
        run_id: '1',
        distance: 5000,
        moving_time: 1800,
        average_speed: 4,
        elevation_gain: 0,
        calories: 0,
        average_heartrate: null,
        max_heartrate: null,
        average_cadence: null,
        average_power: null,
        average_temperature: null,
        start_date: '2024-01-01T00:00:00Z',
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
    expect(container.textContent).toContain('1Runs')
    expect(container.textContent).not.toContain('Avg Heart Rate')
    expect(container.textContent).not.toContain('Max Heart Rate')
    expect(container.textContent).not.toContain('Avg Cadence')
    expect(container.textContent).not.toContain('Avg Power')
    expect(container.textContent).not.toContain('Avg Temp')
    expect(container.textContent).not.toContain('Elevation Gain')
    expect(container.textContent).not.toContain('Calories')
  })

  it('category breakdown: 2 runs + 1 ride shows both sorted by distance desc', () => {
    const acts = [
      baseAct({
        run_id: '1',
        sport_category: 'run',
        distance: 10000,
        start_date: '2024-01-01T00:00:00Z',
      }),
      baseAct({
        run_id: '2',
        sport_category: 'ride',
        distance: 40000,
        start_date: '2024-01-02T00:00:00Z',
      }),
      baseAct({
        run_id: '3',
        sport_category: 'run',
        distance: 20000,
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
    expect(container.textContent).toContain('Ride 40km')
    expect(container.textContent).toContain('Run 30km')
  })

  it('moving time hides when zero', () => {
    const acts = [
      baseAct({
        run_id: '1',
        distance: 5000,
        moving_time: 0,
        start_date: '2024-01-01T00:00:00Z',
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
    expect(container.textContent).not.toContain('Moving Time')
  })

  it('pace hides when null', () => {
    const acts = [
      baseAct({
        run_id: '1',
        distance: 5000,
        moving_time: 1800,
        average_speed: null,
        start_date: '2024-01-01T00:00:00Z',
        sport_category: 'run',
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
    expect(container.textContent).not.toContain('Avg Pace')
  })
})
