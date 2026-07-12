<script lang="ts">
  import { ThemeRegistry } from './registry'

  const themes = $derived(ThemeRegistry.list())
  let selected = $state(ThemeRegistry.active?.manifest.name ?? '')

  function onSwitch(e: Event) {
    const name = (e.target as HTMLSelectElement).value
    selected = name
    ThemeRegistry.setActive(name)
  }
</script>

<div class="theme-switcher">
  <select onchange={onSwitch}>
    <option value="" disabled>Select theme…</option>
    {#each themes as theme}
      <option value={theme.manifest.name} selected={theme.manifest.name === selected}>
        {theme.manifest.displayName}
      </option>
    {/each}
  </select>
</div>

<style>
  .theme-switcher {
    position: fixed;
    top: 10px;
    right: 10px;
    z-index: 100;
  }
  select {
    padding: 4px 8px;
    font-size: 0.8rem;
    border: 1px solid var(--color-border, #333);
    border-radius: 6px;
    background: var(--color-surface, #1e1e1e);
    color: var(--color-text, #e0e0e0);
    cursor: pointer;
  }
</style>
