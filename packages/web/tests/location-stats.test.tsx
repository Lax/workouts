import type { Activity } from '@workouts/shared'
import { LocationStats, useSimpleStore } from '@workouts/theme-simple'
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

describe('LocationStats', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    useSimpleStore.setState({
      activities: [],
      cityFilter: null,
      periodFilter: null,
    })
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('renders loading state', () => {
    act(() => {
      root.render(<LocationStats activities={[]} loading={true} />)
    })
    expect(container.textContent).toContain('Loading')
  })

  it('renders empty state when no activities', () => {
    act(() => {
      root.render(<LocationStats activities={[]} loading={false} />)
    })
    expect(container.textContent).toContain('暂无位置数据')
  })

  it('renders cities when activities have location data', () => {
    const acts = [
      baseAct({ run_id: '1', location_country: '北京', distance: 10000 }),
      baseAct({ run_id: '2', location_country: '上海', distance: 5000 }),
    ]
    act(() => {
      root.render(<LocationStats activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('北京')
    expect(container.textContent).toContain('上海')
    expect(container.textContent).toContain('10 km')
    expect(container.textContent).toContain('5 km')
  })

  it('click city row sets cityFilter in store', () => {
    const acts = [baseAct({ run_id: '1', location_country: '北京', distance: 10000 })]
    act(() => {
      root.render(<LocationStats activities={acts} loading={false} />)
    })
    const cityRow = container.querySelector('.loc-city-row')
    expect(cityRow).not.toBeNull()

    act(() => {
      ;(cityRow as HTMLElement).click()
    })
    expect(useSimpleStore.getState().cityFilter).toBe('北京')
  })
})
