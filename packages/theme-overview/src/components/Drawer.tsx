import { useMemo, useState } from 'react'
import { useOverviewStore } from '../store'
import { ActivityList } from './ActivityList'
import { Filters } from './Filters'
import '../overview.css'

export function Drawer() {
  const drawerOpen = useOverviewStore((s) => s.drawerOpen)
  const toggleDrawer = useOverviewStore((s) => s.toggleDrawer)
  const openCharts = useOverviewStore((s) => s.openCharts)
  const filteredActivities = useOverviewStore((s) => s.filteredActivities)
  const [tab, setTab] = useState<'list' | 'filters'>('list')

  const stats = useMemo(() => {
    const acts = filteredActivities
    return {
      count: acts.length,
      dist: (acts.reduce((s, a) => s + (a.distance ?? 0), 0) / 1000).toFixed(0),
      time: (acts.reduce((s, a) => s + (a.moving_time ?? 0), 0) / 3600).toFixed(1),
      elev: Math.round(acts.reduce((s, a) => s + (a.elevation_gain ?? 0), 0)).toString(),
    }
  }, [filteredActivities])

  function handleToggle(e: React.MouseEvent) {
    e.stopPropagation()
    toggleDrawer()
  }

  return (
    <div className={`drawer${drawerOpen ? ' open' : ''}`}>
      <div className="drawer-handle" onClick={handleToggle} onMouseDown={(e) => e.stopPropagation()}>
        <div className="bar" />
      </div>

      <div
        className="drawer-collapsed"
        onClick={handleToggle}
        onMouseDown={(e) => e.stopPropagation()}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            toggleDrawer()
          }
        }}
      >
        <span className="stat-pill">
          <strong>{stats.count}</strong>次
        </span>
        <span className="stat-pill">
          <strong>{stats.dist}</strong>km
        </span>
        <span className="stat-pill">
          <strong>{stats.time}</strong>h
        </span>
        <span className="stat-pill">
          <strong>{stats.elev}</strong>m
        </span>
        <span className="spacer" />
        <button
          type="button"
          className="icon-btn"
          onClick={(e) => {
            e.stopPropagation()
            openCharts()
          }}
          onMouseDown={(e) => e.stopPropagation()}
        >
          📊
        </button>
        <button
          type="button"
          className="icon-btn"
          onClick={(e) => {
            e.stopPropagation()
            toggleDrawer()
          }}
          onMouseDown={(e) => e.stopPropagation()}
        >
          ▲
        </button>
      </div>

      <div className="drawer-body">
        <div className="drawer-header">
          <div className="tabs">
            <button type="button" className={`tab${tab === 'list' ? ' active' : ''}`} onClick={() => setTab('list')}>
              Activities
            </button>
            <button type="button" className={`tab${tab === 'filters' ? ' active' : ''}`} onClick={() => setTab('filters')}>
              Filters
            </button>
          </div>
          <button type="button" className="icon-btn" onClick={openCharts} onMouseDown={(e) => e.stopPropagation()}>
            📊
          </button>
          <button
            type="button"
            className="icon-btn retract"
            onClick={(e) => {
              e.stopPropagation()
              toggleDrawer()
            }}
            onMouseDown={(e) => e.stopPropagation()}
            aria-label="Close drawer"
          >
            ✕
          </button>
        </div>
        {tab === 'list' ? <ActivityList /> : <Filters />}
      </div>
    </div>
  )
}
