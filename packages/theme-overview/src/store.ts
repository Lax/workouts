import { TILE_PRESET_STORAGE_KEY } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'
import { create } from 'zustand'

export type SortField = 'date' | 'distance' | 'time'

export interface Filters {
  type: string
  source: string
  distanceMin: number | null
  distanceMax: number | null
  search: string
}

export interface OverviewStore {
  activities: Activity[]
  stats: Record<string, unknown> | null
  colorMode: 'type' | 'speed'
  colorScheme: 'light' | 'dark'
  selectedYear: number | null
  selectedMonth: number | null
  drawerOpen: boolean
  showCharts: boolean
  selectedActivity: Activity | null
  detailOpen: boolean
  sortField: SortField
  sortDesc: boolean
  filters: Filters
  tilePresetId: string
  mapHoveredId: string | null
  years: number[]
  availableTypes: [string, number][]
  availableSources: [string, number][]
  filteredActivities: Activity[]
  setActivities: (acts: Activity[]) => void
  openDetail: (act: Activity) => void
  closeDetail: () => void
  openCharts: () => void
  closeCharts: () => void
  toggleSort: (field: SortField) => void
  resetFilters: () => void
  setFilter: (patch: Partial<Filters>) => void
  setSelectedYear: (y: number | null) => void
  setSelectedMonth: (m: number | null) => void
  setColorMode: (m: 'type' | 'speed') => void
  setTilePreset: (id: string) => void
  toggleTheme: () => void
  setMapHoveredId: (id: string | null) => void
  toggleDrawer: () => void
}

const defaultFilters: Filters = { type: '', source: '', distanceMin: null, distanceMax: null, search: '' }

