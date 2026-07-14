import { useTheme } from '@workouts/core'
import { useEffect, useState } from 'react'
import type { DataResult } from './data'
import { fetchData } from './data'

export function useActivities(): DataResult {
  const { config } = useTheme()
  const dataConfig = (config as any)?.data as Record<string, { source: string; optional?: boolean }> | undefined

  const [activities, setActivities] = useState<any[]>([])
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
      try {
        const result = await fetchData(dataConfig!)
        if (!cancelled) {
          setActivities(result.activities)
          setError(result.error)
          setLoading(false)
        }
      } catch (e) {
        if (!cancelled) {
          setError(String(e))
          setLoading(false)
        }
      }
    }
    load()
    return () => {
      cancelled = true
    }
  }, [dataConfig])

  return { activities, loading, error }
}
