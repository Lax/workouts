import type { Stats } from '@lax/plugin-data-source'
import { useMemo, useRef } from 'react'
import {
  buildHRSeries,
  buildMoMSeries,
  buildMonthGrid,
  buildPaceSeries,
  buildVolumeSeries,
  linearScale,
  niceMax,
  type Scale,
  xToIndex,
  type VolumeMetric,
} from '../charts'
import { formatDelta, formatDistance, formatPace } from '../format'
import { DEFAULT_T } from '../labels'

const W = 960
const PLOT_LEFT = 46
const PLOT_RIGHT = W - 14
const PLOT_WIDTH = PLOT_RIGHT - PLOT_LEFT

const PANES = [
  { id: 'volume', h: 150, gap: 18 },
  { id: 'mom', h: 70, gap: 18 },
  { id: 'pace', h: 90, gap: 18 },
  { id: 'hr', h: 90, gap: 18 },
] as const
const X_AXIS_H = 30
const t = DEFAULT_T

function paneY(paneIndex: number): number {
  let y = 0
  for (let i = 0; i < paneIndex; i++) y += PANES[i]!.h + PANES[i]!.gap
  return y
}
function paneBottom(paneIndex: number): number {
  return paneY(paneIndex) + PANES[paneIndex]!.h
}
const TOTAL_H = paneBottom(PANES.length - 1) + X_AXIS_H

interface PaneProps {
  n: number
  xAt: (i: number) => number
  hoveredIndex: number | null
}

function linePath(data: Array<number | null>, xAt: (i: number) => number, yAt: (v: number) => number): string {
  let d = ''
  let started = false
  data.forEach((v, i) => {
    if (v === null || !Number.isFinite(v)) {
      started = false
      return
    }
    const x = xAt(i)
    const y = yAt(v)
    d += started ? `L${x.toFixed(1)},${y.toFixed(1)}` : `M${x.toFixed(1)},${y.toFixed(1)}`
    started = true
  })
  return d
}

function VolumePane({ stats, metric, grid, xAt, hoveredIndex }: PaneProps & { stats: Stats; metric: VolumeMetric; grid: { year: number; month: number; index: number }[] }) {
  const series = useMemo(() => buildVolumeSeries(stats, metric), [stats, metric])
  const top = niceMax(series)
  const y = linearScale([0, top], [paneBottom(0), paneY(0) + 10])
  const area = `${linePath(series, xAt, y)}L${xAt(grid.length - 1)},${paneBottom(0)}L${xAt(0)},${paneBottom(0)}Z`

  let peakIdx = 0
  let peak = -Infinity
  series.forEach((v, i) => {
    if (v > peak) {
      peak = v
      peakIdx = i
    }
  })

  return (
    <g>
      <path d={area} className="pane-area" />
      <line x1={PLOT_LEFT} y1={paneBottom(0)} x2={PLOT_RIGHT} y2={paneBottom(0)} className="pane-axis" />
      <text x={PLOT_LEFT - 6} y={paneY(0) + 12} textAnchor="end" className="pane-label">
        {t('trend.volume')}
      </text>
      <text x={PLOT_LEFT - 6} y={y(0) + 4} textAnchor="end" className="pane-tick">
        {formatDistance(top)}
      </text>
      {peak > 0 ? (
        <g>
          <line x1={xAt(peakIdx)} y1={paneY(0) + 8} x2={xAt(peakIdx)} y2={paneBottom(0)} className="pane-annotation" />
          <text x={xAt(peakIdx) + 4} y={paneY(0) + 18} className="pane-annotation-text">
            {formatDistance(peak)}
          </text>
        </g>
      ) : null}
      {hoveredIndex !== null ? (
        <circle cx={xAt(hoveredIndex)} cy={y(series[hoveredIndex] ?? 0)} r={3.5} className="pane-dot" />
      ) : null}
    </g>
  )
}

