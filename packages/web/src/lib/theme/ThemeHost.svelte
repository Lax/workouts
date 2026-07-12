<script lang="ts">
  import { setContext } from 'svelte'
  import { ThemeRegistry } from './registry'
  import type { ThemeContext } from '@workouts/shared'
  import { getActiveContext } from './host'

  let Layout = $state<any>(null)

  $effect(() => {
    const active = ThemeRegistry.active
    Layout = active?.default ?? null
  })

  let ctx = $state<ThemeContext | null>(null)

  $effect(() => {
    ctx = getActiveContext()
    if (ctx) setContext('theme', ctx)
  })
</script>

{#if ctx && Layout}
  <Layout {ctx} />
{:else if !ctx}
  <div class="theme-host-loading">Loading theme…</div>
{/if}
