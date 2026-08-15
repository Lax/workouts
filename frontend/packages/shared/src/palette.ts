/**
 * palette.ts - single source of truth for the color system.
 *
 * Three hue families are supported:
 *   - warm (default): yellow -> amber -> orange -> red  (sports energy)
 *   - cool:           cyan -> blue -> indigo -> violet
 *   - mono:           neutral black/white/gray ramp
 *
 * Every family defines the full set of tokens so that map polylines,
 * charts, SVG posters and CSS all stay within ONE hue family - no more
 * mixing cold (blue-gray) with warm (yellow-orange) in the same view.
 *
 * Light vs dark variants exist per token because lines/dots must stay
 * legible both on dark tiles/surfaces and on light ones.
 */

export type ColorFamily = 'warm' | 'cool' | 'mono'
export type ColorScheme = 'light' | 'dark'

export interface SchemePair<T> {
  light: T
  dark: T
}

export interface FamilyDef {
  accent: SchemePair<string>
  secondary: SchemePair<string>
  hover: SchemePair<string>
  selected: SchemePair<string>
  activeRow: SchemePair<string>
  hr: SchemePair<string>
  svgCell: SchemePair<string>
  svgSpecial: SchemePair<string>
  svgSpecial2: SchemePair<string>
  categories: Record<string, SchemePair<string>>
  /** speed bands slow -> fast */
  speed: SchemePair<string[]>
  markers: { start: string; end: string }
  /** YearSummaryDrawer dot ramp, index 0 = empty, 6 = max */
  dots: SchemePair<string[]>
}

export const DEFAULT_FAMILY: ColorFamily = 'warm'

