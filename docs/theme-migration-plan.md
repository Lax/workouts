# Theme System — Migration Plan

## Overview

4 个 Phase，依赖关系链式串联：

```
Phase 1 (基础设施)
  │
  ├──→ Phase 2 (overview 打包)
  │
  └──→ Phase 3 (running_page 移植)
            │
            └──→ Phase 4 (SVG 前端化 + 测试)
```

每个 Phase 完成后 `bundle exec rspec` + `pnpm build` 保持绿色。

---

## Phase 1：基础设施

**边界：** Host 壳 + ThemeRegistry + 数据流 + 一个最小验证主题。

### 文件变更

| 操作 | 文件 | 说明 |
|---|---|---|
| ADD | `packages/shared/src/theme-types.ts` | ThemeManifest, ThemeContext, ThemePackage, DataRequirement, ConfigField |
| ADD | `packages/web/src/lib/theme/registry.ts` | ThemeRegistry (register/lookup/list/loadAll/setActive) |
| ADD | `packages/web/src/lib/theme/host.ts` | fetchRequiredData, loadConfig, activateTheme, deactivateTheme |
| ADD | `packages/web/src/lib/theme/ThemeSwitcher.svelte` | 下拉选择器 |
| ADD | `packages/web/src/lib/theme/ThemeHost.svelte` | `<svelte:component>` 挂载 |
| ADD | `packages/plugins/themes/axis/src/manifest.json` | 占位 manifest（先注册不加载） |
| ADD | `packages/plugins/themes/axis/src/Layout.svelte` | 占位 Layout（Hello World） |
| ADD | `packages/plugins/themes/hello-world/manifest.json` | 验证主题 manifest |
| ADD | `packages/plugins/themes/hello-world/Layout.svelte` | 验证主题 Layout |
| MODIFY | `packages/web/src/App.svelte` | 缩为壳，引用 ThemeSwitcher + ThemeHost |
| MODIFY | `packages/web/vite.config.ts` | 增加 `@themes` alias |
| MODIFY | `packages/web/package.json` | 增加 workspace 依赖 `@workouts/theme-axis` |

### 验收标准

1. `pnpm dev` → 看到 Hello World 主题
2. ThemeRegistry.list() 返回 [hello-world]
3. 切换主题（未来）Layout 动态切换
4. `pnpm build` 通过
5. 现有 E2E 测试继续通过（或跳过过渡状态）

### 依赖

- Vite glob 导入支持
- pnpm workspace 协议

---

## Phase 2：overview 主题打包

**边界：** 将 `packages/web/src/lib/` 下现有组件原样搬迁至 `overview` 主题，App.svelte 缩为壳后行为完全不变。

### 搬迁清单

| 源 (`web/src/lib/`) | 目标 (`overview/src/components/`) | 依赖 |
|---|---|---|
| `MapView.svelte` | `MapView.svelte` | `polyline.ts`, `colorMode.ts` |
| `Drawer.svelte` | `Drawer.svelte` | — |
| `ActivityList.svelte` | `ActivityList.svelte` | `polyline.ts`, `colorMode.ts` |
| `DetailPanel.svelte` | `DetailPanel.svelte` | `polyline.ts`, `colorMode.ts` |
| `ChartOverlay.svelte` | `ChartOverlay.svelte` | — |
| `YearPicker.svelte` | `YearPicker.svelte` | — |
| `Filters.svelte` | `Filters.svelte` | — |

### 状态拆分

| 当前 (`web/src/lib/state.svelte.ts`) | 去向 |
|---|---|
| `theme` | 保留在 shell |
| `colorMode` | 移到 `overview/src/colorMode.ts` |
| `posterStyle` | 移到 `overview/src/store.ts` |
| `activities / stats / loading` | 保留在 shell（数据层） |
| `selectedYear / selectedMonth` | 移到 `overview/src/store.ts` |
| `drawerOpen / showCharts` | 移到 `overview/src/store.ts` |
| `selectedActivity / detailOpen` | 移到 `overview/src/store.ts` |
| `sortField / sortDesc / filters` | 移到 `overview/src/store.ts` |
| `mapHoveredId` | 移到 `overview/src/store.ts` |
| `years / availableTypes / availableSources / filteredActivities` | 移到 `overview/src/store.ts` |

Shell 保留：`theme`, `themeList`, `activeTheme`, `activities`, `stats`, `loading`。

### 删除清单（从 `web/src/`）

```
lib/MapView.svelte
lib/Drawer.svelte
lib/ActivityList.svelte
lib/DetailPanel.svelte
lib/ChartOverlay.svelte
lib/YearPicker.svelte
lib/Filters.svelte
lib/colorMode.ts
```

### 验证标准

1. `pnpm dev` → 默认加载 overview 主题 → UI 行为完全不变
2. 地图渲染、抽屉列表、详情面板、图表弹窗功能正常
3. 年份选择、筛选、排序、主题切换正常
4. 所有 E2E 测试通过

### 注意事项

- 搬迁时不改代码逻辑。纯搬运+改 import path
- `package.json` 中 overview 主题的依赖（leaflet, echarts）由 host 提供
- `polyline.ts` 留在 `shared/src/` 共享

---

## Phase 3：running_page 主题移植

**边界：** 将 yihong0618/running_page 的 React 组件移植为 Svelte，复用项目已有的 Leaflet/ECharts。

### React → Svelte 映射

