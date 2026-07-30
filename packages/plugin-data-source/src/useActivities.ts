import { useTheme } from '@workouts/core'
import { useEffect, useState } from 'react'
import type { DataResult } from './data'
import { fetchData, fetchTracks, type TracksMap } from './data'

export interface ActivitiesResult {
  activities: DataResult['activities']
  tracks: TracksMap | null
  tracksLoading: boolean
  loading: boolean
  error?: string
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

    async function load() {
      setLoading(true)
      const { tracks: _tracksEntry, ...fetchConfig } = dataConfig ?? {}
      try {
        const result = await fetchData(fetchConfig)
        if (cancelled) return
        setActivities(result.activities)
        setError(result.error)
        setLoading(false)
      } catch (e) {
        if (cancelled) return
        setError(String(e))
        setLoading(false)
      }

      if (!cancelled && tracksSource) {
        setTracksLoading(true)
        const tracksData = await fetchTracks(tracksSource)
        if (cancelled) return
        setTracks(tracksData)
        setTracksLoading(false)
      }
    }
    load()
    return () => {
      cancelled = true
    }
  }, [dataConfig, tracksSource])

  return { activities, tracks, tracksLoading, loading, error }
}
