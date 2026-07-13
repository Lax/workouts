import type { ThemePlugin } from '@workouts/core'
import { OverviewLayout } from './Layout'

const theme: ThemePlugin = {
  type: 'theme',
  manifest: { id: 'overview', name: 'Overview', version: '0.1.0' },
  Layout: OverviewLayout,
}

export default theme
