import type { TilePreset } from '../tiles'

interface TileSwitcherProps {
  presets: TilePreset[]
  activeId: string
  onSelect: (id: string) => void
  disabledIds?: string[]
}

function PresetIcon({ id }: { id: string }) {
  const props = { width: 14, height: 14, fill: 'none', stroke: 'currentColor', strokeWidth: 1.5, viewBox: '0 0 24 24' }
  switch (id) {
    case 'dark':
      return (
        <svg xmlns="http://www.w3.org/2000/svg" {...props} aria-hidden="true">
          <path strokeLinecap="round" d="M12 2a6 6 0 0 0-3 11.2A4 4 0 0 0 11 17h2a4 4 0 0 0 2-3.8A6 6 0 0 0 12 2Z" />
          <path strokeLinecap="round" d="M9 19h6" />
        </svg>
      )
    case 'light':
      return (
        <svg xmlns="http://www.w3.org/2000/svg" {...props} aria-hidden="true">
          <circle cx="12" cy="8" r="4" />
          <path
            strokeLinecap="round"
            d="M12 2v-1M16.5 4l1.5-1.5M20 8.5h1.5M4 8.5H2.5M7.5 4l-1.5-1.5M12 14v1M16.5 12l1.5 1.5M7.5 12l-1.5 1.5"
          />
        </svg>
      )
    case 'satellite':
      return (
        <svg xmlns="http://www.w3.org/2000/svg" {...props} aria-hidden="true">
          <circle cx="12" cy="12" r="6" />
          <path strokeLinecap="round" d="M12 6v12M6 12h12" />
          <path strokeLinecap="round" d="M8 8l8 8M16 8l-8 8" />
        </svg>
      )
    case 'outdoor':
      return (
        <svg xmlns="http://www.w3.org/2000/svg" {...props} aria-hidden="true">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 20l5-10 4 6 3-5 4 9H4z" />
        </svg>
      )
    case 'dark-minimal':
      return (
        <svg xmlns="http://www.w3.org/2000/svg" {...props} aria-hidden="true">
          <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none" />
        </svg>
      )
    default:
      return null
  }
}

export function TileSwitcher({ presets, activeId, onSelect, disabledIds }: TileSwitcherProps) {
  return (
    <div className="tile-switcher" role="radiogroup" aria-label="Map style">
      {presets.map((p) => {
        const disabled = disabledIds?.includes(p.id)
        return (
          <button
            key={p.id}
            type="button"
            role="radio"
            aria-checked={activeId === p.id}
            className={`tile-btn${activeId === p.id ? ' active' : ''}`}
            disabled={disabled}
            onClick={() => onSelect(p.id)}
            title={disabled ? `Token required for ${p.name}` : p.name}
          >
            <PresetIcon id={p.id} />
          </button>
        )
      })}
    </div>
  )
}
