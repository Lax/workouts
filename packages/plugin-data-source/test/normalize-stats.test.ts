import { describe, expect, it } from 'vitest'
import { normalizeStats } from '../src/data'
import type { Stats } from '../src/types'

const full = {
  summary: {
    total_activities: 2179,
    unique_activities: 1800,
    total_distance_km: 10881.71,
    total_moving_time_h: 1723.76,
    total_elevation_gain_m: 166658.9,
    avg_cadence: 40.4,
    avg_power: null,
    sport_breakdown: [
      { category: 'run', count: 559, distance_km: 5521.5, moving_time_h: 774.8 },
      { category: 'workout', count: 57, distance_km: 0.0, moving_time_h: 10.1 },
    ],
  },
  monthly: [
    { year: 2026, month: 8, count: 24, distance_km: 25.3, moving_time_h: 5.7, avg_pace: "13'25\"", avg_hr: 97, avg_cadence: null, avg_power: null, elevation_gain_m: 18 },
    { year: 2015, month: 8, count: 4, distance_km: 48.7, moving_time_h: 4.7, avg_pace: "5'49\"", avg_hr: null, avg_cadence: null, avg_power: null, elevation_gain_m: 0 },
  ],
  yearly: [{ year: 2026, count: 476, distance_km: 815.1, moving_time_h: 134.4, longest_km: 6.0, streak: 22 }],
  streaks: { current: 8, all_time: 34 },
  activity_types: ['hike', 'ride', 'run', 'walk', 'workout'],
}

describe('normalizeStats', () => {
  it('解析全量 schema（summary/breakdown/monthly/yearly/streaks/types）', () => {
    const s = normalizeStats(full)!
    expect(s).not.toBeNull()
    expect(s.summary.total_activities).toBe(2179)
    expect(s.summary.unique_activities).toBe(1800)
    expect(s.summary.total_distance_km).toBe(10881.71)
    expect(s.summary.avg_cadence).toBe(40.4)
    expect(s.summary.avg_power).toBeNull()
    expect(s.summary.sport_breakdown).toHaveLength(2)
    expect(s.summary.sport_breakdown[0]!.category).toBe('run')
    expect(s.monthly).toHaveLength(2)
    expect(s.monthly[0]!.year).toBe(2015)
    expect(s.monthly[1]!.avg_pace).toBe("13'25\"")
    expect(s.yearly).toHaveLength(1)
    expect(s.streaks.current).toBe(8)
    expect(s.streaks.all_time).toBe(34)
    expect(s.activity_types).toContain('ride')
  })

  it('monthly/yearly 按时间排序', () => {
    const s = normalizeStats(full)!
    expect(s.monthly.map((m) => m.year)).toEqual([2015, 2026])
    expect(s.monthly[0]!.month).toBe(8)
  })

  it('空/畸形容错：null、数组、原始值返回 null', () => {
    expect(normalizeStats(null)).toBeNull()
    expect(normalizeStats([])).toBeNull()
    expect(normalizeStats('x')).toBeNull()
    expect(normalizeStats(undefined)).toBeNull()
  })

  it('部分字段缺省补默认（0 / null / 空数组）', () => {
    const s = normalizeStats({ summary: { total_activities: 5 }, monthly: [], yearly: [], streaks: {} })!
    expect(s.summary.unique_activities).toBe(5)
    expect(s.summary.total_distance_km).toBe(0)
    expect(s.summary.avg_cadence).toBeNull()
    expect(s.summary.sport_breakdown).toEqual([])
    expect(s.monthly).toEqual([])
    expect(s.streaks.current).toBe(0)
    expect(s.activity_types).toEqual([])
  })

  it('unique_activities 缺失时回退 total_activities', () => {
    const s = normalizeStats({ summary: { total_activities: 100 }, streaks: {} })!
    expect(s.summary.unique_activities).toBe(100)
  })

  it('无效 monthly/yearly 条目过滤（year/month 非法）', () => {
    const s = normalizeStats({
      summary: {},
      monthly: [
        { year: 0, month: 3, count: 1, distance_km: 1, moving_time_h: 1, avg_pace: null, avg_hr: null, avg_cadence: null, avg_power: null, elevation_gain_m: 0 },
        { year: 2024, month: 13, count: 1, distance_km: 1, moving_time_h: 1, avg_pace: null, avg_hr: null, avg_cadence: null, avg_power: null, elevation_gain_m: 0 },
        { year: 2024, month: 5, count: 2, distance_km: 3, moving_time_h: 1, avg_pace: null, avg_hr: null, avg_cadence: null, avg_power: null, elevation_gain_m: 0 },
      ],
      yearly: [{ year: 0, count: 1, distance_km: 1, moving_time_h: 1, longest_km: 1, streak: 1 }],
      streaks: {},
    })!
    expect(s.monthly).toHaveLength(1)
    expect(s.monthly[0]!.month).toBe(5)
    expect(s.yearly).toEqual([])
  })

  it('月级 avg_pace 保留原始字符串', () => {
    const s = normalizeStats(full)!
    expect(s.monthly[0]!.avg_pace).toBe("5'49\"")
  })
})

describe('normalizeStats 类型完整性（compile-time Stats 对齐）', () => {
  it('Stats 形状可被完整断言', () => {
    const s: Stats = normalizeStats(full)!
    expect(s.summary.sport_breakdown[0]!.distance_km).toBeGreaterThan(0)
    expect(Array.isArray(s.monthly)).toBe(true)
    expect(typeof s.streaks.current).toBe('number')
  })
})
