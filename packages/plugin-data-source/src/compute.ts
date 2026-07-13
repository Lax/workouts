import type { Activity } from '@workouts/shared'

export function computeYears(activities: Activity[]): number[] {
  const years = new Set<number>()
  for (const a of activities) {
    if (a.start_date) {
      const y = new Date(a.start_date).getFullYear()
      if (!Number.isNaN(y)) years.add(y)
    }
  }
  return [...years].sort((a, b) => b - a)
}

export function computeAvailableTypes(activities: Activity[]): [string, number][] {
  const counts = new Map<string, number>()
  for (const a of activities) {
    const cat = a.sport_category || 'other'
    counts.set(cat, (counts.get(cat) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

export function computeAvailableSources(activities: Activity[]): [string, number][] {
  const counts = new Map<string, number>()
  for (const a of activities) {
    const src = a.source || 'unknown'
    counts.set(src, (counts.get(src) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
}

export function computeFilteredActivities(
  activities: Activity[],
  filters: {
    type: string
    source: string
    distanceMin: number | null
    distanceMax: number | null
    search: string
  },
  sortField: 'date' | 'distance' | 'time',
  sortDesc: boolean,
  year: number | null,
  month: number | null,
): Activity[] {
  let result = activities

  if (filters.type) {
    result = result.filter((a) => a.sport_category === filters.type)
  }
  if (filters.source) {
    result = result.filter((a) => a.source === filters.source)
  }
  if (filters.distanceMin !== null) {
    const min = filters.distanceMin * 1000
    result = result.filter((a) => a.distance !== null && a.distance >= min)
  }
  if (filters.distanceMax !== null) {
    const max = filters.distanceMax * 1000
    result = result.filter((a) => a.distance !== null && a.distance <= max)
  }
  if (filters.search) {
    const q = filters.search.toLowerCase()
    result = result.filter((a) => a.name?.toLowerCase().includes(q))
  }
  if (year !== null && year !== undefined) {
    result = result.filter((a) => {
      if (!a.start_date) return false
      const d = new Date(a.start_date)
      return d.getFullYear() === year && (month === null || month === undefined || d.getMonth() + 1 === month)
    })
  }

  const cmp = (a: Activity, b: Activity): number => {
    switch (sortField) {
      case 'distance':
        return (a.distance ?? 0) - (b.distance ?? 0)
      case 'time':
        return (a.moving_time ?? 0) - (b.moving_time ?? 0)
      case 'date':
        return (a.start_date ?? '').localeCompare(b.start_date ?? '')
    }
  }

  return [...result].sort((a, b) => (sortDesc ? cmp(b, a) : cmp(a, b)))
}
