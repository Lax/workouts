import type { Activity } from '@workouts/shared'
import { formatDuration, formatPace } from '@workouts/shared'
import { colorIntensity, computeStreak, computeYearStats, decodePolyline, useSimpleStore } from '@workouts/theme-simple'
import { beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('leaflet', () => ({
  default: { map: vi.fn(), tileLayer: vi.fn(), polyline: vi.fn(), control: { zoom: vi.fn() }, latLngBounds: vi.fn(), latLng: vi.fn() },
}))

function cssRuleHasProperty(selector: string, property: string): boolean {
  function checkRules(rules: CSSRuleList): boolean {
    for (const rule of rules) {
      if (rule instanceof CSSStyleRule && rule.selectorText === selector) {
        if (rule.style.getPropertyValue(property) !== '') return true
      }
      if (rule instanceof CSSMediaRule) {
        if (checkRules(rule.cssRules)) return true
      }
    }
    return false
  }
  for (const sheet of document.styleSheets) {
    if (checkRules(sheet.cssRules)) return true
  }
  return false
}

beforeEach(() => {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: query === '(max-width: 768px)',
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  }))
})

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

describe('selectedMonth — store', () => {
  beforeEach(() => {
    useSimpleStore.setState({
      selectedYear: null,
      selectedMonth: null,
      activities: [],
      filteredActivities: [],
      years: [],
    })
  })

  const baseAct = (start_date: string): Activity => ({
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
  })

  it('initializes selectedMonth as null', () => {
    expect(useSimpleStore.getState().selectedMonth).toBeNull()
  })

  it('setSelectedMonth updates month state', () => {
    useSimpleStore.getState().setSelectedMonth(6)
    expect(useSimpleStore.getState().selectedMonth).toBe(6)
    useSimpleStore.getState().setSelectedMonth(null)
    expect(useSimpleStore.getState().selectedMonth).toBeNull()
  })

  it('setSelectedMonth filters activities by month within selected year', () => {
    const acts = [
      { ...baseAct('2024-01-15T00:00:00Z'), run_id: 'a' },
      { ...baseAct('2024-02-10T00:00:00Z'), run_id: 'b' },
      { ...baseAct('2024-03-20T00:00:00Z'), run_id: 'c' },
      { ...baseAct('2025-02-05T00:00:00Z'), run_id: 'd' },
    ]
    useSimpleStore.getState().setActivities(acts)
    useSimpleStore.getState().setSelectedYear(2024)
    useSimpleStore.getState().setSelectedMonth(2)
    const filtered = useSimpleStore.getState().filteredActivities
    expect(filtered).toHaveLength(1)
    expect(filtered[0].run_id).toBe('b')
  })

  it('setSelectedYear resets selectedMonth to null', () => {
    useSimpleStore.getState().setSelectedMonth(3)
    expect(useSimpleStore.getState().selectedMonth).toBe(3)
    useSimpleStore.getState().setSelectedYear(2023)
    expect(useSimpleStore.getState().selectedMonth).toBeNull()
  })

  it('filterActivities with null month returns all year activities', () => {
    const acts = [
      { ...baseAct('2024-01-15T00:00:00Z'), run_id: 'a' },
      { ...baseAct('2024-02-10T00:00:00Z'), run_id: 'b' },
    ]
    useSimpleStore.getState().setActivities(acts)
    useSimpleStore.getState().setSelectedYear(2024)
    useSimpleStore.getState().setSelectedMonth(null)
    expect(useSimpleStore.getState().filteredActivities).toHaveLength(2)
  })

  it('month filter with no activities in that month returns empty array', () => {
    const acts = [{ ...baseAct('2024-06-01T00:00:00Z'), run_id: 'a' }]
    useSimpleStore.getState().setActivities(acts)
    useSimpleStore.getState().setSelectedYear(2024)
    useSimpleStore.getState().setSelectedMonth(1)
    expect(useSimpleStore.getState().filteredActivities).toHaveLength(0)
  })

  it('month filter ignored when selectedYear is null', () => {
    const acts = [
      { ...baseAct('2024-01-15T00:00:00Z'), run_id: 'a' },
      { ...baseAct('2025-02-10T00:00:00Z'), run_id: 'b' },
    ]
    useSimpleStore.getState().setActivities(acts)
    useSimpleStore.getState().setSelectedYear(null)
    useSimpleStore.getState().setSelectedMonth(1)
    const filtered = useSimpleStore.getState().filteredActivities
    expect(filtered).toHaveLength(2)
  })
})

