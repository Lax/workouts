import type { Vendor } from '../tiles'

interface LightsToggleProps {
  showLabels: boolean
  onToggle: () => void
  vendor?: Vendor
}

export function LightsToggle({ showLabels, onToggle }: LightsToggleProps) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-label={showLabels ? 'Hide labels' : 'Show labels'}
      title={showLabels ? 'Hide map labels' : 'Show map labels'}
      style={{
        width: 34,
        height: 34,
        background: 'var(--color-surface, #1e1e1e)',
        border: '1px solid var(--color-border, #333)',
        borderRadius: 4,
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: 'var(--color-text, #ccc)',
        fontSize: 16,
        boxShadow: '0 2px 4px rgba(0,0,0,0.3)',
      }}
    >
      {showLabels ? '\u{1F4A1}' : '\u{1F319}'}
    </button>
  )
}
