export interface Activity {
  /** Not exported by Ruby — only present in DB */
  id?: number
  run_id: string
  name: string | null
  distance: number | null
  moving_time: number | null
  /** Not exported by Ruby */
  elapsed_time?: number | null
  sport_category: string
  /** Ruby export writes type instead of sport_category */
  type?: string
  /** Ruby JSON export writes sport_type; dashboard omits it */
  sport_type?: string | null
  start_date: string | null
  start_date_local: string | null
  location_country: string | null
  summary_polyline: string | null
  /** Legacy: old dashboard exports wrote polyline */
  polyline?: string
  average_heartrate: number | null
  max_heartrate: number | null
  average_cadence: number | null
  max_cadence: number | null
  average_power: number | null
  max_power: number | null
  average_temperature: number | null
  calories: number | null
  average_speed: number | null
  elevation_gain: number | null
  source: string | null
  duplicate_info?: string | null
  /** From Ruby geo detection: array of {p:province, c?:city, d?:district, w:weight} */
  divisions?: Array<{ p: string; c?: string; d?: string; t?: string; w: number }>
}

export type SportCategory = 'run' | 'ride' | 'hike' | 'walk' | 'swim' | 'ski' | 'workout' | 'other'

export const CATEGORY_LABELS: Record<SportCategory, string> = {
  run: 'Running',
  ride: 'Cycling',
  hike: 'Hiking',
  walk: 'Walking',
  swim: 'Swimming',
  ski: 'Skiing',
  workout: 'Workout',
  other: 'Other',
}

export function formatDistance(meters: number | null): string {
  if (meters === null || meters === undefined) return '—'
  if (meters < 1000) return `${Math.round(meters)} m`
  return `${(meters / 1000).toFixed(2)} km`
}

export function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return '—'
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

export function formatPace(metersPerSec: number | null): string {
  if (metersPerSec === null || metersPerSec === undefined) return '—'
  if (metersPerSec <= 0) return '—'
  const pace = 1000 / (metersPerSec * 60) // min per km
  const min = Math.floor(pace)
  const sec = Math.round((pace - min) * 60)
  return `${min}:${sec.toString().padStart(2, '0')} /km`
}

export function formatDate(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

// ---- SportMapper ported from lib/workouts/sport_mapper.rb ----

const SPORT_ALIASES: Record<string, SportCategory> = {
  running: 'run',
  trailrun: 'run',
  trail_run: 'run',
  virtualrun: 'run',
  virtual_run: 'run',
  indoorrun: 'run',
  indoor_run: 'run',
  cycling: 'ride',
  biking: 'ride',
  mountainbike: 'ride',
  gravelride: 'ride',
  ebikeride: 'ride',
  virtualride: 'ride',
  virtual_ride: 'ride',
  indoor_ride: 'ride',
  indoorride: 'ride',
  hiking: 'hike',
  walking: 'walk',
  swimming: 'swim',
  skiing: 'ski',
  backcountryski: 'ski',
  nordicski: 'ski',
  strengthtraining: 'workout',
}

const SPORT_KEYWORDS: [RegExp, SportCategory][] = [
  [/\b(?:run|jog|sprint|marathon)\w*\b/i, 'run'],
  [/\b(?:ride|cycl|bike|mountain\.?bike|gravel|ebike)\w*\b/i, 'ride'],
  [/\b(?:hike|climb|mountaineer|trek)\w*\b/i, 'hike'],
  [/\b(?:walk|stroll)\w*\b/i, 'walk'],
  [/\b(?:swim|pool|laps?)\w*\b/i, 'swim'],
  [/\b(?:ski|snowboard|nordic)\w*\b/i, 'ski'],
  [/\b(?:workout|train|gym|fitness|yoga|pilates|crossfit|elliptical|strength)\w*\b/i, 'workout'],
]

const LEV_REFERENCES = [
  'running',
  'run',
  'trailrun',
  'trail_run',
  'virtualrun',
  'virtual_run',
  'indoorrun',
  'indoor_run',
  'cycling',
  'ride',
  'biking',
  'mountainbike',
  'gravelride',
  'ebikeride',
  'virtualride',
  'virtual_ride',
  'indoor_ride',
  'indoorride',
  'hiking',
  'hike',
  'walking',
  'walk',
  'swimming',
  'swim',
  'skiing',
  'ski',
  'workout',
  'strengthtraining',
  'training',
  'elliptical',
  'cardio',
  'functional',
]

function levenshtein(a: string, b: string): number {
  const n = a.length,
    m = b.length
  if (n === 0) return m
  if (m === 0) return n
  const cur: number[] = Array.from({ length: m + 1 }, (_, i) => i)
  for (let i = 1; i <= n; i++) {
    let prev = cur[0]
    cur[0] = i
    for (let j = 1; j <= m; j++) {
      const tmp = cur[j]
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      cur[j] = Math.min(cur[j] + 1, cur[j - 1] + 1, prev + cost)
      prev = tmp
    }
  }
  return cur[m]
}

export * from './cities'
export * from './color-mode'
export * from './geo'
export {
  type Boundary,
  type CityBoundary,
  decodePolyline,
  getStartCoords,
  haversine,
  matchPolygons,
  pointInPolygon,
} from './geo'
export * from './geo-boundaries'
export * from './theme-types'

export type PeriodLabel = 'morning' | 'noon' | 'afternoon' | 'evening' | 'night'

export const PERIOD_CONFIG: Record<PeriodLabel, { label: string; range: [number, number] }> = {
  morning: { label: 'Morning', range: [5, 11] },
  noon: { label: 'Noon', range: [12, 13] },
  afternoon: { label: 'Afternoon', range: [14, 17] },
  evening: { label: 'Evening', range: [18, 20] },
  night: { label: 'Night', range: [21, 4] },
}

export function classifyPeriod(hour: number): PeriodLabel | null {
  if (hour >= 5 && hour <= 11) return 'morning'
  if (hour >= 12 && hour <= 13) return 'noon'
  if (hour >= 14 && hour <= 17) return 'afternoon'
  if (hour >= 18 && hour <= 20) return 'evening'
  if (hour >= 21 || hour <= 4) return 'night'
  return null
}

const PERIOD_ORDER: Record<PeriodLabel, number> = { morning: 0, noon: 1, afternoon: 2, evening: 3, night: 4 }

export function sortPeriods(periods: PeriodLabel[]): PeriodLabel[] {
  return [...periods].sort((a, b) => PERIOD_ORDER[a] - PERIOD_ORDER[b])
}

export function canonicalizeSport(str: string | null | undefined): SportCategory {
  if (!str) return 'other'
  const key = str.toLowerCase().trim()

  if (SPORT_ALIASES[key]) return SPORT_ALIASES[key]

  for (const [re, sport] of SPORT_KEYWORDS) {
    if (re.test(str)) return sport
  }

  let best: string | null = null
  let bestDist = Infinity
  for (const ref of LEV_REFERENCES) {
    const d = levenshtein(key, ref)
    if (d < bestDist) {
      bestDist = d
      best = ref
    }
  }
  if (best && bestDist <= 3) return SPORT_ALIASES[best] ?? (best as SportCategory)

  return 'other'
}
