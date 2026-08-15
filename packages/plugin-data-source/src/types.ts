/** stats.json 全量 schema（与线上 stats.json 字段一致，月/年级数据）。 */

export interface SportBreakdownEntry {
  category: string
  count: number
  distance_km: number
  moving_time_h: number
}

export interface MonthlyStat {
  year: number
  month: number
  count: number
  distance_km: number
  moving_time_h: number
  avg_pace: string | null
  avg_hr: number | null
  avg_cadence: number | null
  avg_power: number | null
  elevation_gain_m: number
}

export interface YearlyStat {
  year: number
  count: number
  distance_km: number
  moving_time_h: number
  longest_km: number
  streak: number
}

export interface Stats {
  summary: {
    total_activities: number
    unique_activities: number
    total_distance_km: number
    total_moving_time_h: number
    total_elevation_gain_m: number
    avg_cadence: number | null
    avg_power: number | null
    sport_breakdown: SportBreakdownEntry[]
  }
  monthly: MonthlyStat[]
  yearly: YearlyStat[]
  streaks: {
    current: number
    all_time: number
  }
  activity_types: string[]
}

export interface StatsResult {
  stats: Stats | null
  loading: boolean
  error?: string
}
