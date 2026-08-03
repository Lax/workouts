# Data Store — Cache / Git Store Spec

## 概述

规范 sync.yml 中数据 restore/save 的步骤顺序、mode 条件、两层容错逻辑、以及 git-by-source 模式下 DB 存储位置。

## 设计规则

### 规则一：数据依赖决定顺序

| 操作 | 依赖的数据 | restore 时机 |
|------|-----------|-------------|
| Import (Apple Health / GPX/FIT/TCX) | DB | 先 restore DB（步骤 2/3/4/5）→ 再 import（步骤 6） |
| Sync (Keep / Garmin / ……) | DB + per-source raw/std + tokens | import 后补充 per-source（步骤 7/8），sync 前 restore tokens（步骤 10） |
| Geo region detection | geo cache | sync 后 restore geo cache（步骤 13） |
| Cron update | workflow 写权限 | 无需数据依赖 |

### 规则二：两层 restore — cache 先读，git 权威覆盖

```
Step 2/3/7: restore from cache      → fast path, 一般不失败
  ↓ (cache miss or stale)
Step 4/5/8: restore from git        → 权威覆盖
  ↓ (git fails — rare)
→ cache 数据仍可用                   → 安全兜底
```

| 模式 | 第一层 | 第二层 | git 失败兜底 |
|------|--------|--------|-------------|
| `git-by-source` | cache（step 2, 7） | git（step 4, 8） | cache 数据 |
| `git-combined` | cache（step 3） | git（step 5） | cache 数据 |
| `git-flat` | n/a（data in checkout） | n/a | n/a |
| `actions-combined` | cache（step 3） | n/a | n/a |
| `actions-by-source` | cache（step 2, 7） | n/a | n/a |

## Backend Modes

由 `DATA_STORE_MODE` 环境变量控制，`steps.data-store.outputs.mode` 透传给各个条件步骤。

| Mode | 含义 | Restore 来源 | Save 目标 | 适用场景 |
|------|------|-------------|-----------|---------|
| `git-flat` | Data in checkout，直接 commit 到 main | checkout（no-op） | `git add + commit` 到 main | 本地开发 / self-hosted runner |
| `git-combined` | 单 git 分支存全部数据 | cache → `data/_/_` branch | `data/_/_` branch + cache | 少量数据，单分支管理 |
| `git-by-source` | 每 source 独立 git 分支 | cache → `_/_/<src>` + `_/db/workouts-db` | 同上分支 + cache | 大体积数据，独立历史 |
| `actions-combined` | 单 GH Actions cache key | Combined cache | Combined cache | 小体积，快速 |
| `actions-by-source` | 每 source 独立 cache key | Per-source cache + DB cache | Per-source cache + DB cache | 大体积，增量缓存 |

## 条件矩阵

### Restore 阶段（步骤 0-10）

| Step | Operation | `git-flat` | `git-combined` | `git-by-source` | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|:---:|:---:|:---:|
| 0 | Setup: git auth, ruby, node | ✓ | ✓ | ✓ | ✓ | ✓ |
| 1 | Config: determine DATA_STORE=mode | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2 | Restore DB from cache | — | — | ✓ | — | ✓ |
| 3 | Restore combined (raw+std+DB) cache | — | ✓ | — | ✓ | — |
| 4 | Restore DB from git `_/db/workouts-db` | — | — | ✓ | — | — |
| 5 | Restore combined git `data/_/_` | — | ✓ | — | — | — |
| 6 | Import Apple Health + GPX/FIT/TCX | ✓ | ✓ | ✓ | ✓ | ✓ |
| 7 | Restore per-source caches (raw+std) | — | — | ✓ | — | ✓ |
| 8 | Restore per-source git branches | — | — | ✓ | — | — |
| 10 | Restore tokens cache | ✓ | ✓ | ✓ | ✓ | ✓ |

### Execution 阶段（步骤 11-18）

| Step | Operation | `git-flat` | `git-combined` | `git-by-source` | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|:---:|:---:|:---:|
| 11 | Run Sync | ✓ | ✓ | ✓ | ✓ | ✓ |
| 12 | Save tokens cache | ✓ | ✓ | ✓ | ✓ | ✓ |
| 13 | Restore geo cache | ✓ | ✓ | ✓ | ✓ | ✓ |
| 14 | Geo region detection | ✓ | ✓ | ✓ | ✓ | ✓ |
| 15 | Read current N | ✓ | ✓ | ✓ | ✓ | ✓ |
| 16 | Calculate new N | ✓ | ✓ | ✓ | ✓ | ✓ |
| 17 | Update sync.yml | schedule | schedule | schedule | schedule | schedule |
| 18 | Commit cron change | schedule+changed | schedule+changed | schedule+changed | schedule+changed | schedule+changed |

### Save 阶段（步骤 20-28）

