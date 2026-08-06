import type { Activity } from '@workouts/shared'
import { normalizeAll } from './normalize'

export interface DataResult {
  activities: Activity[]
  loading: boolean
  error?: string
}

export type TracksMap = Record<string, string>

export function resolveDataUrl(source: string, baseUrl: string): string {
  if (!baseUrl) return source
  if (/^[a-z][a-z0-9+.-]*:/i.test(source) || source.startsWith('//')) return source
  return `${baseUrl.replace(/\/+$/, '')}/${source.replace(/^\/+/, '')}`
}

export function getDataBaseUrl(): string {
  return import.meta.env?.GIT_FIT_DATA_URL ?? ''
}

export async function probeDataUrl(dataConfig: Record<string, { source: string; optional?: boolean }>, baseUrl: string): Promise<boolean> {
  const firstSource = Object.values(dataConfig).find((s) => !s.optional)?.source
  if (!firstSource) return false
  try {
    const res = await fetch(resolveDataUrl(firstSource, baseUrl))
    return res.ok
  } catch {
    return false
  }
}

async function fetchOne(
  key: string,
  source: string,
  optional: boolean,
  baseUrl: string,
): Promise<{ key: string; data: unknown; error?: string }> {
  const url = resolveDataUrl(source, baseUrl)
  try {
    const res = await fetch(url)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return { key, data: await res.json() }
  } catch (e) {
    if (optional) {
      return { key, data: null }
    }
    return { key, data: null, error: `Failed to load ${key} from ${url}: ${e}` }
  }
}

export async function fetchData(
  dataConfig: Record<string, { source: string; optional?: boolean }>,
  baseUrl?: string,
): Promise<{ activities: Activity[]; error?: string }> {
  const entries = Object.entries(dataConfig)
  const effectiveBase = baseUrl ?? getDataBaseUrl()
  const results = await Promise.all(entries.map(([key, { source, optional }]) => fetchOne(key, source, !!optional, effectiveBase)))

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

export async function fetchTracks(source: string, baseUrl?: string): Promise<TracksMap | null> {
  const url = resolveDataUrl(source, baseUrl ?? getDataBaseUrl())
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    return (await res.json()) as TracksMap
  } catch {
    return null
  }
}