export const FAMILIES: Record<ColorFamily, FamilyDef> = {
  warm: {
    accent: { light: '#8a6d00', dark: '#e0ed5e' },
    secondary: { light: '#8a6d00', dark: '#ccd94a' },
    hover: { light: '#fff4d6', dark: '#262626' },
    selected: { light: '#8a6d00', dark: '#e0ed5e' },
    activeRow: { light: '#ffeecb', dark: '#e0ed5e' },
    hr: { light: '#d4d4d4', dark: '#ef4444' },
    svgCell: { light: '#b45309', dark: '#f7d02c' },
    svgSpecial: { light: '#c2410c', dark: '#f9844a' },
    svgSpecial2: { light: '#991b1b', dark: '#ef4444' },
    categories: {
      run: { light: '#8a6d00', dark: '#e0ed5e' },
      ride: { light: '#c2410c', dark: '#ff9f0a' },
      hike: { light: '#9a3412', dark: '#f9844a' },
      walk: { light: '#a16207', dark: '#ffd166' },
      swim: { light: '#be123c', dark: '#ef476f' },
      ski: { light: '#991b1b', dark: '#d62828' },
      workout: { light: '#ea580c', dark: '#f77f00' },
      other: { light: '#6b7280', dark: '#9e9e9e' },
    },
    speed: {
      light: ['#a16207', '#c2410c', '#b91c1c', '#991b1b'],
      dark: ['#ffd166', '#ff9f0a', '#ef5350', '#d62828'],
    },
    markers: { start: '#e0ed5e', end: '#ef4444' },
    dots: {
      light: ['#b0b0b0', '#8a6d00', '#a16207', '#b45309', '#c2410c', '#d62828', '#991b1b'],
      dark: ['#4a4a4a', '#6d5a00', '#a88200', '#d9a400', '#ffb300', '#ff6d00', '#e53935'],
    },
  },

  cool: {
    accent: { light: '#0369a1', dark: '#4dd2ff' },
    secondary: { light: '#0369a1', dark: '#2f80ed' },
    hover: { light: '#f0f9ff', dark: '#0f3460' },
    selected: { light: '#0369a1', dark: '#4dd2ff' },
    activeRow: { light: '#e0f2fe', dark: '#1a3a6a' },
    hr: { light: '#d4d4d4', dark: '#333333' },
    svgCell: { light: '#0284c7', dark: '#7fd8ff' },
    svgSpecial: { light: '#0369a1', dark: '#4dd2ff' },
    svgSpecial2: { light: '#4338ca', dark: '#5e5ce6' },
    categories: {
      run: { light: '#0369a1', dark: '#4dd2ff' },
      ride: { light: '#1e40af', dark: '#2f80ed' },
      hike: { light: '#0e7490', dark: '#00b4d8' },
      walk: { light: '#0284c7', dark: '#7fd8ff' },
      swim: { light: '#1d4ed8', dark: '#2196f3' },
      ski: { light: '#4338ca', dark: '#5e5ce6' },
      workout: { light: '#6d28d9', dark: '#8b5cf6' },
      other: { light: '#6b7280', dark: '#9e9e9e' },
    },
    speed: {
      light: ['#0e7490', '#0369a1', '#1e40af', '#4338ca'],
      dark: ['#90e0ef', '#4dd2ff', '#2f80ed', '#5e5ce6'],
    },
    markers: { start: '#4dd2ff', end: '#5e5ce6' },
    dots: {
      light: ['#b0b0b0', '#0e7490', '#0369a1', '#1e40af', '#0284c7', '#1d4ed8', '#4338ca'],
      dark: ['#4a4a4a', '#0f4c5c', '#0369a1', '#0284c7', '#4dd2ff', '#2f80ed', '#5e5ce6'],
    },
  },

  mono: {
    accent: { light: '#555555', dark: '#d4d4d4' },
    secondary: { light: '#666666', dark: '#b0b0b0' },
    hover: { light: '#eeeeee', dark: '#2a2a2a' },
    selected: { light: '#555555', dark: '#d4d4d4' },
    activeRow: { light: '#e0e0e0', dark: '#3a3a3a' },
    hr: { light: '#d4d4d4', dark: '#444444' },
    svgCell: { light: '#8a8a8a', dark: '#d4d4d4' },
    svgSpecial: { light: '#6b6b6b', dark: '#9c9c9c' },
    svgSpecial2: { light: '#4a4a4a', dark: '#666666' },
    categories: {
      run: { light: '#3a3a3a', dark: '#f0f0f0' },
      ride: { light: '#4a4a4a', dark: '#d0d0d0' },
      hike: { light: '#5a5a5a', dark: '#b2b2b2' },
      walk: { light: '#6a6a6a', dark: '#949494' },
      swim: { light: '#7a7a7a', dark: '#767676' },
      ski: { light: '#8a8a8a', dark: '#5a5a5a' },
      workout: { light: '#4a4a4a', dark: '#c0c0c0' },
      other: { light: '#6b6b6b', dark: '#888888' },
    },
    speed: {
      light: ['#8a8a8a', '#6b6b6b', '#4a4a4a', '#2a2a2a'],
      dark: ['#e0e0e0', '#b0b0b0', '#808080', '#505050'],
    },
    markers: { start: '#d4d4d4', end: '#666666' },
    dots: {
      light: ['#b0b0b0', '#8a8a8a', '#707070', '#565656', '#3c3c3c', '#2a2a2a', '#1a1a1a'],
      dark: ['#4a4a4a', '#5e5e5e', '#727272', '#868686', '#9a9a9a', '#aeaeae', '#c2c2c2'],
    },
  },
}

export function isValidFamily(v: string | null | undefined): v is ColorFamily {
  return v === 'warm' || v === 'cool' || v === 'mono'
}

export function familyFor(v?: string | null): ColorFamily {
  if (isValidFamily(v)) return v
  if (typeof document !== 'undefined' && isValidFamily(document.documentElement.dataset.palette)) {
    return document.documentElement.dataset.palette as ColorFamily
  }
  return DEFAULT_FAMILY
}

export function schemeFor(v?: ColorScheme | null): ColorScheme {
  if (v === 'light' || v === 'dark') return v
  if (typeof document !== 'undefined' && document.documentElement.dataset.theme === 'light') return 'light'
  return 'dark'
}

const NEUTRAL_FALLBACK = '#888'

