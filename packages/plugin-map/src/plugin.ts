import type { RegularPlugin } from '@workouts/core'
import { MapView } from './MapView'

const plugin: RegularPlugin = {
  type: 'plugin',
  manifest: { id: 'map', name: 'Map', version: '0.1.0' },
  setup(api) {
    api.registerComponent('MapView', MapView)
  },
}

export default plugin
