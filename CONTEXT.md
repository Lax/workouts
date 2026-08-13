# Workouts CLI — 项目设计文档

## 项目概述

运动数据聚合 CLI 工具，多渠道同步 → SQLite 数据库 → JSON / CSV / GPX 导出。

**仓库：** `github.com/Lax/workouts`（私有，付费计划）  
**技术栈：** Ruby 3.4（核心逻辑在 git-fit gem）
**部署：** GitHub Actions / GitHub Pages（数据制品：JSON + stats）

---

## CLI 命令

| 命令 | 说明 |
|---|---|
| `git fit sync [--source S] [--act TYPE]` | 同步所有配置源（`--source` 指定单一源，`--act` 按运动类型过滤）|
| `git fit dedup` | 全源重跑去重匹配（覆盖已有 duplicate_info）|
| `git fit import [--source S] [--sport S]` | 从本地目录批量导入 GPX/FIT/TCX/Apple Health |
| `git fit export [json\|csv\|stats\|gpx]` | 导出 JSON/CSV/统计/GPX |
| `git fit auth <garmin\|garmin_cn\|strava>` | 交互式 auth（`auth xoss/xingzhe` 被 git-fit 否决：sync 时自动认证，见 [git-fit auth-model](https://github.com/Lax/git-fit/wiki/specs/auth-model.md)）|
| `git fit db SUBCOMMAND` | 数据库操作 |
| `git fit geo SUBCOMMAND` | 地理行政区域检测 |
| `git fit parse <file.gpx\|file.tcx> [--save]` | 解析 GPX/TCX |
| `git fit init` | 生成默认 config.yml |
| `git fit version` | 版本号 |

---

## 架构

本地仓库是配置与 CI/CD 壳，核心逻辑全部在 git-fit gem：

```
┌─────────────────────────────────────────────────────────┐
│  git fit (git-fit gem)                                  │
│  sync / import / export / dedup / db / geo / parse      │
│  init / strava / gh / install / auth                    │
└────────────────────────┬────────────────────────────────┘
                         │
                ┌────────▼─────────┐
                │   SQLite DB      │
                │  (Sequel ORM)    │
                └──────────────────┘
```

---

## 关键技术决策

| 决策 | 原因 |
|---|---|
| 默认使用系统代理（`HTTP_PROXY`/`HTTPS_PROXY`） | 不再强制绕过代理，XOSS/XingZhe 可通过代理访问中国境内服务 |
| 内联 deploy job 而非 reusable workflow | 调用 `uses:` 在该仓库导致 `startup_failure` |
| cron 管理拆为独立 `sync-scheduler.yml` | 唯一写 `.github/workflows/*.yml` 的工作流，集中持有 `WORKOUTS_SYNC_PAT`（workflows:write）。sync.yml 不再需要 PAT，import action 的 store-state push（SHA256SUMS 回 `GitFit/import/*` 分支）改用默认 GITHUB_TOKEN |
| sync-scheduler 用 persist-credentials:false + bare PAT extraheader + git-auto-commit-action | 不能将 PAT 传给 `actions/checkout`（会被包装为 `x-access-token:` → GitHub App 路由）。`workflows: write` 不是 `permissions:` 块的有效值，无法通过 YAML 声明。改用 `persist-credentials: false` + 手动写入裸 PAT extraheader（不含 `x-access-token:` 前缀），服务器路由为 PAT，token 自带 `repo` 权限含 workflows:write。commit/push 交给 `stefanzweifel/git-auto-commit-action@v7`，复用 bare PAT extraheader 凭据 |
| `__` 分隔 env var（已迁移至 git-fit，本地 config.rb 已删） | 避免与 `garmin_cn` 等 key 中的 `_` 冲突。CI 已改用 `GIT_FIT_` 前缀 env |
| 保留 `upload-artifact` | Pages 部署稳定后再移除 |
| Keep 用摘要数据 | Keep API 不提供 FIT，iGPSPORT 使用 mini_racer + @garmin/fitsdk 解析 FIT |
| `data/raw/{source}/` 平面目录 | 与 running_page `GPX_OUT/` 兼容，symlink 级桥接 |
| Keep raw 存 decrypt JSON | 保留原始 HR 序列和相对时间戳，polyline 生成可重跑 |
| 统一列表：new_ids + missing_raw | 一次 API 调用完成 summary + raw，省 50% API 开销。**（已迁移至 git-fit）** |
| 时间预算在循环顶部 break | 避免写了 summary 但没写 raw 的不一致状态。**（已迁移至 git-fit）** |
| 多源并行使用队列调度 | Runner 启动 N 线程 Worker 池（默认 3），类 1 队列每 source 单元素即为分布式锁。Worker pop = acquire lock，push = release。批量 BATCH_SIZE=5 后交还，减少竞争。**（已迁移至 git-fit）** |
| 超时采用旗标机制 | `@timed_out` 设后不再 pop 新源，但当前 batch 完整收尾。不强制退出，数据一致。**（已迁移至 git-fit）** |
| DedupService 独立于 adapter | 所有 source 完成后统一触发，不再绑定 Strava 内部 `recheck_duplicates`。双向写入，含轨迹对比。**（已迁移至 git-fit）** |
| temp→rename 原子写入 raw 文件 | 崩溃恢复时 `raw_file_exists?` 不误判 |
| Per-source 独立 GH Cache | 每源独立 cache key（`GitFit-data-{source}-v0-{run_id}`），变更检测由 `git-fit-actions/data-store/cache/save@v2.1.2` 内联 `find \| sort \| xargs sha256sum` 计算 SHA256SUMS（无仓库脚本），仅变动的源写 cache。通过 `git-fit-actions/data-store/cache/{restore,save}@v2.1.2` 直连（`sources` 多源循环；save 输出 `changed`/`changed_sources`/`unchanged_sources`/`save_errors` 到 step outputs（GITHUB_OUTPUT），并写 step summary 块）。数据目录示例: `data/raw/{garmin,garmin_cn,igpsport,...}/`, `data/std/{...}/` |
| 导出默认路径 `data/` → `site/` | 源数据与生成制品分离，gitignored |
| `mini_racer` + `@garmin/fitsdk` 解析 FIT | V8 引擎在 Ruby 进程中执行 JS SDK，纯 gem 依赖，无需外部运行时 |
| local_file 适配器单类处理三种格式 | GPX/FIT/TCX 共享相同的文件扫描、L1/L2写入、DB upsert 逻辑，仅解析器不同。单类避免三份重复代码。**（已迁移至 git-fit）** |

---

## 同步适配器

> **同步适配器已迁移至 git-fit gem（`git fit sync`）。** 本地仓库无 adapter 类。以下保留设计摘要。

### 数据源

| 适配器 | 源域名 | 认证 | 特点 |
|---|---|---|---|
| **Keep** | api.gotokeep.com | 手机+密码 | AES-128-CBC 解密，zlib 解压，GCJ-02→WGS84，HR 最近匹配 |
| **iGPSPORT** | prod.zh.igpsport.com | 手机+密码 | FIT 原始格式，使用 mini_racer + @garmin/fitsdk 解析 |
| **XOSS** | backend.xoss.co (国际版) | email+JWT | FIT 下载 + mini_racer/fitsdk 解析，JWT token 缓存 7d |
| **XingZhe** | imxingzhe.com (行者) | RSA 加密密码 + session Cookie | 行者国内版 |
| **Garmin CN** | garmin.cn | SSO + OAuth1→OAuth2（不受 CF 影响）| token 文件持久化 + OAuth1 自动 refresh，GH Cache |
| **Garmin Intl** | garmin.com | DI OAuth2（默认 `--auto`：策略 B Playwright primary — session cookies 365d；策略 A curl-impersonate fallback）| Playwright session cookies 365d, token GH Cache，MFA 首次后零交互 |
| **Strava** | strava.com | OAuth2 refresh_token | 已配置，含多源去重检测。原始文件（FIT/GPX/TCX）下载已迁移至 git-fit：`git fit strava fetch`（stravaweblib gem） |

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
| GPX (导入) | `gpx` | `data/raw/gpx/` | `data/std/gpx/` |
| FIT (导入) | `fit` | `data/raw/fit/` | `data/std/fit/` |
| TCX (导入) | `tcx` | `data/raw/tcx/` | `data/std/tcx/` |

每源变更检测由 `git-fit-actions/data-store/cache/save@v2.1.2` 内联 SHA256SUMS 完成：restore 阶段恢复每源目录，save 阶段通过 `sha256sum -c` 逐源校验，仅变化的源写回 cache。

### Adapter 接口与调度

> 已迁移至 git-fit gem（`git fit sync`），详见 git-fit 仓库。同步适配器继承 `Sync::Base`，实现 `authenticate` / `pending_ids` / `process_one`；Runner 用队列调度 Worker 池（默认 3 线程）+ BATCH_SIZE=5 分派。

### 去重机制

> 已迁移至 git-fit gem（`Dedup::Service`），所有 source 完成后统一触发。

- **一级去重**：`run_id`（`{source}_{platform_id}`），每次同步前读 DB 已有 ID 跳过重复
- **二级去重**：跨全源滑动窗口匹配（5 分钟窗口），时间/距离/时长/类型四因子置信度 + GPS 轨迹采样重叠（`Dedup::Trajectory`），输出 derived/duplicate/similar 写入 `duplicate_info`

---

## 导入适配器

> **已迁移至 git-fit gem。** 以下保留设计摘要。

### 数据源

| 适配器 | 源格式 | 认证 | 特点 |
|---|---|---|---|
| **Apple Health** | export.zip (XML + GPX) | 无 | 从 iOS 健康导出 zip 解析，心率从 HKQuantityTypeIdentifierHeartRate 关联，自动跳过 Strava/Keep/Garmin 等已知源。CI 经 `git-fit-actions/import@v1` action 从 `GitFit/import/apple_health` 分支拉取，检测机制用目录树哈希（`git ls-tree -r` + 过滤标志文件 + sha256sum）编码的 data_hash，精确判断数据文件内容变化。下载后对 `export.zip` 做 ZIP magic-byte 校验（`isZipArchive`，替代旧 composite 的 `file \| grep "Zip archive"`），LFS smudge 漏出或内容损坏即抛错——避免 `git fit import` 内部 rescue 后 exit 0 导致永久误跳。SHA256SUMS 保留用于跨 cache 恢复和快速校验 |
| **LocalFile (GPX)** | .gpx 文件 | 无 | 扫描 `data/import/gpx/`，sport_category 默认 "other"，`--sport` 覆盖。多 track → 多活动 |
| **LocalFile (FIT)** | .fit 文件 | 无 | 扫描 `data/import/fit/`，sport 从 FIT session mesg 提取（通过 decoder.js fitSport）。FIT 纪元时间戳 |
| **LocalFile (TCX)** | .tcx 文件 | 无 | 扫描 `data/import/tcx/`，sport 从 XML Sport 属性提取。多 Activity → 多活动 |
| **2bulu (KML + 2tk)** | .2tk + .kml 文件 | 无（本地导入） | 扫描 `data/import/2bulu/`。Parser 双格式直读：.2tk（native binary，保留分段成绩 sportinfo）+ .kml（TbuluKmlVersion2）。坐标 WGS-84 无需 GCJ-02 纠偏。run_id 用 `2bulu_{YYYYMMDD}_{sha[0,12]}`（日期前缀排序 + 内容哈希去重，规避 trackFileId 冲突）。CI 经 `git-fit-actions/import@v1` action 从 `GitFit/import/2bulu` 分支拉取，检测机制用目录树哈希（`git ls-tree -r` + 过滤标志文件 + sha256sum）编码的 data_hash，精确判断数据文件内容变化。SHA256SUMS 保留用于跨 cache 恢复和快速校验。**官方赛道 KML 不入导入统计**（参考轨迹功能另行规划）。详情见 `~/checkouts/mine/2bulu-research/` 与 [git-fit#67](https://github.com/Lax/git-fit/issues/67) |

### 数据流与差异

> 已迁移至 git-fit gem（`git fit import`）。文件放 `data/import/{gpx,fit,tcx,apple_health,2bulu}/`，目录不存在时跳过不报错。单线程顺序处理，run_id 用内容哈希去重（内容不变自动跳过），单文件失败打印错误继续下一文件。导入无需网络/认证，不做二级去重。

---

### Garmin OAuth 认证机制

详见 wiki [Auth](https://github.com/Lax/workouts/wiki/Auth)

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

1. 环境变量 `GIT_FIT_*`（与 git-fit gem 一致，见 `git fit init` 模板）
2. `` config.yml ``（仓库根目录，git-fit 默认读取；`GIT_FIT_CONFIG_PATH` 显式覆盖路径）
3. git-fit 代码内默认值

### 环境变量命名

```
GIT_FIT_KEEP_PHONE        → sync.keep.phone
GIT_FIT_GARMIN_CN_EMAIL   → sync.garmin_cn.email
GIT_FIT_GARMIN_AUTH_SEED  → sync.garmin.auth_seed
GIT_FIT_STRAVA_CLIENT_ID  → sync.strava.client_id
GIT_FIT_SYNC_TIME_BUDGET  → sync.time_budget           # 全局 sync 配置
GIT_FIT_SYNC_WORKERS      → sync.workers               # 并行 worker 数，默认 3
GIT_FIT_CONFIG_PATH       → config 文件路径             # 默认 config.yml（根目录）
```

前缀 `GIT_FIT_` 后跟 key（大写 + 下划线），单 `_` 分隔（如 `garmin_cn` 保留原样）。
`GIT_FIT_CONFIG_PATH` 为显式覆盖项，默认即根目录 `config.yml`，通常无需设置。

### GitHub Variables

| 变量 | 作用 | 切换命令 |
|---|---|---|
| `vars.RUNNER_LABEL` | 控制 job 的 `runs-on`。默认 `ubuntu-latest`；设 `self-hosted` 切本地 runner（docker compose 模式） | `gh variable set RUNNER_LABEL --body self-hosted` |

### GitHub Secrets 命名

Secrets 名用单 `_`（`SYNC_KEEP_PHONE`），sync.yml 经 `.github/actions/sync-activities` 映射为 `GIT_FIT_KEEP_PHONE` 等 env 传给 `git fit sync`。

---

## SportMapper

> **已迁移至 git-fit gem。** 三层回退链：① ALIASES 精确匹配 → ② KEYWORDS 正则/子串 → ③ Levenshtein（编辑距离 ≤ 3）→ ④ `"other"`。`Parser::Base#normalize_sport_type` 统一委托 `SportMapper.canonicalize`，各适配器保留自己的整数 SPORT_MAP（平台特有 code 体系不可统一）。

---

## 自适应同步周期

```
sync.yml:       schedule (cron: 0 2 */N * *, 0 14 */N * *)
sync-scheduler: workflow_dispatch (sync.yml 数据/DB 变更时触发, commit=true)
                schedule (0 3 * * 0 每周日保底, 覆盖减速分支)

f = 最新活动距今天数

f < N    → N = max(1, N-1)    → 加速
f > 2N+1 → N = min(7, N+1)    → 减速
其余     → N 不变

加速分支依赖数据更新（数据变更触发 sync-scheduler）；减速分支只在
数据不更新时发生（f 增长），由 sync-scheduler 自带的每周日 schedule
保底触发。手动 workflow_dispatch 默认 commit=false 不写回。
```

---

## CI/CD

### ci.yml

| 触发 | 操作 |
|---|---|
| push/PR → master | 2 jobs：`workflow-lint`（actionlint@v2 校验 workflow 语法，shellcheck: false）、`ruby-test`（`bundle exec rspec`） |
| Ruby 版本 | matrix `ruby-version: ["3.4"]` |

### sync.yml

| 触发 | 操作 |
|---|---|
| schedule `*/N` (自适应) | 同步 + 缓存 + 数据变更时触发 sync-scheduler / gh-pages |
| workflow_dispatch | 手动触发同步，不改 cron |
| `vars.RUNNER_LABEL` | 控制 runner 类型。默认 `ubuntu-latest`；设 `self-hosted` 切本地（docker compose 模式） |

### sync-scheduler.yml

| 触发 | 操作 |
|---|---|
| workflow_dispatch（sync.yml `gh workflow run`，数据/DB 变更时） | 读 N → 算 f → sed 改 sync.yml cron → commit+push（commit=true 时） |
| schedule `0 3 * * 0`（每周日，保底） | 同上。覆盖减速分支（f > 2N+1 需在数据不更新时触发） |
| workflow_dispatch（手动） | 读 N → 算 f，默认不写回（commit=false） |

sync-scheduler 是唯一写 `.github/workflows/*.yml` 的工作流，因此唯一持有 `WORKOUTS_SYNC_PAT`（workflows:write）。sync.yml 已移除 PAT，import action 的 store-state push（SHA256SUMS 回 `GitFit/import/*` 分支）改用默认 GITHUB_TOKEN。

### jobs

```
sync job (runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}):
  1. checkout (默认 GITHUB_TOKEN)
  2. setup Ruby + bundle
  3. derive DB paths (db-store/paths@v1.2.2 — 单一真值 GIT_FIT_DATABASE_PATH → dir/name/db-path，供后续所有 DB 路径引用)
  4. restore DB cache (db-store/cache/restore@v1.2.2, db-dir + db-name, git-restore-mode: fallback — cache miss 时从 GitFit/db 分支兜底恢复，输出 git-restored-bytes + save-to-git-branch)
  5. Import data (git-fit-actions/import@v1.0.1, sources: apple_health,2bulu, 目录树哈希检测 + store-state push)
  6. restore per-source caches (data-store/cache/restore@v2.1.2)
  7. Sync activities (sync-activities action — 内含 git fit sync 受 vars.SYNC_TIME_BUDGET / SYNC_TOTAL_TIMEOUT 限制 + git fit strava fetch --limit 10 continue-on-error)
  8. save per-source caches (data-store/cache/save@v2.1.2)
  9. Parse Geo Regions (git-fit-actions/geo-detect@v1.0.2, detect-limit 200)
  10. [db] Checkpoint SQLite WAL
  11. git-save-gate（if: success()，job 成功时透传 restore 的 save-to-git-branch）
  12. save DB cache (db-store/cache/save@v1.2.2, db-dir + db-name, save-to-git-branch 透传 — job 成功 + changed 时 push 回 GitFit/db)
  13. 数据/DB 变更时触发 sync-scheduler.yml (commit=true)
  14. upload DB artifact
  15. 数据/DB 变更时触发 gh-pages deploy
```

> **2026-08 issue #11（已发布）：** data-store/db-store 的 step summary 已发布（`data-store@v2.1.2`、`db-store@v1.2.2`，geo-detect `@v1.0.2`、import `@v1.0.1` 标题/格式对齐），本地 vendor 副本已删除。workflows 全部 pin 小版本 tag（大版本 tag 未移动）。本地开发阶段曾临时 vendor 到 `.github/git-fit-actions/` 并切本地引用，发布后已还原。

### Step summary 约定

> 所有 summary block 一律 action/step 级标题，不写 workflow 级标题（Actions 页面已提供 workflow/job 上下文）。

| 项 | 约定 |
|---|---|
| 标题 | `### GitFit <action> <operation>`（h3）：`GitFit data-store restore/save`、`GitFit db-store restore/save`、`GitFit geo-detect`/`GitFit geo-detect cache`、`GitFit import` |
| 状态词 | 纯文本无 emoji：restore `hit`/`miss`；save `saved`/`unchanged`/`skipped`/`failed` |
| 表型 | **横向布局节约纵向空间**：多源表源作列（表头一行列全部源，`Status`/`Cache key` 各一行，save 尾行 `Changed/Unchanged/Errors`）；单实体表项目作列、单值行。Cache key 去 `GitFit-data-<source>-v0-` 前缀（run-id 段保留、`snapshot` 字保留）；geo key 去前缀截 12 hex |
| 对齐 | 按数据特征：短分类值/布尔/数字/短 token（状态、cache key、bytes、counts）**居中**（`\|:---:\|`）；路径/标签/长文本（DB path、分支名、源名列、cache files、Details）**左对齐**（`\|:---\|`） |
| 实现 | node24 action 用 `@actions/core` summary（纯 builder 函数可单测）；composite action 用 `$GITHUB_STEP_SUMMARY` |
| 冗余 | 不加与 action block 重复的 workflow 级块（sync.yml 原「Write DB summary」step 已删） |

### gh-pages.yml

```
deploy-pages job (runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}):
  1. checkout (WORKOUTS_SYNC_PAT)
  2. setup Ruby + bundle
  3. derive DB paths (db-store/paths@v1)
  4. restore DB cache (db-store/cache/restore@v1, db-dir + db-name)
  5. Download fresh DB artifact (可选, artifact-run-id)
  6. export json → site/activities.json + tracks.json
  7. export stats → site/stats.json
  8. upload-pages-artifact from ./site
  10. deploy-pages@v4
```

### sync-scheduler.yml

```
manage job (runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}):
  1. checkout (persist-credentials: false)
  2. setup Ruby + bundle
  3. restore DB cache (db-store/cache/restore@v1)
  4. Read current cron interval N (grep sync.yml)
  5. Compute new interval (Sequel → f → adjust N)
  6. sed sync.yml (if schedule 或 commit=true)
  7. Configure git (bare PAT extraheader, if schedule 或 commit=true)
  8. Commit cron change (git-auto-commit-action, [skip ci],
     if (schedule 或 commit=true) && configured=true)
```

### git-fit-archive.yml

将 GH Actions cache（GitFit-data-* key）中的 raw/std + DB 数据归档到 git-fit 分支体系。

| 触发 | 操作 |
|---|---|
| schedule `0 4 * * 0` (每周日) | 每源 cache restore → `git add -A` → rename 检测 → 排除纯删除 → commit → push to `GitFit/data/<source>` + `GitFit/db` |
| workflow_dispatch | 手动触发（可选单个 source） |

详见 wiki [CI-CD](https://github.com/Lax/workouts/wiki/CI-CD)。

#### 归档分支

| 分支 | 内容 | 用途 |
|---|---|---|
| `GitFit/data/<source>` | `data/{raw,std}/<source>/` | 每源独立 orphan branch，绕过 cache 7 天 LRU，git-fit cache/restore git-archive 回退层 |
| `GitFit/db` | `data/db/workouts.db` + WAL | DB 单文件归档，gh-pages DB 回退层 |

> `_/_/<source>`（旧命名空间）已冻结保留，不再写入。

> **2026-08 变更：** sync 纯 cache-only，`shall-commit-data` / `shall-commit-db` 机制已移除。raw/std 数据每次 sync 写入 GHA cache（`GitFit-data-*` key），DB 写入 GHA cache；`git-fit-archive.yml` 每周将 cache 内容归档到 `GitFit/data/<source>` + `GitFit/db` 分支，作为 LRU 过期后的 git-archive 回退层。> `_/_/<source>`（旧命名空间）已冻结保留，不再写入。

> **2026-08 DB git 兜底与回写（db-store v1.0.2）：** `db-store/cache/restore@v1` 新增 `git-restore-mode`（none/fallback/force）+ `git-branch`（默认 `GitFit/db`）。sync.yml 用 `fallback`：cache miss 时从 GitFit/db 分支 `git archive` 恢复 DB，并输出 `git-restored-bytes` + `save-to-git-branch`；`db-store/cache/save@v1` 新增 `save-to-git-branch` 输入，在 **job 成功**（`git-save-gate`，`if: success()`）且 DB changed 时经 detached worktree push 回 GitFit/db。原 sync.yml 内联的「Restore from archive branch」step 已移入 action（顺带修复：fallback 恢复现在位于 baseline 之前，cache miss + git 恢复的运行不再误报 changed）。push 用默认 GITHUB_TOKEN（sync.yml 已有 `contents: write`），与每周 archive-db 共用 `concurrency: workouts-db` 串行。

> **2026-08 DB 路径管理单位改为目录（db-store v1.1.0）：** `database-path` 输入替换为 `db-dir` + `db-name`（完整路径内部拼接为 `db-dir/db-name`）。新增 `db-store/paths@v1` action：从单一真值 `GIT_FIT_DATABASE_PATH` 推导 `dir`/`name`/`db-path` 输出，sync / gh-pages / sync-scheduler / archive / unarchive 五个 workflow 全部统一引用 `steps.db-paths.outputs.*`，不再硬编码或拼接路径。restore 的 git archive 改为目录级恢复（严格优于旧双文件调用：分支目录部分存在也能恢复）；`db-name` 校验拒绝路径分隔符与 `.`/`..`（防路径穿越）；`save-to-git-branch` 校验与 `git-branch` 对称。yiyasasa.github.io 同步更新。

> **2026-08 缓存 key 命名纪律（[`Lax/git-fit#51`](https://github.com/Lax/git-fit/issues/51)）：** restore 精确 key 用永不写入的 `-v0-sentinel` 强制前缀回退；unarchive 恢复快照写 `-v0-snapshot`（真实可读内容，可被后续 restore 前缀命中）。二者严禁合并为同一 key，否则触发 F1 粘滞阴影（unarchive 后精确命中 snapshot，永久遮蔽更新的 `-v0-{run}` sync cache）。`git-fit-actions/{data-store,db-store}` 的 `@v1` 已发布修复（v1.0.1）；workouts 侧 `git-fit-archive.yml`（archive restore）与 `git-fit-unarchive.yml`（unarchive save）已内联对齐。快照 key 追加 `-{run_number}-{run_id}` 后缀（与 sync save 格式一致），避免重复 unarchive 的 key 碰撞。

## 部署

### GitHub Pages

前端代码已迁移至 [Lax/running](https://github.com/Lax/running)，本仓库 Pages 仅部署数据制品供其消费。

| 项 | 值 |
|---|---|
| Pages 源 | GitHub Actions |
| URL | `https://lax.github.io/workouts/`（后端数据） |
| 前端看板 | `https://lax.github.io/running/`（Lax/running 部署） |
| 部署目录 | JSON + stats，排除 DB |

---

## 数据架构

详见 wiki [Architecture](https://github.com/Lax/workouts/wiki/Architecture)

L1 raw → L2 标准化 GPS → L3 SQLite 摘要 → L4 构建制品 → L5 部署。
转换规则: 坐标归一化、时间归一化、不丢字段。
每个新源必须实现 L1+L2+L3。

## 文档架构

> **2026-08 变更：** `docs/` 目录已归档至 GitHub Wiki（[Lax/workouts wiki](https://github.com/Lax/workouts/wiki)，主题索引见 [Home](https://github.com/Lax/workouts/wiki)）。设计/调研/实现文档统一按话题存放，不再在仓库内维护 `docs/`。

### 文档分类

每一个需求产出一组文档，共享前缀，后缀区分类型：

| 类型 | 后缀 | 编写方式 | 内容 |
|---|---|---|---|
| 目标文档 | `-goal` | 用户主笔，AI 辅助 | 功能定义、验收标准、边界划分 |
| 调研文档 | `-research` | 共同编写 | 技术调研历史、方案对比、关键决策依据 |
| 实现文档 | `-impl` | 开发过程产出 | 遇到的问题、解决方案、注意事项、变更记录 |

**命名示例：** `garmin-auth-goal.md` / `garmin-auth-research.md` / `garmin-auth-impl.md`

> 历史文档（`data-architecture.md`, `garmin-auth.md` 等）已在归档时按话题合并进 wiki 页面，不保留原名。

### 编写原则

文档给人看也给 AI 看。

| 原则 | 说明 |
|---|---|
| 术语一致 | 代码 / 注释 / wiki / CONTEXT.md 用同一组词。避免同义替换 |
| 显式引用 | 跨文件引用写完整路径或 wiki URL。不写"详见上节" |
| 结构化 > 段落 | 表格 / 列表 > 自然段。AI 解析表格比段落可靠 |
| 约定写出来 | `__` 分隔符、`SOURCE` 占位符含义、OAuth 术语，在注释里写清 |
| 文件锚点 | 每个 wiki 页面以 `# <topic> — <summary>` 开头 |
| 不列测试数量 | 文档中不出现测试用例数量、耗时等数字。测试相关仅写 `测试（全 stub、零网络）` |
| 测试不用 rm_rf | Spec 不得用 `FileUtils.rm_rf` 删除生产目录。用 `Dir.mktmpdir` 管理临时文件 |
| 不重复 OAuth | OAuth token 管理集中在 git-fit 的 `Auth::GarminToken`，其他类不得包含 OAuth 客户端逻辑 |

## 错误消息约定

每条 actionable 错误消息必须包含两个要素：

| 要素 | 格式 | 示例 |
|---|---|---|
| 问题描述 | `<层级>: <失败原因>` | `Garmin: auth_seed decode failed — invalid Base64` |
| 操作指引 | `  <动>: <命令>` | `  Fix: git fit auth garmin --sync` |

规则：
1. 错误不吞 — 每层至少输出一行描述，`rescue` 不加原因视为 bug
2. 操作命令可直接复制粘贴执行（先写 `Fix:`/`Re-auth:`/`Run:` 动词）
3. `sync` count==0 时报 `warn`（黄色），不报 `done`（绿色），避免误认为成功
4. 区分过期类型 — HTTP 400 是数据过期（refresh_token 旋转），HTTP 401 是权限吊销（client_id）
