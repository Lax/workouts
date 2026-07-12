# Workouts CLI — 项目设计文档

## 项目概述

运动数据聚合 CLI 工具，多渠道同步 → SQLite 数据库 → JSON / CSV / SVG 导出。

**仓库：** `github.com/Lax/workouts`（私有，付费计划）  
**技术栈：** Ruby 3.4 (Thor, Sequel, SQLite3, Nokogiri, Faraday) + Svelte 5 / TypeScript (npm workspaces, Vite, Leaflet, ECharts)  
**部署：** Docker / GitHub Actions / GitHub Pages

---

## CLI 命令

| 命令 | 说明 |
|---|---|
| `sync [--source S] [--act TYPE]` | 同步所有配置源（`--source` 指定单一源，`--act` 按运动类型过滤） |
| `dedup` | 全源重跑去重匹配（覆盖已有 duplicate_info） |
| `auth <garmin\|garmin_cn>` | 交互式 Garmin SSO 登录 |
| `export json [--output]` | 导出 JSON |
| `export csv [--output]` | 导出 CSV |
| `export svg --style <style>` | 生成 SVG 海报（5 种风格） |
| `export stats [--output]` | 导出统计摘要 |
| `export gpx [--output]` | 从 L2 文件重新导出 GPX |
| `export all` | 执行所有导出 |
| `migrate igpsport_to_garmin [--limit]` | 上传 iGPSPORT 数据至 Garmin |
| `migrate igpsport_to_garmin_cn [--limit]` | 上传 iGPSPORT 数据至 Garmin CN |
| `db migrate` | 运行数据库迁移 |
| `parse <file.gpx\|file.tcx> [--save]` | 解析本地 GPX/TCX 文件，可选写入 DB |
| `init` | 生成默认 config.yml |
| `version` | 版本号 |

---

## CLI 文件结构

```
lib/workouts/cli.rb              # 主 CLI（Workouts::CLI），加载子模块
lib/workouts/cli/export.rb       # 导出子命令（ExportCLI: json, csv, svg, all）
lib/workouts/cli/sync.rb         # 同步子模块（sync, auth, dedup）
lib/workouts/sync/runner.rb      # Sync::Runner — 队列调度 + Worker 池
lib/workouts/dedup/
  matcher.rb                     # Dedup::Matcher — 置信度计算
  trajectory.rb                  # Dedup::Trajectory — GPS 轨迹重叠判定
  service.rb                     # Dedup::Service — 滑动窗口匹配 + 双向写入
```

---

## 架构

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Strava      │     │  Sync::Runner    │     │ Export::SVG │
│ Garmin      │────▶│  Worker Pool × N │────▶│ Export::JSON│
│ Keep        │     │  Source Queue    │     │ Export::CSV │
│ iGPSPORT    │     │  Output Queue    │     └─────────────┘
│ XOSS (xoss) │     └────┬──────────┬──┘
│ XingZhe     │          │          │
└─────────────┘          │          └───▶ data/raw/{source}/
                         │               (原始 GPS 点阵备份, 每源独立 GH Cache)
                         ▼
                     ┌──────────────────┐
                     │   SQLite DB      │
                     │  (Sequel ORM)    │
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Dedup::Service  │
                     │   Matcher        │
                     │   Trajectory     │
                     └──────────────────┘
