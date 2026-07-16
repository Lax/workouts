interface StatProps {
  value: string | number
  description: string
  className?: string
  variant?: 'default' | 'year-stat'
}

export function Stat({ value, description, className = '', variant = 'default' }: StatProps) {
  const formatted = typeof value === 'number' ? intComma(value) : value
  if (variant === 'year-stat') {
    return (
      <div className={`stat-line ${className}`}>
        <span className="stat-val">{formatted}</span>
        <span className="stat-label">{description}</span>
      </div>
    )
  }
  return (
    <span className={`stat-item ${className}`}>
      <strong>{formatted}</strong> {description}
    </span>
  )
}

export function intComma(n: number): string {
  if (!Number.isFinite(n)) return '—'
  const [int, dec] = n.toFixed(n % 1 === 0 ? 0 : 1).split('.')
  const withComma = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return dec ? `${withComma}.${dec}` : withComma
}
