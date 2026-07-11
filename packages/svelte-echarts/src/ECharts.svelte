<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import * as echarts from 'echarts'

  let { options, theme } = $props<{
    options: echarts.EChartsOption
    theme?: string
  }>()

  let el: HTMLDivElement
  let chart: echarts.ECharts | null = null

  onMount(() => {
    chart = echarts.init(el, theme)
    chart.setOption(options)
  })

  $effect(() => {
    if (chart) chart.setOption(options)
  })

  onDestroy(() => {
    chart?.dispose()
  })
</script>

<div bind:this={el} style="width:100%;height:400px"></div>
