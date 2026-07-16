import type { Activity } from '@workouts/shared'
import { StatsPanel, useSimpleStore } from '@workouts/theme-simple'
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

describe('StatsPanel', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    useSimpleStore.setState({
      activities: [],
      regionFilter: null,
      typeFilter: null,
    })
  })

  afterEach(() => {
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('renders loading state', () => {
    act(() => {
      root.render(<StatsPanel activities={[]} loading={true} />)
    })
    expect(container.textContent).toContain('Loading')
  })

  it('renders empty state when no activities', () => {
    act(() => {
      root.render(<StatsPanel activities={[]} loading={false} />)
    })
    expect(container.textContent).toContain('暂无位置数据')
  })

  it('renders province stats when activities have Chinese location data', () => {
    const acts = [
      baseAct({ run_id: '1', location_country: '北京市朝阳区', distance: 10000 }),
      baseAct({ run_id: '2', location_country: '上海', distance: 5000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('北京')
    expect(container.textContent).toContain('上海')
    expect(container.textContent).toContain('10 km')
    expect(container.textContent).toContain('5 km')
  })

  it('renders type section when multiple sport categories exist', () => {
    const acts = [
      baseAct({ run_id: '1', sport_category: 'run', distance: 10000 }),
      baseAct({ run_id: '2', sport_category: 'ride', distance: 40000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('Running')
    expect(container.textContent).toContain('Cycling')
  })

  it('hides type section when only one sport category', () => {
    const acts = [
      baseAct({ run_id: '1', sport_category: 'run', distance: 10000 }),
      baseAct({ run_id: '2', sport_category: 'run', distance: 5000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    // Check that Running label only appears once (in type label)
    // Single type should hide the section entirely
    expect(container.querySelector('.sp-types')).toBeNull()
  })

  it('click province row sets regionFilter in store', () => {
    const acts = [baseAct({ run_id: '1', location_country: '北京', distance: 10000 })]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    const provinceRow = container.querySelector('.sp-region-row')
    expect(provinceRow).not.toBeNull()

    act(() => {
      ;(provinceRow as HTMLElement).click()
    })
    expect(useSimpleStore.getState().regionFilter).toBe('北京')
  })

  it('click type row sets typeFilter in store', () => {
    const acts = [
      baseAct({ run_id: '1', sport_category: 'run', distance: 10000 }),
      baseAct({ run_id: '2', sport_category: 'ride', distance: 40000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    const typeRows = container.querySelectorAll('.sp-type-row')
    expect(typeRows.length).toBeGreaterThanOrEqual(1)

    act(() => {
      ;(typeRows[0] as HTMLElement).click()
    })
    // First row is ride (highest distance)
    expect(useSimpleStore.getState().typeFilter).toBe('ride')
  })
})