```

---

## 关键技术决策

| 决策 | 原因 |
|---|---|
| 默认使用系统代理（`HTTP_PROXY`/`HTTPS_PROXY`） | 不再强制绕过代理，XOSS/XingZhe 可通过代理访问中国境内服务 |
| 内联 deploy job 而非 reusable workflow | 调用 `uses:` 在该仓库导致 `startup_failure` |
| `__` 分隔 env var | 避免与 `garmin_cn` 等 key 中的 `_` 冲突 |
| 保留 `upload-artifact` | Pages 部署稳定后再移除 |
| Keep 用摘要数据 | Keep API 不提供 FIT，iGPSPORT 使用 mini_racer + @garmin/fitsdk 解析 FIT |
| `data/raw/{source}/` 平面目录 | 与 running_page `GPX_OUT/` 兼容，symlink 级桥接 |
| Keep raw 存 decrypt JSON | 保留原始 HR 序列和相对时间戳，polyline 生成可重跑 |
| 统一列表：new_ids + missing_raw | 一次 API 调用完成 summary + raw，省 50% API 开销 |
| 时间预算在循环顶部 break | 避免写了 summary 但没写 raw 的不一致状态 |
| 多源并行使用队列调度 | Runner 启动 N 线程 Worker 池（默认 3），类 1 队列每 source 单元素即为分布式锁。Worker pop = acquire lock，push = release。批量 BATCH_SIZE=5 后交还，减少竞争 |
| 超时采用旗标机制 | `@timed_out` 设后不再 pop 新源，但当前 batch 完整收尾。不强制退出，数据一致 |
| DedupService 独立于 adapter | 所有 source 完成后统一触发，不再绑定 Strava 内部 `recheck_duplicates`。双向写入，含轨迹对比 |
| temp→rename 原子写入 raw 文件 | 崩溃恢复时 `raw_file_exists?` 不误判 |
| Per-source 独立 GH Cache | 每源独立 cache key (`workouts-raw-v1-{source}-{run_id}`)，通过 `scripts/source-digest.sh` 计算内容 md5 检测变化，仅变动的源写 cache。通过 `.github/actions/sources-cache/restore` + `sources-cache/save` 封装。数据目录示例: `data/raw/{garmin,garmin_cn,igpsport,...}/`, `data/std/{...}/` |
| 导出默认路径 `data/` → `build/` | 源数据与生成制品分离，gitignored |
| `mini_racer` + `@garmin/fitsdk` 解析 FIT | V8 引擎在 Ruby 进程中执行 JS SDK，纯 gem 依赖，无需外部运行时 |

---

## 同步适配器

### 数据源

| 适配器 | 源域名 | 认证 | 特点 |
|---|---|---|---|
| **Keep** | api.gotokeep.com | 手机+密码 | AES-128-CBC 解密，zlib 解压，GCJ-02→WGS84，HR 最近匹配 |
| **iGPSPORT** | prod.zh.igpsport.com | 手机+密码 | FIT 原始格式，使用 mini_racer + @garmin/fitsdk 解析 |
| **XOSS** | backend.xoss.co (国际版) | email+JWT | FIT 下载 + mini_racer/fitsdk 解析，JWT token 缓存 7d |
| **XingZhe** | imxingzhe.com (行者) | RSA 加密密码 + session Cookie | 行者国内版 |
| **Garmin CN** | garmin.cn | SSO + OAuth1→OAuth2（不受 CF 影响）| token 文件持久化 + OAuth1 自动 refresh，GH Cache |
| **Garmin Intl** | garmin.com | DI OAuth2（Playwright primary — session cookies 365d, curl_cffi fallback）| Playwright session cookies 365d, token GH Cache，MFA 首次后零交互 |
| **Strava** | strava.com | OAuth2 refresh_token | 已配置，含多源去重检测 |

### 数据源标识

`run_id` 格式为 `{source_prefix}_{平台ID}`（如 `garmin_12345`、`strava_98765`）。每个源有独立的 L1/L2 文件目录：

| 适配器 | `source_prefix` | L1 `raw_dir` | L2 `std_dir` |
|---|---|---|---|
| Keep | `keep` | `data/raw/keep/` | `data/std/keep/` |
| iGPSPORT | `igpsport` | `data/raw/igpsport/` | `data/std/igpsport/` |
| XOSS | `xoss` | `data/raw/xoss/` | `data/std/xoss/` |
| XingZhe | `xingzhe` | `data/raw/xingzhe/` | `data/std/xingzhe/` |
| Garmin Intl | `garmin` | `data/raw/garmin/` | `data/std/garmin/` |
| Garmin CN | `garmin_cn` | `data/raw/garmin_cn/` | `data/std/garmin_cn/` |
| Strava | `strava` | `data/raw/strava/` | `data/std/strava/` |

每源通过 `scripts/source-digest.sh` 计算内容 md5 作为 digest，用于 CI cache 的变更检测。restore 阶段写入 `data/.source-digests`（统一快照文件），sync 后比对，仅 digest 变化时写回 cache。

### Adapter 接口

每个 adapter 实现三个公共方法，供 Runner 或单源 CLI 调用：

| 方法 | 返回值 | 说明 |
|---|---|---|
| `authenticate` | `true/false` | 登录 / 刷新 token。在 `pending_ids` 前调用，共享 `@access_token` / `@session` 状态 |
| `pending_ids` | `[{id:, type:, summary:}]` | 预拉列表 + 过滤 existing + `skip_type?`。`summary` 保存列表 API 响应，供 `process_one` 使用 |
| `process_one(pending)` | `attrs hash / nil` | 单活动完整流程：fetch detail → write raw → write std → upsert DB |

`call` 方法委拖为 `authenticate + pending_ids.filter_map { \|p\| process_one(p) }.size`，保持单源 CL I 兼容。

### 数据流程

#### 单源模式（`--source`）

```
同步前:
  1. 检查凭证是否存在
  2. 认证（登录 / 刷新 token）