| Step | Operation | `git-flat` | `git-combined` | `git-by-source` | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|:---:|:---:|:---:|
| 20 | Save DB git `_/db/workouts-db` | — | — | ✓ | — | — |
| 21 | Save per-source git branches | — | — | ✓ | — | — |
| 22 | Save combined git `data/_/_` | — | ✓ | — | — | — |
| 23 | Save flat git (commit to main) | ✓ | — | — | — | — |
| 24 | Save DB cache | — | — | ✓ | — | ✓ |
| 25 | Save per-source caches | — | — | ✓ | — | ✓ |
| 26 | Save combined cache | — | ✓ | — | ✓ | — |
| 27 | Upload DB artifact | data changed | data changed | data changed | data changed | data changed |
| 28 | Trigger gh-pages deploy | data changed | data changed | data changed | data changed | data changed |

## Save 条件公式

每个 save 步骤的条件镜像对应 restore 步骤的条件：

```
step 24.if = step 2.if   = mode==actions-by-source || mode==git-by-source
step 25.if = step 7.if   = mode==actions-by-source || mode==git-by-source
step 26.if = step 3.if   = mode==actions-combined  || mode==git-combined
```

### Git 模式双写逻辑 (Safety Net)

```
git-by-source:  git save (20,21) + cache save (24,25)   → git 失败 → cache 兜底
git-combined:   git save (22)    + cache save (26)       → git 失败 → cache 兜底
git-flat:       git save (23) only                        → 无需 cache（checked-out data）
```

## Sync Workflow 步骤顺序

```
setup:
   0  git auth, ruby, node
   1  DATA_STORE=mode 判断

restore DB (两层: cache → git 覆盖):
   2  Restore DB from cache                   if mode needs DB (*)
   3  Restore combined (raw+std+DB) cache     if mode==git-combined || actions-combined
   4  Restore DB from git (_/db/workouts-db)     if mode==git-by-source          (权威覆盖)
   5  Restore combined git (data/_/_)         if mode==git-combined           (权威覆盖)

import:
   6  Import Apple Health + GPX/FIT/TCX       always

restore per-source (两层: cache → git 覆盖):
   7  Restore per-source caches               if mode needs per-source (**)
   8  Restore per-source git branches         if mode==git-by-source           (权威覆盖)

tokens:
  10  Restore tokens cache                    always (有 token sources)
  11  Run Sync                                always
  12  Save tokens cache                       always()

geo:
  13  Restore geo cache                       always
  14  Geo region detection                    always

cron:
  15  Read current N                          always
  16  Calculate new N                         always
  17  Update sync.yml                         if schedule
  18  Commit cron change                      if schedule && changed

save git (按 mode 分支):
  20  Save DB to _/db/workouts-db                if mode==git-by-source
  21  Save per-source git branches            if mode==git-by-source
  22  Save combined git (data/_/_)            if mode==git-combined
  23  Save flat git (commit to main)          if mode==git-flat

save cache (镜像 restore 条件):
  24  Save DB cache                           if step 2 执行过
  25  Save per-source caches                  if step 7 执行过
  26  Save combined cache                     if step 3 执行过

output:
  27  Upload DB artifact                      if data changed
  28  Trigger gh-pages deploy                 if data changed
```

条件注解：
- `(*)  mode needs DB`         = `mode!=git-flat && mode!=actions-combined && mode!=git-combined`
                               = `mode==actions-by-source || mode==git-by-source`
- `(**) mode needs per-source` = `mode==actions-by-source || mode==git-by-source`

## git-by-source DB 处理

### 现状

`data-store/restore` 中 `git-by-source` 模式走 `actions/cache/restore` 还原 DB（行 32-37），不是从 git。这与 `_/db/workouts-db` 分支不一致。

### 变更

| | Restore | Save |
|---|---|---|
| 旧 | `actions/cache/restore`（仅 cache，无 git） | `actions/cache/save`（仅 cache fallback） |
| 新 | cache（step 2）+ git 权威覆盖（step 4） | git（step 20）+ cache（step 24）双层 |

与 `archive.yml` 中的 `archive-db` job 使用同一分支 `_/db/workouts-db`，存档和同步共享同一存储位置。

### 实现方式

DB 的 git restore/save 复用现有 `scripts/data-store-git-save.sh`，该脚本已支持 temp index + tree diff + atomic push。

Restore 步骤 4 的内联 bash：
```bash
if git ls-remote --exit-code origin refs/heads/_/db/workouts-db >/dev/null 2>&1; then
  git fetch origin _/db/workouts-db
  mkdir -p data
  git archive --format=tar origin/_/db/workouts-db \
    data/db/workouts.db 2>/dev/null | tar xf - || true
fi
```

Save 步骤 20：
```bash
bash scripts/data-store-git-save.sh _/db/workouts-db \
  "data/db/workouts.db data/db/workouts.db.checksum"
```

## Composite Actions 拆分

当前 `data-store/restore` 和 `data-store/save`、`sources-cache/restore`、`sources-cache/save`、`sources-git/restore`、`sources-git/save` 等 composite action 全部拆为 sync.yml 内联步骤。

每个步骤的条件由上表矩阵决定，不再经过 composite action 路由。

## 校验和方法（后续实现）

参考 `scripts/data-store-checksum.sh`（当前孤立）和两份 action 中重复的 `.checksum` 生成内联 bash，后续抽取为 `scripts/generate-checksums.sh`。本次文档不包含。
