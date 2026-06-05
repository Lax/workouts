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
| `parse <file.gpx\|file.tcx> [--save]` | 解析本地 GPX/TCX 文件，可选写入 DB |
| `init` | 生成默认 config.yml |
| `migrate` | 运行数据库迁移 |
| `version` | 版本号 |

---

## 架构

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ Strava      │     │  Sync::Base  │     │ Export::SVG │
│ Garmin      │────▶│  upsert      │────▶│ Export::JSON│
│ Keep        │     │  skip_type?  │     │ Export::CSV │
│ iGPSPORT    │     │  privacy     │     └─────────────┘
│ XOSS (xoss) │     └──────┬───────┘
│ XingZhe     │            │
└─────────────┘            ▼
                    ┌──────────────┐
                    │   SQLite DB  │
                    │  (Sequel ORM)│
                    └──────────────┘
```

---

## 同步适配器

### 数据源

| 适配器 | 源域名 | 认证 | 特点 |
|---|---|---|---|
| **Keep** | api.gotokeep.com | 手机+密码 | AES-128-CBC 解密，zlib 解压，GCJ-02→WGS84，HR 最近匹配 |
| **iGPSPORT** | prod.zh.igpsport.com | 手机+密码 | FIT 原始格式，使用摘要 API（跳过 FIT 解析）|
| **XOSS** | backend.xoss.co (国际版) | email+JWT | 三层 SportMapper |
| **XingZhe** | imxingzhe.com (行者) | RSA 加密密码 + session Cookie | 行者国内版 |
| **Garmin CN** | garmin.cn | SSO + OAuth1→OAuth2 | token 文件持久化 + OAuth1 自动 refresh |
| **Garmin** | garmin.com | SSO + OAuth1→OAuth2（CF 429 封禁中）| 支持 garth secret_string 替代方案 |
| **Strava** | strava.com | OAuth2 refresh_token | 待配置 |

### 数据流程

```
同步前:
  1. 检查凭证是否存在 (@email/@phone 等为 nil → return 0)
  2. 认证（登录 / 刷新 token）

同步中:
  1. 读取已存在的 run_id 列表 (existing_run_ids)
  2. 分页拉取活动列表
  3. 跳过已存在的 (next if existing.include?)
  4. 按活动类型过滤 (skip_type?)  
  5. build_attrs → upsert_activity

同步后:
  6. 计算新鲜度 f
  7. f < N → N=max(1,N-1); f > 2N+1 → N=min(7,N+1)
  8. 写回 cron 行 (schedule only)
```

### 去重机制

基于 `run_id` 字段（格式：`{source}_{platform_id}`），每次同步前读取 DB 中已有 ID 列表，跳过重复。

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
  average_heartrate REAL,
  average_speed REAL,                       -- m/s
  elevation_gain REAL,
  source       TEXT,                        -- 来源标识
  created_at   DATETIME,
  updated_at   DATETIME
);
```

---

## 配置体系

### 配置层级（优先级：高→低）

1. 环境变量 `SYNC__SOURCE__KEY`（`__` 双下划线分隔层级）
2. `config/config.yml`（自动加载）
3. `Config::DEFAULTS` 硬编码默认值

### 环境变量命名

```
SYNC__KEEP__PHONE       → sync.keep.phone
SYNC__GARMIN_CN__EMAIL  → sync.garmin_cn.email
SYNC__STRAVA_CLIENT_ID  → sync.strava.client_id
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
| schedule `*/N` (自适应) | 同步 + 导出 + 部署 Pages |
| workflow_dispatch | 手动触发，不改 cron |

### jobs

```
sync job:
  1. checkout
  2. setup Ruby + restore cache
  3. workouts sync (15 secrets → env)
  4. 读 N → 算 f → 可能改 cron
  5. save cache
  6. export json + svg
  7. prepare pages dir (排除 DB)
  8. upload-pages-artifact
  9. upload-artifact (备选)

deploy job:
  if: success()
  permissions: pages:write + id-token:write
  environment: github-pages
  1. download artifact
  2. 生成 index.html
  3. upload-pages-artifact
  4. deploy-pages@v4
```

---

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

## 关键技术决策

| 决策 | 原因 |
|---|---|
| `Net::HTTP.new(host, port, nil*5)` 直连 | 绕过系统代理（`127.0.0.1:64540`） |
| 内联 deploy job 而非 reusable workflow | 调用 `uses:` 在该仓库导致 `startup_failure` |
| `__` 分隔 env var | 避免与 `garmin_cn` 等 key 中的 `_` 冲突 |
| 保留 `upload-artifact` | Pages 部署稳定后再移除 |
| Keep 用摘要数据 | FIT 格式无解析器 |

---

## 项目状态

### 数据库（971 条活动）

| 来源 | 数量 |
|---|---|
| Keep | 837 |
| iGPSPORT | 56 |
| XOSS | 44 |
| XingZhe | 34 |
| Garmin CN | 0（已认证，账号无记录） |
| Garmin 国际版 | CF 429 封禁 |
| Strava | 待配置 |

### 测试

RSpec 53 例，0 失败。覆盖：
- Config（YAML 加载 + env var merge + 未知 key 警告）
- Geo（坐标转换 3 套 + Polyline 编解码）
- Privacy（起终点偏移过滤）
- Parser（GPX + TCX 活动/轨迹/心率解析）
- Export（JSON + CSV 输出格式）
- SportMapper（alias + keyword + Levenshtein）

---

## 后续规划

### P0 — 当前痛点

| 项 | 工作量 | 说明 |
|---|---|---|
| Garmin access_token 环境变量 | 0.5h | `SYNC__GARMIN__ACCESS_TOKEN` 直接使用 bearer token 跳过 SSO |
| Sync Workflows 状态确认 | 0.5h | Pages 部署已验证，确认 cache/artifact 正常流转 |

### P1 — 功能扩展

| 项 | 工作量 | 说明 |
|---|---|---|
| GPX 重新导出 | 1d | `export gpx` 从 polyline 反算 GPS 点 |
| Strava OAuth 交互式授权 | 1d | `auth strava` 启动本地 HTTP server 完成 OAuth 回调 |

### P2 — 工程完善

| 项 | 工作量 | 说明 |
|---|---|---|
| 统一错误处理 | 0.5d | 定义 `SyncError` 基类，统一 rescue 模式 |
| README.md | 1d | 项目文档（安装/配置/使用/架构） |

### 已关闭

| 项 | 状态 |
|---|---|
| Keep spider_sleep 1s → 0.1s | ✅ 已完成 |
| Config 未知 key 警告 | ✅ 已完成 |
| SportMapper 三层回退 | ✅ 已完成 |
| SVG footer rebrand | ✅ 已完成 |
| LICENSE.txt + 移除 email 占位符 | ✅ 已完成 |
| GitHub Pages 部署 | ✅ 已完成 |
| 品牌一致性审计 | ✅ 已完成 |
