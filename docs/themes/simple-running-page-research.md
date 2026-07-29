# Simple 主题参考：yihong0618/running_page 首页调研

调研日期：2026-07-15
来源：https://yihong.run, https://github.com/yihong0618/running_page
用途：theme-simple 复刻参考

## 技术栈

| 类别 | running_page | theme-simple (workouts) |
|---|---|---|
| 框架 | React 19 + TypeScript | React 19 + TypeScript |
| 构建 | Vite + Tailwind v4 | Vite + Tailwind (shared) |
| 地图 | react-map-gl v8 + mapbox-gl v3.23 | Leaflet (plugin-map) |
| 路由 | react-router-dom v7（`/` + `/summary`） | 无路由（single entry） |
| 图表 | Recharts（/summary 卡片内部） | ECharts (plugin-chart) |
| 虚拟列表 | rc-virtual-list v3（/summary 页） | 暂无 |
| 主题 | CSS 变量 + `data-theme` + MutationObserver | CSS 变量 + Bootstrap |
| 头管理 | react-helmet-async | — |
| 动画 | requestAnimationFrame 路线渐显 | 暂无 |

## 整体布局

```
Layout
├── Header (logo + nav + 主题切换)
└── div.mx-auto.max-w-screen-2xl.p-4.lg:flex.lg:p-16
    ├── div.w-full.lg:w-1/3 (左栏)
    │   ├── h1 标题（指向 siteUrl）
    │   └── 条件渲染:
    │       ├── LocationStat（缩放≤3 + IS_CHINESE=true）
    │       └── YearsStat（缩放>3 或非中文）
    └── div.w-full.lg:w-2/3#map-container (右栏)
        ├── RunMap
        │   ├── 路线 (LineLayer, dash+opacity)
        │   ├── RunMapButtons (年份药丸, 左上)
        │   ├── FullscreenControl (右上)
        │   ├── NavigationControl (右下)
        │   └── LightsControl (右上)
        └── 条件渲染:
            ├── SVGStat (year='Total')
            └── RunTable (可排序表格)
```

**Header 实现：** 文档流（非 fixed），64px 圆形 logo + 导航链接 + 主题切换按钮（40×40px）。

## 响应式断点

| 断点 | 左栏 | 地图高度 | RunTable |
|---|---|---|---|
| ≥1024px | flex 并排 `w-1/3` | 600px | 正常 |
| <1024px | 堆叠 100% | 600px | 水平滚动, `min-width: 650px` |
| ≤768px | 100%, `text-5xl` 缩小 | **250px** | 更小字距 |
| ≤480px | — | 250px | `min-width: 550px`, `0.75rem` |

## 配色系统

### CSS 变量

| Token | Light | Dark |
|---|---|---|
| `--color-brand` | `sky-900` | `#e0ed5e` (Nike 绿) |
| `--color-secondary` | `sky-800` | `#ccd94a` |
| `--color-bg` | `neutral-100` | `neutral-900` |
| `--color-tx` | `sky-900` | `var(--color-brand)` |
| `--color-hr` | `neutral-300` | `red-500` |
| `--color-selected` | `sky-900` | `var(--color-brand)` |
| `--color-activity-card` | `neutral-300` | `neutral-700` |
| `--color-run-row-hover-background` | `neutral-200` | `neutral-800` |
| `--svg-color-active-cell` | `neutral-400` | `#4dd2ff` (cyan) |
| `--svg-special-color` | `#d4a574` | `#f7d02c` (gold) |
| `--svg-special-color2` | `#c5756b` | `#f56c6c` (red) |

### 路线颜色（按运动类型）

| 运动类型 | 颜色 | 说明 |
|---|---|---|
| run (generic) | `#e0ed5e` | Nike 荧光绿 |
| run (trail) | `rgb(255,153,51)` | 橙色 |
| run (indoor/treadmill) | `#8899aa` | 灰色 |
| ride (cycling) | `rgb(51,255,87)` | 绿色 |
| hike / walk | `rgb(151,51,255)` | 紫色 |
| swim | `rgb(255,51,51)` | 红色 |
| workout | `#ff6600` | 橙 |
| other | `#e0ed5e` | 同 brand |

Theme-simple 当前使用 `activityColor` from `@workouts/shared`（速度/类型双模式），可供以后追加 running_page 专用颜色映射。

### 字体

| 用途 | 字体 | 字重 |
|---|---|---|
| 正文/标题 | IBM Plex Sans | 400 / 600 / 700 / italic 700 |
| 表格/数字 | IBM Plex Mono | 400 |

注入方式：`Layout.tsx` 的 effect 中 `<link>` Google Fonts。

## 地图参数

| 参数 | 值 |
|---|---|
| 默认瓦片商 | MapCN (CartoCDN, 免费, 无 token) |
| 亮色样式 | `osm-bright` |
| 暗色样式 | `dark-matter` |
| 隐私模式 `PRIVACY_MODE` | 当前 `true`（纯色背景，不加载地图瓦片） |
| 默认灯光 `LIGHTS_ON` | `false` |
| 路线虚线 `USE_DASH_LINE` | `true`（dasharray: [2,2]) |
| 路线透明度 `LINE_OPACITY` | 0.4（正常）/ 1.0（选中/灯光关） |
| 室内路线 | dasharray [4,3]，更低透明度 |
| 动画速度 | 4000m/s，总时长 2500–8000ms，60fps |

### 瓦片商切换

| 供应商 | 需要 Token | 样式数 |
|---|---|---|
| mapcn (Carto) | 否 | 3 (osm-bright, osm-liberty, dark-matter) |
| mapcn_openfreemap | 否 | fallback for China |
| mapbox | pk. token | 6 |
| maptiler | token | 14 |
| stadiamaps | token | 3 |

