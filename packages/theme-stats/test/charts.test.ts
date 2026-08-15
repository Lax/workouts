import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { normalizeStats } from '@lax/plugin-data-source'
import {
  buildHRSeries,
  buildMonthGrid,
  buildMonthYearMatrix,
  buildMoMSeries,
  buildPaceSeries,
  buildVolumeSeries,
  buildYearMonths,
  buildYearlySeries,
  linearScale,
  niceMax,
  xToIndex,
} from '../src/charts'
import { parsePace } from '../src/format'

const stats = normalizeStats(JSON.parse(readFileSync(resolve(__dirname, 'fixtures/stats.json'), 'utf-8')))!

describe('parsePace', () => {
  it("'5'49\"' → 349", () => {
    expect(parsePace("5'49\"")).toBe(349)
  })
  it("'19'57\"' → 1197", () => {
    expect(parsePace("19'57\"")).toBe(1197)
  })
  it('非法输入 → null', () => {
    expect(parsePace('abc')).toBeNull()
    expect(parsePace('')).toBeNull()
  })
})

describe('buildMonthGrid', () => {
  it('从首月覆盖到末月（逐月展开）', () => {
    const grid = buildMonthGrid(stats.monthly)
    expect(grid[0]).toEqual({ year: 2015, month: 8, index: 0 })
    const last = grid[grid.length - 1]!
    expect(last.year).toBe(2026)
    expect(last.month).toBe(8)
    // 2015-08 → 2026-08 = 133 个月
    expect(grid).toHaveLength(133)
    expect(grid[1]).toEqual({ year: 2015, month: 9, index: 1 })
  })
})

describe('buildVolumeSeries', () => {
  it('缺失月补 0，真实月取 distance_km', () => {
    const s = buildVolumeSeries(stats, 'distance_km')
    // 2015-08 有数据
    expect(s[0]).toBeCloseTo(48.7, 1)
    // 2015-09 缺失 → 0
    expect(s[1]).toBe(0)
    // 2019-05 844.7（单月纪录）
    const grid = buildMonthGrid(stats.monthly)
    const idx = grid.findIndex((p) => p.year === 2019 && p.month === 5)
    expect(s[idx]).toBeCloseTo(844.7, 0)
  })

  it('count 序列正确', () => {
    const s = buildVolumeSeries(stats, 'count')
    const grid = buildMonthGrid(stats.monthly)
    const idx = grid.findIndex((p) => p.year === 2026 && p.month === 6)
    expect(s[idx]).toBe(189)
  })
})

describe('buildMoMSeries', () => {
  it('连续真实月才计算环比，前月缺失为 null', () => {
    const s = buildMoMSeries(stats, 'distance_km')
    const grid = buildMonthGrid(stats.monthly)
    // 首月无前月 → null
    expect(s[0]).toBeNull()
    // 2015-08 之后 2015-09 缺失 → null（不拿合成 0 算 -100%）
    expect(s[1]).toBeNull()
    // 2019-04 → 2019-05：844.7 vs 689.2 → +22.6%
    const idx = grid.findIndex((p) => p.year === 2019 && p.month === 5)
    const prev = grid.findIndex((p) => p.year === 2019 && p.month === 4)
    const may = stats.monthly.find((m) => m.year === 2019 && m.month === 5)!
    const apr = stats.monthly.find((m) => m.year === 2019 && m.month === 4)!
    const expected = ((may.distance_km - apr.distance_km) / apr.distance_km) * 100
    expect(s[idx]).toBeCloseTo(expected, 1)
    expect(s[prev]).not.toBeNull()
  })
})

describe('buildPaceSeries / buildHRSeries', () => {
  it('pace 有数据处为秒，无数据为 null（断线）', () => {
    const s = buildPaceSeries(stats)
    const grid = buildMonthGrid(stats.monthly)
    const idx = grid.findIndex((p) => p.year === 2019 && p.month === 5)
    expect(s[idx]).toBe(parsePace(stats.monthly.find((m) => m.year === 2019 && m.month === 5)!.avg_pace!))
    expect(s[0]).toBe(parsePace("5'49\""))
    // 2019-05 有 HR? 实际 43/79 覆盖，取一个真实值
  })

  it('HR 无数据为 null', () => {
    const s = buildHRSeries(stats)
    expect(s.every((v) => v === null || typeof v === 'number')).toBe(true)
    const grid = buildMonthGrid(stats.monthly)
    const idx = grid.findIndex((p) => p.year === 2026 && p.month === 8)
    expect(s[idx]).toBe(97)
  })
})

describe('scale / crosshair', () => {
  it('linearScale 线性映射', () => {
    const scale = linearScale([0, 100], [0, 500])
    expect(scale(0)).toBe(0)
    expect(scale(100)).toBe(500)
    expect(scale(50)).toBe(250)
  })

  it('线性比例映射到反向 range（配速轴：低值→top）', () => {
    // domain [min,max] → range [top,bottom]
    const scale = linearScale([100, 900], [0, 100])
    expect(scale(100)).toBe(0)
    expect(scale(900)).toBe(100)
    expect(scale(500)).toBe(50)
  })

  it('niceMax 给最大值留 padding', () => {
    expect(niceMax([0, 100], 0)).toBe(100)
    expect(niceMax([100], 0.5)).toBe(150)
    expect(niceMax([], 0.1)).toBe(1)
    expect(niceMax([0, 0], 0.1)).toBe(1)
  })

  it('xToIndex 像素 → 索引（夹取）', () => {
    // plotLeft=46, width=900, count=133
    expect(xToIndex(46, 46, 900, 133)).toBe(0)
    expect(xToIndex(946, 46, 900, 133)).toBe(132)
    expect(xToIndex(500, 46, 900, 133)).toBe(Math.round(((500 - 46) / 900) * 132))
    expect(xToIndex(0, 46, 900, 133)).toBe(0)
    expect(xToIndex(9999, 46, 900, 133)).toBe(132)
  })
})

describe('buildYearlySeries / buildYearMonths', () => {
  it('yearly 序列 12 年', () => {
    const y = buildYearlySeries(stats)
    expect(y).toHaveLength(12)
    expect(y[0]!.year).toBe(2015)
    expect(y[y.length - 1]!.year).toBe(2026)
  })

  it('buildYearMonths 补足 12 个月（缺失补 0）', () => {
    const ms = buildYearMonths(stats, 2022)
    expect(ms).toHaveLength(12)
    const hasData = ms.filter((m) => m.distance_km > 0)
    expect(hasData).toHaveLength(1) // 2022 仅 1 个月有数据
  })
})

describe('buildMonthYearMatrix', () => {
  it('行列与格值正确，含同比 prev', () => {
    const m = buildMonthYearMatrix(stats)
    expect(m.years).toContain(2019)
    expect(m.years).toContain(2026)
    // 2019-05 844.7 是全矩阵最大
    expect(m.maxDistance).toBeCloseTo(844.7, 0)
    const cell = m.cells.find((c) => c.year === 2026 && c.month === 1)!
    expect(cell.distance_km).toBeCloseTo(112.5, 1)
    expect(cell.prev).not.toBeNull()
    expect(cell.prev!.distance_km).toBeCloseTo(12, 0)
    // 无数据格
    const empty = m.cells.find((c) => c.year === 2015 && c.month === 1)!
    expect(empty.distance_km).toBeNull()
  })
})
