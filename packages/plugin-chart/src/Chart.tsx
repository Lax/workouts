import { useRef, useEffect } from 'react'
import * as echarts from 'echarts'
import type { EChartsOption } from 'echarts'

export interface ChartProps {
  option: EChartsOption
  style?: React.CSSProperties
  onClick?: (params: any) => void
}

export function Chart({ option, style, onClick }: ChartProps) {
  const elRef = useRef<HTMLDivElement>(null)
  const chartRef = useRef<echarts.ECharts | null>(null)

  useEffect(() => {
    const el = elRef.current
    if (!el) return
    const instance = echarts.init(el)
    chartRef.current = instance
    return () => { instance.dispose(); chartRef.current = null; return }
  }, [])

  useEffect(() => {
    chartRef.current?.setOption(option, { notMerge: true })
  }, [option])

  useEffect(() => {
    const instance = chartRef.current
    if (!instance || !onClick) return
    instance.on('click', onClick)
    return () => { instance.off('click', onClick); return }
  }, [onClick])

  return <div ref={elRef} style={{ width: '100%', height: '100%', ...style }} />
}