同步中:
  3. pending_ids: 分页拉列表 + 过滤 existing + skip_type
  4. process_one 逐活动: API → write raw → write std → upsert DB

同步后:
  5. 计算新鲜度 f → 调整 cron 间隔
```

#### 多源模式（默认）

```
初始化（串行）:
  source 依次: 检查凭证 → authenticate → pending_ids → 入类 1 队列

并行调度:
  Worker 池(默认 3 线程) 循环:
    pop 类 1 队列 → source           [acquire 分布式锁]
    处理最多 BATCH_SIZE=5 活动:
      shift pending_ids[source]
      process_one                   [独占 source，无竞态]
    还有剩余? → push 回队列           [release 锁]
    已完成? → completion -1
    全部完成? → push POISON

扫尾:
  worker.join → 输出队列线程 join
  Dedup::Service.run               [全源去重]
```

### 去重机制

#### 一级去重：`run_id`

基于 `run_id` 字段（格式：`{source}_{platform_id}`），每次同步前读取 DB 中已有 ID 列表，跳过完全重复的活动。这是第一道防线，防止同一活动的重复导入。

#### 二级去重：`Dedup::Service`

所有 source 同步完成后由 Runner 触发，与具体 adapter 解耦。算法跨全源滑动窗口匹配：

**窗口分组：** 按 start_date 排序，5 分钟滑动窗口内两两比较

**置信度因子（`Dedup::Matcher`）：**

| 因子 | 权重 | 条件 |
|---|---|---|
| 时间相近度 | 35% | 开始时间差 ≤ 5min |
| 距离相近度 | 35% | 距离差 ≤ 较大值的 15% |
| 时长相近度 | 15% | 运动时长差 ≤ 较大值的 15% |
| 运动类型匹配 | 15% | 同类型 +15%，不同类型 -10% |

**轨迹分类（`Dedup::Trajectory`）：**

读取 L2 标准化 GPS 文件，默认每 10 点采样一个，检查采样点中 ≥ 30% 在对方轨迹 50m 范围内。此分类覆盖全等、包含、大重叠三种重复轨迹情形。

**分类体系（4 种 flag）：**

| flag | 含义 | 条件 |
|---|---|---|
| `derived` | 极可能是同一活动 | 置信度 ≥ 0.85 |
| `duplicate` | 轨迹高度重叠的重複活动 | 置信度 ≥ 0.15 + GPS 采样重叠 ≥ 30% |
| `similar` | 相似但不是同一活动 | 置信度 ≥ 0.15 + 无轨迹重叠 |
| `overlap` | （旧数据兼容，保留） | — |

**双向写入：** 匹配结果同时写入双方活动的 `duplicate_info` 列（JSON 数组）：

```json
[{"source": "strava", "run_id": "strava_123", "confidence": 0.92, "flag": "derived"}]
```

SVG 导出时，标注上区分 derived（高置信度合并）、duplicate（轨迹重叠）和 similar（低置信度重叠），鼠标悬停显示匹配来源和评分。

---

### Garmin OAuth 认证机制

详见 [docs/garmin-auth.md](docs/garmin-auth.md)

### Garmin Intl vs CN 目录/标识隔离

两个 Garmin 源共享 `GarminBase`，通过子类覆写隔离文件目录和 DB 标识：

| 属性 | Intl (`Garmin`) | CN (`GarminCN`) |
|---|---|---|
| `raw_dir` | `data/raw/garmin/` | `data/raw/garmin_cn/` |
| `std_dir` | `data/std/garmin/` | `data/std/garmin_cn/` |
| `source_prefix` → `run_id` | `garmin_#{id}` | `garmin_cn_#{id}` |
| DB `source` | `"garmin"` | `"garmin_cn"` |

`source_prefix` 方法定义在 `GarminBase`（返回 `"garmin"`），`GarminCN` 覆写返回 `"garmin_cn"`。
`build_attrs` 通过 `source_prefix` 生成 `run_id` 和 `source`，确保 DB 层无冲突。