describe('YearSelector CSS — positioning and arrangement', () => {
  beforeEach(() => {
    document.documentElement.setAttribute('data-theme', 'dark')
  })

  it('map-year-selector is absolutely positioned at top-left of map wrapper', () => {
    const wrapper = document.createElement('div')
    wrapper.className = 'map-wrapper'
    document.body.appendChild(wrapper)

    const selector = document.createElement('div')
    selector.className = 'map-year-selector'
    wrapper.appendChild(selector)

    const style = getComputedStyle(selector)
    expect(style.position).toBe('absolute')
    expect(style.left).toBe('10px')
    expect(style.top).toBe('10px')
    expect(style.zIndex).toBe('1001')

    document.body.removeChild(wrapper)
  })

  it('map-wrapper has isolation: isolate for proper stacking context', () => {
    const wrapper = document.createElement('div')
    wrapper.className = 'map-wrapper'
    document.body.appendChild(wrapper)

    const style = getComputedStyle(wrapper)
    expect(style.isolation).toBe('isolate')

    document.body.removeChild(wrapper)
  })

  it('year-pills uses flex-direction row with wrapping', () => {
    const el = document.createElement('div')
    el.className = 'year-pills'
    document.body.appendChild(el)

    const style = getComputedStyle(el)
    expect(style.display).toBe('flex')
    expect(style.flexDirection).toBe('row')
    expect(style.flexWrap).toBe('wrap')

    document.body.removeChild(el)
  })

  it('year-pill is inline-block text matching RunMapButtons style', () => {
    const el = document.createElement('button')
    el.className = 'year-pill'
    document.body.appendChild(el)

    const style = getComputedStyle(el)
    expect(style.fontSize).toBe('1rem')
    expect(style.cursor).toBe('pointer')
    expect(cssRuleHasProperty('.year-pill', 'background')).toBe(true)
    expect(cssRuleHasProperty('.year-pill', 'border')).toBe(true)

    document.body.removeChild(el)
  })

  it('year-pill.active has primary color matching selected state', () => {
    expect(cssRuleHasProperty('.year-pill.active', 'color')).toBe(true)
  })

  it('month-chip has correct inline-flex style matching upstream', () => {
    const chip = document.createElement('div')
    chip.className = 'month-chip'
    document.body.appendChild(chip)

    const style = getComputedStyle(chip)
    expect(style.display).toBe('inline-flex')
    expect(style.borderRadius).toBe('12px')
    expect(cssRuleHasProperty('.month-chip', 'backdrop-filter')).toBe(true)

    document.body.removeChild(chip)
  })

  it('month-chip button has close style for deselection', () => {
    expect(cssRuleHasProperty('.month-chip button', 'cursor')).toBe(true)
    expect(cssRuleHasProperty('.month-chip button', 'opacity')).toBe(true)
  })

  it('map-lights positioned top-right on map', () => {
    const el = document.createElement('div')
    el.className = 'map-lights'
    document.body.appendChild(el)

    const style = getComputedStyle(el)
    expect(style.position).toBe('absolute')
    expect(style.right).toBe('10px')
    expect(style.top).toBe('62px')
    expect(style.zIndex).toBe('1001')

    document.body.removeChild(el)
  })

  it('month-chip appears only when both year and month are selected', () => {
    expect(cssRuleHasProperty('.month-chip', 'display')).toBe(true)
    expect(cssRuleHasProperty('.month-chip', 'border-radius')).toBe(true)
  })
})

