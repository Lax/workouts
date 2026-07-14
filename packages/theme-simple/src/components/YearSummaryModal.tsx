import { useEffect } from 'react'
import { useSimpleStore } from '../store'
import { YearBarSVG } from './YearBarSVG'
import { YearGridSVG } from './YearGridSVG'

export function YearSummaryModal() {
  const showYearModal = useSimpleStore((s) => s.showYearModal)
  const setShowYearModal = useSimpleStore((s) => s.setShowYearModal)
  const activities = useSimpleStore((s) => s.activities)

  useEffect(() => {
    if (showYearModal === null) return
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') setShowYearModal(null)
    }
    document.addEventListener('keydown', onKeyDown)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKeyDown)
      document.body.style.overflow = ''
    }
  }, [showYearModal, setShowYearModal])

  if (showYearModal === null) return null

  const year = showYearModal

  return (
    <div className="year-summary-overlay" onClick={() => setShowYearModal(null)}>
      <div className="year-summary-content" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="year-summary-close" onClick={() => setShowYearModal(null)}>
          ×
        </button>
        <div className="year-summary-title">{year} 年度总结</div>
        <div className="year-summary-svgs">
          <YearGridSVG year={year} activities={activities} />
          <YearBarSVG year={year} activities={activities} />
        </div>
      </div>
    </div>
  )
}
