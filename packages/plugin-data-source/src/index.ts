export {
  computeAvailableSources,
  computeAvailableTypes,
  computeCities,
  computeLocationSummary,
  computePeriods,
  computeYears,
} from './compute'
export { default } from './plugin'
export type { CityStat, DerivedData, FilterOptions, LocationSummary, PeriodStat, SortField } from './types'
export { useActivities } from './useActivities'
export { computeFilteredActivities, useDerivedData } from './useData'
