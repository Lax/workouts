export {
  computeAvailableSources,
  computeAvailableTypes,
  computeLocationSummary,
  computePeriods,
  computeProvinceStats,
  computeTypeBreakdown,
  computeYears,
  detectLocation,
} from './compute'
export type { TracksMap } from './data'
export { fetchData, fetchTracks } from './data'
export { default } from './plugin'
export type { CityStat, DerivedData, FilterOptions, LocationSummary, PeriodStat, ProvinceStat, SortField, TypeStat } from './types'
export type { ActivitiesResult } from './useActivities'
export { useActivities } from './useActivities'
export { computeFilteredActivities, useDerivedData } from './useData'
