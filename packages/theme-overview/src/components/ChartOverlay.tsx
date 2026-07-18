import { useRequiredComponent } from '@workouts/core'
import { buildMonthlyBarOption, buildTypePieOption } from '@workouts/plugin-chart'
import { useEffect } from 'react'
import { useOverviewStore } from '../store'
import '../overview.css'

function ChartOverlay() {
  const showCharts = useOverviewStore((s) => s.showCharts)
  const closeCharts = useOverviewStore((s) => s.closeCharts)
  const filteredActivities = useOverviewStore((s) => s.filteredActivities)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const setSelectedMonth = useOverviewStore((s) => s.setSelectedMonth)

  const Chart = useRequiredComponent('chart', 'Chart')

  useEffect(() => {
    if (!showCharts) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') closeCharts()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [showCharts, closeCharts])

  if (!showCharts) return null

  const monthOption = buildMonthlyBarOption(filteredActivities)
  const typeOption = buildTypePieOption(filteredActivities)

  return (
    <div className="chart-overlay">
      <button type="button" className="chart-backdrop" onClick={closeCharts} aria-label="Close" />
      <div className="chart-content">
        <div className="chart-card">
          <div className="panel-header">
            <h3 style={{ margin: 0, fontSize: '1rem' }}>Charts</h3>
            <button type="button" className="close-btn" onClick={closeCharts}>
              ×
            </button>
          </div>
          {Chart && (
            <Chart
              option={monthOption}
              style={{ height: 240 }}
              onClick={(params: any) => {
                if (params.dataIndex !== undefined && selectedYear !== null) {
                  const m = parseInt(params.name, 10)
                  if (!Number.isNaN(m)) setSelectedMonth(m)
                }
              }}
            />
          )}
          {Chart && <Chart option={typeOption} style={{ height: 200, marginTop: 16 }} />}
        </div>
      </div>
    </div>
  )
}

export default ChartOverlay
