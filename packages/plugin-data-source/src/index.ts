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
export { default } from './plugin'
export type { CityStat, DerivedData, FilterOptions, LocationSummary, PeriodStat, ProvinceStat, SortField, TypeStat } from './types'
export { useActivities } from './useActivities'
export { computeFilteredActivities, useDerivedData } from './useData'
