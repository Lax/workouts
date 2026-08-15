import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { normalizeStats } from '@lax/plugin-data-source'
import { computeHighlights } from '../src/highlights'

const stats = normalizeStats(JSON.parse(readFileSync(resolve(__dirname, 'fixtures/stats.json'), 'utf-8')))!

describe('computeHighlights（真实数据锚点）', () => {
  it('包含连续运动年数 = 12', () => {
    const hl = computeHighlights(stats, 20)
    const ya = hl.find((h) => h.id === 'years-active')
    expect(ya).toBeDefined()
    expect(ya!.value).toBe('12 年')
  })

  it('包含今年追势 ×8.7（2026 vs 2025 距离）', () => {
    const hl = computeHighlights(stats, 20)
    const ym = hl.find((h) => h.id === 'yoy-momentum')
    expect(ym).toBeDefined()
    expect(ym!.value).toBe('×8.7')
  })

  it('包含单月距离纪录 844.7 km（2019-05）', () => {
    const hl = computeHighlights(stats, 20)
    const bm = hl.find((h) => h.id === 'best-month-distance')
    expect(bm).toBeDefined()
    expect(bm!.value).toBe('844.7 km')
    expect(bm!.detail).toContain('2019-05')
  })

  it('包含最长连续活跃段 25 个月', () => {
    const hl = computeHighlights(stats, 20)
    const la = hl.find((h) => h.id === 'longest-active-months')
    expect(la).toBeDefined()
    expect(la!.value).toBe('25 个月')
    expect(la!.detail).toContain('2018-10')
    expect(la!.detail).toContain('2020-10')
  })

  it('包含当前/历史连续天数', () => {
    const hl = computeHighlights(stats, 20)
    expect(hl.find((h) => h.id === 'current-streak')!.value).toBe('8 天')
    expect(hl.find((h) => h.id === 'all-time-streak')!.value).toBe('34 天')
  })

  it('默认 top 6，按分数降序', () => {
    const hl = computeHighlights(stats)
    expect(hl.length).toBeLessThanOrEqual(6)
    for (let i = 1; i < hl.length; i++) expect(hl[i]!.score).toBeLessThanOrEqual(hl[i - 1]!.score)
  })

  it('空数据返回空数组', () => {
    const empty = normalizeStats({ summary: {}, monthly: [], yearly: [], streaks: {} })!
    expect(computeHighlights(empty)).toEqual([])
  })
})
