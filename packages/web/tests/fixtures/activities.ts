import type { Activity } from '@workouts/shared'

export function generateActivities(count: number = 100): Activity[] {
  const types = ['run', 'ride', 'hike', 'swim', 'walk', 'workout']
  const sources = ['garmin', 'strava', 'keep', 'igpsport']
  const names = ['Morning Run', 'Evening Ride', 'Weekend Hike', 'Lunch Swim', 'Park Walk', 'Gym Session']
  const polyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@'

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
    } as Activity
  })
}