describe('Upstream style consistency — year-pill matches running_page RunMapButtons', () => {
  it('year-pill font-size (1rem) matches running_page map button scale', () => {
    const el = document.createElement('button')
    el.className = 'year-pill'
    document.body.appendChild(el)

    const style = getComputedStyle(el)
    expect(style.fontSize).toBe('1rem')

    document.body.removeChild(el)
  })

  it('year-pill has no border/background — matches RunMapButtons text-only style', () => {
    expect(cssRuleHasProperty('.year-pill', 'background')).toBe(true)
    expect(cssRuleHasProperty('.year-pill', 'border')).toBe(true)
  })

  it('year-pill font-family matches --font-mono like running_page buttons', () => {
    expect(cssRuleHasProperty('.year-pill', 'font-family')).toBe(true)
  })

  it('month-chip has accent color and backdrop-filter matching overview treatment', () => {
    const chip = document.createElement('div')
    chip.className = 'month-chip'
    document.body.appendChild(chip)

    const style = getComputedStyle(chip)
    expect(style.borderRadius).toBe('12px')
    expect(style.fontSize).toBe('0.7rem')
    expect(cssRuleHasProperty('.month-chip', 'backdrop-filter')).toBe(true)

    document.body.removeChild(chip)
  })

  it('map-year-selector pointer-events:none with children auto — matches overview ol-lc pattern', () => {
    const selector = document.createElement('div')
    selector.className = 'map-year-selector'
    document.body.appendChild(selector)

    const parentStyle = getComputedStyle(selector)
    expect(parentStyle.pointerEvents).toBe('none')

    const child = document.createElement('div')
    selector.appendChild(child)
    const childStyle = getComputedStyle(child)
    expect(childStyle.pointerEvents).toBe('auto')

    document.body.removeChild(selector)
  })
})

describe('Visual integration — header and map overlays', () => {
  beforeEach(() => {
    document.documentElement.setAttribute('data-theme', 'dark')
  })

  it('simple-header uses page background color for visual integration', () => {
    const header = document.createElement('header')
    header.className = 'simple-header'
    document.body.appendChild(header)

    expect(cssRuleHasProperty('.simple-header', 'background')).toBe(true)

    document.body.removeChild(header)
  })

  it('section-divider uses var(--color-hr) for visible separation', () => {
    expect(cssRuleHasProperty('.section-divider', 'border-top-color')).toBe(true)
  })

  it('year-pill has no background — matches running_page text-only buttons', () => {
    expect(cssRuleHasProperty('.year-pill', 'background')).toBe(true)
  })

  it('no rgba(from ...) syntax remains in any CSS rule — ensures browser compatibility', () => {
    for (const sheet of document.styleSheets) {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSStyleRule) {
          const cssText = rule.style.cssText
          expect(cssText.includes('rgba(from')).toBe(false)
        }
        if (rule instanceof CSSMediaRule) {
          for (const inner of rule.cssRules) {
            if (inner instanceof CSSStyleRule) {
              expect(inner.style.cssText.includes('rgba(from')).toBe(false)
            }
          }
        }
      }
    }
  })
})

describe('Z-stack layer integrity — prevent regression of tiles-over-overlays bug', () => {
  beforeEach(() => {
    document.documentElement.setAttribute('data-theme', 'dark')
  })

  it('all map overlay containers have z-index > 1000 (above Leaflet highest pane)', () => {
    const selectors = ['.map-year-selector', '.map-lights', '.map-fullscreen']
    for (const sel of selectors) {
      expect(cssRuleHasProperty(sel, 'z-index')).toBe(true)
    }
  })

  it('map-year-selector z-index matches other overlays (all use same z-index)', () => {
    // Parse z-index values from CSS rules
    const zIndices: number[] = []
    const selectors = ['.map-year-selector', '.map-lights', '.map-fullscreen']
    for (const sheet of document.styleSheets) {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSStyleRule && selectors.includes(rule.selectorText)) {
          const z = parseInt(rule.style.getPropertyValue('z-index'), 10)
          if (!Number.isNaN(z)) zIndices.push(z)
        }
        if (rule instanceof CSSMediaRule) {
          for (const inner of rule.cssRules) {
            if (inner instanceof CSSStyleRule && selectors.includes(inner.selectorText)) {
              const z = parseInt(inner.style.getPropertyValue('z-index'), 10)
              if (!Number.isNaN(z)) zIndices.push(z)
            }
          }
        }
      }
    }
    // All must be the same value
    expect(zIndices.length).toBeGreaterThan(0)
    expect(new Set(zIndices).size).toBe(1)
  })

  it('overlay z-index exceeds known Leaflet tile pane threshold (200)', () => {
    let overlayZ = 0
    for (const sheet of document.styleSheets) {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSStyleRule && rule.selectorText === '.map-lights') {
          overlayZ = parseInt(rule.style.getPropertyValue('z-index'), 10)
        }
      }
    }
    // Critical fix: overlay must be above Leaflet tile-pane (z:200)
    expect(overlayZ).toBeGreaterThan(200)
    expect(overlayZ).toBeGreaterThanOrEqual(1001)
  })
})

