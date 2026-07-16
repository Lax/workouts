import type { Activity, GeoLocation } from '@workouts/shared'
import {
  CATEGORY_LABELS,
  CONTINENT_BOUNDARIES,
  classifyPeriod,
  classifyPeriod3,
  extractCity,
  getStartCoords,
  matchPolygons,
  OCEAN_BOUNDARIES,
  PERIOD3_LABELS,
  type PeriodLabel,
  PROVINCE_BOUNDARIES,
  sortPeriods,
} from '@workouts/shared'
import type { CityStat, LocationSummary, PeriodStat, ProvinceStat, TypeStat } from './types'

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

export function detectLocation(activity: { summary_polyline?: string | null; location_country?: string | null }): GeoLocation {
  const coords = getStartCoords(activity.summary_polyline)

  if (coords) {
    const [lat, lng] = coords

    const provinceName = matchPolygons(lat, lng, PROVINCE_BOUNDARIES)
    if (provinceName) {
      return { type: 'province', name: provinceName }
    }

    const continentName = matchPolygons(lat, lng, CONTINENT_BOUNDARIES)
    if (continentName) {
      return { type: 'continent', name: continentName }
    }

    const oceanName = matchPolygons(lat, lng, OCEAN_BOUNDARIES)
    if (oceanName) {
      return { type: 'ocean', name: oceanName }
    }
  }

  const text = activity.location_country
  if (text) {
    const info = extractCity(text)
    if (info) {
      return { type: 'text_fallback', name: info.province || info.name }
    }
    if (text.length < 20 && text !== text.toLowerCase()) {
      return { type: 'text_fallback', name: text }
    }
  }

  return { type: 'unknown', name: '' }
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
    const loc = detectLocation(a)
    if (loc.type === 'unknown') continue
    if (loc.type === 'province') {
      provinces.add(loc.name)
      countries.add('China')
    } else if (loc.type === 'text_fallback') {
      provinces.add(loc.name)
      countries.add('China')
    } else if (loc.type === 'continent') {
      countries.add(loc.name)
    } else if (loc.type === 'ocean') {
      countries.add(loc.name)
    }
  }
  return {
    countries: [...countries].sort(),
    provinces: [...provinces].sort(),
    cities: [...cities].sort(),
  }
}

export function computePeriods3(activities: Activity[]): PeriodStat[] {
  const counts = new Map<string, number>()
  let total = 0
  for (const a of activities) {
    if (!a.start_date_local) continue
    const d = new Date(a.start_date_local)
    const hour = d.getHours()
    if (Number.isNaN(hour)) continue
    const period = classifyPeriod3(hour)
    if (!period) continue
    counts.set(period, (counts.get(period) ?? 0) + 1)
    total++
  }
  if (total === 0) return []
  const order = ['morning', 'afternoon', 'evening']
  return order
    .map((period) => ({
      period,
      label: PERIOD3_LABELS[period] ?? period,
      count: counts.get(period) ?? 0,
      pct: total > 0 ? Math.round(((counts.get(period) ?? 0) / total) * 100) : 0,
    }))
    .filter((p) => p.count > 0)
}

export function computeTypeBreakdown(activities: Activity[]): TypeStat[] {
  const catDist = new Map<string, { count: number; distance: number }>()
  for (const a of activities) {
    const cat = a.sport_category || 'other'
    const existing = catDist.get(cat) ?? { count: 0, distance: 0 }
    existing.count++
    existing.distance += a.distance ?? 0
    catDist.set(cat, existing)
  }
  const total = catDist.size
  if (total === 0) return []
  const grandTotal = [...catDist.values()].reduce((s, v) => s + v.distance, 0)
  return [...catDist.entries()]
    .map(([type, v]) => ({
      type,
      label: (CATEGORY_LABELS as Record<string, string>)[type] ?? type,
      count: v.count,
      distance: v.distance,
      pct: grandTotal > 0 ? Math.round((v.distance / grandTotal) * 100) : 0,
    }))
    .sort((a, b) => b.distance - a.distance)
}

export function computeProvinceStats(activities: Activity[]): ProvinceStat[] {
  const regionDist = new Map<string, number>()
  const regionCount = new Map<string, number>()
  const regionCities = new Map<string, CityStat[]>()
  for (const a of activities) {
    const loc = detectLocation(a)
    if (loc.type === 'unknown') continue
    const name = loc.name
    const d = a.distance ?? 0
    regionDist.set(name, (regionDist.get(name) ?? 0) + d)
    regionCount.set(name, (regionCount.get(name) ?? 0) + 1)
    if (!regionCities.has(name)) regionCities.set(name, [])
  }
  return [...regionDist.entries()]
    .map(([name, distance]) => ({
      province: name,
      distance,
      count: regionCount.get(name) ?? 0,
      cities: [],
    }))
    .sort((a, b) => b.distance - a.distance)
}
