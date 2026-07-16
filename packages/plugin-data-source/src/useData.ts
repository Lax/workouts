import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { computeAvailableSources, computeAvailableTypes, computeLocationSummary, computePeriods, computeYears } from './compute'
import type { DerivedData, FilterOptions, SortField } from './types'
import { useActivities } from './useActivities'

export function useDerivedData(): DerivedData {
  const { activities, loading } = useActivities()
  const acts = (loading ? [] : activities) as Activity[]
  return useMemo(
    () => ({
      years: computeYears(acts),
      availableTypes: computeAvailableTypes(acts),
      availableSources: computeAvailableSources(acts),
      cityStats: [],
      periodStats: computePeriods(acts),
      locationSummary: computeLocationSummary(acts),
    }),
    [acts],
  )
}

export { computeFilteredActivities } from './compute'
export type { FilterOptions, SortField }
