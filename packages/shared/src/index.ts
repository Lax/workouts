export interface Activity {
  id: number
  run_id: string
  name: string | null
  distance: number | null
  moving_time: number | null
  elapsed_time: number | null
  sport_category: string
  /** Ruby dashboard/JSON export writes type instead of sport_category */
  type?: string
  sport_type: string | null
  start_date: string | null
  start_date_local: string | null
  location_country: string | null
  summary_polyline: string | null
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
  duplicate_info: string | null
}

export type SportCategory =
  | 'run'
  | 'ride'
  | 'hike'
  | 'walk'
  | 'swim'
  | 'ski'
  | 'workout'
  | 'other'

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

const CATEGORY_COLORS: Record<SportCategory, string> = {
  run: '#4A90D9',
  ride: '#50C878',
  hike: '#8B6914',
  walk: '#B0BEC5',
  swim: '#00BCD4',
  ski: '#9C27B0',
  workout: '#FF5722',
  other: '#9E9E9E',
}

export function categoryColor(cat: string): string {
  return CATEGORY_COLORS[cat as SportCategory] ?? CATEGORY_COLORS.other
}
