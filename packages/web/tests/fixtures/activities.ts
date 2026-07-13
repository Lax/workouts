import type { Activity } from '@workouts/shared'

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]
}

function isoDate(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}T${String(10 + (d % 12)).padStart(2, '0')}:00:00Z`
}

const CATEGORIES = ['run', 'ride', 'hike', 'walk', 'swim', 'workout'] as const
const SOURCES = ['garmin', 'strava', 'keep']
const NAMES = ['Morning Run', 'Evening Ride', 'Lunch Walk', 'Hill Climb', 'Recovery', 'Long Run', 'Commute', 'Weekend Hike']

export function generateActivities(count: number): Activity[] {
  const acts: Activity[] = []
  for (let i = 0; i < count; i++) {
    const cat = pick([...CATEGORIES])
    const dist = Math.round((2000 + Math.random() * 40000) * 100) / 100
    const speed = 2 + Math.random() * 4
    const moving = Math.round(dist / speed)
    const year = i < count / 2 ? 2025 : 2024
    const month = 1 + (i % 12)
    acts.push({
      run_id: `test-${i}`,
      name: pick(NAMES) + (i % 3 === 0 ? ` #${i}` : ''),
      distance: dist,
      moving_time: moving,
      elapsed_time: Math.round(moving * 1.1),
      sport_category: cat,
      start_date: isoDate(year, month, 1 + (i % 28)),
      start_date_local: isoDate(year, month, 1 + (i % 28)),
      location_country: null,
      source: pick(SOURCES),
      average_heartrate: Math.round(120 + Math.random() * 40),
      max_heartrate: Math.round(160 + Math.random() * 20),
      average_cadence: cat === 'ride' ? 80 + Math.round(Math.random() * 10) : null,
      max_cadence: null,
      average_power: cat === 'ride' ? 150 + Math.round(Math.random() * 100) : null,
      max_power: null,
      average_temperature: Math.round(10 + Math.random() * 25),
      calories: Math.round((dist / 20) * 4),
      average_speed: speed,
      elevation_gain: Math.round(dist * 0.02 + Math.random() * 50),
      summary_polyline: null,
    })
  }
  return acts
}