---

## 数据库

### Schema

```sql
CREATE TABLE activities (
  id           INTEGER PRIMARY KEY,
  run_id       TEXT NOT NULL UNIQUE,        -- "{source}_{平台ID}"
  name         TEXT,
  distance     REAL,                        -- 米
  moving_time  INTEGER,                     -- 秒
  elapsed_time INTEGER,
  sport_category TEXT NOT NULL DEFAULT 'run',-- run/ride/hike/walk/swim/ski/workout/other
  sport_type   TEXT,                        -- 平台原始类型
  start_date   TEXT,                        -- 起始时间
  start_date_local TEXT,
  location_country TEXT,
  summary_polyline TEXT,                    -- Google Polyline 编码
  average_heartrate REAL,                   -- bpm
  max_heartrate REAL,                       -- bpm
  average_cadence REAL,                     -- rpm
  max_cadence REAL,                         -- rpm
  average_power REAL,                       -- watts
  max_power REAL,                           -- watts
  average_temperature REAL,                 -- °C
  calories INTEGER,                         -- kcal
  average_speed REAL,                       -- m/s
  elevation_gain REAL,                      -- m
  source       TEXT,                        -- 来源标识
  duplicate_info TEXT,                      -- 去重匹配信息（JSON 数组）
  created_at   DATETIME,
  updated_at   DATETIME
);
```

---

## 配置体系

### 配置层级（优先级：高→低）

1. 环境变量 `` SYNC__{SOURCE}__KEY ``（`__` 双下划线分隔层级）
2. `` config/config.yml ``（自动加载）
3. `` Config::DEFAULTS `` 硬编码默认值

### 环境变量命名

```
SYNC__KEEP__PHONE       → sync.keep.phone
SYNC__GARMIN_CN__EMAIL  → sync.garmin_cn.email
SYNC__GARMIN__AUTH_SEED → sync.garmin.auth_seed
SYNC__STRAVA_CLIENT_ID  → sync.strava.client_id
SYNC__TIME_BUDGET       → sync.time_budget           # 全局 sync 配置
SYNC__WORKERS           → sync.workers               # 并行 worker 数，默认 3
```

`__` 作为层级分隔符 → key 自身可含单 `_`（如 `garmin_cn`）

### GitHub Variables

| 变量 | 作用 | 切换命令 |
|---|---|---|
| `vars.RUNNER_LABEL` | 控制 sync job 的 `runs-on`。默认 `ubuntu-latest`；设 `self-hosted` 切本地 runner，setup 步骤自动跳过 | `gh variable set RUNNER_LABEL --body self-hosted` |

### GitHub Secrets 命名

Secrets 名用单 `_`（`SYNC_KEEP_PHONE`），Workflow env 块映射为 `SYNC__KEEP__PHONE`。

---

## SportMapper

三层回退链：

```
输入 → ① ALIASES（精确匹配表）
     → ② KEYWORDS（正则/子串匹配）
     → ③ Levenshtein（编辑距离 ≤ 3）
     → ④ "other"
```

- 精确别名：`running` → `run`, `cycling` → `ride`
- 关键词：`mountaineering` → `hike`, `jogging` → `run`
- Levenshtein：`swiming` → `swim`, `runing` → `run`

各适配器保留自己的整数 SPORT_MAP（平台特有 code 体系不可统一）。

---

## 自适应同步周期

```
workflow: 每日触发 (cron: 0 2 */N * *)

f = 最新活动距今天数

f < N    → N = max(1, N-1)    → 加速
f > 2N+1 → N = min(7, N+1)    → 减速
其余     → N 不变

仅 schedule 事件写回 cron，workflow_dispatch 不改
```

---

## CI/CD

### ci.yml

| 触发 | 操作 |
|---|---|
| push/PR → main | `bundle exec rspec` + 语法检查 |
| Ruby 版本 | 3.2 / 3.3 / 3.4 |

### sync.yml

| 触发 | 操作 |
|---|---|
| schedule `*/N` (自适应) | 同步 + 构建 + 部署 Pages |
| workflow_dispatch | 手动触发，不改 cron |
| `vars.RUNNER_LABEL` | 控制 runner 类型。默认 `ubuntu-latest`；设 `self-hosted` 切本地 |

### jobs