| React 组件 | Svelte 映射 | 难度 | 说明 |
|---|---|---|---|
| `Layout/index.tsx` | `Layout.svelte` | 小 | 两栏 flex 布局，header + left(1/3) + right(2/3) |
| `Header/index.tsx` | `components/Header.svelte` | 小 | logo + nav + theme toggle |
| `YearsStat + YearStat` | `components/Sidebar.svelte` | 中 | 年份统计块列表，hover 加载 SVG |
| `RunMap` | `components/MapView.svelte` | 中 | 改 Leaflet，复用 polyline.ts |
| `RunTable + RunRow` | `components/ActivityTable.svelte` | 中 | 可排序表格，点击定位地图 |
| `ActivityList` | `components/VirtualGrid.svelte` | 大 | 虚拟滚动卡片网格，使用 rc-virtual-list 或自实现 |
| `ActivityCard` | `components/ActivityCard.svelte` | 中 | 统计数据 + Recharts → ECharts |
| `ActivityChart` | `components/ActivityChart.svelte` | 小 | ECharts BarChart |
| `RoutePreview` | `components/RoutePreview.svelte` | 中 | 纯 SVG 路线缩略图 |
| `SVGStat` | `components/SVGStat.svelte` | 小 | lazy load github.svg + grid.svg |
| `FilterBar` | `components/FilterBar.svelte` | 小 | sport type + interval 下拉 |
| `LocationStat` | `components/LocationStat.svelte` | 中 | China-specific 位置统计 |
| `Stat` | `components/Stat.svelte` | 小 | 复用统计数字展示 |

### CSS 变量映射

| running_page 变量 | overview 变量 | running_page 值 (dark) | 处理 |
|---|---|---|---|
| `--color-brand` | `--color-accent` | `#e0ed5e` | 主题 style.css 覆盖 |
| `--color-bg` | `--color-bg` | `#171717` | 覆盖 |
| `--color-tx` | `--color-text` | `#e0ed5e` | 覆盖 |
| `--color-hr` | `--color-border` | `#ef4444` | 覆盖 |
| `--color-activity-card` | — | `#404040` | 新增变量 |
| `--color-run-table-thead` | — | `#d4d4d4` | 新增变量 |
| `--svg-color-active-cell` | — | `#4dd2ff` | 新增变量 |

### 功能差异处理

| 功能 | running_page (React) | running_page (Svelte) |
|---|---|---|
| 地图引擎 | react-map-gl + Mapbox | Leaflet + CartoDB tiles |
| 路线渲染 | GeoJSON Source + LineLayer | L.polyline (复用 axis 做法) |
| 地图动画 | RouteAnimator (requestAnimationFrame) | Leaflet flyTo + polyline 逐步渲染 |
| 路线颜色 | useTheme hook → getRuntimeRunColor() | state.svelte.ts → colorMode.ts |
| 图表 | Recharts BarChart in ResponsiveContainer | ECharts BarChart（复用 ECharts.svelte） |
| 虚拟列表 | rc-virtual-list | 自实现或轻量依赖 |
| SVG lazy load | React.lazy + Suspense | Svelte 动态 import + {#await} |
| 路由 | React Router | $state view 切换 |
| 主题切换 | useTheme hook + data-theme attr | 复用 ThemeRegistry.apply() |

### 验证标准

1. 两栏布局正确渲染（左 1/3 + 右 2/3）
2. 左栏显示年份统计（或位置统计，根据 IS_CHINESE 模式）
3. 右栏显示地图，覆盖正确路线颜色
4. 表格点击 → 地图定位
5. 摘要视图卡片网格渲染正确
6. 卡片内 ECharts 柱状图正常
7. 主题 dark/light 切换

---

## Phase 4：测试 + SVG 前端化

**边界：** 补充 Phase 1-3 的测试覆盖，可选优化。

### 测试新增

| 测试范围 | 文件 | 工具 |
|---|---|---|
| ThemeRegistry | `web/src/lib/theme/registry.test.ts` | vitest |
| ThemeHost | `web/src/lib/theme/host.test.ts` | vitest (jsdom) |
| overview Layout | `web/tests/overview.test.ts` | Playwright (复用现有 E2E) |
| running_page Layout | `web/tests/running_page.test.ts` | Playwright |

### SVG 前端化（可选）

将 Ruby SVG 导出逐步移植到 `shared/src/styles/`，使主题可以在前端生成 SVG：

| Ruby 文件 | TypeScript 目标 | 优先级 |
|---|---|---|
| `github.rb` → `GithubDrawer` | `shared/src/styles/github.ts` | 中 |
| `grid.rb` → `GridDrawer` | `shared/src/styles/grid.ts` | 低 |
| `circular.rb` → `CircularDrawer` | `shared/src/styles/circular.ts` | 低 |
| `month_of_life.rb` → `MonthOfLifeDrawer` | `shared/src/styles/month-of-life.ts` | 低 |
| `year_summary.rb` → `YearSummaryDrawer` | `shared/src/styles/year-summary.ts` | 低 |

Phase 4 是持续维护阶段，不设硬性截止时间。

---

## Timeline 估算

| Phase | 文件数 | 预估工作量 |
|---|---|---|
| P1 | 8 新增 + 3 修改 | 1-2 天 |
| P2 | 10 新增 + 2 删除 | 2-3 天 |
| P3 | 15+ 新增 | 5-7 天 |
| P4 | 持续 | N/A |

总计约 8-12 天完成全部 3 个 Phase。

---

## 依赖关系图

```
P1 完成 → 可切换 hello-world 主题
  │
P2 完成 → 当前 UI 正常（overview = 现状）
  │
P3 完成 → running_page 主题可用
  │
P4 持续 → 测试 + SVG 前端化
```
