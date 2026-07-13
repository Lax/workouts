export interface FilterOptions {
  type: string
  source: string
  distanceMin: number | null
  distanceMax: number | null
  search: string
}

export type SortField = 'date' | 'distance' | 'time'

export interface DerivedData {
  years: number[]
  availableTypes: [string, number][]
  availableSources: [string, number][]
}