```
sync job (runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}):
  1. checkout
  2. setup Ruby + bundle (if: vars.RUNNER_LABEL != 'self-hosted')
  3. restore DB cache
  4. record DB digest
  5. restore Garmin token caches
  6. restore per-source caches (sources-cache/restore)
  7. workouts sync (受 SYNC__TIME_BUDGET 限制)
  8. 读 N → 算 f → 可能改 cron
  9. check DB changed
  10. save DB cache + Garmin token caches
  11. save per-source caches (sources-cache/save)
  12. upload DB artifact (for build job)

build job (needs: sync):
  1. checkout + setup Ruby + setup Node
  2. download DB artifact
  3. create build/ dir
  4. export json → build/activities.json
  5. export svg → build/svg/github.svg
  6. validate SVG
  7. export stats → build/stats.json
  8. Svelte build (npm run build)
  9. copy Svelte dist → build/ (index.html + assets/)
  10. upload build artifact

deploy job (needs: build):
  1. download build artifact
  2. upload-pages-artifact from ./build
  3. deploy-pages@v4
```

### archive.yml

将 GH Actions cache 中的 raw/std 数据归档到独立 git branch。

| 触发 | 操作 |
|---|---|
| schedule `0 6 * * 0` (每周日) | 每源 cache restore → `git add -A` → rename 检测 → 排除纯删除 → commit → push to `data/_/<source>` |
| workflow_dispatch | 手动触发 |

详见 [docs/archive-impl.md](docs/archive-impl.md)。

#### 归档分支

`data/_/<source>` — matrix 并发，per-source orphan branch。仅含 `data/{raw,std}/<source>/`，绕过 cache 7 天 LRU，保留全部历史快照（不删除）。

## 部署

### Docker

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export svg --style github
docker compose run --rm workouts export json
```

数据卷：`./data:/app/data`

### GitHub Pages

| 项 | 值 |
|---|---|
| Pages 源 | GitHub Actions |
| 自定义域名 | liulantao.com |
| URL | `https://liulantao.com/workouts/` |
| 部署目录 | 仅 JSON + SVG，排除 DB |

---

## 数据架构

详见 [docs/data-architecture.md](docs/data-architecture.md)

L1 raw → L2 标准化 GPS → L3 SQLite 摘要 → L4 构建制品 → L5 部署。
转换规则: 坐标归一化、时间归一化、不丢字段。
每个新源必须实现 L1+L2+L3。

---

## 前端架构

### monorepo 结构

```
packages/
  shared/             # TypeScript：Activity 类型、格式化、SportMapper、categoryColor
  svelte-echarts/     # ECharts wrapper 组件（workspace-only）
  svelte-leaflet/     # Leaflet wrapper 组件（workspace-only）
  web/                # Svelte 5 SPA — 主力前端
    src/
      app.css                 # CSS 变量（light/dark 双主题）
      main.ts                 # 入口 — mount App
      App.svelte              # 根组件：数据加载、地图 overlay（brand/year/legend/theme）
      lib/
        state.svelte.ts       # 全局状态 ($state) + 计算函数
        Drawer.svelte         # 底部/右侧抽屉（handle+collapsed+body）
        MapView.svelte        # Leaflet 地图 + 路线渲染
        ActivityList.svelte   # 活动列表
        ChartOverlay.svelte   # ECharts 图表（月距离 + 类型分布）
        DetailPanel.svelte    # 详情面板（带 mini-map）
        Filters.svelte        # 筛选面板
        YearPicker.svelte     # 年份选择器
        colorMode.ts          # 速度/类型配色
        polyline.ts           # Google Polyline 解码
    tests/
      build-smoke.js          # L1 bundle 烟雾测试
      state.test.ts           # L2 状态单元测试
      fixtures/activities.ts  # 测试夹具生成器
      e2e/spa.spec.ts         # L3 Playwright E2E
    public/                   # 静态文件：dev 用 fixture JSON
    scripts/
      generate-fixtures.mjs   # JS fixture 生成器（无 Ruby 环境时的 fallback）
```

### 数据流

```
Ruby export (JSON) → packages/web/public/ (dev)
                              → build/ (prod via gh-pages.yml)
                                        ↓
                              fetch('activities.json') + fetch('stats.json')
                                        ↓
                              App.svelte — 归一化 type→sport_category
                                        ↓
                              state.svelte.ts ($state + $effect)
                                        ↓
                              组件：MapView / Drawer / ChartOverlay / DetailPanel
```

