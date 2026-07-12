<script lang="ts">
  import { onMount } from 'svelte'
  import { app } from './lib/state.svelte'
  import type { Activity } from '@workouts/shared'
  import type { StatsJson } from './lib/state.svelte'
  import { ThemeRegistry } from './lib/theme/registry'
  import { activateTheme, setActiveContext } from './lib/theme/host'
  import ThemeHost from './lib/theme/ThemeHost.svelte'
  import ThemeSwitcher from './lib/theme/ThemeSwitcher.svelte'

  onMount(async () => {
    initTheme()
    await ThemeRegistry.loadAll()

    const overview = ThemeRegistry.lookup('overview')

    try {
      const [actRes, statsRes] = await Promise.all([
        fetch('activities.json'),
        fetch('stats.json'),
      ])
      if (actRes.ok) {
        const data: Activity[] = await actRes.json()
        for (const a of data) {
          if (a.type && !a.sport_category) a.sport_category = a.type
        }
        app.activities = data
      }
      if (statsRes.ok) {
        const data: StatsJson = await statsRes.json()
        app.stats = data
      }
    } catch (e) {
      console.warn('Failed to load data', e)
    }

    if (overview) {
      const ctx = await activateTheme('overview', { activities: app.activities, stats: app.stats })
      setActiveContext(ctx)
    }
    app.loading = false
  })

  function initTheme() {
    const saved = localStorage.getItem('theme') || 'dark'
    document.documentElement.setAttribute('data-theme', saved)
  }
</script>

{#if app.loading}
  <div class="loading">Loading…</div>
{:else}
  <ThemeSwitcher />
  <ThemeHost />
{/if}

<style>
  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    color: var(--color-text-secondary, #888);
  }
</style>
