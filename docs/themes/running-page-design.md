# Running Page 主题设计

> **DEPRECATED** — 此文档对应 Svelte 时期架构。项目已迁移至 React 19 + TypeScript，
> 新实现在 `docs/themes/simple-design.md` (theme-simple)。
> 保留此文件仅作为历史参考，不删除。

## 概述

将 yihong0618/running_page 的 React UI 移植为 Svelte 主题。

参考源码：`checkouts/theirs/running_page/src/`

---

## 布局结构

### Main 视图（两栏）

```
┌──────────────────────────────────────────────┐
│  Header（logo + nav + theme toggle）          │
├──────────────────────┬───────────────────────┤
│  LEFT (w-1/3)        │  RIGHT (w-2/3)        │
│                      │                       │
│  Site Title          │  Map (Leaflet)        │
│                      │  ┌───────────────┐   │
│  Year blocks:        │  │ Year btn      │   │
│  - year label        │  │ overlay       │   │
│  - run count         │  └───────────────┘   │
│  - total distance    │                       │
│  - avg pace          │  ActivityTable        │
│  - streak            │  (sortable columns)   │
│  - avg heartrate     │                       │
│                      │                       │
│  Hover → load SVG    │                       │
└──────────────────────┴───────────────────────┘
     Mobile (<768px): stack vertically
```

### Summary 视图（全宽卡片网格）

```
┌──────────────────────────────────────────────┐
│  FilterBar: [Back to Main] [Type ▼] [Int ▼]  │
├──────────────────────────────────────────────┤
│  ┌────────┐ ┌────────┐ ┌────────┐  ← row    │
│  │ Card   │ │ Card   │ │ Card   │           │
│  │ period │ │ period │ │ period │           │
│  │ stats  │ │ stats  │ │ stats  │           │
│  │ chart  │ │ chart  │ │ chart  │           │
│  └────────┘ └────────┘ └────────┘           │
│  ┌────────┐ ┌────────┐                       │
│  │ ...    │ │ ...    │                       │
│  └────────┘ └────────┘                       │
└──────────────────────────────────────────────┘
     Life view: renders full SVG
```

---

## React → Svelte 组件映射

### Layout.svelte

| React | Svelte |
|---|---|
| `Layout/index.tsx` | `Layout.svelte` |
| `Header/index.tsx` | `Header.svelte`（内联，不作为独立组件） |

Layout 是主题入口。管理 `view: 'main' | 'summary'` 切换。

### 左栏：Sidebar.svelte

| React | Svelte | 说明 |
|---|---|---|
| `YearsStat/index.tsx` | `Sidebar.svelte` | 年份列表容器 |
| `YearStat/index.tsx` | `Sidebar.svelte#/YearBlock` | 单年统计块 |
| `Stat/index.tsx` | `Sidebar.svelte#/StatItem` | 数字展示单元 |
| `LocationStat/index.tsx` | `Sidebar.svelte#/LocationBlock` | China 位置统计 |
| `LocationStat/LocationSummary.tsx` | 内联 | 位置汇总 |
| `LocationStat/CitiesStat.tsx` | 内联 | 城市列表 |
| `LocationStat/PeriodStat.tsx` | 内联 | 时段统计 |

### 右栏：MapView.svelte

| React | Svelte |
|---|---|
| `RunMap/index.tsx` | `MapView.svelte` |
| `RunMap/RunMarker.tsx` | 内联 SVG marker |
| `RunMap/RunMapButtons.tsx` | 内联年份按钮 |
| `RunMap/LightsControl.tsx` | 内联灯光切换 |

**地图引擎差异：**

| React (react-map-gl) | Svelte (Leaflet) |
|---|---|
| `Map` → `Source` (geojson) → `Layer` (line) | `L.polyline(points, { color, weight, opacity })` |
| `Source` (animated-run) + `Layer` (animated-run) | Leaflet `flyTo` + `L.polyline` 动画 |
| `FullscreenControl` + `NavigationControl` | `L.control.zoom` |
| `MapboxLanguage` (Chinese) | 不需要（Carto 默认中文） |
| `Mapbox` / `Carto` / `Maptiler` tiles | Carto dark_nolabels / light_nolabels |

复用 axis 的 polyline 渲染模式。

### 表格：ActivityTable.svelte

| React | Svelte |
|---|---|
| `RunTable/index.tsx` | `ActivityTable.svelte` |
| `RunTable/RunRow.tsx` | `ActivityTable.svelte#Row` |

**差异处理：**

| 功能 | React | Svelte |
|---|---|---|
| 排序 | `useState` 手工 | `$state` + `Array.sort()` |
| 点击定位 | `locateActivity(runId)` → `setViewState` | Leaflet `flyTo` + 高亮 |
| 表头样式 | Tailwind class | Svelte scoped CSS |
| 列配置 | `SHOW_ELEVATION_GAIN` 常量 | 主题 config 控制 |

### 卡片网格：VirtualGrid.svelte + ActivityCard.svelte