### 字段名约定

| 前端优先字段 | Ruby 导出字段 | 说明 |
|---|---|---|
| `sport_category` | `type` | App.svelte 归一化：`a.type && !a.sport_category` → copy |
| `summary_polyline` | `summary_polyline` | — |
| `sport_type` | `sport_type` | JSON 导出旧版本写 `subtype`，前端无消费 |

### 层级 (z-index)

| z-index | 元素 |
|---|---|
| 0 | Map container |
| 1 | Map overlays (brand, year picker, legend, theme) |
| 2 | Drawer |
| 3 | Detail panel |
| 4 | Chart overlay |

### 响应式断点

| 断点 | 行为 |
|---|---|
| ≥1024px | Drawer 右侧浮动面板，handle 隐藏，collapsed 48px 统计条 |
| <1024px | Drawer 底部上滑，handle 16px 横条 + collapsed 34px 统计区 |
| ≤640px | Drawer body 55vh |

### 测试分层

| 层 | 工具 | 内容 |
|---|---|---|
| L1 Bundle smoke | Node `new Function()` | 捕获 `effect_orphan` |
| L2 Unit | vitest | 纯函数：computeYears, computeFilteredActivities, computeAvailableTypes |
| L3 E2E | Playwright | 加载、主题、列表、抽屉、详情面板 |

### CI/CD

- **ci.yml**: push/PR → rspec + frontend test job (vitest → build → smoke → playwright)
- **sync.yml**: schedule → sync data → build + deploy (Ruby 全程)
- **gh-pages.yml**: push/PR 或 sync 完成后 → cache DB → export → build → deploy Pages

## 文档架构

### 文档分类

每一个需求产出一组文档，共享前缀，后缀区分类型：

| 类型 | 后缀 | 编写方式 | 内容 |
|---|---|---|---|
| 目标文档 | `-goal` | 用户主笔，AI 辅助 | 功能定义、验收标准、边界划分 |
| 调研文档 | `-research` | 共同编写 | 技术调研历史、方案对比、关键决策依据 |
| 实现文档 | `-impl` | 开发过程产出 | 遇到的问题、解决方案、注意事项、变更记录 |

**命名示例：** `garmin-auth-goal.md` / `garmin-auth-research.md` / `garmin-auth-impl.md`

> 已有文档（`data-architecture.md`, `garmin-auth.md`）保持原名不动，新增文档按此规范命名。

### 编写原则

文档给人看也给 AI 看。

| 原则 | 说明 |
|---|---|
| 术语一致 | 代码 / 注释 / docs/ / CONTEXT.md 用同一组词。避免同义替换 |
| 显式引用 | 跨文件引用写完整路径。不写"详见上节" |
| 结构化 > 段落 | 表格 / 列表 > 自然段。AI 解析表格比段落可靠 |
| 约定写出来 | `__` 分隔符、`SOURCE` 占位符含义、OAuth 术语，在注释里写清 |
| 文件锚点 | 每个 `docs/` 文件以 `# <feature> — <summary>` 开头 |
| 不列测试数量 | 文档中不出现测试用例数量、耗时等数字。测试相关仅写 `测试（全 stub、零网络）` |
| 测试不用 rm_rf | Spec 不得用 `FileUtils.rm_rf` 删除生产目录。用 `Dir.mktmpdir` 管理临时文件 |
| 不重复 OAuth | OAuth token 管理集中在 `Auth::GarminToken`，其他类不得包含 OAuth 客户端逻辑 |

## 错误消息约定

每条 actionable 错误消息必须包含两个要素：

| 要素 | 格式 | 示例 |
|---|---|---|
| 问题描述 | `<层级>: <失败原因>` | `Garmin: auth_seed decode failed — invalid Base64` |
| 操作指引 | `  <动>: <命令>` | `  Fix: ./scripts/garmin_auth_local.sh --sync` |

规则：
1. 错误不吞 — 每层至少输出一行描述，`rescue` 不加原因视为 bug
2. 操作命令可直接复制粘贴执行（先写 `Fix:`/`Re-auth:`/`Run:` 动词）
3. `sync` count==0 时报 `warn`（黄色），不报 `done`（绿色），避免误认为成功
4. 区分过期类型 — HTTP 400 是数据过期（refresh_token 旋转），HTTP 401 是权限吊销（client_id）
