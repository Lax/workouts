/** GridDrawer — draws a grid of route traces.
 *  Maps to upstream GridDrawer / --type grid / grid.svg.
 *  Composes RoutePreviewSVG thumbnails into a N×M grid layout.
 *  When year is null, renders ALL activities (Total view). */

import type { Activity } from '@workouts/shared'
import { useMemo } from 'react'
import { RoutePreviewSVG } from './RoutePreviewSVG'

interface GridDrawerProps {
  year: number | null
  activities: Activity[]
  maxTracks?: number
  columns?: number
}

export function GridDrawer({ year, activities, maxTracks = 20, columns = 4 }: GridDrawerProps) {
  const tracks = useMemo(() => {
    const yearActs = year === null ? activities : activities.filter((a) => a.start_date && new Date(a.start_date).getFullYear() === year)
    return yearActs
      .filter((a) => a.summary_polyline)
      .sort((a, b) => (b.distance ?? 0) - (a.distance ?? 0))
      .slice(0, maxTracks)
  }, [year, activities, maxTracks])

  if (tracks.length === 0) return <div className="empty-state">No route data</div>

  const cellW = 100,
    cellH = 80

  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: 8, padding: '0.5rem' }}>
      {tracks.map((a) => (
        <div
          key={a.run_id}
          style={{
            border: '1px solid var(--color-border, #333)',
            borderRadius: 4,
            overflow: 'hidden',
            background: 'var(--color-surface, #262626)',
          }}
        >
          <RoutePreviewSVG polyline={a.summary_polyline ?? null} width={cellW} height={cellH} />
          <div style={{ padding: '2px 4px', fontSize: 10, color: 'var(--color-text-dim, #666)' }}>
            {((a.distance ?? 0) / 1000).toFixed(1)}km
          </div>
        </div>
      ))}
    </div>
  )
}
