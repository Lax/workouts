import type { Stats } from '@lax/plugin-data-source'
import { computeHighlights } from '../highlights'
import { DEFAULT_T } from '../labels'

export function Highlights({ stats }: { stats: Stats }) {
  const t = DEFAULT_T
  const highlights = computeHighlights(stats)
  if (highlights.length === 0) return null
  return (
    <div className="hl-grid">
      {highlights.map((h) => (
        <div key={h.id} className="hl-card">
          <span className="hl-label">{t(h.labelKey)}</span>
          <span className="hl-value">{h.value}</span>
          {h.detail ? <span className="hl-detail">{h.detail}</span> : null}
        </div>
      ))}
    </div>
  )
}
