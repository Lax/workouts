# Workouts — 产品设计文档

运动数据聚合工具。多渠道同步 → SQLite → JSON/CSV/SVG 导出 → Svelte SPA 可视化。

---

## 1. 用户故事

| 角色 | 故事 |
|---|---|
| 运动者 | 作为多平台用户，我想要自动聚合 Keep / Garmin / Strava 等平台的运动记录，以便在统一视图中回顾全部运动历史。 |
| 数据拥有者 | 作为本地优先用户，我想要无厂商锁定的标准化导出格式，以便在任意工具中分析、存档、迁移。 |
| 浏览者 | 作为前端访客，我想要加载即用的可视化仪表盘，以便直观了解运动趋势、路线分布和统计摘要。 |

## 2. 场景

### A — 多渠道同步

**Actor:** 配置了凭证的 7 个数据源适配器（Keep / Garmin / Garmin CN / Strava / iGPSPORT / XOSS / XingZhe）

**流程：**
1. Runner 依次认证各源
2. Worker 池并行拉取增量活动
3. 每活动：fetch API → write raw → write L2 GPS → upsert DB
4. 全部完成后触发去重（dedup）

**预期：** 重复活动跳过，新活动入库，DSL 写入 trace。时间预算耗尽时优雅中止。

### B — 数据导出

**Actor:** CLI 用户

**流程：** 读 DB → 格式化 → 写文件

**预期：**
- JSON: 全字段活动数组，Svelte SPA 可直接消费
- Stats: 汇总 + 月度 + 年度统计
- SVG: 5 种风格（github/grid/circular/month-of-life/year-summary）
- Dashboard: 自包含 HTML（含 Leaflet + ECharts）
- CSV: 标准表格式

### C — 前端展示

**Actor:** 浏览器用户

**流程：**
1. 加载 `activities.json`（摘要，无 polyline）+ `stats.json`（并行）
2. 归一化字段名（`type` → `sport_category`，`polyline` → `summary_polyline`）
3. 即刻渲染抽屉列表 + 统计面板
4. 后台加载 `tracks.json`（`{ run_id: polyline }` 映射）
5. 合并 tracks → activities，渐进渲染地图路线

**预期：** 无 JS 错误，零等待，交互流畅。

### D — 交互

**Actor:** 前端用户

**行为：**
- 点击左侧年份 → 筛选当年活动
- 列表点击活动 → 详情面板（含 mini-map）
- 底部/右侧抽屉收起/弹出
- 速度/类型图例切换
- 🌓 主题切换（localStorage 持久化）

### E — 响应式

| 视口 | 布局 |
|---|---|
| ≥1024px | 地图全屏，抽屉右侧浮动，年份左侧垂直 |
| 640–1023px | 抽屉底部上滑，年份顶部水平 |
| <640px | 抽屉 body 55vh |

---

## 3. 需求

### 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| F1 | 支持 7 个运动平台的 OAuth/密码认证同步 | P0 |
| F2 | 多源去重（run_id 去重 → 置信度匹配 → 轨迹重叠判定） | P0 |
| F3 | 导出 JSON / CSV / Stats / Dashboard / SVG / GPX | P0 |
| F4 | SPA 地图路线渲染（Google Polyline 解码 + Leaflet） | P0 |
| F5 | 活动列表（排序、筛选、搜索、无限滚动） | P0 |
| F6 | 详情面板（字段展示 + mini-map） | P1 |
| F7 | ECharts 统计图表（月距离柱状图 + 类型分布饼图） | P1 |
| F8 | Light/Dark 双主题（localStorage + prefers-color-scheme） | P1 |
| F9 | 年份/月份选择过滤 | P1 |
| F10 | 速度/类型颜色模式切换 | P1 |
| F11 | 自适应同步周期（根据数据新鲜度自动调整 cron 间隔） | P2 |
| F12 | SVG 海报生成（5 种风格） | P2 |
| F13 | 三端 CLI + SPA 无后端依赖 | P0 |

### 非功能需求

