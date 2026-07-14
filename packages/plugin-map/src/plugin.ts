import type { RegularPlugin } from '@workouts/core'
import { HeroMap } from './HeroMap'
import { MapView } from './MapView'
import { PanelMap } from './PanelMap'

const plugin: RegularPlugin = {
  type: 'plugin',
  manifest: { id: 'map', name: 'Map', version: '0.1.0' },
  setup(api) {
    api.registerComponent('MapView', MapView)
    api.registerComponent('HeroMap', HeroMap)
    api.registerComponent('PanelMap', PanelMap)
  },
}

export default plugin
