import { useEffect, useMemo } from 'react'
import { useSimpleStore } from '../store'
import { GithubDrawer } from './GithubDrawer'
import { YearBarSVG } from './YearBarSVG'

export function SummaryLifeView() {
  const activities = useSimpleStore((s) => s.activities)
  const summaryLifeYear = useSimpleStore((s) => s.summaryLifeYear)
  const setSummaryLifeYear = useSimpleStore((s) => s.setSummaryLifeYear)
  const summarySportType = useSimpleStore((s) => s.summarySportType)

  const years = useMemo(() => {
    const s = new Set<number>()
    for (const a of activities) {
      if (a.start_date) s.add(new Date(a.start_date).getFullYear())
    }
    return Array.from(s).sort((a, b) => b - a)
  }, [activities])

  useEffect(() => {
    if (summaryLifeYear === null && years.length > 0) {
      setSummaryLifeYear(years[0])
    }
  }, [years, summaryLifeYear, setSummaryLifeYear])

  const filteredByYear = useMemo(() => {
    if (!summaryLifeYear) return []
    const yearActs = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === summaryLifeYear)
    if (!summarySportType) return yearActs
    return yearActs.filter((a) => (a.sport_category || a.type) === summarySportType)
  }, [activities, summaryLifeYear, summarySportType])

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      const idx = years.indexOf(summaryLifeYear || years[0])
      if (e.key === 'ArrowLeft' && idx < years.length - 1) {
        setSummaryLifeYear(years[idx + 1])
      } else if (e.key === 'ArrowRight' && idx > 0) {
        setSummaryLifeYear(years[idx - 1])
      }
    }
    window.addEventListener('keydown', handleKey)
    return () => window.removeEventListener('keydown', handleKey)
  }, [summaryLifeYear, years, setSummaryLifeYear])

  return (
    <div className="life-view">
      <div className="life-year-grid">
        {years.map((y) => (
          <button
            key={y}
            type="button"
            className={`life-year-btn${summaryLifeYear === y ? ' active' : ''}`}
            onClick={() => setSummaryLifeYear(y)}
          >
            {y}
          </button>
        ))}
      </div>
      {summaryLifeYear && (
        <div className="life-svgs">
          <GithubDrawer year={summaryLifeYear} activities={filteredByYear} />
          <YearBarSVG year={summaryLifeYear} activities={filteredByYear} />
        </div>
      )}
    </div>
  )
}
