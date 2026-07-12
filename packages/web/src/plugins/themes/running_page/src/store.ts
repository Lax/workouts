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

export function createRunningStore(ctx: ThemeContext) {
  const state = $state({
    view: 'main' as 'main' | 'summary',
    selectedYear: 'all' as string,
    selectedActivity: null as Activity | null,
    mapRuns: [] as Activity[],
    sortField: 'date' as string,
    sortDesc: true,
    summaryInterval: 'monthly' as string,
    summaryType: 'all' as string,
  })

  function computeYearStats(activities: Activity[]): YearStat[] {
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
        totalDistance: acts.reduce((s, a) => s + (a.distance ?? 0), 0),
        avgPace: computeAvgPace(acts),
        streak: 0,
        avgHr: avgOrNull(acts.map(a => a.average_heartrate)),
      }))
  }

  const activities = $derived(ctx.data.activities ?? [] as Activity[])
  const yearStats = $derived(computeYearStats(activities))
  const filteredRuns = $derived(
    state.selectedYear === 'all'
      ? activities
      : activities.filter((a: Activity) => a.start_date && new Date(a.start_date).getFullYear() === Number(state.selectedYear)),
  )

  return {
    state,
    activities,
    yearStats,
    filteredRuns,
  }
}

function computeAvgPace(acts: Activity[]): string {
  const totalDist = acts.reduce((s, a) => s + (a.distance ?? 0), 0)
  const totalTime = acts.reduce((s, a) => s + (a.moving_time ?? 0), 0)
  if (totalDist <= 0 || totalTime <= 0) return '—'
  const pace = totalTime / (totalDist / 1000)
  const min = Math.floor(pace / 60)
  const sec = Math.round(pace % 60)
  return `${min}:${sec.toString().padStart(2, '0')}`
}

function avgOrNull(vals: (number | null)[]): number | null {
  const f = vals.filter((v): v is number => v !== null && v !== undefined)
  return f.length > 0 ? Math.round(f.reduce((s, v) => s + v, 0) / f.length) : null
}