| ID | 需求 | 度量 |
|---|---|---|
| NF1 | 同步时间预算内完成 7 源聚合 | 默认 30min 可配置 |
| NF2 | SPA 静态部署，零运行时 API | 纯文件服务 |
| NF3 | 构建制品 < 2MB（含 Leaflet + ECharts） | 当前 1.25MB JS + 26KB CSS |
| NF4 | 前端测试覆盖三层次 | L1 smoke + L2 unit + L3 E2E |
| NF5 | 字段名在 Ruby → JSON → Svelte 间一致 | `sport_category` / `summary_polyline` |

---

## 4. 设计决策

| 决策 | 选项 | 结论 | 理由 |
|---|---|---|---|
| 架构形态 | B/S vs 静态 CLI+SPA | **CLI 导出 + 静态 SPA** | 零后端运维，Pages 免费部署 |
| 前端框架 | React / Vue / Svelte 5 | **Svelte 5** | 编译期框架，bundle 小；`$state` / `$effect` 简洁 |
| 地图库 | Leaflet vs MapLibre | **Leaflet** | 轻量（39KB），CDN 免配置 |
| 图表库 | ECharts vs Chart.js | **ECharts** | 丰富交互，类型分布 + 月距离适合 |
| 包管理 | pnpm vs npm workspaces | **npm workspaces** | 零额外依赖，CI 预装 |
| 数据流 | API 网关 vs 静态 JSON | **静态 JSON** | fetch 本地文件，无跨域、无鉴权 |
| 主题方案 | CSS-in-JS vs CSS 变量 | **CSS 变量** | `[data-theme]` 切换，无运行时开销 |
| 样式方案 | Tailwind vs scoped CSS | **Scoped `<style>`** | Svelte 原生，零配置，类型安全 |
| DB 缓存 | 无 vs Actions Cache | **Actions Cache** | 跨 workflow 复用 DB 制品 |

见 CONTEXT.md `## 关键技术决策` 章节（约 20 项）及 `docs/frontend-arch-goal.md`。

---

## 5. 规格

### 数据模型

```sql
activities (
  id, run_id UNIQUE, name, distance, moving_time, elapsed_time,
  sport_category, sport_type, start_date, start_date_local,
  location_country, summary_polyline,
  average_heartrate, max_heartrate,
  average_cadence, max_cadence,
  average_power, max_power,
  average_temperature, calories, average_speed, elevation_gain,
  source, duplicate_info
)
```

### 导出 JSON 结构

见 `lib/workouts/export/json.rb` — `format_activity` 输出 21 字段。
Svelte `Activity` 接口定义于 `packages/shared/src/index.ts`。

### 适配器接口

```
authenticate → true/false
pending_ids → [{id:, type:, summary:}]
process_one → attrs hash / nil
```

### 前端组件树

```
App.svelte
├── MapView           — Leaflet 全屏地图 + polyline 渲染
├── .map-overlays     — brand / year-picker / legend-toggle / theme
├── Drawer            — 抽屉（handle + collapsed + body）
│   ├── ActivityList  — 排序筛选列表
│   └── Filters       — 类型/来源/距离/搜索
├── DetailPanel       — 活动详情 slide-up
└── ChartOverlay      — ECharts 月距离 + 类型分布
```

### 工作流

| 触发 | 工作流 | 产出 |
|---|---|---|
| schedule | sync.yml | 数据同步 + DB 缓存 |
| CI completed / sync 完成 | gh-pages.yml | 导出 + 构建 + Pages 部署 |
| push / PR | ci.yml | rspec + frontend test |

---

## 6. 验收

### 测试层

| 层 | 范围 | 工具 | 数量 |
|---|---|---|---|
| Ruby unit + integration | 同步适配器、导出、去重、CLI | RSpec | 483 |
| L1 Bundle smoke | Svelte bundle 无 `effect_orphan` | Node `new Function` | 1 |
| L2 Unit | 状态计算（filter/sort/compute） | Vitest | 16 |
| L3 E2E | SPA 加载、主题、列表、抽屉、详情 | Playwright | 5 |

### CI 门禁

```
ci.yml:     rspec → vitest → build → smoke → playwright
sync.yml:   sync → build → deploy (Ruby 全链路)
gh-pages.yml: cache DB → export → build → deploy
```

### 部署验证

```
https://liulantao.com/workouts/index.html            ← Svelte SPA
```
