# Workouts CLI — 项目设计文档

## 项目概述

运动数据聚合 CLI 工具，多渠道同步 → SQLite 数据库 → JSON / CSV / SVG 导出。

**仓库：** `github.com/Lax/workouts`（私有，付费计划）  
**技术栈：** Ruby 3.4, Thor, Sequel, SQLite3, Nokogiri, Faraday, OAuth  
**部署：** Docker / GitHub Actions / GitHub Pages

---

## CLI 命令

| 命令 | 说明 |
|---|---|
| `sync [--source S] [--act TYPE]` | 同步所有配置源（`--source` 指定单一源，`--act` 按运动类型过滤） |
| `auth <garmin\|garmin_cn>` | 交互式 Garmin SSO 登录 |
| `export json [--output]` | 导出 JSON |
| `export csv [--output]` | 导出 CSV |
| `export svg --style <style>` | 生成 SVG 海报（5 种风格） |
| `export stats [--output]` | 导出统计摘要 |
| `export dashboard [--output]` | 导出自定义仪表盘 HTML |
| `export gpx [--output]` | 从 L2 文件重新导出 GPX |
| `export html` | 导出 HTML（同 dashboard）|
| `export all` | 执行所有导出 |
| `parse <file.gpx\|file.tcx> [--save]` | 解析本地 GPX/TCX 文件，可选写入 DB |
| `init` | 生成默认 config.yml |
| `migrate` | 运行数据库迁移 |
| `version` | 版本号 |

---

## CLI 文件结构

```
lib/workouts/cli.rb              # 主 CLI（Workouts::CLI），加载子模块
lib/workouts/cli/export.rb       # 导出子命令（ExportCLI: json, csv, svg, all）
lib/workouts/cli/sync.rb         # 同步子模块（sync, auth）
```

---

## 架构

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Strava      │     │  Sync::Base  │     │ Export::SVG │
│ Garmin      │────▶│  upsert      │────▶│ Export::JSON│
│ Keep        │     │  write_raw   │     │ Export::CSV │
│ iGPSPORT    │     │  skip_type?  │     └─────────────┘
│ XOSS (xoss) │     └───┬───┬──────┘
│ XingZhe     │         │   │
└─────────────┘         │   └───▶ data/raw/{source}/
                        │           (原始 GPS 点阵备份, 每源独立 GH Cache)
                        ▼
                    ┌──────────────────┐
                    │   SQLite DB      │
                    │  (Sequel ORM)    │
                    └──────────────────┘
```

---

## 同步适配器

### 数据源

| 适配器 | 源域名 | 认证 | 特点 |
|---|---|---|---|
| **Keep** | api.gotokeep.com | 手机+密码 | AES-128-CBC 解密，zlib 解压，GCJ-02→WGS84，HR 最近匹配 |
| **iGPSPORT** | prod.zh.igpsport.com | 手机+密码 | FIT 原始格式，使用 mini_racer + @garmin/fitsdk 解析 |
| **XOSS** | backend.xoss.co (国际版) | email+JWT | 局部 SPORT_MAP 哈希表 |
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

每源通过 `scripts/source-digest.sh` 计算内容 md5 作为 digest，用于 CI cache 的变更检测。`before_digest` 在 restore 阶段记录，sync 后比对，仅 digest 变化时写回 cache。

### 数据流程

```
同步前:
  1. 检查凭证是否存在 (@email/@phone 等为 nil → return 0)
  2. 认证（登录 / 刷新 token）

同步中:
  1. 读取已存在的 run_id 列表 (existing_run_ids)
  2. 分页拉取活动列表 (fetch_run_ids)
  3. 计算 new_ids（未同步的） + missing_raw（已有摘要但缺原始 GPS 的）
  4. 合并为统一列表（new_ids 在前，优先同步）
  5. 逐活动处理:
     a. 时间预算耗尽? → break（下次 CI run 继续）
     b. raw 文件已存在? → next（crash 恢复保护）
     c. 一次 API 调用 → 解密 GPS → 写 raw 文件 + 写 DB (含 summary_polyline)
  6. 按活动类型过滤 (skip_type?)

同步后:
  7. 计算新鲜度 f
  8. f < N → N=max(1,N-1); f > 2N+1 → N=min(7,N+1)
  9. 写回 cron 行 (schedule only)
```

### 去重机制

#### 一级去重：`run_id`

基于 `run_id` 字段（格式：`{source}_{platform_id}`），每次同步前读取 DB 中已有 ID 列表，跳过完全重复的活动。这是第一道防线，防止同一活动的重复导入。

#### 二级去重：多源置信度打分

Strava 适配器在同步完成后会执行 `recheck_duplicates`，用置信度算法扫描 Strava 活动与其它来源（Keep、iGPSPORT 等）的匹配情况。算法考虑三个因子：

- **时间相近度**（权重 40%）：开始时间差 ≤ 5 分钟，越近得分越高
- **距离相近度**（权重 40%）：距离差 ≤ 较大值的 15%
- **时长相近度**（权重 20%）：运动时长差 ≤ 较大值的 15%

综合置信度 ≥ 0.15 即视为匹配，结果写入 `duplicate_info` 列（JSON 数组）：

```json
[{"source": "keep", "run_id": "keep_xxx", "confidence": 0.92, "flag": "derived"}]
```

- `confidence ≥ 0.85` → flag 为 `"derived"`（极可能是同一活动）
- `0.15 ≤ confidence < 0.85` → flag 为 `"overlap"`（部分重叠，需人工判断）

SVG 导出时，标注上会区分 derived（高置信度合并）和 overlap（低置信度重叠），鼠标悬停显示匹配来源和评分。

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
```

`__` 作为层级分隔符 → key 自身可含单 `_`（如 `garmin_cn`）

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

### jobs

```
sync job:
  1. checkout
  2. setup Ruby + bundle
  3. restore DB cache
  4. record DB digest
  5. restore Garmin token caches
  6. restore per-source caches (7 源, 各自独立 GH Cache)
  7. workouts sync (受 SYNC__TIME_BUDGET 限制)
  8. 读 N → 算 f → 可能改 cron
  9. check DB changed
  10. save DB cache + Garmin token caches
  11. save per-source caches (仅变动的源)
  12. upload DB artifact (for build job)

build job (needs: sync):
  1. checkout + setup Ruby
  2. download DB artifact
  3. create build/ dir
  4. export json → build/activities.json
  5. export svg → build/svg/github.svg
  6. validate SVG
  7. export stats → build/stats.json
  8. export dashboard → build/
  9. generate index.html → build/index.html
  10. upload build artifact

deploy job (needs: build):
  1. download build artifact
  2. upload-pages-artifact from ./build
  3. deploy-pages@v4
```

## Docker

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export svg --style github
docker compose run --rm workouts export json
```

数据卷：`./data:/app/data`

---

## GitHub Pages

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
| temp→rename 原子写入 raw 文件 | 崩溃恢复时 `raw_file_exists?` 不误判 |
| Per-source 独立 GH Cache | 每源独立 cache key (`workouts-raw-v1-{source}-{run_id}`)，通过 `scripts/source-digest.sh` 计算内容 md5 检测变化，仅变动的源写 cache。通过 `.github/actions/source-cache/` composite action 封装。数据目录示例: `data/raw/{garmin,garmin_cn,igpsport,...}/`, `data/std/{...}/` |
| 导出默认路径 `data/` → `build/` | 源数据与生成制品分离，gitignored |
| `mini_racer` + `@garmin/fitsdk` 解析 FIT | V8 引擎在 Ruby 进程中执行 JS SDK，纯 gem 依赖，无需外部运行时 |

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
