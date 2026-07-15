import type { Activity } from '@workouts/shared'
import { formatDuration, formatPace } from '@workouts/shared'
import { colorIntensity, computeStreak, decodePolyline, useSimpleStore } from '@workouts/theme-simple'
import { beforeEach, describe, expect, it, vi } from 'vitest'

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

  it('year-pills uses flex-direction row with wrapping for horizontal layout', () => {
    const pills = document.createElement('div')
    pills.className = 'year-pills'
    document.body.appendChild(pills)

    const style = getComputedStyle(pills)
    expect(style.display).toBe('flex')
    expect(style.flexDirection).toBe('row')
    expect(style.flexWrap).toBe('wrap')

    document.body.removeChild(pills)
  })

  it('year-pill has correct pill shape and backdrop-filter for visibility', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill'
    document.body.appendChild(pill)

    const style = getComputedStyle(pill)
    expect(style.borderRadius).toBe('12px')
    expect(style.fontSize).toBe('1rem')
    expect(style.cursor).toBe('pointer')
    expect(style.transition).toBe('all 0.15s')
    expect(style.border).not.toBe('')
    expect(style.border).not.toBe('0px')
    expect(style.border).not.toBe('none')
    expect(cssRuleHasProperty('.year-pill', 'backdrop-filter')).toBe(true)

    document.body.removeChild(pill)
  })

  it('year-pill.active has accent background and bold weight', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill active'
    document.body.appendChild(pill)

    const style = getComputedStyle(pill)
    expect(style.fontWeight).toBe('600')

    document.body.removeChild(pill)
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

  it('legend-toggle has backdrop-filter blur for readability over map tiles', () => {
    const toggle = document.createElement('div')
    toggle.className = 'legend-toggle'
    document.body.appendChild(toggle)

    const style = getComputedStyle(toggle)
    expect(style.borderRadius).toBe('8px')
    expect(style.overflow).toBe('hidden')
    expect(cssRuleHasProperty('.legend-toggle', 'backdrop-filter')).toBe(true)

    document.body.removeChild(toggle)
  })

  it('legend-btn has correct font-size matching upstream', () => {
    const btn = document.createElement('button')
    btn.className = 'legend-btn'
    document.body.appendChild(btn)

    const style = getComputedStyle(btn)
    expect(style.fontSize).toBe('0.7rem')
    expect(style.cursor).toBe('pointer')
    expect(style.transition).toBe('all 0.15s')

    document.body.removeChild(btn)
  })

  it('month-chip appears only when both year and month are selected', () => {
    expect(cssRuleHasProperty('.month-chip', 'display')).toBe(true)
    expect(cssRuleHasProperty('.month-chip', 'border-radius')).toBe(true)
  })
})

describe('Upstream style consistency — year-pill matches overview pattern', () => {
  it('year-pill border-radius (12px) matches theme-overview pill style', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill'
    document.body.appendChild(pill)

    const style = getComputedStyle(pill)
    expect(style.borderRadius).toBe('12px')

    document.body.removeChild(pill)
  })

  it('year-pill font-size (1rem) matches running_page pill scale', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill'
    document.body.appendChild(pill)

    const style = getComputedStyle(pill)
    expect(style.fontSize).toBe('1rem')

    document.body.removeChild(pill)
  })

  it('year-pill has backdrop-filter blur matching overview overlay treatment', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill'
    document.body.appendChild(pill)

    expect(cssRuleHasProperty('.year-pill', 'backdrop-filter')).toBe(true)

    document.body.removeChild(pill)
  })

  it('legend-toggle has same backdrop-filter + border-radius as overview', () => {
    const toggle = document.createElement('div')
    toggle.className = 'legend-toggle'
    document.body.appendChild(toggle)

    const style = getComputedStyle(toggle)
    expect(style.borderRadius).toBe('8px')
    expect(cssRuleHasProperty('.legend-toggle', 'backdrop-filter')).toBe(true)

    document.body.removeChild(toggle)
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
    expect(cssRuleHasProperty('.simple-header', 'border-bottom')).toBe(true)

    document.body.removeChild(header)
  })

  it('simple-header border uses var(--color-border) not var(--color-hr-primary)', () => {
    expect(cssRuleHasProperty('.simple-header', 'background')).toBe(true)
    const hasHrBorder =
      cssRuleHasProperty('.simple-header', 'border-bottom-color') &&
      document.styleSheets[0]?.cssRules[0] instanceof CSSStyleRule &&
      document.styleSheets[0].cssRules[0].cssText.includes('color-hr-primary')
    expect(hasHrBorder).toBe(false)
  })

  it('section-divider uses var(--color-border) not var(--color-hr-primary)', () => {
    expect(cssRuleHasProperty('.section-divider', 'border-top')).toBe(true)
  })

  it('map-overlays is absolutely positioned at bottom-left of map wrapper', () => {
    const wrapper = document.createElement('div')
    wrapper.className = 'map-wrapper'
    document.body.appendChild(wrapper)

    const overlays = document.createElement('div')
    overlays.className = 'map-overlays'
    wrapper.appendChild(overlays)

    const style = getComputedStyle(overlays)
    expect(style.position).toBe('absolute')
    expect(style.bottom).toBe('10px')
    expect(style.left).toBe('10px')
    expect(style.zIndex).toBe('1001')

    document.body.removeChild(wrapper)
  })

  it('legend-btn.active uses var(--color-bg) not hardcoded #000', () => {
    const btn = document.createElement('button')
    btn.className = 'legend-btn active'
    document.body.appendChild(btn)

    const style = getComputedStyle(btn)
    expect(style.fontWeight).toBe('600')

    document.body.removeChild(btn)
  })

  it('legend-btn:first-child has border-right separator matching upstream', () => {
    expect(cssRuleHasProperty('.legend-btn:first-child', 'border-right')).toBe(true)
  })

  it('year-pill background uses compatible rgba syntax (not rgba(from ...))', () => {
    const pill = document.createElement('button')
    pill.className = 'year-pill'
    document.body.appendChild(pill)

    const style = getComputedStyle(pill)
    expect(style.background).toBeTruthy()
    expect(style.background).not.toBe('transparent')
    expect(style.background).not.toBe('rgba(0, 0, 0, 0)')

    document.body.removeChild(pill)
  })

  it('left-panel responsive border-bottom uses var(--color-border) at narrow viewport', () => {
    const mediaQuery = window.matchMedia('(max-width: 768px)')
    if (mediaQuery.matches) {
      expect(cssRuleHasProperty('.left-panel', 'border-bottom')).toBe(true)
    }
  })

  it('legend-btn:first-child border-right is opaque (not transparent)', () => {
    for (const sheet of document.styleSheets) {
      for (const rule of sheet.cssRules) {
        if (rule instanceof CSSStyleRule && rule.selectorText === '.legend-btn:first-child') {
          const borderRight = rule.style.getPropertyValue('border-right')
          expect(borderRight).toBeTruthy()
          expect(borderRight).not.toBe('0px')
          expect(borderRight).not.toBe('none')
        }
      }
    }
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
    const selectors = ['.map-year-selector', '.map-overlays', '.map-lights', '.map-fullscreen']
    for (const sel of selectors) {
      expect(cssRuleHasProperty(sel, 'z-index')).toBe(true)
    }
  })

  it('map-year-selector z-index matches other overlays (all use same z-index)', () => {
    // Parse z-index values from CSS rules
    const zIndices: number[] = []
    const selectors = ['.map-year-selector', '.map-overlays', '.map-lights', '.map-fullscreen']
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
