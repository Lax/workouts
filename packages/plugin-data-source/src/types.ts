export interface FilterOptions {
  type: string
  source: string
  distanceMin: number | null
  distanceMax: number | null
  search: string
}

export type SortField = 'date' | 'distance' | 'time'

export interface CityStat {
  city: string
  distance: number
}

export interface PeriodStat {
  period: string
  label: string
  count: number
  pct: number
}

export interface LocationSummary {
  countries: string[]
  provinces: string[]
  cities: string[]
}

export interface ProvinceStat {
  province: string
  distance: number
  count: number
  cities: CityStat[]
}

export interface TypeStat {
  type: string
  label: string
  count: number
  distance: number
  pct: number
}

export interface DerivedData {
  years: number[]
  availableTypes: [string, number][]
  availableSources: [string, number][]
  cityStats: CityStat[]
  periodStats: PeriodStat[]
  locationSummary: LocationSummary
}