Theme-simple 用 `tiles.ts` builder 模式（`carto()` / `mapbox(token, style?)` / `openfreemap()`）。

### z-index

| z-index | 元素 |
|---|---|
| 2 | 地图控件 (zoom, compass, attribution) |
| 10 | YearSummaryModal 关闭按钮 |
| 1000 | 地图错误通知 |
| 9999 | YearSummaryModal 遮罩 |

## 表格 (RunTable)

| 属性 | 值 |
|---|---|
| 列（无海拔） | `[km, Pace, BPM, Time, Date]` |
| 列（有海拔） | `[km, Elev, Pace, BPM, Time, Date]` |
| 排序 | 表头点击切换升降序，日期默认升序其余降序 |
| 选中行 | `color: var(--color-primary)` |
| 标题分类 | 全马/半马/晨跑/午跑/下午/傍晚/夜跑 |
| 行高亮联动 | 点击 → 地图定位 + hash `#run_{id}` |
| CSS | 水平滚动容器，`min-width: 650px`，小屏缩小至 `0.75rem` |

## 左侧统计 (YearsStat / YearStat)

逐项展示（可点击筛选年份）：

| 统计项 | 单位/格式 |
|---|---|
| 年份 | 文字 |
| 运行次数 | 数字 |
| 总距离 | km (或 mi) |
| 海拔增益 | m (或 ft) |
| 平均配速 | `/km` (或 `/mi`) |
| 最长连续运动天数 | 天 |
| 平均心率 | bpm |

悬浮 1 秒后显示：
- `year_{YYYY}.svg` — 年度活动日历（GitHub 风格热力图）
- `github_{YYYY}.svg` — 年度柱状图

**SVG 机制：** running_page 用 Python `gen_svg.py` 预生成 + Vite `import.meta.glob` 懒加载。Theme-simple 改用 React 内联 SVG 计算（`YearGridSVG.tsx` + `YearBarSVG.tsx`）。

## 交互记录

| 触发 | 效果 |
|---|---|
| 点击表格行 | 地图 `flyTo` 该活动路线，播放渐显动画，URL hash 更新 |
| 点击 SVG 日历格子 | `<desc>` 含 `run_id` → 定位单活动；`<title>` 含日期 → 定位当日全部 |
| 点击年份药丸按钮 | 筛选该年全部路线到地图 |
| 切换明暗主题 | 地图瓦片样式动态切换（保存/恢复视口） |
| 悬浮年份块 | 1s 延迟后浮动显示年度 SVG + GitHub 风格格子 |
| 灯光开关 | 切换无标签底图（关灯）↔ 有标签底图（开灯） |
| 点击地图单路线 | 触发该路线动画 |

## 关键配置常量（running_page `src/utils/const.ts`）

| 常量名 | 默认值 | simple 对应 |
|---|---|---|
| `USE_DASH_LINE` | `true` | 主题 config |
| `LINE_OPACITY` | `0.4` | 主题 config |
| `MAP_HEIGHT` | 600 (desktop) / 250 (mobile) | CSS `height` |
| `PRIVACY_MODE` | `false`（实际当前 `true`） | 主题 config |
| `LIGHTS_ON` | `false` | 主题 config |
| `SHOW_ELEVATION_GAIN` | `true` | 主题 config |
| `IS_CHINESE` | `true` | 主题 config（控制 LocationStat） |
| `MAP_TILE_VENDOR` | `'mapcn'` | tiles.ts builder |
| `ROAD_LABEL_DISPLAY` | `true` | Leaflet tile 自带 |
| `USE_ANIMATION_FOR_GRID` | `false` | 不实现 |
| `RICH_TITLE` | `false` | 不实现 |

## /summary 页面（Simple 暂不实现）

用于参考，描述如下：

| 特性 | 实现 |
|---|---|
| 路由 | `/summary`，`ActivityList` 组件 |
| 虚拟滚动 | `rc-virtual-list`，卡片宽 280px + gap 20px，ResizeObserver 响应式列数 |
| 筛选 | 运动类型 `<select>` + 时间区间 (年/月/周/日/Life) |
| 卡片翻转 | CSS `perspective: 1000px`, `.cardInner preserve-3d`，背面 SVG 路线预览 |
| 图表 | Recharts `<BarChart>` + `ResponsiveContainer`，主题色取自 CSS 变量 |
| Life 视图 | 年份按钮 + 年度 SVG 或 per-sport "month of life" SVG (`mol_running.svg` 等) |
| 键盘导航 | Life 视图 ← → 切换年份 |
| 路线预览 | 250×150px 内联 SVG，解码 polyline，绿点起点红点终点 |

## 与 theme-simple 的设计差异总结

| 功能 | running_page | simple |
|---|---|---|
| 路由 | `/` + `/summary` | single entry |
| CSS | Tailwind + CSS Modules + CSS vars | plain CSS + CSS vars |
| 状态管理 | useState + useMemo | zustand |
| 地图引擎 | react-map-gl + Mapbox | Leaflet (plugin-map) |
| 数据来源 | `static/activities.json` fetch | `useActivities()` (plugin-data-source) |
| SVG 生成 | Python 预处理 + Vite glob lazy | React 内联动态计算 |
| 路线颜色 | 按运动类型固定 | activityColor (shared, 速度/类型双模式) |
| 天气/温度 | 无 | 已有字段 |
| LocationStat | zoom≤3 + IS_CHINESE | 暂不实现 |
| Header | 文档流, logo+nav+theme | 同 |
| 字体 | IBM Plex Sans + Mono | 同 |
| 默认主题 | dark | dark |
