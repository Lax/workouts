import { TILE_PRESET_STORAGE_KEY } from '@workouts/plugin-map'
import type { Activity } from '@workouts/shared'
import { create } from 'zustand'
import { computeStreak } from './compute'
import { clearRunHash, setRunHash } from './utils'

export type SortField = 'date' | 'distance' | 'time' | 'elevation'

export type ViewMode = 'table' | 'grid'

export type SummaryInterval = 'year' | 'month' | 'week' | 'day' | 'life'

export interface SimpleStore {
  activities: Activity[]
  selectedYear: number | null
  selectedMonth: number | null
  colorMode: 'type' | 'speed'
  colorScheme: 'light' | 'dark'
  sortField: SortField
  sortDesc: boolean
  mapHoveredId: string | null
  selectedActivity: Activity | null
  years: number[]
  streaks: Record<number, number>
  totalStreak: number
  filteredActivities: Activity[]
  regionFilter: string | null
  mapCompact: boolean
  typeFilter: string | null
  lightsOn: boolean
  tilePresetId: string
  viewMode: ViewMode
  showYearModal: number | null

  view: 'main' | 'summary'
  summaryInterval: SummaryInterval
  summarySportType: string
  summaryLifeYear: number | null

  setActivities: (acts: Activity[]) => void
  setSelectedYear: (y: number | null) => void
  setSelectedMonth: (m: number | null) => void
  setColorMode: (m: 'type' | 'speed') => void
  toggleTheme: () => void
  toggleSort: (field: SortField) => void
  setMapHoveredId: (id: string | null) => void
  openDetail: (act: Activity) => void
  selectByHash: (act: Activity) => void
  closeDetail: () => void
  setRegionFilter: (region: string | null) => void
  setTypeFilter: (type: string | null) => void
  setViewMode: (mode: ViewMode) => void
  setShowYearModal: (year: number | null) => void
  setLightsOn: (v: boolean) => void
  setTilePreset: (id: string) => void
  setView: (v: 'main' | 'summary') => void
  setSummaryInterval: (i: SummaryInterval) => void
  setSummarySportType: (t: string) => void
  setSummaryLifeYear: (y: number | null) => void
}

function computeYears(acts: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of acts) {
    const dt = a.start_date_local ?? a.start_date
    if (dt) s.add(new Date(dt).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

function filterActivities(
  acts: Activity[],
  selectedYear: number | null,
  selectedMonth: number | null,
  sortField: SortField,
  sortDesc: boolean,
  regionFilter: string | null,
  typeFilter: string | null,
): Activity[] {
  let r = [...acts]
  if (selectedYear !== null) {
    r = r.filter((a) => {
      const dt = a.start_date_local ?? a.start_date
      return dt && new Date(dt).getFullYear() === selectedYear
    })
  }
  if (selectedMonth !== null && selectedYear !== null) {
    r = r.filter((a) => {
      const dt = a.start_date_local ?? a.start_date
      return dt && new Date(dt).getMonth() + 1 === selectedMonth
    })
  }
  if (regionFilter !== null) {
    if (regionFilter === '其它') {
      r = r.filter((a) => {
        const regions = a.divisions
        return !regions || regions.length === 0
      })
    } else {
      r = r.filter((a) => {
        const regions = a.divisions
        if (!regions || regions.length === 0) return false
        return regions.some((reg) => reg.p === regionFilter || reg.c === regionFilter)
      })
    }
  }
  if (typeFilter !== null) {
    r = r.filter((a) => a.sport_category === typeFilter)
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
      case 'elevation':
        return d * ((a.elevation_gain ?? 0) - (b.elevation_gain ?? 0))
      default:
        return 0
    }
  })
  return r
}

