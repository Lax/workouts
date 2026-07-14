import type { Activity } from '@workouts/shared'
import { normalizeAll } from '@workouts/shared'

export interface DataResult {
  activities: Activity[]
  loading: boolean
  error?: string
}

export async function fetchData(
  dataConfig: Record<string, { source: string; optional?: boolean }>,
): Promise<{ activities: Activity[]; error?: string }> {
  const result: Record<string, unknown> = {}
  let error: string | undefined

  for (const [key, { source, optional }] of Object.entries(dataConfig)) {
    try {
      const res = await fetch(source)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      result[key] = await res.json()
    } catch (e) {
      if (optional) {
        result[key] = null
      } else {
        error = `Failed to load ${key} from ${source}: ${e}`
        result[key] = null
      }
    }
  }

  return {
    activities: normalizeAll((result.activities ?? []) as unknown[]),
    error,
  }
}
