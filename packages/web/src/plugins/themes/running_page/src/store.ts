import type { Activity } from '@workouts/shared'
import type { ThemeContext } from '@workouts/shared'

export interface YearStat {
  year: number
  count: number
  totalDistance: number
  avgPace: string
  streak: number
  avgHr: number | null
}

export interface PeriodBucket {
  key: string
  label: string
  activities: Activity[]
  totalDistance: number
  count: number
  avgPace: string
  avgHr: number | null
  dailyDistances: number[]
}

export function createRunningStore(ctx: ThemeContext) {
  const state = $state({
    view: 'main' as 'main' | 'summary',
    selectedYear: 'all' as string,
    selectedActivity: null as Activity | null,
    sortField: 'date' as string,
    sortDesc: true,
    summaryInterval: 'monthly' as string,
    summaryType: 'all' as string,
  })

  const activities = $derived(ctx.data.activities ?? [] as Activity[])

  const yearStats = $derived.by(() => {
    const byYear = new Map<number, Activity[]>()
    for (const a of activities) {
      if (!a.start_date) continue
      const y = new Date(a.start_date).getFullYear()
      if (!byYear.has(y)) byYear.set(y, [])
      byYear.get(y)!.push(a)
    }
    return Array.from(byYear.entries())
      .sort((a, b) => b[0] - a[0])
      .map(([year, acts]) => ({
        year,
        count: acts.length,
        totalDistance: acts.reduce((s, act) => s + (act.distance ?? 0), 0),
        avgPace: computeAvgPace(acts),
        streak: 0,
        avgHr: avgOrNull(acts.map(act => act.average_heartrate)),
      }))
  })

  const filteredRuns = $derived(
    state.selectedYear === 'all'
      ? activities
      : activities.filter((a: Activity) => a.start_date && new Date(a.start_date).getFullYear() === Number(state.selectedYear)),
  )

  const summaryBuckets = $derived.by(() => {
    let pool = activities
    if (state.summaryType !== 'all') {
      pool = pool.filter((a: Activity) => (a.sport_category || a.type || 'other') === state.summaryType)
    }
    return bucketByInterval(pool, state.summaryInterval)
  })

  const availableTypes = $derived.by(() => {
    const s = new Map<string, number>()
    for (const a of activities) {
      const t = a.sport_category || a.type || 'other'
      s.set(t, (s.get(t) || 0) + 1)
    }
    return Array.from(s.entries()).sort((a, b) => b[1] - a[1])
  })

  return { state, activities, yearStats, filteredRuns, summaryBuckets, availableTypes }
}

const computeAvgPace = (acts: Activity[]): string => {
  const totalDist = acts.reduce((s, a) => s + (a.distance ?? 0), 0)
  const totalTime = acts.reduce((s, a) => s + (a.moving_time ?? 0), 0)
  if (totalDist <= 0 || totalTime <= 0) return '—'
  const pace = totalTime / (totalDist / 1000)
  return `${Math.floor(pace / 60)}:${String(Math.round(pace % 60)).padStart(2, '0')}`
}

const avgOrNull = (vals: (number | null)[]): number | null => {
  const f = vals.filter((v): v is number => v !== null && v !== undefined)
  return f.length > 0 ? Math.round(f.reduce((s, v) => s + v, 0) / f.length) : null
}

const bucketByInterval = (acts: Activity[], interval: string): PeriodBucket[] => {
  const buckets = new Map<string, Activity[]>()
  for (const a of acts) {
    if (!a.start_date) continue
    const d = new Date(a.start_date)
    let key: string
    if (interval === 'yearly') key = String(d.getFullYear())
    else if (interval === 'weekly') {
      const y = d.getFullYear()
      const start = new Date(d)
      start.setDate(d.getDate() - d.getDay())
      key = `${y}-W${String(Math.ceil((start.getTime() - new Date(y, 0, 1).getTime()) / 604800000)).padStart(2, '0')}`
    } else if (interval === 'daily') key = d.toISOString().slice(0, 10)
    else key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`

    if (!buckets.has(key)) buckets.set(key, [])
    buckets.get(key)!.push(a)
  }
  return Array.from(buckets.entries())
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([key, bucketActs]) => {
      const daily = new Map<string, number>()
      for (const ba of bucketActs) {
        if (!ba.start_date) continue
        const day = ba.start_date.slice(0, 10)
        daily.set(day, (daily.get(day) || 0) + (ba.distance ?? 0))
      }
      return {
        key,
        label: key,
        activities: bucketActs,
        totalDistance: bucketActs.reduce((s, ba) => s + (ba.distance ?? 0), 0),
        count: bucketActs.length,
        avgPace: computeAvgPace(bucketActs),
        avgHr: avgOrNull(bucketActs.map(ba => ba.average_heartrate)),
        dailyDistances: Array.from(daily.values()),
      }
    })
}