export const useSimpleStore = create<SimpleStore>()((set) => ({
  activities: [],
  selectedYear: null,
  selectedMonth: null,
  colorMode: 'type',
  colorScheme: (document.documentElement.getAttribute('data-theme') || 'dark') as 'light' | 'dark',
  sortField: 'date',
  sortDesc: true,
  mapHoveredId: null,
  selectedActivity: null,
  years: [],
  streaks: {},
  totalStreak: 0,
  filteredActivities: [],
  regionFilter: null,
  mapCompact: false,
  typeFilter: null,
  lightsOn: false,
  tilePresetId: (typeof localStorage !== 'undefined' ? localStorage.getItem(TILE_PRESET_STORAGE_KEY) : null) || 'dark',
  viewMode: typeof window !== 'undefined' && window.innerWidth < 768 ? 'grid' : 'table',
  showYearModal: null,

  view: 'main',
  summaryInterval: 'month',
  summarySportType: '',
  summaryLifeYear: null,

  setActivities: (acts) =>
    set((s) => {
      const ys = computeYears(acts)
      const initialYear = s.selectedYear === null && ys.length > 0 ? ys[0] : s.selectedYear
      const streaks: Record<number, number> = {}
      for (const y of ys) {
        const yearActs = acts.filter((a) => {
          const dt = a.start_date_local ?? a.start_date
          return dt && new Date(dt).getFullYear() === y
        })
        streaks[y] = computeStreak(yearActs)
      }
      return {
        activities: acts,
        selectedYear: initialYear,
        years: ys,
        streaks,
        totalStreak: computeStreak(acts),
        filteredActivities: filterActivities(acts, initialYear, s.selectedMonth, s.sortField, s.sortDesc, s.regionFilter, s.typeFilter),
      }
    }),

  setSelectedYear: (y) =>
    set((s) => ({
      selectedYear: y,
      selectedMonth: null,
      regionFilter: null,
      mapCompact: false,
      typeFilter: null,
      selectedActivity: null,
      mapHoveredId: null,
      filteredActivities: filterActivities(s.activities, y, null, s.sortField, s.sortDesc, null, null),
    })),

  setSelectedMonth: (m) =>
    set((s) => ({
      selectedMonth: m,
      selectedActivity: null,
      mapHoveredId: null,
      filteredActivities: filterActivities(s.activities, s.selectedYear, m, s.sortField, s.sortDesc, s.regionFilter, s.typeFilter),
    })),

  setColorMode: (m) => set({ colorMode: m }),

  setLightsOn: (v: boolean) => set({ lightsOn: v }),
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

  toggleSort: (field) =>
    set((s) => {
      const desc = s.sortField === field ? !s.sortDesc : true
      return {
        sortField: field,
        sortDesc: desc,
        selectedActivity: null,
        mapHoveredId: null,
        filteredActivities: filterActivities(s.activities, s.selectedYear, s.selectedMonth, field, desc, s.regionFilter, s.typeFilter),
      }
    }),

  setMapHoveredId: (id) => set({ mapHoveredId: id }),

  openDetail: (act) =>
    set((s) => {
      if (s.selectedActivity?.run_id === act.run_id) {
        clearRunHash()
        return { selectedActivity: null, mapHoveredId: null }
      }
      setRunHash(act.run_id)
      return { selectedActivity: act, mapHoveredId: act.run_id }
    }),

  selectByHash: (act: Activity) => set({ selectedActivity: act, mapHoveredId: act.run_id }),

  closeDetail: () => {
    clearRunHash()
    set({ selectedActivity: null, mapHoveredId: null })
  },

  setRegionFilter: (region) =>
    set((s) => {
      const next = s.regionFilter === region ? null : region
      return {
        regionFilter: next,
        mapCompact: next === '其它',
        selectedActivity: null,
        mapHoveredId: null,
        filteredActivities: filterActivities(s.activities, s.selectedYear, s.selectedMonth, s.sortField, s.sortDesc, next, s.typeFilter),
      }
    }),

  setTypeFilter: (type) =>
    set((s) => {
      const next = s.typeFilter === type ? null : type
      return {
        typeFilter: next,
        selectedActivity: null,
        mapHoveredId: null,
        filteredActivities: filterActivities(s.activities, s.selectedYear, s.selectedMonth, s.sortField, s.sortDesc, s.regionFilter, next),
      }
    }),

  setViewMode: (mode) => set({ viewMode: mode }),

  setShowYearModal: (year) => set({ showYearModal: year }),

  setView: (v) => set({ view: v }),
  setSummaryInterval: (i) => set({ summaryInterval: i }),
  setSummarySportType: (t) => set({ summarySportType: t }),
  setSummaryLifeYear: (y) => set({ summaryLifeYear: y }),
}))
