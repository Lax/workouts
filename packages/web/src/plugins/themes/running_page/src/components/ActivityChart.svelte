<script lang="ts">
  import { onMount } from 'svelte'
  import * as echarts from 'echarts'

  let { dailyDistances = [] as number[] }: { dailyDistances: number[] } = $props()
  let el: HTMLDivElement
  let chart: echarts.ECharts | null = null

  import { onDestroy } from 'svelte'

  onMount(() => {
    chart = echarts.init(el, undefined, { renderer: 'svg' })
    updateChart()
  })

  onDestroy(() => chart?.dispose())

  function updateChart() {
    if (!chart) return
    chart.setOption({
      grid: { left: 0, right: 0, top: 0, bottom: 0 },
      xAxis: { show: false, type: 'category', data: dailyDistances.map((_, i) => i + 1) },
      yAxis: { show: false },
      series: [{
        type: 'bar',
        data: dailyDistances.map(d => d / 1000),
        barWidth: 3,
        itemStyle: { color: 'var(--color-accent, #e0ed5e)' },
      }],
    })
  }
</script>

<div bind:this={el} class="chart"></div>

<style>
  .chart { width: 100%; height: 40px; }
</style>
