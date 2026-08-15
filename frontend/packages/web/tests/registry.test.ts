import { createPluginAPI, createRegistry } from '@git-fit/core'
import { describe, expect, it, vi } from 'vitest'

describe('createRegistry', () => {
  it('returns object with register and get methods', () => {
    const r = createRegistry()
    expect(r).toHaveProperty('register')
    expect(r).toHaveProperty('get')
  })

  it('stores and retrieves a component', () => {
    const r = createRegistry()
    const Comp = vi.fn()
    r.register('plugin-a', 'Foo', Comp)
    expect(r.get('plugin-a', 'Foo')).toBe(Comp)
  })

  it('returns null for unregistered component', () => {
    const r = createRegistry()
    expect(r.get('unknown', 'Foo')).toBeNull()
  })

  it('scopes components by pluginId', () => {
    const r = createRegistry()
    const CompA = vi.fn()
    const CompB = vi.fn()
    r.register('plugin-a', 'Widget', CompA)
    r.register('plugin-b', 'Widget', CompB)
    expect(r.get('plugin-a', 'Widget')).toBe(CompA)
    expect(r.get('plugin-b', 'Widget')).toBe(CompB)
  })

  it('overwrites when same pluginId + name', () => {
    const r = createRegistry()
    const Old = vi.fn()
    const New = vi.fn()
    r.register('p', 'X', Old)
    r.register('p', 'X', New)
    expect(r.get('p', 'X')).toBe(New)
  })
})

describe('createPluginAPI', () => {
  it('provides registerComponent scoped to pluginId', () => {
    const r = createRegistry()
    const api = createPluginAPI(r, 'my-plugin')
    const Comp = vi.fn()
    api.registerComponent('Btn', Comp)
    expect(r.get('my-plugin', 'Btn')).toBe(Comp)
  })

  it('does not affect other plugin scopes', () => {
    const r = createRegistry()
    const apiA = createPluginAPI(r, 'a')
    const _apiB = createPluginAPI(r, 'b')
    apiA.registerComponent('X', vi.fn())
    expect(r.get('b', 'X')).toBeNull()
  })
})
