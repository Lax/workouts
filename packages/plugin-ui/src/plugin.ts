import type { RegularPlugin } from '@workouts/core'
import { Card, Badge } from './components'

const plugin: RegularPlugin = {
  type: 'plugin',
  manifest: { id: 'ui', name: 'UI', version: '0.1.0' },
  setup(api) {
    api.registerComponent('Card', Card)
    api.registerComponent('Badge', Badge)
  },
}

export default plugin
