# Overview 主题设计

## 概述

overview 主题 = 当前 `packages/web/` 下地图中心 UI 的直接打包。功能不变，组件原样搬迁。

最终移入 overview 后，`packages/web/` 不再包含任何视觉组件。

---

## 组件搬迁清单

### 从 `web/src/lib/` 搬入 `themes/overview/src/components/`

| 组件 | 原路径 | 目标路径 | 导入依赖 |
|---|---|---|---|
| MapView | `web/src/lib/MapView.svelte` | `components/MapView.svelte` | `polyline.ts`, `colorMode.ts` |
| Drawer | `web/src/lib/Drawer.svelte` | `components/Drawer.svelte` | — |
| ActivityList | `web/src/lib/ActivityList.svelte` | `components/ActivityList.svelte` | `polyline.ts`, `colorMode.ts` |
| DetailPanel | `web/src/lib/DetailPanel.svelte` | `components/DetailPanel.svelte` | `polyline.ts`, `colorMode.ts` |
| ChartOverlay | `web/src/lib/ChartOverlay.svelte` | `components/ChartOverlay.svelte` | — |
| YearPicker | `web/src/lib/YearPicker.svelte` | `components/YearPicker.svelte` | — |
| Filters | `web/src/lib/Filters.svelte` | `components/Filters.svelte` | — |

### 从 `web/src/lib/` 搬入 `themes/overview/src/`

| 文件 | 原路径 | 目标路径 |
|---|---|---|
| colorMode | `web/src/lib/colorMode.ts` | `colorMode.ts` |
| state (主题相关部分) | `web/src/lib/state.svelte.ts` | `store.ts` |

### 共享不动

| 文件 | 路径 | 理由 |
|---|---|---|
| polyline.ts | `web/src/lib/polyline.ts` → `shared/src/polyline.ts` | 多个主题共享 |

---

## 状态拆分

### Host 壳保留 (`web/src/lib/state.svelte.ts`)

```typescript
export const app = $state({
  activities: [] as Activity[],
  stats: null as StatsJson | null,
  loading: true,
  theme: 'light' as string,
  themeList: [] as ThemePackage[],
  activeTheme: 'overview' as string,
})
```

### Overview 主题内 (`themes/overview/src/store.ts`)

```typescript
export function createOverviewStore(ctx: ThemeContext) {
  const state = $state({
    colorMode: 'speed' as 'speed' | 'type',
    selectedYear: null as number | null,
    selectedMonth: null as number | null,
    drawerOpen: false,
    showCharts: false,
    selectedActivity: null as Activity | null,
    detailOpen: false,
    sortField: 'date' as SortField,
    sortDesc: true,
    filters: { type: '', source: '', distanceMin: null, distanceMax: null, search: '' },
    mapHoveredId: null as string | null,
    // 计算属性（由 $derived 实现）
    years: [] as number[],
    availableTypes: [] as [string, number][],
    availableSources: [] as [string, number][],
    filteredActivities: [] as Activity[],
  })
  ctx.registerStore('overview', state)
  return state
}
```

`colorMode.ts` 从 `colorMode.ts` 导入 `activityColor`（函数逻辑不变，文件搬入 overview）。

---

## Layout.svelte

```svelte
<script lang="ts">
  import { getContext, onMount } from 'svelte'
  import type { ThemeContext } from '@workouts/shared/theme-types'
  import MapView from './components/MapView.svelte'
  import Drawer from './components/Drawer.svelte'
  import DetailPanel from './components/DetailPanel.svelte'
  import ChartOverlay from './components/ChartOverlay.svelte'
  import YearPicker from './components/YearPicker.svelte'
  import { createOverviewStore } from './store'

  const ctx = getContext<ThemeContext>('theme')
  const store = createOverviewStore(ctx)
  store.activities = ctx.data.activities
</script>

<!-- 等同于当前 App.svelte 的模板 -->
<MapView />
<div class="map-overlays">
  <!-- brand + YearPicker + legend + theme toggle -->
</div>
<Drawer />
<DetailPanel />
<ChartOverlay />
```

模板内容维持当前 App.svelte 原样搬迁。

---

## 搬迁规则

1. **不改逻辑。** 组件代码仅做以下修改：
   - `import` path 改为相对于 overview 主题内
   - `state.svelte.ts` 引用改为 `store.ts` 引用
   - 数据获取从 `app.activities` 改为 `ctx.data.activities`
2. **CSS 变量。** overview 主题 `style.css` 注入 `data-theme="overview"`，覆盖 host 默认值
3. **polyline.ts** 先从 `web/src/lib/` 搬到 `shared/src/polyline.ts`，所有主题统一引用

---

## 验证清单

- [ ] `pnpm dev` → overview 主题 → 地图渲染
- [ ] 抽屉打开/关闭，活动列表渲染
- [ ] 详情面板打开/关闭
- [ ] 图表弹窗
- [ ] 年份选择切换
- [ ] 运动类型/来源筛选
- [ ] 排序（日期/距离/时间）
- [ ] 地图路线颜色按 speed/type 切换
- [ ] 主题 dark/light 切换
- [ ] 搜索功能
- [ ] 数据加载异常处理
