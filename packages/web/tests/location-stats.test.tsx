import type { Activity } from '@workouts/shared'
import { computeRegionStats, StatsPanel, useSimpleStore } from '@workouts/theme-simple'
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

  it('renders empty section when no activities', () => {
    act(() => {
      root.render(<StatsPanel activities={[]} loading={false} />)
    })
    expect(container.textContent).toBe('')
  })

  it('renders province stats when activities have divisions data', () => {
    const acts = [
      baseAct({ run_id: '1', divisions: [{ p: '河北省', w: 1.0 }], distance: 10000 }),
      baseAct({ run_id: '2', divisions: [{ p: '台湾省', w: 1.0 }], distance: 5000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('河北省')
    expect(container.textContent).toContain('台湾省')
    expect(container.textContent).toContain('10 km')
    expect(container.textContent).toContain('5 km')
  })

  it('renders SAR province rows with correct names', () => {
    const acts = [
      baseAct({ run_id: 'hk', divisions: [{ p: '香港特别行政区', w: 1.0 }], distance: 8000 }),
      baseAct({ run_id: 'mo', divisions: [{ p: '澳门特别行政区', w: 1.0 }], distance: 3000 }),
    ]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('香港特别行政区')
    expect(container.textContent).toContain('澳门特别行政区')
    expect(container.textContent).toContain('8 km')
    expect(container.textContent).toContain('3 km')
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
    const acts = [baseAct({ run_id: '1', divisions: [{ p: '河北省', w: 1.0 }], distance: 10000 })]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    const provinceRow = container.querySelector('.sp-province-row')
    expect(provinceRow).not.toBeNull()

    act(() => {
      ;(provinceRow as HTMLElement).click()
    })
    expect(useSimpleStore.getState().regionFilter).toBe('河北省')
  })

  it('renders 其它 row when activities have no divisions', () => {
    const acts = [baseAct({ run_id: '1', distance: 10000 }), baseAct({ run_id: '2', distance: 5000 })]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    expect(container.textContent).toContain('其它')
    expect(container.textContent).toContain('15 km')
  })

  it('click 其它 row sets regionFilter to 其它', () => {
    const acts = [baseAct({ run_id: '1', distance: 10000 })]
    act(() => {
      root.render(<StatsPanel activities={acts} loading={false} />)
    })
    const otherRow = container.querySelector('.sp-province-row')
    expect(otherRow).not.toBeNull()

    act(() => {
      ;(otherRow as HTMLElement).click()
    })
    expect(useSimpleStore.getState().regionFilter).toBe('其它')
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

describe('computeRegionStats', () => {
  it('returns empty array for no activities', () => {
    expect(computeRegionStats([])).toEqual([])
  })

  it('returns all activities under 其它 when no activities have divisions', () => {
    const acts = [baseAct({}), baseAct({ distance: 8000 })]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ name: '其它', distance: 13000, count: 2 })
  })

  it('places 其它 at end after sorted named regions', () => {
    const acts = [
      baseAct({ run_id: '1', divisions: [{ p: '河北省', w: 1.0 }], distance: 10000 }),
      baseAct({ run_id: '2', distance: 5000 }),
      baseAct({ run_id: '3', divisions: [{ p: '北京市', w: 1.0 }], distance: 2000 }),
    ]
    const result = computeRegionStats(acts).map((r) => r.name)
    expect(result).toEqual(['河北省', '北京市', '其它'])
  })

  it('no 其它 when all activities have divisions', () => {
    const acts = [baseAct({ divisions: [{ p: '河北省', w: 1.0 }] }), baseAct({ divisions: [{ p: '北京市', w: 1.0 }] })]
    const names = computeRegionStats(acts).map((r) => r.name)
    expect(names).not.toContain('其它')
  })

  it('groups by province from divisions', () => {
    const acts = [
      baseAct({ run_id: '1', divisions: [{ p: '河北省', w: 1.0 }], distance: 10000 }),
      baseAct({ run_id: '2', divisions: [{ p: '河北省', w: 1.0 }], distance: 5000 }),
    ]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ name: '河北省', distance: 15000, count: 2 })
  })

  it('handles weighted divisions crossing multiple provinces', () => {
    const acts = [
      baseAct({
        run_id: '1',
        divisions: [
          { p: '河北省', w: 0.6 },
          { p: '北京市', w: 0.4 },
        ],
        distance: 10000,
      }),
    ]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(2)
    expect(result.find((r) => r.name === '河北省')!.distance).toBe(6000)
    expect(result.find((r) => r.name === '北京市')!.distance).toBe(4000)
  })

  it('uses country as province from Nominatim-style divisions', () => {
    const acts = [baseAct({ run_id: '1', divisions: [{ p: 'United States', c: 'California', w: 1.0 }], distance: 8000 })]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0].name).toBe('United States')
  })

  it('sorts by distance descending', () => {
    const acts = [
      baseAct({ run_id: '1', divisions: [{ p: '北京市', w: 1.0 }], distance: 5000 }),
      baseAct({ run_id: '2', divisions: [{ p: '河北省', w: 1.0 }], distance: 15000 }),
      baseAct({ run_id: '3', divisions: [{ p: '上海市', w: 1.0 }], distance: 10000 }),
    ]
    const result = computeRegionStats(acts).map((r) => r.name)
    expect(result).toEqual(['河北省', '上海市', '北京市'])
  })

  it('handles Hong Kong SAR province', () => {
    const acts = [baseAct({ divisions: [{ p: '香港特别行政区', w: 1.0 }], distance: 12000 })]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ name: '香港特别行政区', distance: 12000, count: 1 })
  })

  it('handles Macau SAR province', () => {
    const acts = [baseAct({ divisions: [{ p: '澳门特别行政区', w: 1.0 }], distance: 6000 })]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ name: '澳门特别行政区', distance: 6000, count: 1 })
  })

  it('handles Taiwan province', () => {
    const acts = [baseAct({ divisions: [{ p: '台湾省', w: 1.0 }], distance: 20000 })]
    const result = computeRegionStats(acts)
    expect(result).toHaveLength(1)
    expect(result[0]).toMatchObject({ name: '台湾省', distance: 20000, count: 1 })
  })

  it('handles mix of SAR and regular provinces sorted by distance', () => {
    const acts = [
      baseAct({ divisions: [{ p: '香港特别行政区', w: 1.0 }], distance: 5000 }),
      baseAct({ divisions: [{ p: '河北省', w: 1.0 }], distance: 15000 }),
      baseAct({ divisions: [{ p: '台湾省', w: 1.0 }], distance: 10000 }),
      baseAct({ divisions: [{ p: '澳门特别行政区', w: 1.0 }], distance: 3000 }),
    ]
    const result = computeRegionStats(acts).map((r) => ({ name: r.name, distance: r.distance }))
    expect(result).toEqual([
      { name: '河北省', distance: 15000 },
      { name: '台湾省', distance: 10000 },
      { name: '香港特别行政区', distance: 5000 },
      { name: '澳门特别行政区', distance: 3000 },
    ])
  })
})
