import type { ThemePlugin } from '@workouts/core'
import dsPlugin from '@workouts/plugin-data-source'
import mapPlugin from '@workouts/plugin-map'
import chartPlugin from '@workouts/plugin-chart'
import uiPlugin from '@workouts/plugin-ui'
import { OverviewLayout } from './Layout'

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'overview', name: 'Overview', version: '0.1.0' },
  Layout: OverviewLayout,
  plugins: {
    'data-source': dsPlugin,
    'map': mapPlugin,
    'chart': chartPlugin,
    'ui': uiPlugin,
  },
}

export default theme
export { useOverviewStore } from './store'
export type { OverviewStore, Filters, SortField } from './store'