export function speedColor(speedMs: number | null | undefined, family?: ColorFamily, scheme?: ColorScheme): string {
  if (speedMs === null || speedMs === undefined) return NEUTRAL_FALLBACK
  const fam = FAMILIES[familyFor(family)]
  const sc = schemeFor(scheme)
  const bands = fam.speed[sc]
  const kmh = speedMs * 3.6
  if (kmh < 3) return bands[0]
  if (kmh < 6) return bands[1]
  if (kmh < 9) return bands[2]
  return bands[3]
}

export function typeColor(type: string | null | undefined, family?: ColorFamily, scheme?: ColorScheme): string {
  if (type === null || type === undefined) return NEUTRAL_FALLBACK
  const fam = FAMILIES[familyFor(family)]
  const sc = schemeFor(scheme)
  return fam.categories[type]?.[sc] ?? NEUTRAL_FALLBACK
}

export function categoryColor(cat: string | null | undefined, family?: ColorFamily, scheme?: ColorScheme): string {
  return typeColor(cat ?? null, family, scheme)
}

export function activityColor(
  act: { average_speed?: number | null; type?: string | null },
  mode: string,
  family?: ColorFamily,
  scheme?: ColorScheme,
): string {
  return mode === 'speed' ? speedColor(act.average_speed ?? null, family, scheme) : typeColor(act.type ?? null, family, scheme)
}

export function markerColor(kind: 'start' | 'end', family?: ColorFamily): string {
  return FAMILIES[familyFor(family)].markers[kind]
}

export function dotColor(dist: number, family?: ColorFamily, scheme?: ColorScheme): string {
  const fam = FAMILIES[familyFor(family)]
  const sc = schemeFor(scheme)
  const dots = fam.dots[sc]
  if (dist === 0) return dots[0]
  if (dist < 1000) return dots[1]
  if (dist < 2000) return dots[2]
  if (dist < 4000) return dots[3]
  if (dist < 6000) return dots[4]
  if (dist < 10000) return dots[5]
  return dots[6]
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

function mix(a: string, b: string, t: number): string {
  const [ra, ga, ba] = hexToRgb(a)
  const [rb, gb, bb] = hexToRgb(b)
  const r = Math.round(ra + (rb - ra) * t)
  const g = Math.round(ga + (gb - ga) * t)
  const bl = Math.round(ba + (bb - ba) * t)
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${bl.toString(16).padStart(2, '0')}`
}

/**
 * Continuous gradient across the family's hot ramp (the speed ramp).
 * ratio 0..1 -> cold(0) .. hot(1). Used by CircularDrawer / MonthOfLifeDrawer.
 */
export function gradientColor(ratio: number, family?: ColorFamily, scheme?: ColorScheme): string {
  const fam = FAMILIES[familyFor(family)]
  const sc = schemeFor(scheme)
  const stops = fam.speed[sc]
  const clamped = Math.max(0, Math.min(1, ratio))
  const pos = clamped * (stops.length - 1)
  const i = Math.min(stops.length - 2, Math.floor(pos))
  return mix(stops[i], stops[i + 1], pos - i)
}

export function applyFamily(el: HTMLElement, family: ColorFamily, scheme: ColorScheme): void {
  const f = FAMILIES[family]
  el.dataset.palette = family
  const set = (name: string, value: string) => el.style.setProperty(name, value)
  set('--color-accent', f.accent[scheme])
  set('--color-brand', f.accent[scheme])
  set('--color-primary', f.accent[scheme])
  set('--color-secondary', f.secondary[scheme])
  set('--color-hover', f.hover[scheme])
  set('--color-selected', f.selected[scheme])
  set('--color-active-row', f.activeRow[scheme])
  set('--color-hr', f.hr[scheme])
  set('--svg-color-active-cell', f.svgCell[scheme])
  set('--svg-special-color', f.svgSpecial[scheme])
  set('--svg-special-color2', f.svgSpecial2[scheme])
  const bands = f.speed[scheme]
  set('--color-speed-1', bands[0])
  set('--color-speed-2', bands[1])
  set('--color-speed-3', bands[2])
  set('--color-speed-4', bands[3])
}
