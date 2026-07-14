import type { ThemePlugin } from '@workouts/core'
import chartPlugin from '@workouts/plugin-chart'
import dsPlugin from '@workouts/plugin-data-source'
import mapPlugin from '@workouts/plugin-map'
import { SimpleLayout } from './Layout'

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'simple', name: 'Simple', version: '0.1.0' },
  Layout: SimpleLayout,
  plugins: {
    'data-source': dsPlugin,
    map: mapPlugin,
    chart: chartPlugin,
  },
}

export default theme
export { useSimpleStore } from './store'