function computeYears(acts: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of acts) {
    const dt = a.start_date_local ?? a.start_date
    if (dt) s.add(new Date(dt).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

function computeAvailableTypes(acts: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of acts) {
    const cat = a.sport_category || a.type || 'other'
    s.set(cat, (s.get(cat) || 0) + 1)
  }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function computeAvailableSources(acts: Activity[]): [string, number][] {
  const s = new Map<string, number>()
  for (const a of acts) {
    const src = a.source || 'unknown'
    s.set(src, (s.get(src) || 0) + 1)
  }
  return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
}

function filterActivities(
  acts: Activity[],
  filters: Filters,
  sortField: SortField,
  sortDesc: boolean,
  selectedYear: number | null,
  selectedMonth: number | null,
): Activity[] {
  let r = [...acts]
  if (selectedYear !== null)
    r = r.filter((a) => {
      const dt = a.start_date_local ?? a.start_date
      return dt && new Date(dt).getFullYear() === selectedYear
    })
  if (selectedMonth !== null && selectedYear !== null)
    r = r.filter((a) => {
      const dt = a.start_date_local ?? a.start_date
      return dt && new Date(dt).getFullYear() === selectedYear && new Date(dt).getMonth() + 1 === selectedMonth
    })
  if (filters.type) r = r.filter((a) => (a.sport_category || a.type || 'other') === filters.type)
  if (filters.source) r = r.filter((a) => a.source === filters.source)
  if (filters.distanceMin !== null) {
    const minM = filters.distanceMin * 1000
    r = r.filter((a) => a.distance !== null && a.distance >= minM)
  }
  if (filters.distanceMax !== null) {
    const maxM = filters.distanceMax * 1000
    r = r.filter((a) => a.distance !== null && a.distance <= maxM)
  }
  if (filters.search) {
    const q = filters.search.toLowerCase()
    r = r.filter((a) => a.name?.toLowerCase().includes(q))
  }
  r.sort((a, b) => {
    const d = sortDesc ? -1 : 1
    switch (sortField) {
      case 'date':
        return d * (a.start_date ?? '').localeCompare(b.start_date ?? '')
      case 'distance':
        return d * ((a.distance ?? 0) - (b.distance ?? 0))
      case 'time':
        return d * ((a.moving_time ?? 0) - (b.moving_time ?? 0))
      default:
        return 0
    }
  })
  return r
}

function recompute(
  acts: Activity[],
  filters: Filters,
  sortField: SortField,
  sortDesc: boolean,
  selectedYear: number | null,
  selectedMonth: number | null,
) {
  return {
    years: computeYears(acts),
    availableTypes: computeAvailableTypes(acts),
    availableSources: computeAvailableSources(acts),
    filteredActivities: filterActivities(acts, filters, sortField, sortDesc, selectedYear, selectedMonth),
  }
}

export const useOverviewStore = create<OverviewStore>()((set) => ({
  activities: [],
  stats: null,
  colorMode: 'type',
  colorScheme: (document.documentElement.getAttribute('data-theme') || 'dark') as 'light' | 'dark',
  selectedYear: null,
  selectedMonth: null,
  drawerOpen: false,
  showCharts: false,
  selectedActivity: null,
  detailOpen: false,
  sortField: 'date',
  sortDesc: true,
  filters: defaultFilters,
  tilePresetId: (typeof localStorage !== 'undefined' ? localStorage.getItem(TILE_PRESET_STORAGE_KEY) : null) || 'dark',
  mapHoveredId: null,
  years: [],
  availableTypes: [],
  availableSources: [],
  filteredActivities: [],

  setActivities: (acts) =>
    set((s) => ({
      activities: acts,
      ...recompute(acts, s.filters, s.sortField, s.sortDesc, s.selectedYear, s.selectedMonth),
    })),
  openDetail: (act) => set({ selectedActivity: act, detailOpen: true, drawerOpen: false }),
  closeDetail: () => set({ detailOpen: false, selectedActivity: null }),
  openCharts: () => set({ showCharts: true, drawerOpen: false }),
  closeCharts: () => set({ showCharts: false }),
  toggleSort: (field) =>
    set((s) => {
      const desc = s.sortField === field ? !s.sortDesc : true
      return {
        sortField: field,
        sortDesc: desc,
        filteredActivities: filterActivities(s.activities, s.filters, field, desc, s.selectedYear, s.selectedMonth),
      }
    }),
  resetFilters: () =>
    set((s) => ({
      filters: { ...defaultFilters },
      selectedMonth: null,
      filteredActivities: filterActivities(s.activities, defaultFilters, s.sortField, s.sortDesc, s.selectedYear, null),
    })),
  setFilter: (patch) =>
    set((s) => {
      const f = { ...s.filters, ...patch }
      return { filters: f, filteredActivities: filterActivities(s.activities, f, s.sortField, s.sortDesc, s.selectedYear, s.selectedMonth) }
    }),
  setSelectedYear: (y) =>
    set((s) => ({
      selectedYear: y,
      selectedMonth: y !== s.selectedYear ? null : s.selectedMonth,
      selectedActivity: null,
      detailOpen: false,
      filteredActivities: filterActivities(
        s.activities,
        s.filters,
        s.sortField,
        s.sortDesc,
        y,
        y !== s.selectedYear ? null : s.selectedMonth,
      ),
    })),
  setSelectedMonth: (m) =>
    set((s) => ({
      selectedMonth: m,
      filteredActivities: filterActivities(s.activities, s.filters, s.sortField, s.sortDesc, s.selectedYear, m),
    })),
  setColorMode: (m) => set({ colorMode: m }),
  setTilePreset: (id: string) => {
    localStorage.setItem(TILE_PRESET_STORAGE_KEY, id)
    set({ tilePresetId: id })
  },
  toggleTheme: () =>
    set((s) => {
      const next = s.colorScheme === 'light' ? 'dark' : 'light'
      document.documentElement.setAttribute('data-theme', next)
      localStorage.setItem('theme', next)
      return { colorScheme: next }
    }),
  setMapHoveredId: (id) => set({ mapHoveredId: id }),
  toggleDrawer: () => set((s) => ({ drawerOpen: !s.drawerOpen })),
}))
