import type { RegularPlugin } from '@workouts/core'
import { Chart } from './Chart'

const plugin: RegularPlugin = {
  type: 'plugin',
  manifest: { id: 'chart', name: 'Chart', version: '0.1.0' },
  setup(api) {
    api.registerComponent('Chart', Chart)
  },
}

export default plugin
