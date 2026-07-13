import { createRoot } from 'react-dom/client'
import type { Config, ThemePlugin, RegularPlugin, ThemeProps } from './types'
import { createRegistry, createPluginAPI } from './registry'
import { ThemeProvider } from './context'
import { ErrorBoundary } from './ErrorBoundary'

export async function bootstrap(
  config: Config,
  entry: string,
  options?: { data?: ThemeProps['data'] },
): Promise<void> {
  const themeId = config.entries?.[entry] ?? config.theme
  if (!themeId) throw new Error(`No theme configured for entry "${entry}"`)

  const theme = await loadTheme(themeId)
  const registry = createRegistry()

  await loadPlugins(config, registry)

  const data = options?.data ?? await fetchData(config.data ?? {})

  const root = document.getElementById('root')
  if (!root) throw new Error('No #root element found')

  const reactRoot = createRoot(root)
  reactRoot.render(
    <ErrorBoundary>
      <ThemeProvider data={data} config={{}} registry={registry}>
        <theme.Layout data={data} config={{}} registry={registry} />
      </ThemeProvider>
    </ErrorBoundary>,
  )
}

async function loadTheme(id: string): Promise<ThemePlugin> {
  const mod = await import(/* @vite-ignore */ `@workouts/theme-${id}`)
  const plugin = mod.default as ThemePlugin
  if (plugin.type !== 'theme') throw new Error(`Module "${id}" is not a theme plugin`)
  return plugin
}

async function loadPlugins(config: Config, registry: ReturnType<typeof createRegistry>): Promise<void> {
  for (const [id, _pluginConfig] of Object.entries(config.plugins ?? {})) {
    const mod = await import(/* @vite-ignore */ `@workouts/plugin-${id}`)
    const plugin = mod.default as RegularPlugin
    if (plugin.type === 'plugin' && plugin.setup) {
      plugin.setup(createPluginAPI(registry, plugin.manifest.id))
    }
  }
}

async function fetchData(
  dataConfig: Record<string, { source: string; optional?: boolean }>,
): Promise<ThemeProps['data']> {
  const result: Record<string, unknown> = {}
  let error: string | undefined

  for (const [key, { source, optional }] of Object.entries(dataConfig)) {
    try {
      const res = await fetch(source)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      result[key] = await res.json()
    } catch (e) {
      if (optional) {
        result[key] = null
      } else {
        error = `Failed to load ${key} from ${source}: ${e}`
        result[key] = null
      }
    }
  }

  return {
    activities: (result.activities ?? []) as ThemeProps['data']['activities'],
    stats: (result.stats ?? null) as ThemeProps['data']['stats'],
    error,
  }
}
