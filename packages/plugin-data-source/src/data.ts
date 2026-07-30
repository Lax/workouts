import type { Activity } from '@workouts/shared'
import { normalizeAll } from './normalize'

export interface DataResult {
  activities: Activity[]
  loading: boolean
  error?: string
}

export type TracksMap = Record<string, string>

async function fetchOne(
  key: string,
  source: string,
  optional: boolean,
): Promise<{ key: string; data: unknown; error?: string }> {
  try {
    const res = await fetch(source)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return { key, data: await res.json() }
  } catch (e) {
    if (optional) {
      return { key, data: null }
    }
    return { key, data: null, error: `Failed to load ${key} from ${source}: ${e}` }
  }
}

export async function fetchData(
  dataConfig: Record<string, { source: string; optional?: boolean }>,
): Promise<{ activities: Activity[]; error?: string }> {
  const entries = Object.entries(dataConfig)
  const results = await Promise.all(
    entries.map(([key, { source, optional }]) => fetchOne(key, source, !!optional)),
  )

  const dataMap: Record<string, unknown> = {}
  let error: string | undefined

  for (const r of results) {
    dataMap[r.key] = r.data
    if (r.error) error = r.error
  }

  return {
    activities: normalizeAll((dataMap.activities ?? []) as unknown[]),
    error,
  }
}

export async function fetchTracks(url: string): Promise<TracksMap | null> {
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    return (await res.json()) as TracksMap
  } catch {
    return null
  }
}
