# Simple 主题设计

## 概述

将 yihong0618/running_page 的 Index 页面（`/` 路由）忠实移植为 workouts 的 `theme-simple` 主题。

复刻目标：`checkouts/theirs/running_page/src/pages/index.tsx`

## 布局结构

```
┌──────────────────────────────────────────────┐
│  Header (文档流, 非浮动)                      │
├──────────────────────┬───────────────────────┤
│  LEFT (flex: 1/3)    │  RIGHT (flex: 2/3)    │
│  整页可滚动           │                       │
│                      │  MapView              │
│  Site Title + Link   │  (variant="contained")│
│                      │  + Year pills overlay │
│  YearsStat:          │                       │
│  ┌─ YearBlock ──┐    │  RunTable / SVGStat   │
│  │ runs  dist    │    │  (可排序, click→map)  │
│  │ pace  streak  │    │                       │
│  │ HR   elev     │    │                       │
│  │ hover → SVG   │    │                       │
│  └───────────────┘    │                       │
│  × N years            │                       │
└──────────────────────┴───────────────────────┘
     Mobile (<768px): stack vertically
```

## 关键架构决策

### MapView variant prop

`packages/plugin-map/src/MapView.tsx`

| Prop | 值 | 容器样式 | 使用场景 |
|---|---|---|---|
| `variant` | `'fullscreen'` (default) | `position: fixed; inset: 0` | overview 主题 |
| | `'contained'` | `height: 100%; width: 100%` | simple 主题（父容器约束） |

两种模式除 CSS 外无任何逻辑分支。Leaflet API（初始化、polyline 渲染、事件、tooltip）完全一致。

simple 用法：
```tsx
<div className="map-wrapper">
  <MapView variant="contained" ... />
</div>
```

父容器 `.map-wrapper` 设显式高度，MapView 通过 `height: 100%` 填满。

### 两栏布局

- 使用 CSS flexbox（非全屏 MapView + 浮动 overlay）
- Header 文档流置顶，左/右列在 Header 下方并排
- 整页可滚动（原版 running_page 行为）
- 断点：`<768px` 堆叠为单列

### 状态管理

zustand store（与 overview 主题一致模式）：

| 状态 | 类型 | 说明 |
|---|---|---|
| `selectedYear` | `number \| null` | `null` = all |
| `colorMode` | `'type' \| 'speed'` | 路线颜色模式 |
| `colorScheme` | `'light' \| 'dark'` | 主题 |
| `sortField` / `sortDesc` | 排序 | 表格排序 |
| `mapHoveredId` | `string \| null` | 地图/表格联动高亮 |
| `filteredActivities` | `Activity[]` | 计算属性 |

### 数据来源

- `useActivities()` / `useDerivedData()` from `@workouts/plugin-data-source`
- Activity 类型: `@workouts/shared`
- 格式化: `formatDistance`, `formatPace`, `formatRunTime` from `@workouts/shared`

### 内联 SVG 生成（替代原版 Python SVG）

| 原版 | Simple 替代 |
|---|---|
| `year_{YYYY}.svg` (Python gen_svg) | `YearGridSVG.tsx` — GitHub 风格贡献网格 |
| `github_{YYYY}.svg` (Python gen_svg) | `YearBarSVG.tsx` — 月度柱状图 |

两者均在 React 中用 `useMemo` 计算 + 内联 SVG 渲染。

## 文件结构

```
packages/theme-simple/
├── package.json
├── tsconfig.json
└── src/
    ├── index.tsx                 # ThemePlugin entry + store re-export
    ├── Layout.tsx                # Two-column layout
    ├── store.ts                  # Zustand store
    ├── simple.css                # All styles
    ├── utils.ts                  # Helpers (hash, filter, sort)
    └── components/
        ├── Header.tsx            # Logo + nav + theme toggle
        ├── YearsStat.tsx         # Year stat cards list
        ├── YearStat.tsx          # Single year block
        ├── YearGridSVG.tsx       # Inline contribution grid
        ├── YearBarSVG.tsx        # Inline monthly bar chart
        ├── RunTable.tsx          # Sortable activity table
        ├── RunRow.tsx            # Table row
        ├── MapOverlays.tsx       # Year pills + legend
        └── SVGStat.tsx           # Total year overview
```

## 组件树

