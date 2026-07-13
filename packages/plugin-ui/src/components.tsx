import type { ReactNode } from 'react'

export function Card({ children, className, style }: { children: ReactNode; className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={className}
      style={{
        background: 'var(--color-surface)',
        borderRadius: 8,
        padding: 16,
        border: '1px solid var(--color-border)',
        ...style,
      }}
    >
      {children}
    </div>
  )
}

export function Badge({ label, color }: { label: string; color?: string }) {
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 8px',
        borderRadius: 4,
        fontSize: 12,
        background: color ?? 'var(--color-accent)',
        color: '#fff',
      }}
    >
      {label}
    </span>
  )
}
