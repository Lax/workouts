import type { EChartsOption } from 'echarts'
import { BarChart, PieChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import type { ECharts } from 'echarts/core'
import { init, use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { useEffect, useRef } from 'react'

use([BarChart, PieChart, TooltipComponent, GridComponent, CanvasRenderer])

export interface ChartProps {
  option: EChartsOption
  style?: React.CSSProperties
  onClick?: (params: any) => void
}

export function Chart({ option, style, onClick }: ChartProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<ECharts | null>(null)

  useEffect(() => {
    const el = elRef.current
    if (!el) return
    const instance = init(el)
    chartRef.current = instance
    return () => {
      instance.dispose()
      chartRef.current = null
    }
  }, [])

  useEffect(() => {
    chartRef.current?.setOption(option, { notMerge: true })
  }, [option])

  useEffect(() => {
    const instance = chartRef.current
    if (!instance || !onClick) return
    instance.on('click', onClick)
    return () => {
      instance.off('click', onClick)
    }
  }, [onClick])

  return <div ref={elRef} style={{ width: '100%', height: '100%', ...style }} />
}
