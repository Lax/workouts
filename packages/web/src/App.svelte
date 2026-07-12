<script lang="ts">
  import type { ThemeContext } from '@workouts/shared'

  let { Layout, ctx }: { Layout: any; ctx: ThemeContext } = $props()
</script>

<Layout {ctx} />
