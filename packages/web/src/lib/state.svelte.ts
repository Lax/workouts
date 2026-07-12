import { type Activity } from '@workouts/shared'

export interface StatsJson {
  summary: {
    total_activities: number
    total_distance_km: number
    total_moving_time_h: number
    total_elevation_gain_m: number
    avg_cadence: number | null
    avg_power: number | null
    sport_breakdown: { category: string; count: number; distance_km: number; moving_time_h: number }[]
  }
  monthly: {
    year: number
    month: number
    count: number
    distance_km: number
    moving_time_h: number
    avg_pace: string
    avg_hr: number | null
    avg_cadence: number | null
    avg_power: number | null
    elevation_gain_m: number
  }[]
  yearly: {
    year: number
    month: number
    count: number
    distance_km: number
    moving_time_h: number
    longest_km: number
    streak: number
  }[]
  streaks: { current: number; all_time: number }
  activity_types: string[]
}

export type SortField = 'date' | 'distance' | 'time'
export type ColorMode = 'speed' | 'type'

export interface Filters {
  type: string
  source: string
  distanceMin: number | null
  distanceMax: number | null
  search: string
}

export const app = $state({
  activities: [] as Activity[],
  stats: null as StatsJson | null,
  loading: true,
  theme: 'dark' as string,
})

function activityType(a: Activity): string {
  return a.sport_category || a.type || 'other'
}

export function computeYears(activities: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of activities) {
    if (a.start_date) s.add(new Date(a.start_date).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

export function computeAvailableTypes(activities: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of activities) {
    const t = activityType(a)
    s.set(t, (s.get(t) || 0) + 1)
  }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

export function computeAvailableSources(activities: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of activities) {
    const src = a.source || 'unknown'
    s.set(src, (s.get(src) || 0) + 1)
  }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

export function computeFilteredActivities(
  activities: Activity[],
  filters: Filters,
  sortField: SortField,
  sortDesc: boolean,
  selectedYear: number | null,
  selectedMonth: number | null,
): Activity[] {
  let result = [...activities]

  if (selectedYear !== null) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      return new Date(a.start_date).getFullYear() === selectedYear
    })
  }

  if (selectedMonth !== null && selectedYear !== null) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      const d = new Date(a.start_date)
      return d.getFullYear() === selectedYear && d.getMonth() + 1 === selectedMonth
    })
  }

  if (filters.type) {
    result = result.filter((a) => activityType(a) === filters.type)
  }

  if (filters.source) {
    result = result.filter((a) => a.source === filters.source)
  }

  if (filters.distanceMin !== null) {
    const minM = filters.distanceMin * 1000
    result = result.filter((a) => a.distance !== null && a.distance >= minM)
  }

  if (filters.distanceMax !== null) {
    const maxM = filters.distanceMax * 1000
    result = result.filter((a) => a.distance !== null && a.distance <= maxM)
  }

  if (filters.search) {
    const q = filters.search.toLowerCase()
    result = result.filter((a) => a.name?.toLowerCase().includes(q))
  }

  result.sort((a, b) => {
    const dir = sortDesc ? -1 : 1
    switch (sortField) {
      case 'date':
        return dir * ((a.start_date ?? '').localeCompare(b.start_date ?? ''))
      case 'distance':
        return dir * ((a.distance ?? 0) - (b.distance ?? 0))
      case 'time':
        return dir * ((a.moving_time ?? 0) - (b.moving_time ?? 0))
      default:
        return 0
    }
  })

  return result
}
