import type { TilePreset } from '../tiles'

interface TileSwitcherProps {
  presets: TilePreset[]
  activeId: string
  onSelect: (id: string) => void
  disabledIds?: string[]
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
            {p.name}
          </button>
        )
      })}
    </div>
  )
}
