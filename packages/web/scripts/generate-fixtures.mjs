import { writeFileSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const publicDir = join(__dirname, '..', 'public')

mkdirSync(publicDir, { recursive: true })

const types = ['run', 'ride', 'hike', 'swim', 'walk', 'workout']
const sources = ['garmin', 'strava', 'keep', 'igpsport']
const names = ['Morning Run', 'Evening Ride', 'Weekend Hike', 'Lunch Swim', 'Park Walk', 'Gym Session']
const polyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@'

function generateActivities(count) {
  return Array.from({ length: count }, (_, i) => {
    const year = [2023, 2024, 2025][i % 3]
    const month = (i % 12) + 1
    const day = (i % 28) + 1
    const type = types[i % types.length]
    const dist = [3000, 5000, 10000, 15000, 21097, 42195, 20000, 50000, 80000][i % 9]

    return {
      run_id: `${sources[i % sources.length]}_${i + 1}`,
      name: names[i % names.length],
      distance: dist,
      moving_time: Math.round(dist / 2.5),
      elapsed_time: Math.round(dist / 2),
      sport_category: type,
      start_date: `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(6 + (i % 12)).padStart(2, '0')}:00:00Z`,
      start_date_local: `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}T${String(6 + (i % 12)).padStart(2, '0')}:00:00`,
      summary_polyline: polyline,
      average_heartrate: 140 + (i % 40),
      max_heartrate: 170 + (i % 20),
      average_cadence: 75 + (i % 15),
      max_cadence: null,
      average_power: type === 'ride' ? 150 + (i % 100) : null,
      max_power: null,
      average_temperature: 15 + (i % 20),
      calories: null,
      average_speed: null,
      elevation_gain: type === 'hike' ? 200 + ((i * 10) % 500) : (i % 20) * 10,
      source: sources[i % sources.length],
      location_country: null,
    }
  })
}

const activities = generateActivities(150)
writeFileSync(join(publicDir, 'activities.json'), JSON.stringify(activities))
console.log(`Generated ${activities.length} activities → public/activities.json`)

const stats = {
  summary: {
    total_activities: 150,
    total_distance_km: activities.reduce((s, a) => s + a.distance / 1000, 0),
    total_moving_time_h: activities.reduce((s, a) => s + a.moving_time / 3600, 0),
    total_elevation_gain_m: activities.reduce((s, a) => s + (a.elevation_gain || 0), 0),
    avg_cadence: 82,
    avg_power: null,
    sport_breakdown: types.map(t => ({
      category: t,
      count: activities.filter(a => a.sport_category === t).length,
      distance_km: activities.filter(a => a.sport_category === t).reduce((s, a) => s + a.distance / 1000, 0),
      moving_time_h: activities.filter(a => a.sport_category === t).reduce((s, a) => s + a.moving_time / 3600, 0),
    })),
  },
  monthly: Array.from({ length: 36 }, (_, i) => ({
    year: 2023 + Math.floor(i / 12),
    month: (i % 12) + 1,
    count: 3 + (i % 7),
    distance_km: 20 + (i * 5) % 100,
    moving_time_h: 2 + (i % 8),
    avg_pace: `${5 + (i % 3)}:${String(10 + (i % 50)).padStart(2, '0')}`,
    avg_hr: 130 + (i % 30),
    avg_cadence: 75 + (i % 10),
    avg_power: null,
    elevation_gain_m: 100 + (i * 20) % 800,
  })),
  yearly: [2023, 2024, 2025].map((y, i) => ({
    year: y, month: 12, count: 40 + i * 10,
    distance_km: 300 + i * 100,
    moving_time_h: 50 + i * 15,
    longest_km: 21.1 + i * 5,
    streak: 5 + i * 3,
  })),
  streaks: { current: 5, all_time: 23 },
  activity_types: types,
}
writeFileSync(join(publicDir, 'stats.json'), JSON.stringify(stats))
console.log(`Generated stats → public/stats.json`)
