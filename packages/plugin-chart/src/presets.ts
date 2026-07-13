import type { Activity } from '@workouts/shared'
import { categoryColor } from '@workouts/shared'
import type { EChartsOption } from 'echarts'

export function buildMonthlyBarOption(activities: Activity[]): EChartsOption {
  const monthMap = new Map<string, number>()
  for (const a of activities) {
    if (!a.start_date || !a.distance) continue
    const key = a.start_date.slice(0, 7)
    monthMap.set(key, (monthMap.get(key) || 0) + a.distance / 1000)
  }
  const sorted = Array.from(monthMap.entries()).sort(([a], [b]) => a.localeCompare(b))
  return {
    tooltip: { trigger: 'axis' as const },
    grid: { left: 50, right: 20, bottom: 30, top: 20 },
    xAxis: { type: 'category' as const, data: sorted.map(([m]) => m.slice(5)), axisLabel: { color: '#888' } },
    yAxis: { type: 'value' as const, name: 'km', axisLabel: { color: '#888' } },
    series: [{ type: 'bar' as const, data: sorted.map(([, v]) => Math.round(v * 100) / 100), itemStyle: { color: '#4DD2FF' } }],
  }
}

export function buildTypePieOption(activities: Activity[]): EChartsOption {
  const typeMap = new Map<string, number>()
  for (const a of activities) {
    if (!a.distance) continue
    const t = a.sport_category || 'other'
    typeMap.set(t, (typeMap.get(t) || 0) + a.distance / 1000)
  }
  const data = Array.from(typeMap.entries()).map(([name, value]) => ({
    name,
    value: Math.round(value * 100) / 100,
    itemStyle: { color: categoryColor(name) },
  }))
  return {
    tooltip: { trigger: 'item' as const, formatter: '{b}: {c} km' },
    series: [
      {
        type: 'pie' as const,
        radius: ['40%', '70%'],
        center: ['50%', '50%'],
        data,
        label: { color: '#e0e0e0' },
        itemStyle: { borderRadius: 4 },
      },
    ],
  }
}
