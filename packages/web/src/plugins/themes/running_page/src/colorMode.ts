export const CAT_COLORS: Record<string, string> = {
  run: '#e0ed5e',
  trail_run: '#ff9933',
  indoor_run: '#8899aa',
  ride: '#33ff57',
  hike: '#9733ff',
  walk: '#9733ff',
  swim: '#ff3333',
  workout: '#ff6600',
  other: '#e0ed5e',
}

export function activityColor(type: string | null): string {
  return CAT_COLORS[type ?? ''] ?? CAT_COLORS.other
}