```
ThemePlugin.Layout (= SimpleLayout)
  ├── Header (logo, nav, theme toggle)
  └── div.layout
      ├── aside.left-panel
      │   ├── Site title
      │   └── YearsStat
      │       └── YearStat × N
      │           ├── Stat: run count
      │           ├── Stat: total distance
      │           ├── Stat: avg pace
      │           ├── Stat: streak
      │           ├── Stat: avg HR
      │           ├── Stat: elevation gain
      │           └── hover: YearGridSVG + YearBarSVG
      └── main.right-panel
          ├── div.map-wrapper
          │   ├── MapView (variant="contained")
          │   └── MapOverlays (year pills + color legend)
          └── RunTable or SVGStat (conditional: year === 'Total')
```

## 与原版 running_page 的差异

| 功能 | running_page (React) | Simple (React 19) |
|---|---|---|
| 地图引擎 | react-map-gl + Mapbox | Leaflet (plugin-map MapView) |
| 数据获取 | useActivities (自建) | useActivities (plugin-data-source) |
| 状态管理 | useState + useMemo | zustand |
| CSS | Tailwind + CSS Modules + CSS vars | plain CSS + CSS vars |
| 路线颜色 | getRuntimeSingleRunColor() | activityColor (shared) |
| SVG 生成 | Python 预处理 + SVGR lazy load | React 内联 SVG 动态计算 |
| 路由 | react-router-dom (/, /summary) | 无路由 (仅 single entry) |
| 地区统计 | LocationStat (zoom≤3 + IS_CHINESE) | 暂不实现 (数据源无 provinces) |

## 视觉规范（继承自 running_page）

### CSS 变量

遵循原版 running_page 的暗色配色体系：

| 用途 | running_page 值 | 对应 workouts 变量 |
|---|---|---|
| 品牌色 (accent) | `#e0ed5e` (Nike 荧光绿) | `--color-accent` |
| 页面背景 | `#171717` | `--color-bg` |
| 面板背景 | `#262626` | `--color-surface` |
| 卡片背景 | `#404040` | — |
| 主文字 | `#e0e0e0` | `--color-text` |
| 次要文字 | `#d4d4d4` | `--color-text-secondary` |
| 边框 | `#333333` | `--color-border` |
| 分割线 | `#ef4444` (红色) | — |
| 选中行 | `#e0ed5e` | `--color-active-row` |

### 字体

| 用途 | 字体 | 来源 |
|---|---|---|
| 正文/标题 | IBM Plex Sans (400/600/700/italic 700) | Google Fonts |
| 表格/数字 | IBM Plex Mono | Google Fonts |

Layout 中通过 `<link>` 注入：
```tsx
const link = document.createElement('link')
link.href = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:ital,wght@0,400;0,600;0,700;1,700&family=IBM+Plex+Mono&display=swap'
link.rel = 'stylesheet'
document.head.appendChild(link)
```

### 路线颜色（按运动类型）

原版 running_page 使用固定颜色映射（而非我们的 speed/type 双模式）：

| 运动类型 | 颜色 |
|---|---|
| run (generic) | `#e0ed5e` |
| run (trail) | `#ff9933` |
| run (indoor / treadmill) | `#8899aa` |
| ride (cycling) | `#33ff57` |
| hike / walk | `#9733ff` |
| swim | `#ff3333` |
| workout | `#ff6600` |
| other | `#e0ed5e` |

当前实现使用 `activityColor` from `@workouts/shared`（速度/类型双模式），未来可追加 running_page 专用的颜色模式作为第三种 `colorMode`。

### 地图引擎差异（running_page → workouts）

| 原版 (react-map-gl + Mapbox) | workouts (Leaflet + CartoDB) |
|---|---|
| `Source` (geojson) → `Layer` (line) | `L.polyline(points, { color, weight, opacity })` |
| `animated-run` Source + Layer | 暂无动画（未来可用 `requestAnimationFrame`） |
| `FullscreenControl` + `NavigationControl` | `L.control.zoom` |
| Mapbox Language (中文) | 不需要（Carto tile 默认中文） |
| Mapbox / Carto / Maptiler tiles | Carto `dark_nolabels` / `light_nolabels` |

### 配置字段（待实现）

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `defaultYear` | string | `"all"` | 默认年份过滤 |
| `privacyMode` | boolean | `false` | 隐藏地图瓦片，仅显示路线 |
| `showElevationGain` | boolean | `true` | 表格中显示海拔列 |

## 响应式

| 断点 | 行为 |
|---|---|
| ≥768px | 两栏并排 |
| <768px | 单列堆叠 (left 在上，right 在下) |
