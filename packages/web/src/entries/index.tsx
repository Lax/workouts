import { bootstrap } from '@workouts/core'
import config from '../../config.json'
import overviewTheme from '@workouts/theme-overview'
import dsPlugin from '@workouts/plugin-data-source'
import mapPlugin from '@workouts/plugin-map'
import chartPlugin from '@workouts/plugin-chart'
import uiPlugin from '@workouts/plugin-ui'

bootstrap(config, 'index', {
  theme: overviewTheme,
  plugins: { 'data-source': dsPlugin, 'map': mapPlugin, 'chart': chartPlugin, 'ui': uiPlugin },
})
