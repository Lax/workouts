import { useMemo } from 'react'
import { useOverviewStore } from '../store'
import '../overview.css'

export function Drawer() {
  const drawerOpen = useOverviewStore((s) => s.drawerOpen)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const availableYears = useOverviewStore((s) => s.years)
  const setSelectedYear = useOverviewStore((s) => s.setSelectedYear)
  const setSelectedMonth = useOverviewStore((s) => s.setSelectedMonth)
  const selectedMonth = useOverviewStore((s) => s.selectedMonth)
  const openCharts = useOverviewStore((s) => s.openCharts)
  const toggleDrawer = useOverviewStore((s) => s.toggleDrawer)

  const yearItems = useMemo(() => {
    const items: { y: number; ms: number[] }[] = []
    for (const y of availableYears) {
      items.push({ y, ms: selectedYear === y ? [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] : [] })
    }
    return items
  }, [availableYears, selectedYear])

  return (
    <>
      <button type="button" className="drawer-toggle" onClick={toggleDrawer}>
        {drawerOpen ? '→' : '←'} {useOverviewStore.getState().filteredActivities.length} activities
      </button>

      <div className={'drawer-panel' + (drawerOpen ? ' open' : '')}>
        <div className="panel-header">
          <span style={{ fontWeight: 600 }}>Filters</span>
          <div style={{ display: 'flex', gap: 4 }}>
            <button type="button" onClick={() => openCharts()} style={{ padding: '2px 8px', fontSize: '0.7rem', borderRadius: 4, border: '1px solid var(--color-border)', cursor: 'pointer', background: 'var(--color-bg)', color: 'var(--color-text)' }}>
              Charts
            </button>
            <button type="button" onClick={() => useOverviewStore.getState().resetFilters()} style={{ padding: '2px 8px', fontSize: '0.7rem', borderRadius: 4, border: '1px solid var(--color-border)', cursor: 'pointer', background: 'var(--color-bg)', color: 'var(--color-text)' }}>
              Reset
            </button>
          </div>
        </div>

        <FiltersSection />

        <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
          {yearItems.map(({ y, ms }) => (
            <div key={y}>
              <button
                type="button"
                onClick={() => setSelectedYear(selectedYear === y ? null : y)}
                style={{
                  padding: '2px 6px', fontSize: '0.65rem', borderRadius: 4, border: 'none', cursor: 'pointer',
                  background: selectedYear === y ? 'var(--color-accent)' : 'var(--color-bg)',
                  color: selectedYear === y ? '#000' : 'var(--color-text)',
                }}
              >
                {y}
              </button>
              {ms.length > 0 && (
                <div style={{ display: 'flex', gap: 2, flexWrap: 'wrap', marginTop: 2 }}>
                  {ms.map((m) => (
                    <button
                      type="button"
                      key={m}
                      onClick={() => setSelectedMonth(selectedMonth === m ? null : m)}
                      style={{
                        padding: '1px 4px', fontSize: '0.65rem', borderRadius: 4, border: 'none', cursor: 'pointer',
                        background: selectedMonth === m ? 'var(--color-accent)' : 'var(--color-bg)',
                        color: selectedMonth === m ? '#000' : 'var(--color-text)',
                      }}
                    >
                      {m}月
                    </button>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>

        <div style={{ marginTop: 8, borderTop: '1px solid var(--color-border)', paddingTop: 8 }}>
          <ActivityList />
        </div>
      </div>
    </>
  )
}

function FiltersSection() {
  const filters = useOverviewStore((s) => s.filters)
  const availableTypes = useOverviewStore((s) => s.availableTypes)
  const availableSources = useOverviewStore((s) => s.availableSources)
  const setFilter = useOverviewStore((s) => s.setFilter)

  const chipClass = (active: boolean) => 'chip' + (active ? ' active' : '')

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.75rem' }}>
      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        {availableTypes.map(([t, c]) => (
          <button
            type="button"
            key={t}
            className={chipClass(filters.type === t)}
            onClick={() => setFilter({ type: filters.type === t ? '' : t })}
          >
            {t} ({c})
          </button>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        {availableSources.map(([s, c]) => (
          <button
            type="button"
            key={s}
            className={chipClass(filters.source === s)}
            onClick={() => setFilter({ source: filters.source === s ? '' : s })}
          >
            {s} ({c})
          </button>
        ))}
      </div>
      <input
        placeholder="Search..."
        value={filters.search}
        onChange={(e) => setFilter({ search: e.target.value })}
        style={{
          padding: '4px 8px', borderRadius: 4, border: '1px solid var(--color-border)',
          background: 'var(--color-bg)', color: 'var(--color-text)', fontSize: '0.75rem',
        }}
      />
    </div>
  )
}

function ActivityList() {
  const filtered = useOverviewStore((s) => s.filteredActivities)
  const sortField = useOverviewStore((s) => s.sortField)
  const sortDesc = useOverviewStore((s) => s.sortDesc)
  const toggleSort = useOverviewStore((s) => s.toggleSort)
  const openDetail = useOverviewStore((s) => s.openDetail)

  const headers: { label: string; field: 'date' | 'distance' | 'time' }[] = [
    { label: 'Date', field: 'date' },
    { label: 'Dist', field: 'distance' },
    { label: 'Time', field: 'time' },
  ]

  return (
    <div style={{ fontSize: '0.7rem' }}>
      <div
        style={{
          display: 'grid', gridTemplateColumns: '1fr 60px 50px', gap: 4,
          paddingBottom: 4, borderBottom: '1px solid var(--color-border)', marginBottom: 4,
        }}
      >
        {headers.map((h) => (
          <button type="button" className="sort-header"
            key={h.field}
            onClick={() => toggleSort(h.field)}
            style={{ fontWeight: sortField === h.field ? 700 : 400 }}
          >
            {h.label} {sortField === h.field ? (sortDesc ? '↓' : '↑') : ''}
          </button>
        ))}
      </div>
      {filtered.map((a) => (
        <button type="button"
          key={a.run_id}
          onClick={() => openDetail(a)}
          style={{
            display: 'grid', gridTemplateColumns: '1fr 60px 50px', gap: 4,
            padding: '2px 0', cursor: 'pointer', borderRadius: 2,
            background: 'none', border: 'none', textAlign: 'left', color: 'inherit', width: '100%', fontSize: '0.7rem',
          }}
        >
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {a.start_date?.slice(5, 10) || '??-??'} {a.name || 'Untitled'}
          </span>
          <span>{a.distance ? (a.distance / 1000).toFixed(1) : '—'}</span>
          <span>{a.moving_time ? `${Math.floor(a.moving_time / 60)}m` : '—'}</span>
        </button>
      ))}
    </div>
  )
}
