/** 数值/时间格式化（国际惯例：千分位、km/h/m、'mm'ss"）。 */

/** "5'49\"" → 349（秒）。解析失败返回 null。 */
export function parsePace(s: string): number | null {
  const m = /^(\d+)'(\d+)(")?$/.exec(s.trim())
  if (!m) return null
  return Number(m[1]) * 60 + Number(m[2])
}

/** 秒 → "5'49\"" */
export function formatPace(seconds: number): string {
  const total = Math.round(seconds)
  const min = Math.floor(total / 60)
  const sec = total % 60
  return `${min}'${String(sec).padStart(2, '0')}"`
}

/** km → 千分位。≥1000 取整，否则 1 位小数。 */
export function formatDistance(km: number): string {
  if (!Number.isFinite(km)) return '0'
  if (km >= 1000) return `${Math.round(km).toLocaleString()} km`
  return `${km.toFixed(1)} km`
}

export function formatCount(n: number): string {
  return Math.round(n).toLocaleString()
}

export function formatHours(h: number): string {
  return `${Math.round(h).toLocaleString()} h`
}

export function formatElevation(m: number): string {
  return `${Math.round(m).toLocaleString()} m`
}

/** ±百分比：+853% / -12%。null 或非有限值返回 null。 */
export function formatDelta(pct: number | null): string | null {
  if (pct === null || !Number.isFinite(pct)) return null
  const sign = pct > 0 ? '+' : ''
  return `${sign}${Math.round(pct)}%`
}

/** "3.4" 倍 */
export function formatTimes(x: number): string {
  return x.toFixed(1)
}

export function monthLabel(month: number): string {
  return `${month}月`
}
