import { useEffect } from 'react'
import { useRequiredComponent } from '@workouts/core'
import { buildMonthlyBarOption, buildTypePieOption } from '@workouts/plugin-chart'
import { useOverviewStore } from '../store'

export function ChartOverlay() {
  const showCharts = useOverviewStore((s) => s.showCharts)
  const closeCharts = useOverviewStore((s) => s.closeCharts)
  const filteredActivities = useOverviewStore((s) => s.filteredActivities)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const setSelectedMonth = useOverviewStore((s) => s.setSelectedMonth)

  const Chart = useRequiredComponent('chart', 'Chart')

  useEffect(() => {
    if (!showCharts) return
    function onKey(e: KeyboardEvent) { if (e.key === 'Escape') closeCharts() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [showCharts, closeCharts])

  if (!showCharts) return null

  const monthOption = buildMonthlyBarOption(filteredActivities)
  const typeOption = buildTypePieOption(filteredActivities)

  return (
    <div
      onClick={(e) => { if (e.target === e.currentTarget) closeCharts() }}
      style={{
        position: 'fixed', inset: 0, zIndex: 4,
        background: 'rgba(0,0,0,0.5)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
    >
      <div style={{
        background: 'var(--color-surface)', borderRadius: 12, padding: 16,
        width: '90%', maxWidth: 600, animation: 'fadeIn 0.15s ease-out',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h3 style={{ margin: 0, fontSize: '1rem' }}>Charts</h3>
          <button onClick={closeCharts} style={{ background: 'none', border: 'none', color: 'var(--color-text)', fontSize: '1.5rem', cursor: 'pointer' }}>×</button>
        </div>
        {Chart && (
          <Chart
            option={monthOption}
            style={{ height: 240 }}
            onClick={(params: any) => {
              if (params.dataIndex !== undefined && selectedYear !== null) {
                const m = parseInt(params.name, 10)
                if (!isNaN(m)) setSelectedMonth(m)
              }
            }}
          />
        )}
        {Chart && <Chart option={typeOption} style={{ height: 200, marginTop: 16 }} />}
      </div>
    </div>
  )
}