function MoMPane({ stats, metric, xAt, hoveredIndex }: PaneProps & { stats: Stats; metric: VolumeMetric }) {
  const series = useMemo(() => buildMoMSeries(stats, metric), [stats, metric])
  const maxAbs = Math.max(
    ...series.filter((v): v is number => v !== null && Number.isFinite(v)).map((v) => Math.abs(v)),
    1,
  )
  const y = linearScale([-maxAbs, maxAbs], [paneBottom(1), paneY(1) + 8])
  const zero = y(0)
  const barW = Math.max(1, PLOT_WIDTH / series.length - 1)
  return (
    <g>
      <line x1={PLOT_LEFT} y1={zero} x2={PLOT_RIGHT} y2={zero} className="pane-axis" />
      <text x={PLOT_LEFT - 6} y={paneY(1) + 12} textAnchor="end" className="pane-label">
        {t('trend.mom')}
      </text>
      {series.map((v, i) => {
        if (v === null) return null
        const h = Math.abs(y(v) - zero)
        const top = v >= 0 ? zero - h : zero
        return (
          <rect
            key={i}
            x={xAt(i) - barW / 2}
            y={top}
            width={barW}
            height={Math.max(0.5, h)}
            className={v >= 0 ? 'mom-up' : 'mom-down'}
          />
        )
      })}
      {hoveredIndex !== null ? (
        <circle cx={xAt(hoveredIndex)} cy={series[hoveredIndex] !== null ? y(series[hoveredIndex]!) : zero} r={3.5} className="pane-dot" />
      ) : null}
    </g>
  )
}

function LinePane({
  id,
  series,
  yLabel,
  scale,
  hoveredIndex,
  xAt,
}: PaneProps & { id: string; series: Array<number | null>; yLabel: string; scale: Scale }) {
  const i = PANES.findIndex((p) => p.id === id)
  const path = linePath(series, xAt, scale)
  const domain = scale.domain as [number, number]
  const lo = Math.min(...domain)
  const hi = Math.max(...domain)
  return (
    <g>
      <path d={path} className="pane-line" />
      <line x1={PLOT_LEFT} y1={paneBottom(i)} x2={PLOT_RIGHT} y2={paneBottom(i)} className="pane-axis" />
      <text x={PLOT_LEFT - 6} y={paneY(i) + 12} textAnchor="end" className="pane-label">
        {yLabel}
      </text>
      <text x={PLOT_LEFT - 6} y={scale(hi) + 4} textAnchor="end" className="pane-tick">
        {id === 'pace' ? formatPace(hi) : Math.round(hi).toString()}
      </text>
      <text x={PLOT_LEFT - 6} y={scale(lo) + 4} textAnchor="end" className="pane-tick">
        {id === 'pace' ? formatPace(lo) : Math.round(lo).toString()}
      </text>
      {hoveredIndex !== null ? (
        <circle
          cx={xAt(hoveredIndex)}
          cy={series[hoveredIndex] !== null ? scale(series[hoveredIndex]!) : scale(0)}
          r={3.5}
          className="pane-dot"
        />
      ) : null}
    </g>
  )
}

export interface LinkedTimeChartProps {
  stats: Stats
  metric: VolumeMetric
  onMetricChange: (m: VolumeMetric) => void
  hoveredIndex: number | null
  onHoverIndex: (i: number | null) => void
  hoveredYear: number | null
}

const METRICS: { key: VolumeMetric; label: string }[] = [
  { key: 'distance_km', label: 'metric.distance' },
  { key: 'count', label: 'metric.count' },
  { key: 'moving_time_h', label: 'metric.time' },
  { key: 'elevation_gain_m', label: 'metric.elevation' },
]

