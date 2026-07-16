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
      aria-label={showLabels ? 'Turn off map lights' : 'Turn on map lights'}
      title={showLabels ? 'Turn off map lights' : 'Turn on map lights'}
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
      {showLabels ? (
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={1.5}
          stroke="currentColor"
          width={18}
          height={18}
          aria-hidden="true"
        >
          <path strokeLinecap="round" d="M12 2a6 6 0 0 0-3 11.2A4 4 0 0 0 11 17h2a4 4 0 0 0 2-3.8A6 6 0 0 0 12 2Z" />
          <path strokeLinecap="round" d="M9 19h6" />
          <path strokeLinecap="round" d="M12 1.5v-1" />
          <path strokeLinecap="round" d="M16.5 4l1.5-1.5" />
          <path strokeLinecap="round" d="M20 8.5h1.5" />
          <path strokeLinecap="round" d="M4 8.5H2.5" />
          <path strokeLinecap="round" d="M7.5 4l-1.5-1.5" />
        </svg>
      ) : (
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          strokeWidth={1.5}
          stroke="currentColor"
          width={18}
          height={18}
          aria-hidden="true"
        >
          <path strokeLinecap="round" d="M12 2a6 6 0 0 0-3 11.2A4 4 0 0 0 11 17h2a4 4 0 0 0 2-3.8A6 6 0 0 0 12 2Z" />
          <path strokeLinecap="round" d="M9 19h6" />
        </svg>
      )}
    </button>
  )
}
