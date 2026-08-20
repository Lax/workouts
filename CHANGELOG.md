# Changelog

> 核心逻辑（sync / import / export / dedup / db / geo / parse）已迁移至 git-fit gem，本仓库仅保留配置与 CI/CD。下述条目中标注「git-fit」的已迁移，详细实现见 git-fit 仓库。

## 2026-08 — footprint 主题视觉定稿

| Item | Status |
|---|---|
| theme-footprint 0.0.1 接入（全屏足迹地图 + 左侧抽屉列表/筛选/图表覆层） | ✅ 已完成 |
| theme-footprint 0.0.2：锐利高对比红橙轨迹（Steplife 风格，`plugin-ui-map` edge+core 双线，暗色 edge `#ff3b30` + core `#ff9f0a`，亮色 edge `#c41e3a` + core `#f97316`，统一配色，无 ride 区分/无白点/无 star；`workouts` 升级至 `^0.0.2`） | ✅ 已完成 |
| plugin-ui-map 0.0.4：双线 polyline 渲染 + 深浅色板支持（`workouts` 升级至 `^0.0.4`） | ✅ 已完成 |

## 2026-08 — thin-shell 迁移

| Item | Status |
|---|---|
| 薄壳彻底移除：删除 `exe/workouts` + `lib/`（workouts.rb/cli.rb/version.rb）+ `spec/cli/`，全命令直接用 `git fit`（auth 旗标逐一对齐） | ✅ 已完成 |
| 部署三件套移除：删除 Dockerfile + docker-compose.yml + .dockerignore + Makefile + workouts-cli.gemspec，Gemfile 改为独立声明 git-fit 依赖。仓库成为纯配置 + CI/CD 壳 | ✅ 已完成 |
| workouts-cli 剥为薄壳：删除 sync/auth/fit/db/export 本地实现，`auth`/`db`/`geo`/`init`/`parse` 委托 git-fit | ✅ 已完成 |
| Garmin 认证迁移至 `git fit auth garmin`（-A/-B/--auto/--sync/--mfa-code），Python 脚本删除（git-fit #66） | ✅ 已完成 |
| `git fit auth garmin` 默认策略改为 `--auto`（B primary / A fallback） | ✅ 已完成 |
| XingZhe session cookie 跨 CI 持久化（git-fit 0.11.1） | ✅ 已完成 |
| per-source 独立 GH Cache（`GitFit-data-{source}-v0-{run_id}`，data-store@v2），废弃 `workouts-raw-v1-*` | ✅ 已完成 |
| sync 纯 cache-only：`shall-commit-data/db` 移除，`git-fit-archive.yml` 每周归档到 `GitFit/data/*` + `GitFit/db` 分支 | ✅ 已完成 |
| 缓存 key 命名纪律（restore 用 `-v0-sentinel`，unarchive 用 `-v0-snapshot`，严禁合并，git-fit#51） | ✅ 已完成 |
| DB git 兜底与回写（db-store v1.0.2）：restore `git-restore-mode: fallback` + save `save-to-git-branch`，cache miss 时从 `GitFit/db` 恢复、job 成功时 push 回（移入 action，修复 baseline 误报 changed） | ✅ 已完成 |
| DB 路径管理单位改为目录（db-store v1.1.0）：`db-dir` + `db-name` 替代 `database-path`，新增 `db-store/paths` 推导 `dir/name/db-path`，sync / gh-pages / sync-scheduler / archive / unarchive 统一引用 `steps.db-paths.outputs.*`（git restore 目录级、db-name 防路径穿越） | ✅ 已完成 |
| 前端包体系引入（`@lax/*` 发布至 GitHub Packages，`Lax/git-fit-web`）：core（bootstrap/registry/`useComponent`）+ shared + web-build + plugin-data-source + theme-hello-world，workouts 经 `frontend-build` 部署自有主题 | ✅ 已完成 |
| theme-stats 统计看板（八区块：现状焦点/高光卡/四面板趋势/年度/月度/YoY 热力图/构成/坚持度，URL hash 同步 + 深浅色板；月度年份头部） | ✅ 已完成 |
| 全站浮动导航（core `SiteNav` host 无条件挂载 + plugin-nav 纯视图，`config.plugins` shim 注入，`site.nav` 两级解析 labels/false） | ✅ 已完成 |
| theme-timeline 纵向时间线主题 0.0.1（竖直月时间轴 + 月度活动卡片 + 左侧统计/详情双态面板 + 赛事匹配；赛事数据 newbie.run 一次性迁移 → `data/events/races.json`，gh-pages `jq -c` 压缩；全项目时间规则=活动发生地时间三级回退） | ✅ 已完成 |
| theme-timeline 0.0.2（渐进加载/月份 IO 懒挂载/骨架屏首屏提速；卡片多列网格 `minmax(260px,1fr)`；左栏 380px + 详情单列防溢出；月份切换视觉强化；卡片 hover 轨迹推近 + 选中 Ken Burns 循环） | ✅ 已完成 |

