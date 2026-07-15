import { useSimpleStore } from '../store'
import { YearSummaryDrawer } from './YearSummaryDrawer'

export function SummaryLifeView() {
  const activities = useSimpleStore((s) => s.activities)
  const summaryLifeYear = useSimpleStore((s) => s.summaryLifeYear)
  const setSummaryLifeYear = useSimpleStore((s) => s.setSummaryLifeYear)
  const years = useSimpleStore((s) => s.years)

  return (
    <div className="life-view">
      <div className="life-year-grid">
        {years.map((y) => (
          <button
            key={y}
            type="button"
            className={`life-year-btn${summaryLifeYear === y ? ' active' : ''}`}
            onClick={() => setSummaryLifeYear(summaryLifeYear === y ? null : y)}
          >
            {y}
          </button>
        ))}
      </div>
      {summaryLifeYear && (
        <div className="life-svgs">
          <YearSummaryDrawer year={summaryLifeYear} activities={activities} />
        </div>
      )}
    </div>
  )
}