export function LinkedTimeChart({ stats, metric, onMetricChange, hoveredIndex, onHoverIndex, hoveredYear }: LinkedTimeChartProps) {
  const svgRef = useRef<SVGSVGElement>(null)

  const grid = useMemo(() => buildMonthGrid(stats.monthly), [stats.monthly])
  const n = grid.length
  const xAt = (i: number): number => (n > 1 ? PLOT_LEFT + (PLOT_WIDTH * i) / (n - 1) : PLOT_LEFT + PLOT_WIDTH / 2)

  const paceSeries = useMemo(() => buildPaceSeries(stats), [stats])
  const hrSeries = useMemo(() => buildHRSeries(stats), [stats])
  const paceDomain: [number, number] = useMemo(() => {
    const vals = paceSeries.filter((v): v is number => v !== null && Number.isFinite(v))
    if (vals.length === 0) return [300, 600]
    return [Math.min(...vals), Math.max(...vals)]
  }, [paceSeries])
  const hrDomain: [number, number] = useMemo(() => {
    const vals = hrSeries.filter((v): v is number => v !== null && Number.isFinite(v))
    if (vals.length === 0) return [80, 120]
    return [Math.min(...vals), Math.max(...vals)]
  }, [hrSeries])

  // 配速反向轴：低值（快）在顶部。domain [min,max] → range [top,bottom]
  const paceScale = linearScale(paceDomain, [paneY(2) + 8, paneBottom(2)])
  const hrScale = linearScale(hrDomain, [paneBottom(3), paneY(3) + 8])

  function onMove(e: React.MouseEvent<SVGSVGElement>) {
    const svg = svgRef.current
    if (!svg) return
    const rect = svg.getBoundingClientRect()
    if (rect.width <= 0) return
    const viewX = ((e.clientX - rect.left) * W) / rect.width
    onHoverIndex(xToIndex(viewX, PLOT_LEFT, PLOT_WIDTH, n))
  }

  const yearRange = useMemo(() => {
    if (hoveredYear === null) return null
    const start = grid.findIndex((p) => p.year === hoveredYear && p.month === 1)
    const end = grid.findIndex((p) => p.year === hoveredYear && p.month === 12)
    if (start === -1) return null
    const x1 = xAt(start)
    const x2 = end !== -1 ? xAt(end) : x1
    return { x1, x2 }
  }, [hoveredYear, grid])

  const volumeAt = hoveredIndex !== null ? buildVolumeSeries(stats, metric)[hoveredIndex] : null
  const momAt = hoveredIndex !== null ? buildMoMSeries(stats, metric)[hoveredIndex] : null
  const paceAt = hoveredIndex !== null ? paceSeries[hoveredIndex] : null
  const hrAt = hoveredIndex !== null ? hrSeries[hoveredIndex] : null
  const timeAt = hoveredIndex !== null ? grid[hoveredIndex] : null

  return (
    <div className="ltc">
      <div className="ltc-metrics" role="group" aria-label={t('trend.volume')}>
        {METRICS.map((m) => (
          <button
            key={m.key}
            type="button"
            className={`ltc-metric-btn ${metric === m.key ? 'active' : ''}`}
            onClick={() => onMetricChange(m.key)}
          >
            {t(m.label)}
          </button>
        ))}
      </div>
      <div className="ltc-plot">
        <svg
          ref={svgRef}
          viewBox={`0 0 ${W} ${TOTAL_H}`}
          className="ltc-svg"
          onMouseMove={onMove}
          onMouseLeave={() => onHoverIndex(null)}
        >
          {yearRange ? (
            <rect x={yearRange.x1} y={0} width={Math.max(1, yearRange.x2 - yearRange.x1)} height={paneBottom(3)} className="ltc-year-band" />
          ) : null}
          <VolumePane stats={stats} metric={metric} grid={grid} n={n} xAt={xAt} hoveredIndex={hoveredIndex} />
          <MoMPane stats={stats} metric={metric} n={n} xAt={xAt} hoveredIndex={hoveredIndex} />
          <LinePane id="pace" series={paceSeries} yLabel={t('trend.pace')} scale={paceScale} n={n} xAt={xAt} hoveredIndex={hoveredIndex} />
          <LinePane id="hr" series={hrSeries} yLabel={t('trend.hr')} scale={hrScale} n={n} xAt={xAt} hoveredIndex={hoveredIndex} />
          {hoveredIndex !== null ? (
            <line x1={xAt(hoveredIndex)} y1={0} x2={xAt(hoveredIndex)} y2={paneBottom(3)} className="ltc-crosshair" />
          ) : null}
          <g className="pane-axis">
            {grid.map((p, i) => {
              if (p.month === 1) {
                return (
                  <text key={i} x={xAt(i)} y={paneBottom(3) + 16} textAnchor="middle" className="pane-year">
                    {p.year}
                  </text>
                )
              }
              return null
            })}
          </g>
        </svg>
        {hoveredIndex !== null && timeAt ? (
          <div className="ltc-readout" aria-live="polite">
            <div className="ltc-readout-time">
              {timeAt.year}-{String(timeAt.month).padStart(2, '0')}
            </div>
            <div className="ltc-readout-row">
              <span className="dot dot-volume" />
              {t('trend.volume')}: {volumeAt !== null ? formatDistance(volumeAt) : '—'}
            </div>
            <div className="ltc-readout-row">
              <span className="dot dot-mom" />
              {t('trend.mom')}: {momAt !== null ? formatDelta(momAt) ?? '—' : '—'}
            </div>
            <div className="ltc-readout-row">
              <span className="dot dot-pace" />
              {t('trend.pace')}: {paceAt !== null ? formatPace(paceAt) : '—'}
            </div>
            <div className="ltc-readout-row">
              <span className="dot dot-hr" />
              {t('trend.hr')}: {hrAt !== null ? `${Math.round(hrAt)} bpm` : '—'}
            </div>
          </div>
        ) : null}
      </div>
    </div>
  )
}
