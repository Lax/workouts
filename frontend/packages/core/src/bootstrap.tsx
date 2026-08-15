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

  const data = options.data ?? { activities: [], stats: null }

  const root = document.getElementById('root')
  if (!root) throw new Error('No #root element found')

  const reactRoot = createRoot(root)
  reactRoot.render(
    <ErrorBoundary>
      <ThemeProvider data={data} config={config as unknown as Record<string, unknown>} registry={registry}>
        <theme.Layout data={data} config={config as unknown as Record<string, unknown>} registry={registry} />
      </ThemeProvider>
    </ErrorBoundary>,
  )
}
