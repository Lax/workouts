# Data Store — Cache Only Spec

> **2026-08 变更：** `shall-commit-data` / `shall-commit-db` 机制已移除。sync 纯 cache-only，git 备份由 `git-fit-archive.yml` 每周归档承担（GHA cache → `GitFit/data/<source>` + `GitFit/db` 分支）。本文档保留历史多模式架构记录，当前生效部分见下文注记。

## 概述

规范 sync.yml 中数据 restore/save 的步骤顺序、cache 容错逻辑。当前 sync 纯 cache-only（`data-store/restore` + `data-store/save` + `git-fit-actions/db-store/cache/*`），git 备份由 `git-fit-archive.yml` 周归档承担。git-* 模式（`git-flat`/`git-combined`/`git-by-source`）已移除。

## 设计规则

### 规则一：数据依赖决定顺序

| 操作 | 依赖的数据 | restore 时机 |
|------|-----------|-------------|
| Import (Apple Health / GPX/FIT/TCX) | DB | 先 restore DB（步骤 2/3/4/5）→ 再 import（步骤 6） |
| Sync (Keep / Garmin / ……) | DB + per-source raw/std + tokens | import 后补充 per-source（步骤 7/8），sync 前 restore tokens（步骤 10） |
| Geo region detection | geo cache | sync 后 restore geo cache（步骤 13） |
| Cron update | workflow 写权限 | 无需数据依赖 |

### 规则二：cache restore + archive fallback

```
Step 2/7: restore from cache      → fast path, 一般不失败
  ↓ (cache miss or stale)
Step 4/5: restore from git archive → 权威覆盖（git-fit-archive.yml 每周刷新 GitFit/data/<src> + GitFit/db）
  ↓ (git archive fails — rare)
→ cache 数据仍可用                   → 安全兜底
```

| 模式 | 第一层 | 第二层 | git 失败兜底 |
|------|--------|--------|-------------|
| `actions-by-source` | cache（step 2, 7） | git archive（GitFit/data/<src>、GitFit/db） | cache 数据 |
| `actions-combined` | cache（step 3） | n/a | cache 数据 |

## Backend Modes

> **2026-08 变更：** `git-flat` / `git-combined` / `git-by-source` 模式已移除。sync 纯 cache-only，由 `git-fit-archive.yml` 周归档承担 git 备份。

| Mode | 含义 | Restore 来源 | Save 目标 | 适用场景 |
|------|------|-------------|-----------|---------|
| `actions-by-source` | 每 source 独立 GH Actions cache key | Per-source cache + DB cache + git archive fallback（GitFit/data/<src>、GitFit/db） | Per-source cache + DB cache | 大体积，增量缓存（当前唯一模式） |
| `actions-combined` | 单 GH Actions cache key | Combined cache | Combined cache | 小体积，快速 |

## 条件矩阵

### Restore 阶段（步骤 0-10）

| Step | Operation | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|
| 0 | Setup: git auth, ruby, node | ✓ | ✓ |
| 1 | Config | ✓ | ✓ |
| 2 | Restore DB from cache | — | ✓ |
| 3 | Restore combined (raw+std+DB) cache | ✓ | — |
| 4 | Restore DB from git archive `GitFit/db`（cache miss 回退） | — | ✓ |
| 5 | Restore combined git `data/_/_`（已废弃，git-combined 模式移除） | — | — |
| 6 | Import Apple Health + GPX/FIT/TCX | ✓ | ✓ |
| 7 | Restore per-source caches (raw+std) | — | ✓ |
| 8 | Restore per-source git branches（已废弃，git-by-source 模式移除） | — | — |
| 10 | Restore tokens cache | ✓ | ✓ |

### Execution 阶段（步骤 11-18）

| Step | Operation | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|
| 11 | Run Sync | ✓ | ✓ |
| 12 | Save tokens cache | ✓ | ✓ |
| 13 | Restore geo cache | ✓ | ✓ |
| 14 | Geo region detection | ✓ | ✓ |
| 15 | Read current N | ✓ | ✓ |
| 16 | Calculate new N | ✓ | ✓ |
| 17 | Update sync.yml | schedule | schedule |
| 18 | Commit cron change | schedule+changed | schedule+changed |

### Save 阶段（步骤 20-28）

