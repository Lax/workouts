import { useMemo } from 'react'
import { useOverviewStore } from '../store'

export function Drawer() {
  const drawerOpen = useOverviewStore((s) => s.drawerOpen)
  const selectedYear = useOverviewStore((s) => s.selectedYear)
  const availableYears = useOverviewStore((s) => s.years)
  const setSelectedYear = useOverviewStore((s) => s.setSelectedYear)
  const setSelectedMonth = useOverviewStore((s) => s.setSelectedMonth)
  const selectedMonth = useOverviewStore((s) => s.selectedMonth)
  const _closeDetail = useOverviewStore((s) => s.closeDetail)
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
      <div
        onClick={toggleDrawer}
        style={{
          position: 'fixed',
          top: 0,
          right: 0,
          bottom: 0,
          width: 48,
          zIndex: 2,
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: 'var(--color-text-secondary)',
          fontSize: '0.75rem',
          writingMode: 'vertical-lr',
          background: 'var(--color-bg)',
          borderLeft: '1px solid var(--color-border)',
          userSelect: 'none',
        }}
      >
        {drawerOpen ? '→' : '←'} {useOverviewStore.getState().filteredActivities.length} activities
      </div>

      <div
        style={{
          position: 'fixed',
          top: 0,
          right: drawerOpen ? 0 : -360,
          bottom: 0,
          width: 320,
          zIndex: 3,
          background: 'var(--color-surface)',
          borderLeft: '1px solid var(--color-border)',
          transition: 'right 0.2s ease',
          overflowY: 'auto',
          padding: 10,
          display: 'flex',
          flexDirection: 'column',
          gap: 8,
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
          <span style={{ fontWeight: 600 }}>Filters</span>
          <div style={{ display: 'flex', gap: 4 }}>
            <button onClick={() => openCharts()} style={btnStyle}>
              Charts
            </button>
            <button onClick={() => useOverviewStore.getState().resetFilters()} style={btnStyle}>
              Reset
            </button>
          </div>
        </div>

        <FiltersSection />

        <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
          {yearItems.map(({ y, ms }) => (
            <div key={y}>
              <button
                onClick={() => setSelectedYear(selectedYear === y ? null : y)}
                style={{
                  ...chipStyle,
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
                      key={m}
                      onClick={() => setSelectedMonth(selectedMonth === m ? null : m)}
                      style={{
                        ...chipStyle,
                        fontSize: '0.65rem',
                        padding: '1px 4px',
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

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.75rem' }}>
      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        {availableTypes.map(([t, c]) => (
          <button
            key={t}
            onClick={() => setFilter({ type: filters.type === t ? '' : t })}
            style={{
              ...chipStyle,
              background: filters.type === t ? 'var(--color-accent)' : 'var(--color-bg)',
              color: filters.type === t ? '#000' : 'var(--color-text)',
            }}
          >
            {t} ({c})
          </button>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
        {availableSources.map(([s, c]) => (
          <button
            key={s}
            onClick={() => setFilter({ source: filters.source === s ? '' : s })}
            style={{
              ...chipStyle,
              background: filters.source === s ? 'var(--color-accent)' : 'var(--color-bg)',
              color: filters.source === s ? '#000' : 'var(--color-text)',
            }}
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
          padding: '4px 8px',
          borderRadius: 4,
          border: '1px solid var(--color-border)',
          background: 'var(--color-bg)',
          color: 'var(--color-text)',
          fontSize: '0.75rem',
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
          display: 'grid',
          gridTemplateColumns: '1fr 60px 50px',
          gap: 4,
          paddingBottom: 4,
          borderBottom: '1px solid var(--color-border)',
          marginBottom: 4,
        }}
      >
        {headers.map((h) => (
          <div
            key={h.field}
            onClick={() => toggleSort(h.field)}
            style={{ cursor: 'pointer', fontWeight: sortField === h.field ? 700 : 400 }}
          >
            {h.label} {sortField === h.field ? (sortDesc ? '↓' : '↑') : ''}
          </div>
        ))}
      </div>
      {filtered.map((a) => (
        <div
          key={a.run_id}
          onClick={() => openDetail(a)}
          style={{
            display: 'grid',
            gridTemplateColumns: '1fr 60px 50px',
            gap: 4,
            padding: '2px 0',
            cursor: 'pointer',
            borderRadius: 2,
          }}
        >
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {a.start_date?.slice(5, 10) || '??-??'} {a.name || 'Untitled'}
          </span>
          <span>{a.distance ? (a.distance / 1000).toFixed(1) : '—'}</span>
          <span>{a.moving_time ? `${Math.floor(a.moving_time / 60)}m` : '—'}</span>
        </div>
      ))}
    </div>
  )
}

const btnStyle: React.CSSProperties = {
  padding: '2px 8px',
  fontSize: '0.7rem',
  borderRadius: 4,
  border: '1px solid var(--color-border)',
  cursor: 'pointer',
  background: 'var(--color-bg)',
  color: 'var(--color-text)',
}

const chipStyle: React.CSSProperties = {
  padding: '2px 6px',
  fontSize: '0.65rem',
  borderRadius: 4,
  border: 'none',
  cursor: 'pointer',
}
