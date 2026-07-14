import type { Activity } from './index'

export function normalize(raw: unknown): Activity {
  if (!raw || typeof raw !== 'object') {
    return emptyActivity()
  }
  const r = raw as Record<string, unknown>
  return {
    run_id: String(r.run_id ?? ''),
    name: (r.name as string) ?? null,
    distance: (r.distance as number) ?? null,
    moving_time: (r.moving_time as number) ?? null,
    elapsed_time: (r.elapsed_time as number) ?? null,
    sport_category: (r.sport_category as string) || (r.type as string) || 'other',
    sport_type: (r.sport_type as string) ?? null,
    start_date: (r.start_date as string) ?? null,
    start_date_local: (r.start_date_local as string) ?? null,
    location_country: (r.location_country as string) ?? null,
    summary_polyline: (r.summary_polyline as string) ?? (r.polyline as string) ?? null,
    average_heartrate: (r.average_heartrate as number) ?? null,
    max_heartrate: (r.max_heartrate as number) ?? null,
    average_cadence: (r.average_cadence as number) ?? null,
    max_cadence: (r.max_cadence as number) ?? null,
    average_power: (r.average_power as number) ?? null,
    max_power: (r.max_power as number) ?? null,
    average_temperature: (r.average_temperature as number) ?? null,
    calories: (r.calories as number) ?? null,
    average_speed: (r.average_speed as number) ?? null,
    elevation_gain: (r.elevation_gain as number) ?? null,
    source: (r.source as string) ?? null,
    duplicate_info: (r.duplicate_info as string) ?? null,
  }
}

function emptyActivity(): Activity {
  return {
    run_id: '',
    name: null,
    distance: null,
    moving_time: null,
    elapsed_time: null,
    sport_category: 'other',
    sport_type: null,
    start_date: null,
    start_date_local: null,
    location_country: null,
    summary_polyline: null,
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
    source: null,
    duplicate_info: null,
  }
}

export function normalizeAll(raw: unknown[]): Activity[] {
  if (!Array.isArray(raw)) return []
  return raw.map((item) => normalize(item))
}
