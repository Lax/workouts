import type { Activity } from '@workouts/shared'
import { classifyPeriod, extractCity } from '@workouts/shared'
import { create } from 'zustand'
import { clearRunHash, setRunHash } from './utils'

export type SortField = 'date' | 'distance' | 'time' | 'elevation'

export type ViewMode = 'table' | 'grid'

export interface SimpleStore {
  activities: Activity[]
  selectedYear: number | null
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
  cityFilter: string | null
  periodFilter: string | null
  showLabels: boolean
  viewMode: ViewMode
  showYearModal: number | null

  setActivities: (acts: Activity[]) => void
  setSelectedYear: (y: number | null) => void
  setColorMode: (m: 'type' | 'speed') => void
  toggleTheme: () => void
  toggleSort: (field: SortField) => void
  setMapHoveredId: (id: string | null) => void
  openDetail: (act: Activity) => void
  selectByHash: (act: Activity) => void
  closeDetail: () => void
  setCityFilter: (city: string | null) => void
  setPeriodFilter: (period: string | null) => void
  setViewMode: (mode: ViewMode) => void
  setShowYearModal: (year: number | null) => void
  setShowLabels: (v: boolean) => void
}

function computeYears(acts: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of acts) {
    if (a.start_date) s.add(new Date(a.start_date).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

export function computeStreak(acts: Activity[]): number {
  const dates = acts
    .filter((a) => a.start_date)
    .map((a) => new Date(a.start_date!).toISOString().slice(0, 10))
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

function filterActivities(
  acts: Activity[],
  selectedYear: number | null,
  sortField: SortField,
  sortDesc: boolean,
  cityFilter: string | null,
  periodFilter: string | null,
): Activity[] {
  let r = [...acts]
  if (selectedYear !== null) {
    r = r.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === selectedYear)
  }
  if (cityFilter !== null) {
    r = r.filter((a) => extractCity(a.location_country)?.name === cityFilter)
  }
  if (periodFilter !== null) {
    r = r.filter((a) => {
      if (!a.start_date_local) return false
      const d = new Date(a.start_date_local)
      const hour = d.getHours()
      if (Number.isNaN(hour)) return false
      return classifyPeriod(hour) === periodFilter
    })
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
  cityFilter: null,
  periodFilter: null,
  showLabels: true,
  viewMode: 'table',
  showYearModal: null,

  setActivities: (acts) =>
    set((s) => {
      const ys = computeYears(acts)
      const initialYear = s.selectedYear === null && ys.length > 0 ? ys[0] : s.selectedYear
      const streaks: Record<number, number> = {}
      for (const y of ys) {
        const yearActs = acts.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === y)
        streaks[y] = computeStreak(yearActs)
      }
      return {
        activities: acts,
        selectedYear: initialYear,
        years: ys,
        streaks,
        totalStreak: computeStreak(acts),
        filteredActivities: filterActivities(acts, initialYear, s.sortField, s.sortDesc, s.cityFilter, s.periodFilter),
      }
    }),

  setSelectedYear: (y) =>
    set((s) => ({
      selectedYear: y,
      cityFilter: null,
      periodFilter: null,
      filteredActivities: filterActivities(s.activities, y, s.sortField, s.sortDesc, null, null),
    })),

  setColorMode: (m) => set({ colorMode: m }),

  setShowLabels: (v) => set({ showLabels: v }),

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
        filteredActivities: filterActivities(s.activities, s.selectedYear, field, desc, s.cityFilter, s.periodFilter),
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

  setCityFilter: (city) =>
    set((s) => {
      const next = s.cityFilter === city ? null : city
      return {
        cityFilter: next,
        filteredActivities: filterActivities(s.activities, s.selectedYear, s.sortField, s.sortDesc, next, s.periodFilter),
      }
    }),

  setPeriodFilter: (period) =>
    set((s) => {
      const next = s.periodFilter === period ? null : period
      return {
        periodFilter: next,
        filteredActivities: filterActivities(s.activities, s.selectedYear, s.sortField, s.sortDesc, s.cityFilter, next),
      }
    }),

  setViewMode: (mode) => set({ viewMode: mode }),

  setShowYearModal: (year) => set({ showYearModal: year }),
}))
