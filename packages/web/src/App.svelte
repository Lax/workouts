<script lang="ts">
  import { onMount } from 'svelte'
  import { formatDistance, formatDuration } from '@workouts/shared'

  let activities: any[] = $state([])
  let loading = $state(true)

  onMount(async () => {
    try {
      const res = await fetch('/activities.json')
      activities = await res.json()
    } catch {
      console.warn('Failed to load activities.json')
    } finally {
      loading = false
    }
  })

  function theme() {
    const current = document.documentElement.getAttribute('data-theme') || 'light'
    const next = current === 'light' ? 'dark' : 'light'
    document.documentElement.setAttribute('data-theme', next)
    localStorage.setItem('theme', next)
  }

  onMount(() => {
    const saved = localStorage.getItem('theme')
    if (saved) {
      document.documentElement.setAttribute('data-theme', saved)
    } else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
      document.documentElement.setAttribute('data-theme', 'dark')
    }
  })
</script>

<header>
  <h1>Workouts</h1>
  <button onclick={theme} class="theme-toggle" aria-label="Toggle theme">🌓</button>
</header>

<main>
  {#if loading}
    <p class="loading">Loading…</p>
  {:else if activities.length === 0}
    <p class="empty">No activities yet.</p>
  {:else}
    <div class="activity-list">
      {#each activities as act}
        <div class="activity-card">
          <h3>{act.name || 'Untitled'}</h3>
          <div class="stats">
            <span>{formatDistance(act.distance)}</span>
            <span>{formatDuration(act.moving_time)}</span>
            <span>{act.average_heartrate ? `${Math.round(act.average_heartrate)} bpm` : '—'}</span>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</main>

<style>
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.5rem;
    background: var(--color-surface);
    border-bottom: 1px solid var(--color-border);
  }

  h1 {
    font-size: 1.25rem;
    font-weight: 600;
  }

  .theme-toggle {
    background: none;
    border: 1px solid var(--color-border);
    border-radius: 6px;
    padding: 0.25rem 0.5rem;
    cursor: pointer;
    font-size: 1.1rem;
  }

  main {
    padding: 1.5rem;
  }

  .loading,
  .empty {
    color: var(--color-text-secondary);
    text-align: center;
    padding: 3rem 0;
  }

  .activity-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .activity-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 8px;
    padding: 1rem;
  }

  .activity-card h3 {
    font-size: 1rem;
    margin-bottom: 0.5rem;
  }

  .stats {
    display: flex;
    gap: 1rem;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
  }
</style>
