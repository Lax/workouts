import { classifyPeriod, extractCity, sortPeriods, type PeriodLabel } from '@workouts/shared'
import type { Activity } from '@workouts/shared'
import type { CityStat, LocationSummary, PeriodStat } from './types'

export function computeYears(activities: Activity[]): number[] {
  const years = new Set<number>()
  for (const a of activities) {
    if (a.start_date) {
      const y = new Date(a.start_date).getFullYear()
      if (!Number.isNaN(y)) years.add(y)
    }
  }
  return [...years].sort((a, b) => b - a)
}

export function computeAvailableTypes(activities: Activity[]): [string, number][] {
  const counts = new Map<string, number>()
  for (const a of activities) {
    const cat = a.sport_category || 'other'
    counts.set(cat, (counts.get(cat) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

export function computeAvailableSources(activities: Activity[]): [string, number][] {
  const counts = new Map<string, number>()
  for (const a of activities) {
    const src = a.source || 'unknown'
    counts.set(src, (counts.get(src) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

export function computeFilteredActivities(
  activities: Activity[],
  filters: {
    type: string
    source: string
    distanceMin: number | null
    distanceMax: number | null
    search: string
  },
  sortField: 'date' | 'distance' | 'time',
  sortDesc: boolean,
  year: number | null,
  month: number | null,
): Activity[] {
  let result = activities

  if (filters.type) {
    result = result.filter((a) => a.sport_category === filters.type)
  }
  if (filters.source) {
    result = result.filter((a) => a.source === filters.source)
  }
  if (filters.distanceMin !== null) {
    const min = filters.distanceMin * 1000
    result = result.filter((a) => a.distance !== null && a.distance >= min)
  }
  if (filters.distanceMax !== null) {
    const max = filters.distanceMax * 1000
    result = result.filter((a) => a.distance !== null && a.distance <= max)
  }
  if (filters.search) {
    const q = filters.search.toLowerCase()
    result = result.filter((a) => a.name?.toLowerCase().includes(q))
  }
  if (year !== null && year !== undefined) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      const d = new Date(a.start_date)
      return d.getFullYear() === year && (month === null || month === undefined || d.getMonth() + 1 === month)
    })
  }

  const cmp = (a: Activity, b: Activity): number => {
    switch (sortField) {
      case 'distance':
        return (a.distance ?? 0) - (b.distance ?? 0)
      case 'time':
        return (a.moving_time ?? 0) - (b.moving_time ?? 0)
      case 'date':
        return (a.start_date ?? '').localeCompare(b.start_date ?? '')
    }
  }

  return [...result].sort((a, b) => (sortDesc ? cmp(b, a) : cmp(a, b)))
}

export function computeCities(activities: Activity[]): CityStat[] {
  const cityDist = new Map<string, number>()
  for (const a of activities) {
    const info = extractCity(a.location_country)
    if (!info) continue
    const d = a.distance ?? 0
    cityDist.set(info.name, (cityDist.get(info.name) ?? 0) + d)
  }
  return [...cityDist.entries()]
    .map(([city, distance]) => ({ city, distance }))
    .sort((a, b) => b.distance - a.distance)
}

export function computePeriods(activities: Activity[]): PeriodStat[] {
  const counts = new Map<string, number>()
  let total = 0
  for (const a of activities) {
    if (!a.start_date_local) continue
    const d = new Date(a.start_date_local)
    const hour = d.getHours()
    if (Number.isNaN(hour)) continue
    const period = classifyPeriod(hour)
    if (!period) continue
    counts.set(period, (counts.get(period) ?? 0) + 1)
    total++
  }
  if (total === 0) return []
  return sortPeriods([...counts.keys()] as PeriodLabel[]).map((period) => ({
    period,
    label: PERIOD_LABELS[period],
    count: counts.get(period) ?? 0,
    pct: Math.round(((counts.get(period) ?? 0) / total) * 100),
  }))
}

const PERIOD_LABELS: Record<string, string> = {
  morning: '晨跑',
  noon: '午间',
  afternoon: '午后',
  evening: '傍晚',
  night: '夜跑',
}

export function computeLocationSummary(activities: Activity[]): LocationSummary {
  const countries = new Set<string>()
  const provinces = new Set<string>()
  const cities = new Set<string>()
  for (const a of activities) {
    const loc = a.location_country
    if (!loc) continue
    const info = extractCity(loc)
    if (info) {
      cities.add(info.name)
      provinces.add(info.province)
      countries.add(info.country)
    } else if (loc.length < 20 && loc !== loc.toLowerCase()) {
      countries.add(loc)
    }
  }
  return {
    countries: [...countries].sort(),
    provinces: [...provinces].sort(),
    cities: [...cities].sort(),
  }
}
