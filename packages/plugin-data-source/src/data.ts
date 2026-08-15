import type { MonthlyStat, SportBreakdownEntry, Stats, YearlyStat } from './types'

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null
}

function num0(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null
}

function asObj(v: unknown): Record<string, unknown> {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {}
}

function normalizeBreakdown(raw: unknown): SportBreakdownEntry[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((e) => {
      const b = asObj(e)
      return {
        category: String(b.category ?? 'other'),
        count: num0(b.count),
        distance_km: num0(b.distance_km),
        moving_time_h: num0(b.moving_time_h),
      }
    })
    .filter((e) => e.count > 0 || e.distance_km > 0 || e.moving_time_h > 0)
}

function normalizeMonthly(raw: unknown): MonthlyStat[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((e) => {
      const b = asObj(e)
      return {
        year: num0(b.year),
        month: num0(b.month),
        count: num0(b.count),
        distance_km: num0(b.distance_km),
        moving_time_h: num0(b.moving_time_h),
        avg_pace: str(b.avg_pace),
        avg_hr: num(b.avg_hr),
        avg_cadence: num(b.avg_cadence),
        avg_power: num(b.avg_power),
        elevation_gain_m: num0(b.elevation_gain_m),
      }
    })
    .filter((e) => e.year > 0 && e.month >= 1 && e.month <= 12)
    .sort((a, b) => a.year - b.year || a.month - b.month)
}

function normalizeYearly(raw: unknown): YearlyStat[] {
  if (!Array.isArray(raw)) return []
  return raw
    .map((e) => {
      const b = asObj(e)
      return {
        year: num0(b.year),
        count: num0(b.count),
        distance_km: num0(b.distance_km),
        moving_time_h: num0(b.moving_time_h),
        longest_km: num0(b.longest_km),
        streak: num0(b.streak),
      }
    })
    .filter((e) => e.year > 0)
    .sort((a, b) => a.year - b.year)
}

/**
 * 归一化 stats.json → Stats。容错：缺字段补默认、null/数组/原始值返回 null、
 * monthly/yearly 排序、无效条目过滤。
 */
export function normalizeStats(raw: unknown): Stats | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
  const r = asObj(raw)
  const s = asObj(r.summary)
  const total = num0(s.total_activities)
  const unique = num(s.unique_activities) ?? total
  const streaks = asObj(r.streaks)

  return {
    summary: {
      total_activities: total,
      unique_activities: unique,
      total_distance_km: num0(s.total_distance_km),
      total_moving_time_h: num0(s.total_moving_time_h),
      total_elevation_gain_m: num0(s.total_elevation_gain_m),
      avg_cadence: num(s.avg_cadence),
      avg_power: num(s.avg_power),
      sport_breakdown: normalizeBreakdown(s.sport_breakdown),
    },
    monthly: normalizeMonthly(r.monthly),
    yearly: normalizeYearly(r.yearly),
    streaks: {
      current: num0(streaks.current),
      all_time: num0(streaks.all_time),
    },
    activity_types: Array.isArray(r.activity_types)
      ? r.activity_types.map((t) => String(t)).filter((t) => t.length > 0)
      : [],
  }
}

export function resolveDataUrl(source: string, baseUrl: string): string {
  if (!baseUrl) return source
  if (/^[a-z][a-z0-9+.-]*:/i.test(source) || source.startsWith('//')) return source
  return `${baseUrl.replace(/\/+$/, '')}/${source.replace(/^\/+/, '')}`
}

export function getDataBaseUrl(): string {
  return import.meta.env?.GIT_FIT_DATA_URL ?? ''
}

export async function probeDataUrl(source: string, baseUrl: string): Promise<boolean> {
  if (!source) return false
  try {
    const res = await fetch(resolveDataUrl(source, baseUrl))
    return res.ok
  } catch {
    return false
  }
}

export async function fetchStats(source: string, baseUrl?: string): Promise<unknown> {
  const url = resolveDataUrl(source, baseUrl ?? getDataBaseUrl())
  const res = await fetch(url)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}
