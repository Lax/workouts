<script lang="ts">
  import { setContext, onMount } from 'svelte'
  import { ThemeRegistry } from './registry'
  import type { ThemeContext } from '@workouts/shared'
  import { getActiveContext } from './host'

  let Layout = $state<any>(null)
  let ctx = $state<ThemeContext | null>(null)

  onMount(() => {
    ctx = getActiveContext()
    if (ctx) setContext('theme', ctx)

    return ThemeRegistry.onChange(() => {
      const active = ThemeRegistry.active
      Layout = active?.default ?? null
      ctx = getActiveContext()
      if (ctx) setContext('theme', ctx)
    })
  })
</script>

{#if ctx && Layout}
  <Layout {ctx} />
{:else if !ctx}
  <div class="theme-host-loading">Loading theme…</div>
{/if}
