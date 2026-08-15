import { fireEvent, render, screen } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { normalizeStats, type StatsResult } from '@lax/plugin-data-source'
import type { ThemeProps } from '@lax/core'
import { StatsLayout } from '../src/StatsLayout'
import { LinkedTimeChart, type LinkedTimeChartProps } from '../src/components/LinkedTimeChart'

const stats = normalizeStats(JSON.parse(readFileSync(resolve(__dirname, 'fixtures/stats.json'), 'utf-8')))!

let mockResult: Partial<StatsResult>

const themeProps = (): ThemeProps => ({
  data: { activities: [], stats: null },
  config: {},
  registry: { register: () => {}, get: () => null },
})

vi.mock('@lax/plugin-data-source', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@lax/plugin-data-source')>()
  return {
    ...actual,
    useStats: () => ({ stats: null, loading: false, error: undefined, ...mockResult }),
  }
})

describe('StatsLayout', () => {
  beforeEach(() => {
    vi.resetModules()
    vi.restoreAllMocks()
  })

  it('loading 态显示加载文案', async () => {
    mockResult = { loading: true }
    const { StatsLayout: StatsLayoutMod } = await import('../src/StatsLayout')
    render(<StatsLayoutMod {...themeProps()} />)
    expect(screen.getByText('加载中…')).toBeInTheDocument()
  })

  it('error 态显示暂无数据与错误信息', async () => {
    mockResult = { error: 'HTTP 404' }
    const { StatsLayout: StatsLayoutMod } = await import('../src/StatsLayout')
    render(<StatsLayoutMod {...themeProps()} />)
    expect(screen.getByText('暂无数据')).toBeInTheDocument()
    expect(screen.getByText('HTTP 404')).toBeInTheDocument()
  })

  it('数据态渲染核心数值（与线上 stats.json 一致）', async () => {
    mockResult = { stats }
    const { StatsLayout: StatsLayoutMod } = await import('../src/StatsLayout')
    render(<StatsLayoutMod {...themeProps()} />)
    // Hero 卡片
    expect(screen.getByText('10,882 km')).toBeInTheDocument()
    expect(screen.getByText('2,179')).toBeInTheDocument()
    expect(screen.getByText('1,724 h')).toBeInTheDocument()
    expect(screen.getByText('166,659 m')).toBeInTheDocument()
    // 亮点
    expect(screen.getByText('12 年')).toBeInTheDocument()
    expect(screen.getByText('×8.7')).toBeInTheDocument()
    // Section 标题
    expect(screen.getByText(/现状焦点/)).toBeInTheDocument()
    expect(screen.getByText(/周期对比/)).toBeInTheDocument()
    expect(screen.getByText(/坚持度/)).toBeInTheDocument()
  })
})

describe('LinkedTimeChart crosshair 联动', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  const rect = {
    width: 960,
    height: 500,
    left: 0,
    top: 0,
    right: 960,
    bottom: 500,
    x: 0,
    y: 0,
    toJSON: () => ({}),
  } as DOMRect

  it('mouseMove → onHoverIndex 收到索引；leave → null', () => {
    vi.spyOn(SVGElement.prototype, 'getBoundingClientRect').mockReturnValue(rect)
    const onHover = vi.fn()
    const props: LinkedTimeChartProps = {
      stats,
      metric: 'distance_km',
      onMetricChange: () => {},
      hoveredIndex: null,
      onHoverIndex: onHover,
      hoveredYear: null,
    }
    render(<LinkedTimeChart {...props} />)
    const svg = document.querySelector('.ltc-svg')!
    fireEvent.mouseMove(svg, { clientX: 500 })
    expect(onHover).toHaveBeenCalledTimes(1)
    const idx = onHover.mock.calls[0]![0] as number
    expect(Number.isInteger(idx)).toBe(true)
    expect(idx).toBeGreaterThanOrEqual(0)
    fireEvent.mouseLeave(svg)
    expect(onHover).toHaveBeenLastCalledWith(null)
  })

  it('hoveredIndex 非空时显示时间读卡与各 pane 值', () => {
    vi.spyOn(SVGElement.prototype, 'getBoundingClientRect').mockReturnValue(rect)
    const props: LinkedTimeChartProps = {
      stats,
      metric: 'distance_km',
      onMetricChange: () => {},
      hoveredIndex: 0,
      onHoverIndex: () => {},
      hoveredYear: null,
    }
    const { container } = render(<LinkedTimeChart {...props} />)
    // index 0 = 2015-08
    expect(container.querySelector('.ltc-readout-time')!.textContent).toBe('2015-08')
    // Volume 读卡显示 48.7 km
    expect(container.querySelector('.ltc-readout')!.textContent).toContain('48.7 km')
  })

  it('metric 切换按钮存在且可点击', () => {
    const onMetric = vi.fn()
    const props: LinkedTimeChartProps = {
      stats,
      metric: 'count',
      onMetricChange: onMetric,
      hoveredIndex: null,
      onHoverIndex: () => {},
      hoveredYear: null,
    }
    render(<LinkedTimeChart {...props} />)
    fireEvent.click(screen.getByRole('button', { name: '距离' }))
    expect(onMetric).toHaveBeenCalledWith('distance_km')
  })
})
