<script lang="ts">
  import { setContext } from 'svelte'
  import type { ThemeContext } from '@workouts/shared'
  let { ctx }: { ctx: ThemeContext } = $props()
</script>

<div class="hello-world">
  <h1>{ctx.themeName}</h1>
  <p>Theme: <strong>{ctx.theme}</strong></p>
  <p>Activities loaded: {ctx.data.activities?.length ?? 0}</p>
</div>

<style>
  .hello-world {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100vh;
    color: var(--color-text, #e0e0e0);
    background: var(--color-bg, #121212);
  }
  h1 { font-size: 2rem; margin-bottom: 1rem; }
</style>
