import type { Stats } from '@lax/plugin-data-source'
import { formatCount, formatDistance, formatTimes } from './format'

export interface Highlight {
  id: string
  /** labels.ts 的 key */
  labelKey: string
  /** 数值（已格式化，如 "845 km"、"×8.7"） */
  value: string
  /** 补充说明（可选） */
  detail?: string
  /** 显著性分数，越大越值得展示 */
  score: number
}

interface Rule {
  id: string
  labelKey: string
  score: number
  value: string
  detail?: string
}

function monthYearLabel(year: number, month: number): string {
  return `${year}-${String(month).padStart(2, '0')}`
}

/** 连续活跃月份段：返回最长段长度（个月）。 */
function longestActiveMonths(stats: Stats): { months: number; start: string; end: string } {
  if (stats.monthly.length === 0) return { months: 0, start: '', end: '' }
  const keys = new Set(stats.monthly.map((m) => `${m.year}-${String(m.month).padStart(2, '0')}`))
  const first = stats.monthly[0]!
  const last = stats.monthly[stats.monthly.length - 1]!
  const startIdx = first.year * 12 + first.month
  const endIdx = last.year * 12 + last.month
  let best = 0
  let bestStart = ''
  let bestEnd = ''
  let cur = 0
  let curStart = ''
  for (let i = startIdx; i <= endIdx; i++) {
    const yy = Math.floor(i / 12)
    const mm = (i % 12) + 1
    const k = `${yy}-${String(mm).padStart(2, '0')}`
    if (keys.has(k)) {
      if (cur === 0) curStart = monthYearLabel(yy, mm)
      cur++
      if (cur > best) {
        best = cur
        bestStart = curStart
        bestEnd = monthYearLabel(yy, mm)
      }
    } else {
      cur = 0
    }
  }
  return { months: best, start: bestStart, end: bestEnd }
}

/** 连续运动年数（每年至少 1 个月有数据）。 */
function yearsActive(stats: Stats): { count: number; from: number; to: number } {
  const years = [...new Set(stats.monthly.map((m) => m.year))].sort((a, b) => a - b)
  if (years.length === 0) return { count: 0, from: 0, to: 0 }
  let best = 1
  let cur = 1
  for (let i = 1; i < years.length; i++) {
    if (years[i] === years[i - 1]! + 1) cur++
    else cur = 1
    if (cur > best) best = cur
  }
  return { count: best, from: years[years.length - 1]! - best + 1, to: years[years.length - 1]! }
}

/** 规则式亮点挖掘 + 分数排序，返回 top N。 */
export function computeHighlights(stats: Stats, topN = 6): Highlight[] {
  const rules: Rule[] = []

  // 今年 momentum：最新年 vs 上一年距离
  const yearly = [...stats.yearly].sort((a, b) => a.year - b.year)
  const last = yearly[yearly.length - 1]
  const prev = yearly[yearly.length - 2]
  if (last && prev && prev.distance_km > 0) {
    const ratio = last.distance_km / prev.distance_km
    if (ratio >= 1.3) {
      rules.push({
        id: 'yoy-momentum',
        labelKey: 'hl.yoyMomentum',
        score: Math.min(ratio, 20) * 1.4,
        value: `×${formatTimes(ratio)}`,
        detail: `${last.year} ${formatDistance(last.distance_km)} vs ${prev.year} ${formatDistance(prev.distance_km)}`,
      })
    }
  }

  // 单月纪录（距离）
  if (stats.monthly.length > 0) {
    const bestM = [...stats.monthly].sort((a, b) => b.distance_km - a.distance_km)[0]!
    rules.push({
      id: 'best-month-distance',
      labelKey: 'hl.bestMonthDistance',
      score: 9,
      value: formatDistance(bestM.distance_km),
      detail: `${monthYearLabel(bestM.year, bestM.month)} · ${formatCount(bestM.count)} 次`,
    })
  }

  // 单月纪录（次数）
  if (stats.monthly.length > 0) {
    const bestC = [...stats.monthly].sort((a, b) => b.count - a.count)[0]!
    rules.push({
      id: 'best-month-count',
      labelKey: 'hl.bestMonthCount',
      score: 8,
      value: formatCount(bestC.count),
      detail: `${monthYearLabel(bestC.year, bestC.month)} · ${formatDistance(bestC.distance_km)}`,
    })
  }

  // 最长连续活跃段
  const seg = longestActiveMonths(stats)
  if (seg.months >= 3) {
    rules.push({
      id: 'longest-active-months',
      labelKey: 'hl.longestActiveMonths',
      score: Math.min(seg.months, 30) * 0.5,
      value: `${seg.months} 个月`,
      detail: `${seg.start} → ${seg.end}`,
    })
  }

  // 连续运动年数
  const ya = yearsActive(stats)
  if (ya.count >= 3) {
    rules.push({
      id: 'years-active',
      labelKey: 'hl.yearsActive',
      score: ya.count * 0.8,
      value: `${ya.count} 年`,
      detail: `${ya.from} → ${ya.to}`,
    })
  }

  // 当前/历史连续天数
  if (stats.streaks.current > 0) {
    rules.push({
      id: 'current-streak',
      labelKey: 'hl.currentStreak',
      score: Math.min(stats.streaks.current, 30) * 0.7,
      value: `${stats.streaks.current} 天`,
    })
  }
  if (stats.streaks.all_time > 0) {
    rules.push({
      id: 'all-time-streak',
      labelKey: 'hl.allTimeStreak',
      score: Math.min(stats.streaks.all_time, 40) * 0.6,
      value: `${stats.streaks.all_time} 天`,
    })
  }

  // 季节性：累计次数最多的月份
  if (stats.monthly.length > 0) {
    const byMonth = new Map<number, { count: number; dist: number }>()
    for (const m of stats.monthly) {
      const c = byMonth.get(m.month) ?? { count: 0, dist: 0 }
      c.count += m.count
      c.dist += m.distance_km
      byMonth.set(m.month, c)
    }
    const top = [...byMonth.entries()].sort((a, b) => b[1].count - a[1].count)[0]!
    rules.push({
      id: 'seasonality',
      labelKey: 'hl.seasonality',
      score: 5,
      value: `${top[0]}月`,
      detail: formatDistance(top[1].dist),
    })
  }

  // 平均单次距离
  if (stats.summary.unique_activities > 0) {
    rules.push({
      id: 'avg-per-activity',
      labelKey: 'hl.avgPerActivity',
      score: 4,
      value: formatDistance(stats.summary.total_distance_km / stats.summary.unique_activities),
    })
  }

  // 最长单次（历年 longest 最大）
  if (yearly.length > 0) {
    const longest = [...yearly].sort((a, b) => b.longest_km - a.longest_km)[0]!
    if (longest.longest_km > 0) {
      rules.push({
        id: 'longest-activity',
        labelKey: 'hl.longestActivity',
        score: 6,
        value: formatDistance(longest.longest_km),
        detail: `${longest.year}`,
      })
    }
  }

  return rules.sort((a, b) => b.score - a.score).slice(0, topN)
}