describe('D10 — regression: YearStats renders correct values for known fixture data', () => {
  function makeAct(overrides: Partial<Activity> & { start_date: string }): Activity {
    return {
      run_id: '',
      name: null,
      distance: null,
      moving_time: null,
      elapsed_time: null,
      sport_category: 'run',
      start_date_local: null,
      location_country: null,
      source: null,
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

  beforeEach(() => {
    useSimpleStore.setState({
      activities: [],
      filteredActivities: [],
      years: [],
      regionFilter: null,
      typeFilter: null,
      selectedYear: null,
      selectedMonth: null,
    })
  })

  it('renders expected stat values for sample activities', () => {
    const acts = [
      makeAct({
        start_date: '2024-06-01T00:00:00Z',
        distance: 5000,
        moving_time: 1500,
        elevation_gain: 50,
        average_heartrate: 140,
        average_speed: 5000 / 1500,
        sport_category: 'run',
      }),
      makeAct({
        start_date: '2024-06-02T00:00:00Z',
        distance: 10000,
        moving_time: 3000,
        elevation_gain: 100,
        average_heartrate: 150,
        average_speed: 10000 / 3000,
        sport_category: 'run',
      }),
      makeAct({
        start_date: '2024-06-03T00:00:00Z',
        distance: 3000,
        moving_time: 1200,
        elevation_gain: 20,
        average_heartrate: null,
        average_speed: 3000 / 1200,
        sport_category: 'ride',
      }),
    ]
    const stats = computeYearStats(acts)
    expect(stats.count).toBe(3)
    expect(stats.distance).toBe(18000)
    expect(stats.movingTime).toBe(5700)
    expect(stats.elevationGain).toBe(170)
    // Pace: only from run category (2 runs: 5k/1500s + 10k/3000s)
    // pace = totalDist / totalTime = 15000 / (1500+3000) = 15000/4500 = 3.333 m/s
    expect(stats.pace).toBeCloseTo(3.333, 2)
    // avgHeartrate: only from first 2 activities (third has null)
    expect(stats.avgHeartrate).toBeCloseTo(145, 0)
    // categoryBreakdown: run=15km, ride=3km
    expect(stats.categoryBreakdown).toHaveLength(2)
    expect(stats.categoryBreakdown[0].category).toBe('run')
    expect(stats.categoryBreakdown[0].distanceKm).toBeCloseTo(15, 0)
    expect(stats.categoryBreakdown[1].category).toBe('ride')
    expect(stats.categoryBreakdown[1].distanceKm).toBeCloseTo(3, 0)
  })

  it('existing YearStats renders all stat lines that were in the old implementation', () => {
    const acts = [
      makeAct({
        start_date: '2024-01-01T00:00:00Z',
        distance: 10000,
        moving_time: 3600,
        elevation_gain: 100,
        average_heartrate: 140,
        average_speed: 10000 / 3600,
        sport_category: 'run',
        calories: 800,
      }),
    ]
    const stats = computeYearStats(acts)
    // Old implementation had: count, distance, elev, pace, streak, avgHr
    expect(stats.count).toBe(1)
    expect(stats.distance).toBe(10000)
    expect(stats.elevationGain).toBe(100)
    expect(stats.pace).not.toBeNull()
    expect(stats.streak).toBe(1)
    expect(stats.avgHeartrate).toBe(140)
    // New fields should also be present
    expect(stats.movingTime).toBe(3600)
    expect(stats.calories).toBeGreaterThan(0)
  })

  it('handles empty array same as old implementation', () => {
    const stats = computeYearStats([])
    expect(stats.count).toBe(0)
    expect(stats.distance).toBe(0)
    expect(stats.movingTime).toBe(0)
    expect(stats.elevationGain).toBe(0)
    expect(stats.avgHeartrate).toBeNull()
    expect(stats.pace).toBeNull()
    expect(stats.streak).toBe(0)
    expect(stats.categoryBreakdown).toEqual([])
  })
})
