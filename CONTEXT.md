# Workouts CLI — 项目设计文档

## 项目概述

运动数据聚合 CLI 工具，多渠道同步 → SQLite 数据库 → JSON / CSV / GPX 导出。

**仓库：** `github.com/Lax/workouts`（私有）  
**技术栈：** Ruby 3.4（核心逻辑在 git-fit gem）  
**部署：** GitHub Actions / GitHub Pages（数据制品：JSON + stats + 前端主题）

> 本仓库是配置 + CI/CD 壳，核心逻辑全部在 git-fit gem。设计/调研/实现细节见 wiki（文末指针表），本文件只留规则与现状摘要。

---

## CLI 命令

| 命令 | 说明 |
|---|---|
| `git fit sync [--source S] [--act TYPE]` | 同步所有配置源（`--source` 指定单一源，`--act` 按运动类型过滤）|
| `git fit dedup` | 全源重跑去重匹配（覆盖已有 duplicate_info）|
| `git fit import [--source S] [--sport S]` | 从本地目录批量导入 GPX/FIT/TCX/Apple Health |
| `git fit export [json\|csv\|stats\|gpx]` | 导出 JSON/CSV/统计/GPX |
| `git fit auth <garmin\|garmin_cn\|strava>` | 交互式 auth（xoss/xingzhe 在 sync 时自动认证，见 [git-fit auth-model](https://github.com/Lax/git-fit/wiki/specs/auth-model.md)）|
| `git fit db SUBCOMMAND` | 数据库操作 |
| `git fit geo SUBCOMMAND` | 地理行政区域检测 |
| `git fit parse <file.gpx\|file.tcx> [--save]` | 解析 GPX/TCX |
| `git fit init` | 生成默认 config.yml |
| `git fit version` | 版本号 |

---

## 架构

```
┌──────────────────────────────────────────────┐
│  git fit (git-fit gem)                       │
│  sync / import / export / dedup / db / geo   │
└────────────────────┬─────────────────────────┘
                     ▼
              ┌─────────────┐
              │  SQLite DB  │  (Sequel ORM)
              └─────────────┘
```

## 关键技术决策（现状摘要；完整历史表见 wiki Architecture「关键决策」）

| 决策 | 原因 |
|---|---|
| 默认使用系统代理（`HTTP_PROXY`/`HTTPS_PROXY`） | 不再强制绕过，XOSS/XingZhe 可经代理访问境内服务 |
| cron 管理拆独立 `sync-scheduler.yml` | 唯一写 `.github/workflows/*.yml` 的工作流，唯一持有 `WORKOUTS_SYNC_PAT`（workflows:write）；sync.yml 无 PAT |
| sync-scheduler 用 persist-credentials:false + bare PAT extraheader + git-auto-commit-action | PAT 不能传给 `actions/checkout`（会被包装 `x-access-token:` → GitHub App 路由）；`workflows: write` 不是有效 permissions 值 |
| `GIT_FIT_` 前缀 env var | 避免与 `garmin_cn` 等 key 中的 `_` 冲突 |
| 导出默认路径 `data/` → `site/` | 源数据与生成制品分离，gitignored |
| Keep 用摘要数据；iGPSPORT/XOSS 用 mini_racer + @garmin/fitsdk 解析 FIT | Keep API 不提供 FIT；纯 gem 依赖无外部运行时 |
| Per-source 独立 GH Cache | 每源独立 key（`GitFit-data-{source}-v0-{run_id}`），SHA256SUMS 检测变更仅写变动源 |
| 多源并行队列调度 + 超时旗标 + DedupService 独立 | 均已迁移 git-fit gem |

---

## 同步适配器

> 已迁移 git-fit gem（`git fit sync`），本地无 adapter 类。`run_id` = `{source_prefix}_{平台ID}`；每源 L1/L2 目录 = `data/{raw,std}/{source_prefix}/`。

| 源 | `source_prefix` | 认证 | 特点 |
|---|---|---|---|
| Keep | `keep` | 手机+密码 | AES-128-CBC 解密，zlib 解压，GCJ-02→WGS84，HR 最近匹配 |
| iGPSPORT | `igpsport` | 手机+密码 | FIT 原始格式，mini_racer+fitsdk 解析 |
| XOSS | `xoss` | email+JWT | FIT 下载 + fitsdk 解析，JWT 缓存 7d |
| XingZhe | `xingzhe` | RSA 密码 + session Cookie | 行者国内版 |
| Garmin CN | `garmin_cn` | SSO + OAuth1→OAuth2 | token 文件持久化 + OAuth1 自动 refresh |
| Garmin Intl | `garmin` | DI OAuth2（`--auto`：策略 B Playwright primary / 策略 A curl-impersonate fallback） | session cookies 365d，MFA 首次后零交互 |
| Strava | `strava` | OAuth2 refresh_token | 原始文件下载：`git fit strava fetch`（stravaweblib gem） |

**去重**：一级 `run_id` 去重；二级跨全源滑动窗口（5 分钟）时间/距离/时长/类型四因子 + 轨迹采样重叠（`Dedup::Trajectory`），输出 derived/duplicate/similar 写 `duplicate_info`。详见 wiki Dedup。

## 导入适配器

> 已迁移 git-fit gem（`git fit import`）。文件放 `data/import/{gpx,fit,tcx,apple_health,2bulu}/`，目录不存在跳过；run_id 内容哈希去重，单文件失败继续；无网络/认证，不做二级去重。

| 适配器 | 格式 | 要点 |
|---|---|---|
| Apple Health | export.zip (XML+GPX) | 心率 HKQuantityTypeIdentifierHeartRate 关联，自动跳过已知源；ZIP magic-byte 校验 |
| LocalFile GPX/FIT/TCX | .gpx/.fit/.tcx | sport 分别从 GPX/XML Sport / FIT session mesg 提取；多 track/Activity → 多活动 |
| 2bulu | .2tk + .kml | Parser 双格式直读（native binary 保留分段成绩 + TbuluKmlVersion2）；WGS-84 无需纠偏；run_id `2bulu_{YYYYMMDD}_{sha[0,12]}`；官方赛道 KML 不入统计 |

## Garmin Intl vs CN 隔离

两源共享 `GarminBase`，子类覆写隔离目录/标识（`GarminCN` 覆写 `source_prefix` → `"garmin_cn"`）：

| 属性 | Intl | CN |
|---|---|---|
| `raw_dir`/`std_dir` | `data/{raw,std}/garmin/` | `data/{raw,std}/garmin_cn/` |
| `run_id` / DB `source` | `garmin_#{id}` / `"garmin"` | `garmin_cn_#{id}` / `"garmin_cn"` |

---

## 数据库

```sql
CREATE TABLE activities (
  id INTEGER PRIMARY KEY, run_id TEXT NOT NULL UNIQUE,  -- "{source}_{平台ID}"
  name TEXT, distance REAL,        -- 米
  moving_time INTEGER, elapsed_time INTEGER,            -- 秒
  sport_category TEXT NOT NULL DEFAULT 'run',           -- run/ride/hike/walk/swim/ski/workout/other
  sport_type TEXT, start_date TEXT, start_date_local TEXT,
  location_country TEXT, summary_polyline TEXT,         -- Google Polyline
  average_heartrate REAL, max_heartrate REAL,           -- bpm
  average_cadence REAL, max_cadence REAL,               -- rpm
  average_power REAL, max_power REAL,                   -- watts
  average_temperature REAL, calories INTEGER,
  average_speed REAL, elevation_gain REAL, elevation_loss REAL,
  elevation_min REAL, elevation_max REAL, steps INTEGER,
  source TEXT, duplicate_info TEXT,                     -- 去重信息（JSON 数组）
  created_at DATETIME, updated_at DATETIME
);
```

---

## 配置体系

### 层级（高→低）

1. 环境变量 `GIT_FIT_*` → 2. `config.yml`（根目录；`GIT_FIT_CONFIG_PATH` 覆盖）→ 3. git-fit 默认值

### 环境变量命名

`GIT_FIT_` 前缀 + key（大写+下划线），单 `_` 分隔（`garmin_cn` 保留原样）。例：`GIT_FIT_KEEP_PHONE → sync.keep.phone`、`GIT_FIT_SYNC_TIME_BUDGET → sync.time_budget`、`GIT_FIT_CONFIG_PATH → config 路径`。

### 环境变量文件约定

| 文件 | 入库 | 内容 |
|---|---|---|
| `.env` | 提交 | 配置选项（非敏感），镜像 GitHub Variables |
| `.env.local` | gitignore | 本地凭据，覆盖 `.env` |
| `.env.local.example` | 提交 | 模板；CI 对应 Secrets（`SYNC_*`） |

加载：`set -a; source .env; source .env.local; set +a`（无自动加载器）。

### GitHub Variables / Secrets

| 变量 | 作用 |
|---|---|
| `vars.RUNNER_LABEL` | `runs-on`：默认 `ubuntu-latest`，设 `self-hosted` 切本地 runner |
| `vars.GIT_FIT_DATABASE_PATH` | SQLite 路径（默认 `data/db/workouts.db`）|
| `vars.SYNC_TIME_BUDGET` / `SYNC_TOTAL_TIMEOUT` | 单次 sync 时间预算 / Runner 总超时 |

Secrets 名单 `_`（`SYNC_KEEP_PHONE`），sync.yml 经 `.github/actions/sync-activities` 映射为 `GIT_FIT_*` env。DB 路径单一真值 = `GIT_FIT_DATABASE_PATH`，全部 workflow 经 `db-store/paths@v1` 推导 `dir/name/db-path`。

### 前端站点配置（config.json）

> 与 `config.yml`（运行配置）语义隔离；由 `frontend-build@v1` 传给 `git-fit-web build --config`。

```json
{
  "entries": { "index": "timeline", "stats": "stats", "about": "hello-world" },
  "plugins": { "@lax/plugin-nav": {} },
  "site": { "nav": { "labels": { "index": "时间线", "stats": "统计", "about": "关于" } } },
  "data": {
    "stats": { "source": "stats.json", "optional": false },
    "activities": { "source": "activities.json", "optional": true },
    "tracks": { "source": "tracks.json", "optional": true },
    "races": { "source": "races.json", "optional": true }
  },
  "events": [],
  "themes": { "timeline": { "site": { "title": "时间线" }, "events": [] } }
}
```

- `entries`：key → `${key}.html`，value = themeId → `@lax/theme-${themeId}`
- `plugins`：站点级插件（web-build 生成 import 注入 bootstrap，全 entry 生效）
- `site.nav`：`false` 禁用，`labels` 覆盖默认标签；两级解析 `themes.<id>.site.<field>` > `site.<field>` > 内置 fallback
- `events` / `themes.<id>.events`：手动赛事，三层 merge（见下）

---

## 前端架构

**包**（`Lax/git-fit-web` → GitHub Packages `@lax/*`，0.0.x）：`shared`（类型/格式化/geo）/ `core`（bootstrap+registry+SiteNav host）/ `web-build`（CLI）/ `plugin-data-source`（useStats/useActivities）/ `plugin-nav` / `theme-hello-world` / `theme-stats` / `theme-timeline`。详见 wiki Frontend-Architecture 与 git-fit-web README。

**运行机制**：`bootstrap(config,{theme,plugins})` 依次 setup 插件 `registerComponent`；`config.plugins` 由 entry shim 注入；core `SiteNav` host 无条件挂载读 entries，plugin-nav 只供纯视图（单向依赖）。

**theme-timeline**：竖直月时间轴 + 右侧多列卡片（`minmax(260px,1fr)`，轨迹 SVG 背景，hover 推近 / 选中 Ken Burns）+ 左侧 380px 面板（总览卡 + IO 滚动联动月份；点卡片切详情标签页，详情含总览顶部轨迹缩略图 + 5 组语义卡片、轨迹交互地图）。性能：渐进加载（先摘要后 tracks）+ 轨迹共享 observer 懒加载（进视口才解码）+ `RouteBgSVG` `requestIdleCallback` + `MapLRU100` 缓存 + `Douglas-Peucker 0.0001` 简化（15044→167 点，`@lax/shared sideEffects:false` tree-shaking 已验证，DOM 真实视口 <5000）+ 固定卡高三态卡片（border/text/detail，150ms settled）。即时跳转 + 一帧校正 + C 位落点（`monthScroll.ts`），轨迹交互地图支持 wheel 缩放/drag 平移/双击重置 + `stroke-dasharray` 2s 绘制（`prefers-reduced-motion` 禁用）+ 起点/终点标记。hash `#a=<run_id>` / `#m=<month>` / `#v=<view>` 深链。

**全项目时间规则**（`theme-timeline/src/time.ts`）：
1. `start_date_local` 带偏移 → 墙上钟 `slice`（发生地时间，无 TZ 转换）
2. 无偏移/仅 UTC → 浏览器本地时区解析
3. 仍无法确定 → 东八区（`Asia/Shanghai`）

**赛事数据管道**：newbie.run `races.yml`（17 场）+ `_data/races/*` 定义 → `scripts/migrate_races.rb` 一次性迁移 → `data/events/races.json`（git 追踪）；gh-pages `jq -c` 压缩到 site/。三层 merge：`themes.timeline.events` > `events` > races.json（同 id 字段覆盖）；`activityLocalDate === event.date` 全天匹配。

---

## SportMapper

> 已迁移 git-fit gem。三层回退：ALIASES 精确 → KEYWORDS 正则 → Levenshtein（≤3）→ `"other"`。各适配器保留平台 SPORT_MAP。

## 自适应同步周期

```
sync.yml schedule (0 2 */N, 0 14 */N)；sync-scheduler 数据变更触发 / 每周日保底
f = 最新活动距今天数
f < N    → N = max(1, N-1)     加速（依赖数据更新触发）
f > 2N+1 → N = min(7, N+1)     减速（每周日保底）
其余 → N 不变；手动 dispatch 默认 commit=false
```

## CI/CD

| workflow | 触发 | 作用 |
|---|---|---|
| `ci.yml` | push/PR → master | actionlint + `bundle exec rspec`（Ruby 3.4 matrix）|
| `sync.yml` | schedule `*/N` + dispatch | 同步 + 缓存 + 数据变更触发 scheduler/gh-pages |
| `sync-scheduler.yml` | 数据变更 + 每周日保底 | 读 N → 算 f → sed 改 sync.yml cron（唯一写 workflow 的持有 PAT）|
| `gh-pages.yml` | CI 成功后 deploy | export json/stats → stage races.json → `frontend-build` → deploy-pages |
| `git-fit-archive.yml` | 每周日 | cache → `GitFit/data/<source>` + `GitFit/db` orphan 分支（LRU 兜底）|

**关键事实**：DB cache 恢复用 `db-store/cache/restore@v1`（`git-restore-mode: fallback` 从 `GitFit/db` git archive 兜底）+ `save@v1`（job 成功且 changed 时 push 回）；缓存 key 纪律（`-v0-sentinel` restore / `-v0-snapshot` unarchive，严禁合并）；data-store/db-store/geo-detect/import 均 pin 大版本 tag，默认分支 `mainline`。完整步骤见 `.github/workflows/*.yml` 与 wiki CI-CD。

**Step summary 约定**（git-fit-actions 写 action 时）：`### GitFit <action> <operation>` 标题；状态 cell 前缀 `✅/⏭️/❌`；横向表型、短值居中长文本左对齐。详见 wiki CI-CD。

## 部署

| 项 | 值 |
|---|---|
| Pages 源 | GitHub Actions |
| URL | `https://lax.github.io/workouts/` |
| 数据制品 | `activities.json` / `tracks.json` / `stats.json` / `races.json`（排除 DB）|
| 前端页面 | `index.html`（timeline）/ `stats.html`（stats）/ `about.html`（hello-world）|
| 独立前端 | `https://lax.github.io/running/`（Lax/running running_page 看板）|

## 数据架构

L1 raw → L2 标准化 GPS → L3 SQLite 摘要 → L4 构建制品 → L5 部署。转换：坐标/时间归一化、不丢字段；新源必须实现 L1+L2+L3。详见 wiki Architecture。

## 文档架构

`docs/` 已归档至 [wiki](https://github.com/Lax/workouts/wiki)（主题索引 [Home](https://github.com/Lax/workouts/wiki)），仓库内不再维护 `docs/`。每个需求产出一组文档，共享前缀：`-goal`（功能定义/验收）/ `-research`（调研/方案对比）/ `-impl`（实现记录）。编写原则：术语一致、显式引用（完整路径/wiki URL）、结构化（表格 > 段落）、约定写出来、文件锚点 `# <topic> — <summary>`、不列测试数量、测试不用 `rm_rf`、OAuth 逻辑集中在 `Auth::GarminToken`。

## 错误消息约定

每条 actionable 错误消息含两要素：

| 要素 | 格式 | 示例 |
|---|---|---|
| 问题描述 | `<层级>: <失败原因>` | `Garmin: auth_seed decode failed — invalid Base64` |
| 操作指引 | `  <动>: <命令>` | `  Fix: git fit auth garmin --sync` |

规则：错误不吞（`rescue` 不加原因视为 bug）；命令可复制粘贴（`Fix:`/`Re-auth:`/`Run:`）；`sync` count==0 报 `warn` 不报 `done`；区分 HTTP 400（数据过期/refresh_token 旋转）vs 401（权限吊销/client_id）。

---

## Wiki 指针表

| 页面 | 内容 |
|---|---|
| [Home](https://github.com/Lax/workouts/wiki) | 主题索引 |
| [Architecture](https://github.com/Lax/workouts/wiki/Architecture) | 产品设计、数据架构、**关键决策完整表** |
| [Sources](https://github.com/Lax/workouts/wiki/Sources) | 数据源适配与字段标准 |
| [Sync](https://github.com/Lax/workouts/wiki/Sync) | 同步进度展示 |
| [Auth](https://github.com/Lax/workouts/wiki/Auth) | Garmin OAuth |
| [CI-CD](https://github.com/Lax/workouts/wiki/CI-CD) | workflow/action 基建与 Step summary 约定 |
| [Dedup](https://github.com/Lax/workouts/wiki/Dedup) | 跨源去重设计 |
| [Geo](https://github.com/Lax/workouts/wiki/Geo) | 地理区域检测 |
| [Testing](https://github.com/Lax/workouts/wiki/Testing) | 测试改进 |
| [Frontend-Architecture](https://github.com/Lax/workouts/wiki/Frontend-Architecture) | 前端包/主题/构建/发布流程 |
