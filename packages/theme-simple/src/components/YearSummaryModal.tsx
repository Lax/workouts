import { useEffect } from 'react'
import { useSimpleStore } from '../store'

export function YearSummaryModal() {
  const showYearModal = useSimpleStore((s) => s.showYearModal)
  const setShowYearModal = useSimpleStore((s) => s.setShowYearModal)

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
          <YearGridSVG year={year} />
          <YearBarSVG year={year} />
        </div>
      </div>
    </div>
  )
}

function YearGridSVG({ year }: { year: number }) {
  const activities = useSimpleStore((s) => s.activities)
  const yearActs = activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
  const totalKm = yearActs.reduce((s, a) => s + (a.distance ?? 0), 0) / 1000

  return (
    <div style={{ fontSize: 13, color: 'var(--color-text-secondary)' }}>
      <div style={{ fontWeight: 600, marginBottom: 8, color: 'var(--color-text)' }}>
        {year} · {yearActs.length} 次活动 · {totalKm.toFixed(0)} km
      </div>
      <div style={{ lineHeight: 1.8 }}>{yearActs.length > 0 ? `${yearActs.length} activities` : 'No data'}</div>
    </div>
  )
}

function YearBarSVG({ year }: { year: number }) {
  const activities = useSimpleStore((s) => s.activities)
  const monthActs = Array.from({ length: 12 }, (_, i) => {
    const acts = activities.filter((a) => {
      if (!a.start_date) return false
      const d = new Date(a.start_date)
      return d.getFullYear() === year && d.getMonth() === i
    })
    return acts.reduce((s, a) => s + (a.distance ?? 0), 0)
  })
  const maxDist = Math.max(...monthActs, 1)

  return (
    <div>
      <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 8, color: 'var(--color-text)' }}>Monthly Distance (km)</div>
      <div style={{ display: 'flex', gap: 4, alignItems: 'flex-end', height: 100 }}>
        {monthActs.map((dist, i) => {
          const monthLabel = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'][i]
          return (
            <div key={monthLabel} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <div
                style={{
                  width: '100%',
                  height: `${(dist / maxDist) * 80}px`,
                  background: 'var(--color-accent, #e0ed5e)',
                  borderRadius: '2px 2px 0 0',
                  minHeight: dist > 0 ? 4 : 0,
                  transition: 'height 0.3s',
                }}
              />
              <div style={{ fontSize: 10, color: 'var(--color-text-secondary)', marginTop: 4 }}>{monthLabel}</div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
