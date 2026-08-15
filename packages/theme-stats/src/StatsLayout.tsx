import type { Stats } from '@lax/plugin-data-source'
import type { ThemeProps } from '@lax/core'
import { useStats } from '@lax/plugin-data-source'
import { useMemo, useState } from 'react'
import { latestYear, type VolumeMetric } from './charts'
import { Consistency } from './components/Consistency'
import { Highlights } from './components/Highlights'
import { LinkedTimeChart } from './components/LinkedTimeChart'
import { MonthlyChart } from './components/MonthlyChart'
import { OverviewCards } from './components/OverviewCards'
import { SportBreakdown } from './components/SportBreakdown'
import { YoYHeatmap } from './components/YoYHeatmap'
import { YearlyChart } from './components/YearlyChart'
import { DEFAULT_T, sectionTitle } from './labels'

export function StatsLayout(_props: ThemeProps): React.JSX.Element {
  const t = DEFAULT_T
  const { stats, loading, error } = useStats()

  const [selectedYear, setSelectedYear] = useState<number | null>(null)
  const [metric, setMetric] = useState<VolumeMetric>('distance_km')
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null)
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null)
  const [hoveredYear, setHoveredYear] = useState<number | null>(null)

  const effectiveYear = useMemo(
    () => (stats ? selectedYear ?? latestYear(stats) : null),
    [stats, selectedYear],
  )

  if (loading) {
    return (
      <div className="stats">
        <div className="stats-loading">{t('loading')}</div>
      </div>
    )
  }
  if (error || !stats) {
    return (
      <div className="stats">
        <div className="stats-error">
          <h2>{t('empty.title')}</h2>
          <p>{t('empty.desc')}</p>
          {error ? <pre>{error}</pre> : null}
        </div>
      </div>
    )
  }

  const span = stats.monthly.length
    ? `${stats.monthly[0]!.year}-${String(stats.monthly[0]!.month).padStart(2, '0')} → ${
        stats.monthly[stats.monthly.length - 1]!.year
      }-${String(stats.monthly[stats.monthly.length - 1]!.month).padStart(2, '0')}`
    : ''

  return (
    <div className="stats">
      <header className="stats-header">
        <h1 className="stats-title">{t('stats.tagline')}</h1>
        {span ? (
          <p className="stats-period">
            {t('stats.period')}: {span} · {stats.summary.total_activities.toLocaleString()} {t('overview.activities')}
          </p>
        ) : null}
      </header>

      <section className="stats-section" aria-label={t('overview.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'overview.title')}</h2>
        <OverviewCards stats={stats} />
      </section>

      <section className="stats-section" aria-label={t('highlights.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'highlights.title')}</h2>
        <Highlights stats={stats} />
      </section>

      <section className="stats-section" aria-label={t('trend.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'trend.title')}</h2>
        <LinkedTimeChart
          stats={stats}
          metric={metric}
          onMetricChange={setMetric}
          hoveredIndex={hoveredIndex}
          onHoverIndex={setHoveredIndex}
          hoveredYear={hoveredYear}
        />
      </section>

      <section className="stats-section" aria-label={t('yearly.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'yearly.title')}</h2>
        <YearlyChart
          stats={stats}
          selectedYear={effectiveYear}
          onSelectYear={(y) => setSelectedYear(y)}
          hoveredYear={hoveredYear}
          onHoverYear={setHoveredYear}
        />
      </section>

      {effectiveYear !== null ? (
        <section className="stats-section" aria-label={t('monthly.title')}>
          <h2 className="stats-section-title">{sectionTitle(t, 'monthly.title')}</h2>
          <MonthlyChart stats={stats} year={effectiveYear} metric={metric} />
        </section>
      ) : null}

      <section className="stats-section" aria-label={t('period.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'period.title')}</h2>
        <YoYHeatmap stats={stats} />
      </section>

      <section className="stats-section" aria-label={t('composition.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'composition.title')}</h2>
        <SportBreakdown stats={stats} selected={selectedCategory} onSelect={setSelectedCategory} />
      </section>

      <section className="stats-section" aria-label={t('consistency.title')}>
        <h2 className="stats-section-title">{sectionTitle(t, 'consistency.title')}</h2>
        <Consistency stats={stats} />
      </section>

      <footer className="stats-footer">
        {t('footer.source')}: stats.json
      </footer>
    </div>
  )
}
