import theme from '@workouts/theme-hello-world'
import { act } from 'react'
import { createRoot, type Root } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

describe('HelloWorldLayout', () => {
  let root: Root
  let container: HTMLDivElement

  beforeEach(() => {
    container = document.createElement('div')
    document.body.appendChild(container)
    root = createRoot(container)
    globalThis.fetch = vi.fn()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    act(() => root.unmount())
    document.body.removeChild(container)
  })

  it('renders package names and calls fetch with relative URL', async () => {
    vi.mocked(fetch).mockResolvedValue({
      ok: true,
      json: async () => ({
        workspace: [{ name: '@workouts/core', version: '1.0.0' }],
        runtime: [{ name: 'react', version: '18.0.0' }],
        tooling: [{ name: 'vite', version: '5.0.0' }],
      }),
    } as Response)

    await act(async () => {
      root.render(<theme.Layout data={{ activities: [], stats: null }} config={{}} registry={{ register: vi.fn(), get: vi.fn() }} />)
    })

    expect(vi.mocked(fetch)).toHaveBeenCalledWith('versions.json')
    expect(container.textContent).toContain('@workouts/core')
    expect(container.textContent).toContain('react')
    expect(container.textContent).toContain('vite')
  })

  it('renders error on fetch failure', async () => {
    vi.mocked(fetch).mockResolvedValue({
      ok: false,
      status: 404,
    } as Response)

    await act(async () => {
      root.render(<theme.Layout data={{ activities: [], stats: null }} config={{}} registry={{ register: vi.fn(), get: vi.fn() }} />)
    })

    expect(container.textContent).toContain('Failed to load version data: HTTP 404')
  })
})
