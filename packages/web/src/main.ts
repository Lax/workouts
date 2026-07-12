import { mount } from 'svelte'
import App from './App.svelte'
import './app.css'
import { loadData, buildThemeContext, metaTheme } from './lib/theme/mount'
import type { ThemeContext } from '@workouts/shared'

async function start() {
  const themeName = metaTheme() || 'overview'
  const [data, layoutMod] = await Promise.all([
    loadData(),
    import(`./plugins/themes/${themeName}/src/Layout.svelte`),
  ])
  const ctx: ThemeContext = buildThemeContext(themeName, themeName, data)
  const Layout = layoutMod.default

  const app = mount(App, {
    target: document.getElementById('app')!,
    props: { Layout, ctx },
  })
}

start()
