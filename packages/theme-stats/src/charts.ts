import type { MonthlyStat, Stats } from '@lax/plugin-data-source'
import { parsePace } from './format'

export type VolumeMetric = 'distance_km' | 'count' | 'moving_time_h' | 'elevation_gain_m'

export interface MonthPoint {
  year: number
  month: number
  index: number
}

function monthKey(year: number, month: number): string {
  return `${year}-${month}`
}

/** 全时段统一月网格：monthly 首末之间逐月展开（含无数据月）。 */
export function buildMonthGrid(monthly: MonthlyStat[]): MonthPoint[] {
  if (monthly.length === 0) return []
  const first = monthly[0]!
  const last = monthly[monthly.length - 1]!
  const grid: MonthPoint[] = []
  let y = first.year
  let m = first.month
  let i = 0
  while (y < last.year || (y === last.year && m <= last.month)) {
    grid.push({ year: y, month: m, index: i })
    i++
    m++
    if (m > 12) {
      m = 1
      y++
    }
  }
  return grid
}

function monthlyMap(stats: Stats): Map<string, MonthlyStat> {
  return new Map(stats.monthly.map((m) => [monthKey(m.year, m.month), m]))
}

/** 运动量序列：网格逐月，缺失月补 0。 */
export function buildVolumeSeries(stats: Stats, metric: VolumeMetric): number[] {
  const map = monthlyMap(stats)
  return buildMonthGrid(stats.monthly).map((p) => map.get(monthKey(p.year, p.month))?.[metric] ?? 0)
}

/**
 * 环比序列（%）：当前月与上一网格月均为「真实数据」（非补 0）才计算，否则 null。
 * 避免用合成 0 计算 -100% 的误导环比。
 */
export function buildMoMSeries(stats: Stats, metric: VolumeMetric): (number | null)[] {
  const map = monthlyMap(stats)
  const grid = buildMonthGrid(stats.monthly)
  return grid.map((p, i) => {
    const cur = map.get(monthKey(p.year, p.month))
    if (!cur) return null
    if (i === 0) return null
    const prev = map.get(monthKey(grid[i - 1]!.year, grid[i - 1]!.month))
    if (!prev) return null
    const prevV = prev[metric]
    if (prevV === 0) return null
    return ((cur[metric] - prevV) / prevV) * 100
  })
}

/** 配速序列（秒，反向轴：值越低越快）。无数据/无法解析 → null（断线）。 */
export function buildPaceSeries(stats: Stats): (number | null)[] {
  const map = monthlyMap(stats)
  return buildMonthGrid(stats.monthly).map((p) => {
    const m = map.get(monthKey(p.year, p.month))
    if (!m?.avg_pace) return null
    return parsePace(m.avg_pace)
  })
}

/** 心率序列（bpm）。无数据 → null（断线）。 */
export function buildHRSeries(stats: Stats): (number | null)[] {
  const map = monthlyMap(stats)
  return buildMonthGrid(stats.monthly).map((p) => map.get(monthKey(p.year, p.month))?.avg_hr ?? null)
}

/** 线性比例尺（纯函数）。 */
export interface Scale {
  (v: number): number
  domain: [number, number]
  range: [number, number]
}

export function linearScale(domain: [number, number], range: [number, number]): Scale {
  const fn = (v: number): number => {
    const t = (v - domain[0]) / (domain[1] - domain[0] || 1)
    return range[0] + t * (range[1] - range[0])
  }
  fn.domain = domain
  fn.range = range
  return fn
}

/** y 轴 nice 上限：最大值 + pad 比例（保证 ≤0 或空序列落到 1）。 */
export function niceMax(values: Array<number | null>, padRatio = 0.08): number {
  let mx = 0
  for (const v of values) {
    if (v !== null && Number.isFinite(v) && v > mx) mx = v
  }
  if (mx <= 0) return 1
  return mx * (1 + padRatio)
}

/** crosshair：x 像素 → 网格索引（夹取）。 */
export function xToIndex(x: number, plotLeft: number, plotWidth: number, count: number): number {
  if (plotWidth <= 0 || count <= 0) return 0
  const t = (x - plotLeft) / plotWidth
  const idx = Math.round(t * (count - 1))
  return Math.max(0, Math.min(count - 1, idx))
}

export interface YearlySeries {
  year: number
  count: number
  distance_km: number
  moving_time_h: number
  longest_km: number
  streak: number
}

export function buildYearlySeries(stats: Stats): YearlySeries[] {
  return stats.yearly.map((y) => ({ ...y }))
}

export function latestYear(stats: Stats): number | null {
  if (stats.yearly.length === 0) return null
  return stats.yearly[stats.yearly.length - 1]!.year
}

export interface HeatmapCell {
  year: number
  month: number
  distance_km: number | null
  count: number | null
  prev: { year: number; distance_km: number | null } | null
}

export interface MonthYearMatrix {
  years: number[]
  cells: HeatmapCell[]
  maxDistance: number
}

/** 月×年矩阵：行=月份 1-12，列=年份。prev = 上年同月距离（同比）。无数据格 null。 */
export function buildMonthYearMatrix(stats: Stats): MonthYearMatrix {
  const years = [...new Set(stats.monthly.map((m) => m.year))].sort((a, b) => a - b)
  const map = monthlyMap(stats)
  const cells: HeatmapCell[] = []
  let maxDistance = 0
  for (const year of years) {
    for (let month = 1; month <= 12; month++) {
      const cur = map.get(monthKey(year, month))
      const prev = map.get(monthKey(year - 1, month))
      const d = cur?.distance_km ?? null
      if (d !== null && d > maxDistance) maxDistance = d
      cells.push({
        year,
        month,
        distance_km: d,
        count: cur?.count ?? null,
        prev: prev ? { year: year - 1, distance_km: prev.distance_km } : null,
      })
    }
  }
  return { years, cells, maxDistance }
}

/** 选中年的 12 月序列（0 填充）。 */
export function buildYearMonths(stats: Stats, year: number): MonthlyStat[] {
  const map = monthlyMap(stats)
  const out: MonthlyStat[] = []
  for (let month = 1; month <= 12; month++) {
    const real = map.get(monthKey(year, month))
    out.push(
      real ?? {
        year,
        month,
        count: 0,
        distance_km: 0,
        moving_time_h: 0,
        avg_pace: null,
        avg_hr: null,
        avg_cadence: null,
        avg_power: null,
        elevation_gain_m: 0,
      },
    )
  }
  return out
}
