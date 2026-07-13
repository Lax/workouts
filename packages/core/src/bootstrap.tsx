import { createRoot } from 'react-dom/client'
import { ThemeProvider } from './context'
import { ErrorBoundary } from './ErrorBoundary'
import { createPluginAPI, createRegistry } from './registry'
import type { Config, ThemePlugin, ThemeProps } from './types'

export async function bootstrap(
  config: Config,
  options: {
    theme?: ThemePlugin
    data?: ThemeProps['data']
  },
): Promise<void> {
  const theme = options.theme
  if (!theme) throw new Error('bootstrap requires a theme')

  const registry = createRegistry()

  for (const plugin of Object.values(theme.plugins ?? {})) {
    if (plugin.type === 'plugin' && plugin.setup) {
      plugin.setup(createPluginAPI(registry, plugin.manifest.id))
    }
  }

  const data = options.data ?? (await fetchData(config.data ?? {}))
  // Normalize: Ruby export writes type instead of sport_category
  for (const a of data.activities) {
    if (a.type && !a.sport_category) a.sport_category = a.type
    if (!a.summary_polyline && (a as any).polyline) a.summary_polyline = (a as any).polyline
  }

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

async function fetchData(dataConfig: Record<string, { source: string; optional?: boolean }>): Promise<ThemeProps['data']> {
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
