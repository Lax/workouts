import { useTheme } from '@lax/core'
import { useEffect, useState } from 'react'
import { fetchStats, getDataBaseUrl, normalizeStats, probeDataUrl } from './data'
import type { StatsResult } from './types'

export const STATS_URL_STORAGE_KEY = 'git-fit-stats-url'

function storedUrl(): string | undefined {
  try {
    return localStorage.getItem(STATS_URL_STORAGE_KEY) ?? undefined
  } catch {
    return undefined
  }
}

function saveUrl(url: string): void {
  try {
    localStorage.setItem(STATS_URL_STORAGE_KEY, url)
  } catch {
    // storage unavailable — URL applies for this session only
  }
}

/**
 * 仅加载 stats.json 的 hook（theme-stats 专用，不加载 activities/tracks）。
 * 读取 config.data.stats.source，复用 baseUrl → 失败 prompt 手动输入 → localStorage 持久化。
 */
export function useStats(): StatsResult {
  const { config } = useTheme()
  const dataConfig = (config as Record<string, unknown>).data as
    | Record<string, { source: string; optional?: boolean }>
    | undefined
  const statsSource =
    dataConfig?.stats?.source ?? Object.values(dataConfig ?? {}).find((d) => !d.optional)?.source

  const [stats, setStats] = useState<StatsResult['stats']>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | undefined>(undefined)

  useEffect(() => {
    if (!statsSource) {
      setLoading(false)
      return
    }
    const source: string = statsSource
    let cancelled = false
    let prompted = false

    async function load(baseUrl?: string): Promise<void> {
      if (cancelled) return
      setLoading(true)
      try {
        const raw = await fetchStats(source, baseUrl)
        if (cancelled) return
        setStats(normalizeStats(raw))
        setError(undefined)
        setLoading(false)
      } catch (e) {
        if (cancelled) return
        if (!getDataBaseUrl() && !prompted && typeof window !== 'undefined' && window.prompt) {
          prompted = true
          const entered = window.prompt(
            'Failed to load workout stats. Enter the JSON data URL (e.g. https://liulantao.com/workouts/):',
            baseUrl ?? storedUrl() ?? '',
          )
          if (entered?.trim()) {
            const candidate = entered.trim()
            const valid = await probeDataUrl(source, candidate)
            if (cancelled) return
            if (valid) {
              saveUrl(candidate)
              await load(candidate)
              return
            }
            window.alert(`Invalid data URL: ${candidate}`)
          }
        }
        setError(e instanceof Error ? e.message : String(e))
        setLoading(false)
      }
    }

    void load(storedUrl())
    return () => {
      cancelled = true
    }
  }, [statsSource, dataConfig])

  return { stats, loading, error }
}