| Step | Operation | `actions-combined` | `actions-by-source` |
|------|-----------|:---:|:---:|
| 20 | Save DB git `GitFit/db`（已废弃，git-by-source 模式移除） | — | — |
| 21 | Save per-source git branches（已废弃） | — | — |
| 22 | Save combined git `data/_/_`（已废弃，git-combined 模式移除） | — | — |
| 23 | Save flat git (commit to main)（已废弃，git-flat 模式移除） | — | — |
| 24 | Save DB cache | — | ✓ |
| 25 | Save per-source caches | — | ✓ |
| 26 | Save combined cache | ✓ | — |
| 27 | Upload DB artifact | data changed | data changed |
| 28 | Trigger gh-pages deploy | data changed | data changed |

## Save 条件公式

```
step 24.if = step 2.if   = mode==actions-by-source
step 25.if = step 7.if   = mode==actions-by-source
step 26.if = step 3.if   = mode==actions-combined
```

> git-* 模式的双写逻辑（git save + cache save）已随 shall-commit 机制移除。

## Sync Workflow 步骤顺序

```
setup:
   0  git auth, ruby, node

restore:
   1  Restore DB from cache                   if mode needs DB
   2  Restore per-source caches               if mode needs per-source
   3  Restore DB from git archive (GitFit/db)  cache miss 回退
   4  Restore per-source git archive (GitFit/data/<src>)  cache miss 回退

import:
   5  Import Apple Health + GPX/FIT/TCX       always

tokens:
   6  Restore tokens cache                    always
   7  Run Sync                                always
   8  Save tokens cache                       always()

geo:
   9  Restore geo cache                       always
  10  Geo region detection                    always

cron:
  11  Read current N                          always
  12  Calculate new N                         always
  13  Update sync.yml                         if schedule
  14  Commit cron change                      if schedule && changed

save cache:
  15  Save DB cache                           if step 1 执行过
  16  Save per-source caches                  if step 2 执行过
  17  Save combined cache                     if step 3 执行过

output:
  18  Upload DB artifact                      if data changed
  19  Trigger gh-pages deploy                 if data changed
```

## git-by-source DB 处理（已废弃）

> 本节描述旧 `git-by-source` 模式的 DB 处理。shall-commit 机制移除后，sync 纯 cache-only，DB 由 `git-fit-actions/db-store/cache/restore@v1` + `cache/save@v1` 管理，git 备份由 `git-fit-archive.yml` archive-db job 周归档到 `GitFit/db`。本节保留作为历史参考。

### 现状（旧）

`data-store/restore` 中 `git-by-source` 模式走 `actions/cache/restore` 还原 DB（行 32-37），不是从 git。这与 `GitFit/db` 分支不一致。

### 变更（旧）

| | Restore | Save |
|---|---|---|
| 旧 | `actions/cache/restore`（仅 cache，无 git） | `actions/cache/save`（仅 cache fallback） |
| 新 | cache（step 2）+ git 权威覆盖（step 4） | git（step 20）+ cache（step 24）双层 |

与 `git-fit-archive.yml` 中的 `archive-db` job 使用同一分支 `GitFit/db`，存档和同步共享同一存储位置。

### 实现方式（旧）

> 以下为旧 `git-by-source` 模式的实现记录，shall-commit 移除后不再使用。

DB 的 git restore/save 曾复用 `scripts/data-store-git-save.sh`，该脚本已支持 temp index + tree diff + atomic push。（脚本随 shall-commit 移除已删除。）

Restore 步骤 4 的内联 bash：
```bash
if git ls-remote --exit-code origin refs/heads/GitFit/db >/dev/null 2>&1; then
  git fetch origin GitFit/db
  mkdir -p data
  git archive --format=tar origin/GitFit/db \
    data/db/workouts.db 2>/dev/null | tar xf - || true
fi
```

Save 步骤 20（已废弃）：
```bash
bash scripts/data-store-git-save.sh GitFit/db \
  "data/db/workouts.db data/db/workouts.db.checksum"
```

## Composite Actions 拆分

当前 `data-store/restore`（每源 restore + SHA256SUMS 生成）和 `data-store/save`（每源 save + `any_changed`/`changed_sources`/`unchanged_sources` 聚合输出）composite action 封装 restore/save 逻辑。shall-commit 移除后 `sources-git/restore`、`sources-git/save` 已删除；`data-store/sources-cache/*` 已上提为 `data-store/{restore,save}`（2026-08）。

每个步骤的条件由上表矩阵决定，不再经过 composite action 路由。

## 校验和方法（后续实现）

参考 `scripts/data-store-checksum.sh`（当前孤立）和两份 action 中重复的 `.checksum` 生成内联 bash，后续抽取为 `scripts/generate-checksums.sh`。本次文档不包含。
