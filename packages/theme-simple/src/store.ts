import type { Activity } from '@workouts/shared'
import { create } from 'zustand'
import { clearRunHash, setRunHash } from './utils'

export type SortField = 'date' | 'distance' | 'time'

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
  filteredActivities: Activity[]

  setActivities: (acts: Activity[]) => void
  setSelectedYear: (y: number | null) => void
  setColorMode: (m: 'type' | 'speed') => void
  toggleTheme: () => void
  toggleSort: (field: SortField) => void
  setMapHoveredId: (id: string | null) => void
  openDetail: (act: Activity) => void
  closeDetail: () => void
}

function computeYears(acts: Activity[]): number[] {
  const s = new Set<number>()
  for (const a of acts) {
    if (a.start_date) s.add(new Date(a.start_date).getFullYear())
  }
  return Array.from(s).sort((a, b) => b - a)
}

function filterActivities(acts: Activity[], selectedYear: number | null, sortField: SortField, sortDesc: boolean): Activity[] {
  let r = [...acts]
  if (selectedYear !== null) {
    r = r.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === selectedYear)
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
  filteredActivities: [],

  setActivities: (acts) =>
    set((s) => {
      const ys = computeYears(acts)
      const initialYear = s.selectedYear === null && ys.length > 0 ? ys[0] : s.selectedYear
      return {
        activities: acts,
        selectedYear: initialYear,
        years: ys,
        filteredActivities: filterActivities(acts, initialYear, s.sortField, s.sortDesc),
      }
    }),

  setSelectedYear: (y) =>
    set((s) => ({
      selectedYear: y,
      filteredActivities: filterActivities(s.activities, y, s.sortField, s.sortDesc),
    })),

  setColorMode: (m) => set({ colorMode: m }),

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
        filteredActivities: filterActivities(s.activities, s.selectedYear, field, desc),
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

  closeDetail: () => {
    clearRunHash()
    set({ selectedActivity: null, mapHoveredId: null })
  },
}))
