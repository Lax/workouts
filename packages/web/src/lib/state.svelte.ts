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
  selectedYear: null as number | null,
  selectedMonth: null as number | null,
  theme: 'light' as 'light' | 'dark',
  colorMode: 'speed' as ColorMode,
  drawerOpen: false,
  showCharts: false,
  selectedActivity: null as Activity | null,
  detailOpen: false,
  sortField: 'date' as SortField,
  sortDesc: true,
  filters: { type: '', source: '', distanceMin: null, distanceMax: null, search: '' } as Filters,
  mapHoveredId: null as string | null,
  years: [] as number[],
  availableTypes: [] as [string, number][],
  availableSources: [] as [string, number][],
  filteredActivities: [] as Activity[],
})

export function computeYears(activities: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of activities) {
    if (a.start_date) s.add(new Date(a.start_date).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

function activityType(a: Activity): string {
  return a.sport_category || a.type || 'other'
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

export function initReactivity() {
  $effect(() => {
    app.activities
    app.years = computeYears(app.activities)
    app.availableTypes = computeAvailableTypes(app.activities)
    app.availableSources = computeAvailableSources(app.activities)
    app.filteredActivities = computeFilteredActivities(app.activities, app.filters, app.sortField, app.sortDesc, app.selectedYear, app.selectedMonth)
  })

  $effect(() => {
    app.selectedYear
    app.selectedMonth
    app.filters.type
    app.filters.source
    app.filters.distanceMin
    app.filters.distanceMax
    app.filters.search
    app.sortField
    app.sortDesc
    app.filteredActivities = computeFilteredActivities(app.activities, app.filters, app.sortField, app.sortDesc, app.selectedYear, app.selectedMonth)
  })
}

export function toggleSort(field: SortField) {
  if (app.sortField === field) {
    app.sortDesc = !app.sortDesc
  } else {
    app.sortField = field
    app.sortDesc = true
  }
}

export function openDetail(act: Activity) {
  app.selectedActivity = act
  app.detailOpen = true
  app.drawerOpen = false
}

export function closeDetail() {
  app.detailOpen = false
  app.selectedActivity = null
}

export function openCharts() {
  app.showCharts = true
  app.drawerOpen = false
}

export function closeCharts() {
  app.showCharts = false
}

export function resetFilters() {
  app.filters.type = ''
  app.filters.source = ''
  app.filters.distanceMin = null
  app.filters.distanceMax = null
  app.filters.search = ''
  app.selectedMonth = null
}

export function initTheme() {
  const saved = localStorage.getItem('theme')
  if (saved) {
    app.theme = saved as 'light' | 'dark'
  } else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    app.theme = 'dark'
  }
  document.documentElement.setAttribute('data-theme', app.theme)
}

export function toggleTheme() {
  app.theme = app.theme === 'light' ? 'dark' : 'light'
  document.documentElement.setAttribute('data-theme', app.theme)
  localStorage.setItem('theme', app.theme)
}

export function currentTheme(): 'dark' | 'light' {
  return (document.documentElement.getAttribute('data-theme') as 'dark' | 'light') || 'light'
}
