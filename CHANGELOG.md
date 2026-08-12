# Changelog

> 核心逻辑（sync / import / export / dedup / db / geo / parse）已迁移至 git-fit gem，本仓库为薄壳 CLI。下述条目中标注「git-fit」的已迁移，详细实现见 git-fit 仓库。

## 2026-08 — thin-shell 迁移

| Item | Status |
|---|---|
| workouts-cli 剥为薄壳：删除 sync/auth/fit/db/export 本地实现，`auth`/`db`/`geo`/`init`/`parse` 委托 git-fit | ✅ 已完成 |
| Garmin 认证迁移至 `git fit auth garmin`（-A/-B/--auto/--sync/--mfa-code），Python 脚本删除（git-fit #66） | ✅ 已完成 |
| `git fit auth garmin` 默认策略改为 `--auto`（B primary / A fallback） | ✅ 已完成 |
| XingZhe session cookie 跨 CI 持久化（git-fit 0.11.1） | ✅ 已完成 |
| per-source 独立 GH Cache（`GitFit-data-{source}-v0-{run_id}`，data-store@v2），废弃 `workouts-raw-v1-*` | ✅ 已完成 |
| sync 纯 cache-only：`shall-commit-data/db` 移除，`git-fit-archive.yml` 每周归档到 `GitFit/data/*` + `GitFit/db` 分支 | ✅ 已完成 |
| 缓存 key 命名纪律（restore 用 `-v0-sentinel`，unarchive 用 `-v0-snapshot`，严禁合并，git-fit#51） | ✅ 已完成 |
| DB git 兜底与回写（db-store v1.0.2）：restore `git-restore-mode: fallback` + save `save-to-git-branch`，cache miss 时从 `GitFit/db` 恢复、job 成功时 push 回（移入 action，修复 baseline 误报 changed） | ✅ 已完成 |

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
