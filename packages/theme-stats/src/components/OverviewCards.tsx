import type { Stats } from '@lax/plugin-data-source'
import { formatCount, formatDistance, formatElevation, formatHours } from '../format'
import { DEFAULT_T } from '../labels'

function Card({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="ov-card">
      <span className="ov-label">{label}</span>
      <span className="ov-value">{value}</span>
      {sub ? <span className="ov-sub">{sub}</span> : null}
    </div>
  )
}

export function OverviewCards({ stats }: { stats: Stats }) {
  const t = DEFAULT_T
  const s = stats.summary
  return (
    <div className="ov-grid">
      <Card label={t('overview.totalDistance')} value={formatDistance(s.total_distance_km)} />
      <Card
        label={t('overview.activities')}
        value={formatCount(s.total_activities)}
        sub={`${t('overview.uniqueActivities')} ${formatCount(s.unique_activities)}`}
      />
      <Card label={t('overview.totalTime')} value={formatHours(s.total_moving_time_h)} />
      <Card label={t('overview.totalElevation')} value={formatElevation(s.total_elevation_gain_m)} />
      <Card label={t('overview.currentStreak')} value={`${stats.streaks.current} ${t('overview.days')}`} />
      <Card label={t('overview.allTimeStreak')} value={`${stats.streaks.all_time} ${t('overview.days')}`} />
      {s.avg_cadence !== null ? (
        <Card label={t('overview.avgCadence')} value={`${s.avg_cadence} rpm`} />
      ) : null}
    </div>
  )
}
