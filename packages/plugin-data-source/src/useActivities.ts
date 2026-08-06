import { useTheme } from '@workouts/core'
import { useEffect, useState } from 'react'
import type { DataResult } from './data'
import { fetchData, fetchTracks, getDataBaseUrl, probeDataUrl, type TracksMap } from './data'

export interface ActivitiesResult {
  activities: DataResult['activities']
  tracks: TracksMap | null
  tracksLoading: boolean
  loading: boolean
  error?: string
}

export const DATA_URL_STORAGE_KEY = 'git-fit-data-url'

function storedDataUrl(): string | undefined {
  try {
    return localStorage.getItem(DATA_URL_STORAGE_KEY) ?? undefined
  } catch {
    return undefined
  }
}

function saveDataUrl(url: string): void {
  try {
    localStorage.setItem(DATA_URL_STORAGE_KEY, url)
  } catch {
    // storage unavailable — URL applies for this session only
  }
}

export function useActivities(): ActivitiesResult {
  const { config } = useTheme()
  const dataConfig = (config as any)?.data as Record<string, { source: string; optional?: boolean }> | undefined
  const tracksSource = (config as any)?.data?.tracks?.source as string | undefined

  const [activities, setActivities] = useState<any[]>([])
  const [tracks, setTracks] = useState<TracksMap | null>(null)
  const [tracksLoading, setTracksLoading] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | undefined>()

  useEffect(() => {
    if (!dataConfig) {
      setLoading(false)
      return
    }
    let cancelled = false
    let prompted = false

    async function load(baseUrl?: string) {
      if (cancelled) return
      setLoading(true)
      const { tracks: _tracksEntry, ...fetchConfig } = dataConfig ?? {}
      const result = await fetchData(fetchConfig, baseUrl)
      if (cancelled) return
      setActivities(result.activities)

      if (!result.error) {
        setError(undefined)
        setLoading(false)
        if (tracksSource) {
          setTracksLoading(true)
          const tracksData = await fetchTracks(tracksSource, baseUrl)
          if (cancelled) return
          setTracks(tracksData)
          setTracksLoading(false)
        }
        return
      }

      if (!getDataBaseUrl() && !prompted && typeof window !== 'undefined' && window.prompt) {
        prompted = true
        const entered = window.prompt(
          'Failed to load workout data. Enter the JSON data URL (e.g. https://lax.github.io/workouts/):',
          baseUrl ?? storedDataUrl() ?? '',
        )
        if (entered?.trim()) {
          const candidate = entered.trim()
          const valid = await probeDataUrl(fetchConfig, candidate)
          if (cancelled) return
          if (valid) {
            saveDataUrl(candidate)
            await load(candidate)
            return
          }
          window.alert(`Invalid data URL: ${candidate}`)
        }
      }

      setError(result.error)
      setLoading(false)
    }

    load(storedDataUrl())
    return () => {
      cancelled = true
    }
  }, [dataConfig, tracksSource])

  return { activities, tracks, tracksLoading, loading, error }
}
