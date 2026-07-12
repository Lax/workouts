import type { Activity } from '@workouts/shared'
import type { ThemeContext } from '@workouts/shared'

export type SortField = 'date' | 'distance' | 'time'

export interface Filters {
  type: string
  source: string
  distanceMin: number | null
  distanceMax: number | null
  search: string
}

export function createOverviewStore(ctx: ThemeContext) {
  let acts: Activity[] = $state([])

  const state = $state({
    activities: [] as Activity[],
    colorMode: 'speed' as 'speed' | 'type',
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

  function computeYears(activities: Activity[]): number[] {
    const s = new Set<number>()
    for (const a of activities) {
      if (a.start_date) s.add(new Date(a.start_date).getFullYear())
    }
    return Array.from(s).sort((a, b) => b - a)
  }

  function activityType(a: Activity): string {
    return a.sport_category || a.type || 'other'
  }

  function computeAvailableTypes(activities: Activity[]): [string, number][] {
    const s = new Map<string, number>()
    for (const a of activities) {
      const t = activityType(a)
      s.set(t, (s.get(t) || 0) + 1)
    }
    return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
  }

  function computeAvailableSources(activities: Activity[]): [string, number][] {
    const s = new Map<string, number>()
    for (const a of activities) {
      const src = a.source || 'unknown'
      s.set(src, (s.get(src) || 0) + 1)
    }
    return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
  }

  function computeFilteredActivities(): Activity[] {
    return filterActivities(acts, state.filters, state.sortField, state.sortDesc, state.selectedYear, state.selectedMonth)
  }

  function updateDerived() {
    state.years = computeYears(acts)
    state.availableTypes = computeAvailableTypes(acts)
    state.availableSources = computeAvailableSources(acts)
    state.filteredActivities = computeFilteredActivities()
  }

  function openDetail(act: Activity) {
    state.selectedActivity = act
    state.detailOpen = true
    state.drawerOpen = false
  }

  function closeDetail() {
    state.detailOpen = false
    state.selectedActivity = null
  }

  function openCharts() {
    state.showCharts = true
    state.drawerOpen = false
  }

  function closeCharts() {
    state.showCharts = false
  }

  function toggleSort(field: SortField) {
    if (state.sortField === field) {
      state.sortDesc = !state.sortDesc
    } else {
      state.sortField = field
      state.sortDesc = true
    }
  }

  function resetFilters() {
    state.filters = { type: '', source: '', distanceMin: null, distanceMax: null, search: '' }
    state.selectedMonth = null
  }

  $effect(() => {
    acts
    state.filters
    state.sortField
    state.sortDesc
    state.selectedYear
    state.selectedMonth
    updateDerived()
  })

  Object.defineProperties(state, {
    activities: {
      get: () => acts,
      set: (v: Activity[]) => { acts = v; updateDerived() },
    },
  })

  return { state, openDetail, closeDetail, openCharts, closeCharts, toggleSort, resetFilters }
}

function filterActivities(
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
    result = result.filter((a) => (a.sport_category || a.type || 'other') === filters.type)
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
