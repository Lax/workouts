# Archive — data/{raw,std,db} 定期归档

## 目标

将 GH Actions cache 中的每源 raw/std 数据以及 workouts.db，按源独立归档到 git branch，实现：
- **长期留存** — 绕过 cache 7 天 LRU 限制
- **历史追溯** — git 天然提供版本 diff
- **零侵占 main** — 归档数据不进 main，走独立 orphan branch

## 分支命名

`_/_/<source>` — 如 `_/_/xoss`、`_/_/igpsport`
`_/db/workouts-db` — DB 单文件归档

命名含 `/`，git/GitHub 均支持，UI 显示为 `data/ → _/ → xoss` 文件夹层级。`_/db/workouts-db` 显示为 `_ / workouts-db`，单深度区别于 per-source 双深度。

## 流程

```
Step 0: checkout main + 配置 PAT extraheader（用于后续 git push）
Step 1: ls-remote → 分支不存在则 plumbing 创建空 commit + push
Step 2: git fetch + checkout _/_/$SRC
        （此后 index 只含 archive 文件，与 main 隔离）
Step 3: cache restore → 覆盖 disk（写入新文件、覆盖已有、不删旧文件）
Step 4: git add -f -A（含所有变动，包括删除）
        → write-tree
        → diff-tree -M50% HEAD $TREE
        → --diff-filter=D 捕获纯删除（排除 rename R）
        → reset HEAD 排除纯删除
        → diff --cached --quiet? skip : commit + push
```

### archive-db 简化流程

`archive-db` job 独立于 matrix，处理 `data/db/workouts.db` 单文件归档到 `_/db/workouts-db` 分支：

```
Step 0-2: 同上（checkout main → 创建/切换 _/db/workouts-db）
Step 3: cache restore data/db/workouts.db（key: GitFit-db-v0-*）
Step 4: git add -f -A data/db/workouts.db → diff --cached --quiet? skip : commit + push
```

单文件无需 rename 检测和删除排除。`git write-tree` + `diff-tree` 步骤省略。

## 机制详解

### Step 1 — 首次分支创建

用 plumbing 避免切换 HEAD：

```bash
EMPTY_TREE=$(git hash-object -t tree --stdin -w < /dev/null)
COMMIT=$(git -c user.name=workouts-bot -c user.email=bot@workouts \
  commit-tree -m "chore: init archive branch $BRANCH" "$EMPTY_TREE")
git push origin "$COMMIT:refs/heads/$BRANCH"
```

- 动态计算空树 hash（不同 git 版本计算结果不同，`commit-tree` 接受本地对象）
- `commit-tree` 创建 commit 对象须指定作者身份（`-c user.name/email`）
- 不碰 index、不碰 worktree、不切换 HEAD
- Step 2 统一从 main 出发，fetch + checkout

### Step 2 — checkout 的 index 隔离

`git checkout _/_/xoss` 后，index 和 worktree 只含 archive branch 的跟踪文件（`data/raw/xoss/`、`data/std/xoss/`）。main 的文件完全不被纳入。

### Step 4 — rename 保护 + 删除排除

| 操作 | 效果 |
|---|---|
| `git add -f -A <pathspec>` | 全部 stage（新增、修改、重命名、删除） |
| `git write-tree` | 从 index 构建新 tree |
| `git diff-tree -M50% HEAD $TREE` | 比较 HEAD 与新 tree，自动检测重命名 |
| `--diff-filter=D` | 捕获纯删除（R 不被捕获） |
| `git reset HEAD -- $file` | 排除纯删除，保留旧文件在 archive |

重命名（R）被正常 commit，纯删除（D）被拦截。

### concurrency

```yaml
jobs:
  archive:
    concurrency:
      group: archive-${{ matrix.source }}
      cancel-in-progress: false
```

`concurrency` 必须放在 job 内部而非 workflow 顶层，因为 `matrix.source` 只在 job 的 `strategy.matrix` 作用域内生效。同源排队、不同源并行。防止首次创建分支的 race condition 和 push 冲突。

## 文件结构

```
.github/workflows/archive.yml   # 归档 workflow（含 archive + archive-db 两个 job）
```

全部逻辑内联在 workflow 中，不拆分脚本文件。

## 涉及的工具链

| 工具 | 用途 |
|---|---|
| `actions/checkout@v4` | 初始检出 main |
| `actions/cache/restore@v4` | 加载 per-source / DB cache |
| `git ls-remote` | 检查远程分支是否存在 |
| `git commit-tree` | 创建 orphan commit（plumbing） |
| `git fetch / checkout` | 切到 archive branch |
| `git add -f -A` | stage 所有变动（force 绕过 .gitignore） |
| `git write-tree` | 从 index 构建 tree |
| `git diff-tree -M50%` | rename-aware diff |
| `git reset HEAD` | 排除纯删除 |
| `git push <commit>:refs/heads/<branch>` | 推送新分支 / 更新已有分支 |

## 已知局限

| 局限 | 原因 | 影响 |
|---|---|---|
| push 失败不重试 | 网络 / PAT 过期等极端情况 | 下次运行自动 catch up |
| 极小概率 rename 误判 | `-M50%` 阈值设置 | 低相似度改名视为 D+A，旧文件保留、新文件新增 |
| archive 永远不删除 | 纯删除被 `reset HEAD` 排除 | 源站已删的活动，archive 中仍保留历史快照 |
| `_/db/workouts-db` 二进制增长 | `workouts.db` ~2.8MB，每周全量 blob commit | 每年 ~145MB，对 git 可接受 |

## 实现记录

### 迭代历史

| 轮次 | 失败点 | 原因 | 修正 |
|---|---|---|---|
| 1 | workflow 解析失败 | `concurrency` 放在 workflow 顶层（`matrix.source` 未定义） | 移入 `jobs.archive.concurrency` |
| 2 | `commit-tree` 报 Author identity unknown | `actions/checkout@v4` 的 Post-job cleanup 清空 git config（含 user.name/email） | 加 `-c user.name=workouts-bot -c user.email=bot@workouts` |
| 3 | 全部通过 | — | — |

### 验证结果（2026-07-03）

首次手动触发 `workflow_dispatch` 后，7 个源全部成功归档，远程分支均已创建：

| 分支 | 文件数 | 状态 |
|---|---|---|
| `data/_/keep` | 1738 | 成功 |
| `data/_/igpsport` | 170 | 成功 |
| `data/_/garmin` | 74 | 成功 |
| `data/_/strava` | ~70 | 成功 |
| `data/_/xingzhe` | 66 | 成功 |
| `data/_/garmin_cn` | 2 | 成功 |
| `data/_/xoss` | 0 | 无 cache 数据，正确 skip |
| `_/db/workouts-db` | 1 (DB) | 待验证 |

### 对抗审查最终结论

本地模拟 4 个核心场景（rename/delete/no-change/first-run），全部通过。

## 相关设计文档

- [CONTEXT.md](../CONTEXT.md) — 项目整体架构
- [data-architecture.md](data-architecture.md) — 数据分层设计
