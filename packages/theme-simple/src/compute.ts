import type { Activity } from '@workouts/shared'

interface CategoryBreakdown {
  category: string
  distanceKm: number
  count: number
}

interface YearStats {
  count: number
  distance: number
  movingTime: number
  elevationGain: number
  avgHeartrate: number | null
  maxHeartrate: number | null
  avgCadence: number | null
  maxCadence: number | null
  avgPower: number | null
  maxPower: number | null
  avgTemperature: number | null
  calories: number
  avgSpeed: number | null
  pace: number | null
  streak: number
  categoryBreakdown: CategoryBreakdown[]
}

const PACECATEGORIES = ['run', 'hike', 'walk']

export function computeYearStats(activities: Activity[]): YearStats {
  let count = 0
  let distance = 0
  let movingTime = 0
  let elevationGain = 0
  let calories = 0
  let hrSum = 0
  let hrCount = 0
  let maxHr: number | null = null
  let cadenceSum = 0
  let cadenceCount = 0
  let maxCadence: number | null = null
  let powerSum = 0
  let powerCount = 0
  let maxPower: number | null = null
  let tempSum = 0
  let tempCount = 0
  let speedSum = 0
  let speedCount = 0
  let totalPaceDist = 0
  let totalPaceTime = 0
  const catMap = new Map<string, { distanceKm: number; count: number }>()

  for (const a of activities) {
    count++
    distance += a.distance ?? 0
    movingTime += a.moving_time ?? 0
    elevationGain += a.elevation_gain ?? 0
    calories += a.calories ?? 0

    if (a.average_heartrate != null) {
      hrSum += a.average_heartrate
      hrCount++
    }
    if (a.max_heartrate != null && (maxHr === null || a.max_heartrate > maxHr)) {
      maxHr = a.max_heartrate
    }

    if (a.average_cadence != null) {
      cadenceSum += a.average_cadence
      cadenceCount++
    }
    if (a.max_cadence != null && (maxCadence === null || a.max_cadence > maxCadence)) {
      maxCadence = a.max_cadence
    }

    if (a.average_power != null) {
      powerSum += a.average_power
      powerCount++
    }
    if (a.max_power != null && (maxPower === null || a.max_power > maxPower)) {
      maxPower = a.max_power
    }

    if (a.average_temperature != null) {
      tempSum += a.average_temperature
      tempCount++
    }

    if (a.average_speed != null && a.average_speed > 0) {
      speedSum += a.average_speed
      speedCount++
      if (PACECATEGORIES.includes(a.sport_category)) {
        const d = a.distance ?? 0
        totalPaceDist += d
        totalPaceTime += d / a.average_speed
      }
    }

    const cat = a.sport_category
    const existing = catMap.get(cat)
    if (existing) {
      existing.distanceKm += (a.distance ?? 0) / 1000
      existing.count++
    } else {
      catMap.set(cat, { distanceKm: (a.distance ?? 0) / 1000, count: 1 })
    }
  }

  const categoryBreakdown = [...catMap.entries()]
    .map(([category, v]) => ({ category, distanceKm: Math.round(v.distanceKm * 100) / 100, count: v.count }))
    .sort((a, b) => b.distanceKm - a.distanceKm)

  return {
    count,
    distance,
    movingTime,
    elevationGain,
    avgHeartrate: hrCount > 0 ? hrSum / hrCount : null,
    maxHeartrate: maxHr,
    avgCadence: cadenceCount > 0 ? cadenceSum / cadenceCount : null,
    maxCadence,
    avgPower: powerCount > 0 ? powerSum / powerCount : null,
    maxPower,
    avgTemperature: tempCount > 0 ? tempSum / tempCount : null,
    calories,
    avgSpeed: speedCount > 0 ? speedSum / speedCount : null,
    pace: totalPaceTime > 0 ? totalPaceDist / totalPaceTime : null,
    streak: computeStreak(activities),
    categoryBreakdown,
  }
}

export function computeStreak(acts: Activity[]): number {
  const dates = acts
    .filter((a) => a.start_date)
    .map((a) => a.start_date!.slice(0, 10))
    .sort()
  if (dates.length === 0) return 0
  const unique = [...new Set(dates)].sort()
  let maxStreak = 1
  let current = 1
  for (let i = 1; i < unique.length; i++) {
    const diff = (new Date(unique[i]).getTime() - new Date(unique[i - 1]).getTime()) / 86400000
    if (Math.round(diff) === 1) {
      current++
      if (current > maxStreak) maxStreak = current
    } else {
      current = 1
    }
  }
  return maxStreak
}
