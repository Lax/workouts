import type { RegularPlugin } from '@lax/core'

const plugin: RegularPlugin = {
  type: 'plugin',
  manifest: { id: 'data-source', name: 'Data Source', version: '0.1.0' },
  setup(_api) {},
}

export default plugin
