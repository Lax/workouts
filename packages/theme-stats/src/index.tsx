import type { ThemePlugin } from '@lax/core'
import { StatsLayout } from './StatsLayout'
import dsPlugin from '@lax/plugin-data-source'
import './stats.css'

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'stats', name: 'Stats', version: '0.1.0' },
  Layout: StatsLayout,
  plugins: {
    'data-source': dsPlugin,
  },
}

export default theme