| React | Svelte |
|---|---|
| `ActivityList/index.tsx` | `VirtualGrid.svelte` |
| `ActivityList/ActivityCardInner` | `ActivityCard.svelte` |
| `ActivityList/ActivityChart.tsx` | `ActivityChart.svelte` |
| `RoutePreview/index.tsx` | `RoutePreview.svelte` |

**卡片交互：**

| 功能 | React | Svelte |
|---|---|---|
| 虚拟滚动 | `rc-virtual-list` | 自实现（或使用 `svelte-virtual-list`） |
| 卡片翻转 (day view) | CSS `rotateY(180deg)` | 同，CSS 3D transform |
| 图表 | Recharts `BarChart` | ECharts BarChart（复用 ECharts.svelte） |
| 响应式列数 | ResizeObserver + `Math.floor(w / 280)` | 同逻辑 |

### SVGStat.svelte

| React | Svelte |
|---|---|
| `SVGStat/index.tsx` | `SVGStat.svelte` |
| `assets/index.tsx` (Vite glob) | Svelte `{#await}` 动态 import |

Lazy load `github.svg` + `grid.svg`（由 Ruby CLI 生成），渲染到内联 SVG。

### FilterBar.svelte

| React | Svelte |
|---|---|
| `ActivityList` 的 select 控件 | `FilterBar.svelte` |

---

## 配色系统

### CSS 变量覆盖（`style.css`）

```css
[data-theme='running_page'] {
  /* Brand */
  --color-brand: #e0ed5e;

  /* Backgrounds */
  --color-bg: #171717;
  --color-surface: #262626;
  --color-card: #404040;

  /* Text */
  --color-text: #e0e0e0;
  --color-text-secondary: #d4d4d4;
  --color-text-dim: #666666;

  /* UI */
  --color-border: #333333;
  --color-hr: #ef4444;
  --color-hover: #262626;
  --color-selected: #e0ed5e;

  /* SVG */
  --svg-color-active-cell: #4dd2ff;
  --svg-special-color: #f7d02c;
  --svg-special-color2: #f56c6c;

  /* Fonts */
  --font-sans: 'IBM Plex Sans', sans-serif;
  --font-mono: 'IBM Plex Mono', monospace;
}
```

### 路线颜色（`colorMode.ts`）

| 运动类型 | 颜色 |
|---|---|
| run (generic) | `#e0ed5e` (brand) |
| run (trail) | `#ff9933` (orange) |
| run (indoor) | `#8899aa` (gray) |
| ride | `#33ff57` (green) |
| hike / walk | `#9733ff` (purple) |
| swim | `#ff3333` (red) |
| workout | `#ff6600` |
| other | `#e0ed5e` (brand) |

```typescript
// colorMode.ts
const RUNNING_PAGE_CAT_COLORS: Record<string, string> = {
  run: '#e0ed5e',
  trail_run: '#ff9933',
  indoor_run: '#8899aa',
  ride: '#33ff57',
  hike: '#9733ff',
  walk: '#9733ff',
  swim: '#ff3333',
  workout: '#ff6600',
}
```

---

## 字体

| 用途 | running_page (React) | running_page (Svelte) |
|---|---|---|
| 正文/标题 | IBM Plex Sans | IBM Plex Sans（Google Fonts 加载） |
| 表格/地图 UI | IBM Plex Mono | IBM Plex Mono |

在 `Layout.svelte` 的 `onMount` 中注入 Google Fonts：

```svelte
onMount(() => {
  const link = document.createElement('link')
  link.href = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,600;0,700;1,700&family=IBM+Plex+Mono&display=swap'
  link.rel = 'stylesheet'
  document.head.appendChild(link)
})
```

---

## Manifest

```json
{
  "name": "running_page",
  "displayName": "Running Page",
  "version": "1.0.0",
  "description": "Two-column dashboard + activity feed + summary grid. Ported from yihong0618/running_page",
  "author": "Lax",

  "data": {
    "activities": { "source": "activities.json", "optional": false },
    "stats": { "source": "stats.json", "optional": true }
  },

  "config": {
    "defaultYear": {
      "type": "string",
      "default": "all",
      "description": "Default year filter"
    },
    "privacyMode": {
      "type": "boolean",
      "default": false,
      "description": "Hide map tiles, show routes only"
    },
    "showElevationGain": {
      "type": "boolean",
      "default": true,
      "description": "Show elevation gain column in table"
    }
  }
}
```

---

## 与 axis 的差异

| | axis | running_page |
|---|---|---|
| 布局 | 全屏地图 + 抽屉列表 | 两栏：左统计 + 右地图/表格 |
| 默认主题 | light | dark |
| 强调色 | `#4DD2FF` (cyan) | `#e0ed5e` (Nike green) |
| 字体 | system | IBM Plex Sans + Mono |
| 活动列表 | 抽屉内缩略图 | 地图下方可排序表格 |
| 摘要视图 | ECharts 模态弹窗 | 全屏卡片网格 |
| 年份选择 | YearPicker 竖排 | 左栏 YearStat 统计块 |
| 路线颜色 | speed/type 双色模式 | 按运动类型固定颜色 |
| 路线动画 | 无 | 选中活动渐显动画 |
