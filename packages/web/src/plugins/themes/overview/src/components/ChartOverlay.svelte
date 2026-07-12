<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte'
  import * as echarts from 'echarts'
  import { getContext } from 'svelte'
  const { state: store, closeCharts } = getContext('overview-store') as any

  let chartEl: HTMLDivElement
  let smallEl: HTMLDivElement
  let chart: echarts.ECharts | null = null
  let smallChart: echarts.ECharts | null = null

  function buildMonthlyData() {
    const monthMap = new Map<string, number>()
    for (const a of store.filteredActivities) {
      if (!a.start_date || !a.distance) continue
      const key = a.start_date.slice(0, 7)
      monthMap.set(key, (monthMap.get(key) || 0) + a.distance / 1000)
    }
    const sorted = Array.from(monthMap.entries()).sort(([a], [b]) => a.localeCompare(b))
    return {
      months: sorted.map(([m]) => m.slice(5)),
      values: sorted.map(([, v]) => Math.round(v * 100) / 100),
    }
  }

  function buildTypeData() {
    const typeMap = new Map<string, number>()
    for (const a of store.filteredActivities) {
      if (!a.distance) continue
      const t = a.sport_category || 'other'
      typeMap.set(t, (typeMap.get(t) || 0) + a.distance / 1000)
    }
    return Array.from(typeMap.entries()).map(([name, value]) => ({ name, value: Math.round(value * 100) / 100 }))
  }

  $effect(() => {
    if (!store.showCharts) return

    chart?.dispose()
    smallChart?.dispose()
    chart = null
    smallChart = null

    tick().then(() => {
      if (!chartEl) return

      const monthData = buildMonthlyData()

      chart = echarts.init(chartEl)
      chart.setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 50, right: 20, bottom: 30, top: 20 },
        xAxis: {
          type: 'category',
          data: monthData.months,
          axisLabel: { color: '#888' },
        },
        yAxis: {
          type: 'value',
          name: 'km',
          axisLabel: { color: '#888' },
        },
        series: [
          {
            type: 'bar',
            data: monthData.values,
            itemStyle: { color: '#4DD2FF' },
          },
        ],
      })

      chart.on('click', (params: any) => {
        if (params.dataIndex !== undefined && store.selectedYear !== null) {
          const monthNum = parseInt(params.name, 10)
          if (!isNaN(monthNum)) store.selectedMonth = monthNum
        }
      })

      smallChart = echarts.init(smallEl)
      const typeData = buildTypeData()
      smallChart.setOption({
        tooltip: { trigger: 'item', formatter: '{b}: {c} km' },
        series: [
          {
            type: 'pie',
            radius: ['40%', '70%'],
            center: ['50%', '50%'],
            data: typeData,
            label: { color: '#e0e0e0' },
            itemStyle: {
              borderRadius: 4,
            },
          },
        ],
      })
    })
  })

  function handleBgClick(e: MouseEvent) {
    if (e.target === e.currentTarget) closeCharts()
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === 'Escape') closeCharts()
  }

  onMount(() => document.addEventListener('keydown', handleKey))
  onDestroy(() => {
    document.removeEventListener('keydown', handleKey)
    chart?.dispose()
    smallChart?.dispose()
  })
</script>

{#if store.showCharts}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="overlay" onclick={handleBgClick}>
    <div class="panel">
      <div class="panel-header">
        <h3>Charts</h3>
        <button class="close-btn" onclick={closeCharts}>×</button>
      </div>
      <div bind:this={chartEl} class="chart-main"></div>
      <div bind:this={smallEl} class="chart-small"></div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 4;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .panel {
    background: var(--color-surface, #16213e);
    border-radius: 12px;
    width: 90%;
    max-width: 600px;
    padding: 1rem;
    animation: fadeIn 0.15s ease-out;
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: scale(0.95); }
    to { opacity: 1; transform: scale(1); }
  }

  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
  }

  h3 {
    font-size: 1rem;
    color: var(--color-text, #e0e0e0);
    margin: 0;
  }

  .close-btn {
    background: none;
    border: none;
    color: var(--color-text, #e0e0e0);
    font-size: 1.5rem;
    cursor: pointer;
    padding: 0;
    line-height: 1;
  }

  .chart-main {
    height: 240px;
  }

  .chart-small {
    height: 200px;
    margin-top: 1rem;
  }
</style>
