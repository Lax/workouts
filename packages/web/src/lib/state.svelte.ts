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
  error: '',
  selectedYear: null as number | null,
  selectedMonth: null as number | null,
  colorMode: 'type' as ColorMode,
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

function computeYears() {
  const s = new Set<number>()
  for (const a of app.activities) {
    if (a.start_date) s.add(new Date(a.start_date).getFullYear())
  }
  app.years = Array.from(s).sort((a, b) => b - a)
}

function computeAvailableTypes() {
  const s = new Map<string, number>()
  for (const a of app.activities) {
    const t = a.sport_category || 'other'
    s.set(t, (s.get(t) || 0) + 1)
  }
  app.availableTypes = Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function computeAvailableSources() {
  const s = new Map<string, number>()
  for (const a of app.activities) {
    const src = a.source || 'unknown'
    s.set(src, (s.get(src) || 0) + 1)
  }
  app.availableSources = Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function computeFilteredActivities() {
  let result = [...app.activities]

  if (app.selectedYear !== null) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      return new Date(a.start_date).getFullYear() === app.selectedYear
    })
  }

  if (app.selectedMonth !== null && app.selectedYear !== null) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      const d = new Date(a.start_date)
      return d.getFullYear() === app.selectedYear && d.getMonth() + 1 === app.selectedMonth
    })
  }

  if (app.filters.type) {
    result = result.filter((a) => a.sport_category === app.filters.type)
  }

  if (app.filters.source) {
    result = result.filter((a) => a.source === app.filters.source)
  }

  if (app.filters.distanceMin !== null) {
    const minM = app.filters.distanceMin * 1000
    result = result.filter((a) => a.distance !== null && a.distance >= minM)
  }

  if (app.filters.distanceMax !== null) {
    const maxM = app.filters.distanceMax * 1000
    result = result.filter((a) => a.distance !== null && a.distance <= maxM)
  }

  if (app.filters.search) {
    const q = app.filters.search.toLowerCase()
    result = result.filter((a) => a.name?.toLowerCase().includes(q))
  }

  result.sort((a, b) => {
    const dir = app.sortDesc ? -1 : 1
    switch (app.sortField) {
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

  app.filteredActivities = result
}

$effect(() => {
  app.activities
  computeYears()
  computeAvailableTypes()
  computeAvailableSources()
  computeFilteredActivities()
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
  computeFilteredActivities()
})

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
    document.documentElement.setAttribute('data-theme', saved)
  } else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
    document.documentElement.setAttribute('data-theme', 'dark')
  }
}

export function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme') || 'light'
  const next = current === 'light' ? 'dark' : 'light'
  document.documentElement.setAttribute('data-theme', next)
  localStorage.setItem('theme', next)
}

export function currentTheme(): 'dark' | 'light' {
  return (document.documentElement.getAttribute('data-theme') as 'dark' | 'light') || 'light'
}
