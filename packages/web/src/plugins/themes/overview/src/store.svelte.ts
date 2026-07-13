import type { Activity } from '@workouts/shared'
import type { ThemeContext } from '@workouts/shared'

export interface StatsJson {
  summary: { total_activities: number; total_distance_km: number; total_moving_time_h: number; total_elevation_gain_m: number; avg_cadence: number | null; avg_power: number | null; sport_breakdown: { category: string; count: number; distance_km: number; moving_time_h: number }[] }
  monthly: { year: number; month: number; count: number; distance_km: number; moving_time_h: number; avg_pace: string; avg_hr: number | null; avg_cadence: number | null; avg_power: number | null; elevation_gain_m: number }[]
  yearly: { year: number; month: number; count: number; distance_km: number; moving_time_h: number; longest_km: number; streak: number }[]
  streaks: { current: number; all_time: number }
  activity_types: string[]
}

export type SortField = 'date' | 'distance' | 'time'

export interface Filters {
  type: string; source: string; distanceMin: number | null; distanceMax: number | null; search: string
}

export { computeYears, computeAvailableTypes, computeAvailableSources, filterActivities as computeFilteredActivities }

export function createOverviewStore(ctx: ThemeContext) {
  let activitiesInput: Activity[] = $state([])

  const state = $state({
    activities: [] as Activity[],
    stats: null as StatsJson | null,
    colorMode: 'speed' as 'speed' | 'type',
    colorScheme: (document.documentElement.getAttribute('data-theme') || 'dark') as 'dark' | 'light',
    selectedYear: null as number | null,
    selectedMonth: null as number | null,
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

  function recompute() {
    const acts = activitiesInput
    state.activities = acts
    state.years = computeYears(acts)
    state.availableTypes = computeAvailableTypes(acts)
    state.availableSources = computeAvailableSources(acts)
    state.filteredActivities = filterActivities(acts, state.filters, state.sortField, state.sortDesc, state.selectedYear, state.selectedMonth)
  }

  $effect(() => {
    activitiesInput
    state.filters
    state.sortField
    state.sortDesc
    state.selectedYear
    state.selectedMonth
    recompute()
  })

  return {
    state,
    setActivities: (v: Activity[]) => { activitiesInput = v },
    openDetail: (act: Activity) => { state.selectedActivity = act; state.detailOpen = true; state.drawerOpen = false },
    closeDetail: () => { state.detailOpen = false; state.selectedActivity = null },
    openCharts: () => { state.showCharts = true; state.drawerOpen = false },
    closeCharts: () => { state.showCharts = false },
    toggleSort: (field: SortField) => {
      if (state.sortField === field) { state.sortDesc = !state.sortDesc }
      else { state.sortField = field; state.sortDesc = true }
    },
    resetFilters: () => { state.filters = { type: '', source: '', distanceMin: null, distanceMax: null, search: '' }; state.selectedMonth = null },
  }
}

function computeYears(acts: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of acts) { if (a.start_date) s.add(new Date(a.start_date).getFullYear()) }
  return Array.from(s).sort((a, b) => b - a)
}

function computeAvailableTypes(acts: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of acts) {
    s.set(a.sport_category || a.type || 'other', (s.get(a.sport_category || a.type || 'other') || 0) + 1)
  }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function computeAvailableSources(acts: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of acts) { const src = a.source || 'unknown'; s.set(src, (s.get(src) || 0) + 1) }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function filterActivities(
  activities: Activity[], filters: Filters, sortField: SortField, sortDesc: boolean,
  selectedYear: number | null, selectedMonth: number | null,
): Activity[] {
  let r = [...activities]
  if (selectedYear !== null) r = r.filter(a => a.start_date && new Date(a.start_date).getFullYear() === selectedYear)
  if (selectedMonth !== null && selectedYear !== null) r = r.filter(a => a.start_date && new Date(a.start_date).getFullYear() === selectedYear && new Date(a.start_date).getMonth() + 1 === selectedMonth)
  if (filters.type) r = r.filter(a => (a.sport_category || a.type || 'other') === filters.type)
  if (filters.source) r = r.filter(a => a.source === filters.source)
  if (filters.distanceMin !== null) { const minM = filters.distanceMin * 1000; r = r.filter(a => a.distance !== null && a.distance >= minM) }
  if (filters.distanceMax !== null) { const maxM = filters.distanceMax * 1000; r = r.filter(a => a.distance !== null && a.distance <= maxM) }
  if (filters.search) { const q = filters.search.toLowerCase(); r = r.filter(a => a.name?.toLowerCase().includes(q)) }
  r.sort((a, b) => {
    const d = sortDesc ? -1 : 1
    switch (sortField) {
      case 'date': return d * ((a.start_date ?? '').localeCompare(b.start_date ?? ''))
      case 'distance': return d * ((a.distance ?? 0) - (b.distance ?? 0))
      case 'time': return d * ((a.moving_time ?? 0) - (b.moving_time ?? 0))
      default: return 0
    }
  })
  return r
}
