import type { ThemeContext } from '@workouts/shared'
import type { Activity } from '@workouts/shared'

export interface DataResult {
  activities: Activity[]
  stats: Record<string, any> | null
}

export async function loadData(): Promise<DataResult> {
  try {
    const [actRes, statsRes] = await Promise.all([
      fetch('activities.json'),
      fetch('stats.json'),
    ])
    const activities: Activity[] = actRes.ok ? await actRes.json() : []
    for (const a of activities) {
      if (a.type && !a.sport_category) a.sport_category = a.type
      if (!a.summary_polyline && a.polyline) a.summary_polyline = a.polyline
    }
    const stats = statsRes.ok ? await statsRes.json() : null
    return { activities, stats }
  } catch (e) {
    console.warn('Failed to load data', e)
    return { activities: [], stats: null }
  }
}

export function buildThemeContext(theme: string, themeName: string, data: DataResult): ThemeContext {
  return {
    data: { activities: data.activities, stats: data.stats },
    config: {},
    theme,
    themeName,
    updateConfig: () => {},
    registerStore: () => null,
  }
}

export function metaTheme(): string | null {
  const el = document.querySelector('meta[name="app-theme"]')
  return el?.getAttribute('content') ?? null
}