## 2026-08 — 详情面板与性能优化

| Item | Status |
|---|---|
| Backfill 修复 Strava/iGPSPORT/Keep naive datetime（`scripts/backfill_keep_time.rb` + `backfill.yml`，幂等 0 更新） | ✅ 已完成（#28） |
| 数据层 max_power / avg_max_power（git-fit 0.14.3→0.15.0，plugin-data-source 0.0.5→0.0.6，theme-timeline 0.0.22 / theme-stats 0.0.10 双功率指标） | ✅ 已完成 |
| RouteBgSVG `requestIdleCallback` + `MapLRU100` 缓存（theme-timeline 0.0.23，#24） | ✅ 已完成 |
| `@lax/shared` `sideEffects:false` tree-shaking 验证（index 35.9k/gzip11.4k，haversine/geo-boundaries 0 打包，#25） | ✅ 已完成 |
| DOM 节点评估（100/200/500 真实视口 388/488/788 <5000，#26） | ✅ 已完成 |
| Douglas-Peucker 0.0001 简化 15044→167 点（theme-timeline 0.0.24，#27） | ✅ 已完成 |
| DetailPanel 优化：总览顶部轨迹缩略图 + 5 组语义卡片（表现/心肺·功率/节奏/地形/环境，补 elevation_loss/min/max/steps）+ 轨迹交互地图（RouteMap: wheel/drag/双击重置，`stroke-dasharray` 2s，起终点标记，`prefers-reduced-motion` 禁用，theme-timeline 0.0.25） | ✅ 已完成 |

## 2026-07 — 数据链路与 CI 基建

| Item | Status |
|---|---|
| 目录树哈希检测 Apple Health / 2bulu 导入数据变化（`.github/git-fit-actions/import`，JS action，`sources` 一次性传入） | ✅ 已完成 |
| 2bulu（两步路）.2tk / .kml 导入（git-fit 0.12.0） | ✅ 已完成 |
| Geo 区域检测（`git fit geo detect`，AMap + Nominatim，content-hash cache key） | ✅ 已完成 |
| Apple Health export.zip 导入（心率关联，跳过已知源） | ✅ 已完成 |
| LocalFile 三格式导入（GPX / FIT / TCX，单类适配器） | ✅ 已完成 |
| Garmin 国际版 DI OAuth2（Playwright 策略 B primary + curl-impersonate 策略 A fallback，session cookie 365d） | ✅ 已完成（git-fit） |
| 数据导出路径 `data/` → `site/`（源数据与制品分离） | ✅ 已完成 |
| 多源去重检测（Dedup::Service，四因子置信度 + 轨迹重叠） | ✅ 已完成（git-fit） |
| SportMapper 三层回退（ALIASES → KEYWORDS → Levenshtein → other） | ✅ 已完成（git-fit） |
| mini_racer + @garmin/fitsdk 解析 FIT（Keep / iGPSPORT / XOSS） | ✅ 已完成（git-fit） |
| Keep 解密 pipeline（AES-128-CBC + zlib + GCJ-02→WGS84，raw 存 decrypt JSON） | ✅ 已完成（git-fit） |
| GitHub Pages 数据制品部署（json + stats，前端已迁 [Lax/running](https://github.com/Lax/running)） | ✅ 已完成 |

## 历史（pre 迁移，实现已迁 git-fit）

| Item | Status |
|---|---|
| L1/L2/L3 三层数据架构（raw → std JSON → SQLite 摘要） | ✅ 已完成 |
| GitHub Pages 部署 + 3-job workflow（sync / build / deploy） | ✅ 已完成 |
| 原始数据 GH Cache（替代 submodule） | ✅ 已完成 |
| Strava OAuth2 自动 refresh + 原始文件下载（stravaweblib，`git fit strava fetch`） | ✅ 已完成 |
| 配置 env 前缀 `GIT_FIT_*`（与 git-fit gem 一致） | ✅ 已完成 |
