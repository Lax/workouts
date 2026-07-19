export const SPEED_COLORS = [
  { max: 3, color: '#4A90D9' },
  { max: 6, color: '#50C878' },
  { max: 9, color: '#FFD700' },
  { max: Infinity, color: '#FF4500' },
]

export const CAT_COLORS: Record<string, string> = {
  run: '#4DD2FF',
  walk: '#4ECDC4',
  ride: '#FF6B6B',
  hike: '#FFD93D',
  swim: '#00BCD4',
  ski: '#9C27B0',
  workout: '#FF5722',
  other: '#9E9E9E',
}

export function speedColor(speedMs: number | null): string {
  if (speedMs === null || speedMs === undefined) return '#888'
  const kmh = speedMs * 3.6
  for (const band of SPEED_COLORS) {
    if (kmh < band.max) return band.color
  }
  return '#888'
}

export function typeColor(type: string | null): string {
  return CAT_COLORS[type ?? ''] ?? '#888'
}

export function activityColor(act: { average_speed?: number | null; type?: string | null }, mode: string): string {
  return mode === 'speed' ? speedColor(act.average_speed ?? null) : typeColor(act.type ?? null)
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [Number.parseInt(h.slice(0, 2), 16), Number.parseInt(h.slice(2, 4), 16), Number.parseInt(h.slice(4, 6), 16)]
}

function rgbToHex(r: number, g: number, b: number): string {
  const clamp = (n: number) => Math.max(0, Math.min(255, Math.round(n)))
  return `#${[r, g, b].map((c) => clamp(c).toString(16).padStart(2, '0')).join('')}`
}

export function tintColor(hex: string, amount: number, bgHex: string): string {
  const [r, g, b] = hexToRgb(hex)
  const [br, bg, bb] = hexToRgb(bgHex)
  const targetR = 255 - br
  const targetG = 255 - bg
  const targetB = 255 - bb
  const tr = r + (targetR - r) * amount
  const tg = g + (targetG - g) * amount
  const tb = b + (targetB - b) * amount
  return rgbToHex(tr, tg, tb)
}
