import { useMemo } from 'react'
import { useTheme } from '@workouts/core'
import type { Activity } from '@workouts/shared'
import { computeYears, computeAvailableTypes, computeAvailableSources } from './compute'
import type { DerivedData, FilterOptions, SortField } from './types'

export function useDerivedData(): DerivedData {
  const { data } = useTheme()
  const activities = (data.activities ?? []) as Activity[]
  return useMemo(
    () => ({
      years: computeYears(activities),
      availableTypes: computeAvailableTypes(activities),
      availableSources: computeAvailableSources(activities),
    }),
    [activities],
  )
}

export { computeFilteredActivities } from './compute'
export type { FilterOptions, SortField }
