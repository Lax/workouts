# git-fit db-store 引入 — 实现方案

> 范围：仅替换 sync.yml 中 DB restore/save 逻辑为 git-fit 0.5.9 自带的 `db-store` composite actions。不动 data-store、tokens-cache、Apple Health import、sync 逻辑等其他部分。

---

## 0. 前提：Gemfile.lock 已升级

```
-  revision: 7af01426b4a3fb35f66f56cfc7441f49aa16a6b7   (0.5.7)
+  revision: 0b41784d2d87fcbf239b73fe2b720aa423107aa9   (0.5.8)
+  revision: 917de90833e8a6df41676c9d6d1c3b6e0a3d1b2c   (0.5.9)
```

Gemfile.lock 已升级并 committed（`fc8750c`）。`git-fit install actions --check` 通过。

---

## 0.5 变量命名评估：`steps.db-save.outputs.db-changed`

### 当前命名

`db-changed` 语义：`true` = DB 有变更需执行保存操作。

### 评估

| 维度 | `db-changed` | 替代方案 `changed` |
|---|---|---|
| 直观性 | 中等 — 需理解 "save is required" 这个条件判断逻辑 | 高 — 直接表达状态 |
| 常见模式 | 不常见 | `steps.changed.outputs.any_changed`（本项目 data-store/save 已用） |
| 一致性 | 与 data-store/save 的 `any_changed` 命名风格不一致 | 一致 |
| 布尔语义 | 反问式（"需要保存吗？"） | 陈述式（"已变更"） |

### 结论

`db-changed` 功能上可用，但不是最优命名。建议向 git-fit 提交 issue 建议改为 `changed` 或 `db-changed`，与 data-store 命名风格统一。

**本次实现不等待 issue 合并，直接使用 `steps.db-save.outputs.db-changed`。** 若 git-fit 后续版本改为 `changed`，同步修改 sync.yml 中两处引用（Edit 5 + Edit 6）。

---

## 1. git-fit db-store actions 模板分析

已通过 `GIT_FIT_DATABASE_PATH=data/workouts.db bundle exec git-fit install actions` 生成到 `.github/actions/db-store/`。

### 1.1 restore 内建 steps（按序）

```
1. Build cache key (id: ck)                     → 无条件
2. Check DB git branch (id: db-git-check)        → shall-commit-db == 'true'
3. Restore DB from git                           → shall-commit-db && exists
4. Restore DB cache (actions/cache/restore@v4)   → 无条件
5. Verify DB restore                             → 无条件, outputs: clean
        若无 checksum: sha256sum > {path}.SHA256SUMS
```

| 输入 | 默认值 | workouts 传入值 |
|---|---|---|
| `path` | `data/workouts.db` | `data/workouts.db` |
| `key-prefix` | `git-fit-db` | `workouts-db` |
| `db-schema-hash` | `""` | `${{ hashFiles('db/migrations/*.rb') }}` |
| `shall-commit-db` | `'false'` | `${{ steps.mode.outputs.shall_commit_db }}` |
| `git-branch` | `_/fit-db` | `_/workouts-db` |
| `commit-author-name` | `"git-fit-bot"` | `"workouts-bot"` |
| `commit-author-email` | `"bot@git-fit"` | `"bot@workouts"` |

### 1.2 save 内建 steps（按序）

```
1. Check DB changed (id: check)                  → 无条件
        若有 checksum 且匹配: db-changed=false; 否则: true
2. Generate DB SHA256SUMS                        → db-changed == 'true'
3. Save DB git (commit-tree → push)              → shall-commit-db && db-changed
4. Build cache key (id: ck)                      → 无条件
5. Save DB cache (actions/cache/save@v4)         → db-changed == 'true'
```

| 输出 | 说明 |
|---|---|
| `db-changed` | `true` = DB 有变更需保存 |
| `saved` | `true` = 实际执行了保存操作（cache 或 git） |

> **Note:** save step 3 使用 `commit-tree` 直接写 ref 到 git-branch，不经过 working tree / index，不影响后续 `git add` / `git commit` 操作。

---

## 2. cache key 兼容性验证

| 环节 | 现有值 | db-store 生成值 |
|---|---|---|
| key | `workouts-db-v1-${{ hashFiles('db/migrations/*.rb') }}-${{ github.run_id }}` | `workouts-db-v1-${mhash}-${{ github.run_id }}` |
| restore-keys | `workouts-db-v1-` | 同左 |
| key-prefix 输入 | — | `workouts-db` |
| db-schema-hash 输入 | — | `${{ hashFiles('db/migrations/*.rb') }}` |

渲染逻辑：
```
mhash = inputs.db-schema-hash (非空则 "workouts-db-v1-abc123-{run_id}"，空则 "workouts-db-v1-{run_id}")
```

完全一致。❇

---

## 3. 同步流程对比：现有 vs 目标

### 3.1 restore 侧

```
现有:
  61  # ── DB restore (before import) ──
  62  Check DB git branch          ─┐
  73  Restore DB from git           ├─ 由 db-store/restore 内建
  82  Restore DB cache              │
  91  Verify DB restore (id: db-restore-check)  ─┘

目标:
  61  # ── DB restore (git-fit db-store) ──
  62  uses: ./.github/actions/db-store/restore   ← 一个 step 替代 4 个
```

`db-restore-check.outputs.clean` 不再被保存侧引用 → 可删除 id。

### 3.2 save 侧

```
现有:
 244  # ── DB save (by-source) ──
 245  Check DB changed (id: db-check)  ─┐
 256  Generate DB SHA256SUMS             │
 261  Save DB git (data-store-git-save)  ├─ 由 db-store/save 内建
 267  Save DB cache                     ─┘
 276  # ── Data save ──
 284  # ── Git add + unified commit ──
 285  Git add DB                        ← 删除（db-store/save 已 push 到 branch）
 291  Git add sources                   ← 不变
 299  Unified commit                    ← 条件简化（仅 source data）

目标:
 244  # ── DB save (git-fit db-store) ──
 245  uses: ./.github/actions/db-store/save (id: db-save)
 276  # ── Data save ──
 284  # ── Git add + unified commit ──
 285  Git add sources
 290  Unified commit (仅 data)
```

`steps.db-check.outputs.db_changed` 不再存在 → 下游替换为 `steps.db-save.outputs.db-changed`。

---

## 4. 精确编辑序列

所有 edit 针对 `.github/workflows/sync.yml`。按序执行，每步有精确 oldString。

---

### Edit 1：替换 DB restore section（行 61-106）

**删除：** comment `# ── DB restore (before import)` + 4 个 step（Check DB git branch, Restore DB from git, Restore DB cache, Verify DB restore）

**插入：** db-store/restore step + 新 comment

```oldString
      # ── DB restore (before import — import needs DB) ──
      - name: Check DB git branch
        id: db-git-check
        if: steps.mode.outputs.shall_commit_db == 'true'
        shell: bash
        run: |
          if git ls-remote --exit-code origin refs/heads/_/workouts-db >/dev/null 2>&1; then
            echo "exists=true" >> $GITHUB_OUTPUT
          else
            echo "exists=false" >> $GITHUB_OUTPUT
          fi

      - name: Restore DB from git
        if: steps.mode.outputs.shall_commit_db == 'true' && steps.db-git-check.outputs.exists == 'true'
        shell: bash
        run: |
          git fetch origin _/workouts-db
          mkdir -p data
          git archive --format=tar origin/_/workouts-db \
            data/workouts.db data/workouts.db.SHA256SUMS 2>/dev/null | tar xf - || true

      - name: Restore DB cache
        uses: actions/cache/restore@v4
        with:
          path: |-
            data/workouts.db
            data/workouts.db.SHA256SUMS
          key: workouts-db-v1-${{ hashFiles('db/migrations/*.rb') }}-${{ github.run_id }}
          restore-keys: workouts-db-v1-

      - name: Verify DB restore
        id: db-restore-check
        if: steps.mode.outputs.shall_commit_db != 'true'
        shell: bash
        run: |
          if [ ! -f data/workouts.db ]; then
            echo "clean=true" >> $GITHUB_OUTPUT
            exit 0
          fi
          ck="data/workouts.db.SHA256SUMS"
          if [ -f "$ck" ] && sha256sum -c "$ck" --quiet 2>/dev/null; then
            echo "clean=true" >> $GITHUB_OUTPUT
          else
            echo "clean=false" >> $GITHUB_OUTPUT
            [ ! -f "$ck" ] && bash scripts/generate-checksums.sh data/workouts.db
          fi
```

```newString
      # ── DB restore (git-fit db-store) ──
      - uses: ./.github/actions/db-store/restore
        with:
          path: data/workouts.db
          key-prefix: workouts-db
          db-schema-hash: ${{ hashFiles('db/migrations/*.rb') }}
          shall-commit-db: ${{ steps.mode.outputs.shall_commit_db }}
          git-branch: _/workouts-db
```

**影响行数：** 删除 46 行，插入 8 行。净 -38 行。

---

### Edit 2：替换 DB save section（行 244-274）

**删除：** comment `# ── DB save (by-source) ──` + 4 个 step（Check, Generate SHA256SUMS, Save DB git, Save DB cache）

**插入：** db-store/save step + 新 comment

```oldString
      # ── DB save (by-source) ──
      - name: Check DB changed
        id: db-check
        shell: bash
        run: |
          ck="data/workouts.db.SHA256SUMS"
          if [ -f "$ck" ] && sha256sum -c "$ck" --quiet 2>/dev/null; then
            echo "db_changed=false" >> $GITHUB_OUTPUT
          else
            echo "db_changed=true" >> $GITHUB_OUTPUT
          fi

      - name: Generate DB SHA256SUMS
        if: steps.db-check.outputs.db_changed == 'true'
        shell: bash
        run: bash scripts/generate-checksums.sh data/workouts.db

      - name: Save DB git
        if: steps.mode.outputs.shall_commit_db == 'true' && (steps.db-check.outputs.db_changed == 'true' || steps.db-restore-check.outputs.clean == 'false')
        shell: bash
        run: bash scripts/data-store-git-save.sh _/workouts-db \
          "data/workouts.db data/workouts.db.SHA256SUMS"

      - name: Save DB cache
        if: steps.db-check.outputs.db_changed == 'true' || steps.db-restore-check.outputs.clean == 'false'
        uses: actions/cache/save@v4
        with:
          path: |-
            data/workouts.db
            data/workouts.db.SHA256SUMS
          key: workouts-db-v1-${{ hashFiles('db/migrations/*.rb') }}-${{ github.run_id }}
```

```newString
      # ── DB save (git-fit db-store) ──
      - uses: ./.github/actions/db-store/save
        id: db-save
        with:
          path: data/workouts.db
          key-prefix: workouts-db
          db-schema-hash: ${{ hashFiles('db/migrations/*.rb') }}
          shall-commit-db: ${{ steps.mode.outputs.shall_commit_db }}
          git-branch: _/workouts-db
```

**影响行数：** 删除 31 行，插入 8 行。净 -23 行。

---

### Edit 3：删除 Git add DB step（行 284-289）

**删除：** Git add DB step。保留 section comment（Git add sources 在其后）。

```oldString
      # ── Git add + unified commit (for commit mode) ──
      - name: Git add DB
        if: steps.mode.outputs.shall_commit_db == 'true' && (steps.db-check.outputs.db_changed == 'true' || steps.db-restore-check.outputs.clean == 'false')
        shell: bash
        run: |
          git add -f data/workouts.db data/workouts.db.SHA256SUMS

      - name: Git add sources
```

```newString
      # ── Git add + unified commit (for commit mode) ──
      - name: Git add sources
```

**说明：** db-store/save 内建 `commit-tree` 直接 push 到 `_/workouts-db` branch，不再需要 stage DB 到 main branch commit。

**影响行数：** 删除 6 行，净 -6 行。

---

### Edit 4：简化 Unified commit 条件（行 299-300）

**oldString**
```yaml
      - name: Unified commit
        if: (steps.mode.outputs.shall_commit_db == 'true' && (steps.db-check.outputs.db_changed == 'true' || steps.db-restore-check.outputs.clean == 'false')) || (steps.mode.outputs.shall_commit_data == 'true' && steps.data-save.outputs.any_changed == 'true')
```

**newString**
```yaml
      - name: Unified commit
        if: steps.mode.outputs.shall_commit_data == 'true' && steps.data-save.outputs.any_changed == 'true'
```

**说明：** DB 不由 unified commit 提交到 main——db-store/save 已将其 push 到 `_/workouts-db`。统一 commit 现在只负责 source data。

---

### Edit 5：替换 Upload DB artifact 条件（行 319）

```oldString
        if: steps.db-check.outputs.db_changed == 'true' || steps.data-save.outputs.any_changed == 'true'
```

```newString
        if: steps.db-save.outputs.db-changed == 'true' || steps.data-save.outputs.any_changed == 'true'
```

**影响：** 1 处。

---

### Edit 6：替换 Trigger gh-pages deploy 条件（行 326）

```oldString
        if: steps.db-check.outputs.db_changed == 'true' || steps.data-save.outputs.any_changed == 'true'
```

```newString
        if: steps.db-save.outputs.db-changed == 'true' || steps.data-save.outputs.any_changed == 'true'
```

**影响：** 1 处。

---

## 5. 最终 sync.yml DB 相关 steps 清单

| 行 | Step | 类型 |
|---|---|---|
| 61 | db-store/restore | `uses` composite action |
| 108 | Restore import marker (Apple Health) | 不变 |
| 115 | Import Apple Health | 不变 |
| 139 | data-store/restore | 不变 |
| 145 | tokens-cache/restore | 不变 |
| 148 | Sync | 不变 |
| 244 | db-store/save (id: db-save) | `uses` composite action |
| 276 | data-store/save | 不变 |
| 284 | Git add sources | 不变 |
| 290 | Unified commit | 条件简化 |
| 317 | Upload DB artifact | 条件替换 |
| 325 | Trigger gh-pages deploy | 条件替换 |

共 12 个 DB/storage 相关 step。其中：
- 新增 2 个（db-store/restore + db-store/save）
- 删除 6 个（Check git branch, Restore git, Restore cache, Verify, Check changed, Generate SHA256SUMS, Save cache, Save git, Git add DB）
- 修改条件 3 处（Unified commit, Upload artifact, Deploy trigger）

总数：从 ~80 行 DB 相关 YAML → ~16 行。净减少 ~64 行。

---

## 6. 生成的 action 文件校验

两文件由 `GIT_FIT_DATABASE_PATH=data/workouts.db bundle exec git-fit install actions` 生成。

### 6.1 restore/action.yml 关键行

```yaml
# 行 6:  default: data/workouts.db      ← 由 GIT_FIT_DATABASE_PATH 注入
# 行 9:  default: git-fit-db             ← 需通过 key-prefix 输入覆盖
# 行 18: default: _/fit-db                ← 需通过 git-branch 输入覆盖
# 行 59: restore-keys: ${{ inputs.key-prefix }}-v1-  ← 与现有一致
```

### 6.2 save/action.yml 关键行

```yaml
# 行 6:  default: data/workouts.db
# 行 9:  default: git-fit-db
# 行 18: default: _/fit-db
# 行 22: outputs.db-changed           ← 替代旧 db_changed
# 行 50-76: Save DB git 步骤             ← commit-tree 方式
```

### 6.3 输出变量确认

**restore：** 无暴露 output（`clean` 仅内部 `$GITHUB_OUTPUT`，无 `outputs:` 声明）

**save：** `db-changed`（string: `"true"` / `"false"`），等价于旧 `db-check.outputs.db_changed`

---

## 7. gh-pages workflow: db-store/restore 集成

gh-pages.yml 原使用 bare `actions/cache/restore` 恢复 DB，仅依赖 cache（7 天 TTL）。已替换为 `db-store/restore`，提供分层恢复：

```
优先级（高→低）:
  1. actions/download-artifact@v4   ← 仅 manual dispatch 且有 artifact-run-id 时
  2. git archive origin/GitFit/db   ← shall-commit-db: true 时启用
  3. actions/cache/restore@v4 (schema key)   ← db-store 内建
  4. actions/cache/restore@v4 (prefix fallback)   ← db-store 内建
```

```yaml
# .github/workflows/gh-pages.yml (行 49-55)
- uses: ./.github/actions/db-store/restore
  with:
    path: data/workouts.db
    key-prefix: workouts-db
    db-schema-hash: ${{ hashFiles('db/migrations/*.rb') }}
    shall-commit-db: true
    git-branch: GitFit/db   # 迁移后（当前 gh-pages.yml 已用 git-fit-actions/db-store，此段为旧版 db-store 快照）
```

**变更原因：** 当 cache 过期且 archive 尚未运行时，gh-pages 可能拿到空 DB。git branch 恢复层确保至少有一个 sync 完成后的 DB 可用。

**注意：** `download-artifact` step 在 `db-store/restore` 之后执行，仅在 manual dispatch 且有 `artifact-run-id` 时覆盖。normal `workflow_run` 触发时跳过，避免覆盖当前 DB。

---

## 8. data-store sha256sum subshell 崩溃修复

**文件：**
- `.github/actions/data-store/save/action.yml`
- `.github/actions/data-store/sources-cache/save/action.yml`
- `.github/actions/data-store/sources-git/save/action.yml`

**根因：** Ubuntu runner 上 `sha256sum -c --quiet` 仍向 stderr 输出 `file: FAILED`。原始代码在 subshell 中运行：

```bash
(cd "$dir" && sha256sum -c SHA256SUMS --quiet 2>/dev/null)
```

stderr 泄露到父进程的 `$GITHUB_OUTPUT`，触发 GHA `Invalid format` 错误。

**修复：** 将 `sha256sum` 隔离在独立 subshell，外层用 `if ! (cd ...)` 判断：

```bash
if [ ! -f "$dir/SHA256SUMS" ] || ! (cd "$dir" && sha256sum -c SHA256SUMS --quiet 2>/dev/null); then
  changed=true
fi
```

---

## 9. 跨 workflow 并发控制：`workouts-db` concurrency group

**问题：** `sync.yml`（via db-store/save）和 `git-fit-archive.yml`（archive-db job）均向 `GitFit/db` branch 写入，无协调机制。并发 push 可能触发 non-fast-forward  rejection。

**修复：** 两 job 共享 concurrency group `workouts-db`：

```yaml
# sync.yml sync job
concurrency:
  group: workouts-db
  cancel-in-progress: false

# git-fit-archive.yml archive-db job
concurrency:
  group: workouts-db
  cancel-in-progress: false
```

`cancel-in-progress: false` 确保两 workflow 互相排队，不取消对方。

---

## 10. 待跟进：`shall-commit-db` 语义歧义

已向 `Lax/git-fit` 提交 issue：https://github.com/Lax/git-fit/issues/10

`shall-commit-db` 在 `db-store/save` 中语义正确（是否提交到 git），但在 `db-store/restore` 中语义相反（是否从 git 恢复）。建议 rename 为 `use-git-branch` 并走 deprecation 路径。

当前 workouts 项目中，`shall-commit-db: true` 传入 `db-store/restore` 的语义是"从 git branch 恢复"，需留意上游修复后的迁移。

---

## 11. 文件变更清单（已 committed）

| 文件 | 状态 | 说明 |
|---|---|---|
| `Gemfile.lock` | committed（`fc8750c`） | 0.5.8 → 0.5.9 |
| `.github/actions/db-store/restore/action.yml` | committed（`fc8750c`） | v0.5.9 模板：`outputs.clean`，`id: db-restore-check` |
| `.github/actions/db-store/save/action.yml` | committed（`fc8750c`） | v0.5.9 模板：`db-changed`/`saved` outputs，`commit-author-*` inputs |
| `.github/actions/data-store/save/action.yml` | committed（`fc8750c`） | sha256sum subshell 隔离修复 |
| `.github/actions/data-store/sources-cache/save/action.yml` | committed（`fc8750c`） | sha256sum subshell 隔离修复 |
| `.github/actions/data-store/sources-git/save/action.yml` | committed（`fc8750c`） | sha256sum subshell 隔离修复 |
| `.github/workflows/sync.yml` | committed（`fc8750c` + `aa09a0d`） | concurrency group，db-changed refs，commit-author passthrough，移除 stray `shall-commit-db` |
| `.github/workflows/git-fit-archive.yml` | committed（`aa09a0d` 引入，后经多次演化） | archive-db concurrency group 改为 `workouts-db`；迁移至 GitFit/data/<source> + GitFit/db 分支体系 |
| `.github/workflows/gh-pages.yml` | committed（`aa09a0d`） | bare `actions/cache/restore` → `db-store/restore` + git branch fallback |

> **设计决策：为何不动态生成？** GitHub Actions 的 `uses:` 在 workflow parse time 解析，运行时无法创建并使用 composite action。因此 `.github/actions/db-store/` 必须作为静态文件提交到仓库。与现有 `data-store/`、`tokens-cache/` 模式一致。git-fit 升级后需重新运行 `install actions` 并 commit 更新后的文件。

| 文件 | 状态 | 说明 |
|---|---|---|
| `scripts/generate-checksums.sh` | 不变 | 仍被 data-store actions 调用 |
| `scripts/data-store-git-save.sh` | 不变 | 仍被 data-store/sources-git 调用 |
| `.github/actions/data-store/` | 不变 | raw/std 数据管理 |
| `.github/actions/tokens-cache/` | 不变 | token 缓存 |

---

## 8. 实际提交记录

变更已通过 2 个 commit 推送至 `main`：

```bash
fc8750c  chore: upgrade git-fit to v0.5.9 + fix data-store sha256sum crash
aa09a0d  fix: add cross-workflow concurrency for _/workouts-db + gh-pages git restore
```

**fc8750c 包含：**
- Gemfile.lock: git-fit 0.5.8 → 0.5.9
- db-store/restore + db-store/save 重新生成（v0.5.9 模板）
- sync.yml: `save-required` → `db-changed`，新增 `commit-author-*` passthrough
- 3 个 data-store save action sha256sum subshell 隔离修复

**aa09a0d 包含：**
- sync.yml + git-fit-archive.yml: concurrency group `workouts-db`
- gh-pages.yml: bare `actions/cache/restore` → `db-store/restore` + git branch fallback

---

## 9. 验证清单

| # | 验证项 | 状态 |
|---|---|---|
| 1 | `git-fit install actions --check` 通过 | ✅ `fc8750c` CI 已验证 |
| 2 | `bundle exec rspec` 通过 | ✅ 687 examples, 0 failures |
| 3 | 无残留引用 `steps.db-check` | ✅ 已清除 |
| 4 | 无残留引用 `steps.db-restore-check` | ✅ 已清除 |
| 5 | 无残留引用 `steps.db-git-check` | ✅ 已清除 |
| 6 | gem 版本 0.5.9 | ✅ `bundle exec git-fit version` |
| 7 | db-store actions 包含正确 path | ✅ `rg 'data/workouts.db' .github/actions/db-store/ -l` → 2 文件 |
| 8 | sync.yml 中 `db-changed` 引用正确 | ✅ L257, L264 |
| 9 | sync.yml 中 `commit-author-name/email` 传入 db-store/save | ✅ L218-219 |
| 10 | gh-pages.yml 使用 `db-store/restore` + `shall-commit-db: true` | ✅ L49-55 |
| 11 | git-fit-archive.yml archive-db concurrency group = `workouts-db` | ✅ L71 |
| 12 | data-store/save 无 `shall-commit-db` 传入（GHA warning 修复） | ✅ 已移除 |

---

## 10. 风险矩阵

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| `GitFit/data/<source>` 分支并发写入冲突 | 低 | git-fit-archive weekly job 与 sync data-store/save（commit 模式）同时 push，non-fast-forward rejection | 目前 git-fit-archive 每周日 04:00 触发，sync 每 2 天触发，冲突窗口小。如需消除，可对 per-source branches 增加 concurrency group |
| db-store/save 的 `commit-tree` push 到 git-branch 失败 | 低 | DB branch 未保存，artifact 仍可用 | `build` job 从 artifact 下载 DB，不依赖 branch |
| `shall-commit-db` 语义歧义导致误用 | 低 | restore 中 `true` 意为"从 git 恢复"而非"提交到 git" | 已向 git-fit 提交 Issue #10；当前 gh-pages.yml 传入 `true` 语义正确 |
| cache key 不一致导致 cache miss | 极低 | 首次 sync 无 cache | keys 已验证等价；cache miss 只影响首次 restore |

---

## 11. 动态生成可行性评估：`.github/actions/db-store/` 能否运行时生成？

### 问题

是否可以在 workflow 运行时通过 `git fit install actions` 动态生成 composite actions，而不将其固化在代码仓库中？

### 结论：不可行

根据 GitHub Actions 官方文档（About custom actions / Creating a composite action）：

> Composite actions 是仓库中的 YAML 文件，通过 `uses: ./.github/actions/<name>` 引用。
> Workflow 在 **parse time**（执行任何 step 之前）解析所有 `uses:` 引用路径。

**关键限制：**

| 限制 | 说明 |
|---|---|
| `uses:` 解析时机 | workflow 文件在 runner 上 checkout 后、任何 step 执行前完成解析 |
| 路径要求 | `uses: ./.github/actions/<name>` 必须指向已存在的 `action.yml` 文件 |
| 无法运行时创建 | 在 step 中 `run:` 创建的文件，无法被同 job 内后续 step 的 `uses:` 引用 |
| 安全性 | 运行时生成 composite action 会导致 workflow 内容在运行时改变，破坏可审计性 |

### 可行的替代模式

| 模式 | 原理 | 适用场景 |
|---|---|---|
| **生成后 commit** | 专用 workflow/job 运行 `git fit install actions` → commit 产物 → 主 workflow `uses` 这些文件 | 需要 actions 随 git-fit 版本自动更新时 |
| **内联 run 步骤** | 不使用 composite actions，将 db-store 逻辑直接写在 `run:` bash 块中 | 逻辑简单、不想维护独立 action 文件时 |
| **版本化发布** | git-fit 发布时附带预生成的 action 文件，使用者从固定版本引用 | 类似 `actions/checkout@v4` 模式 |

### 决策

**将 `.github/actions/db-store/` 提交到仓库**。理由：

1. 与现有模式一致：`data-store/` 和 `tokens-cache/` 均以相同方式管理
2. 生成代价低：`git fit install actions` 一次执行，产生 2 个静态 YAML 文件
3. 可审计：workflow 引用的 action 内容在 review 时可见
4. 维护成本可控：git-fit 升级时重新运行 `install actions` 并 commit

> **注意：** git-fit 升级后需重新运行 `GIT_FIT_DATABASE_PATH=data/workouts.db bundle exec git-fit install actions` 更新 action 文件。建议在 upgrade 流程中增加此步骤。

---

## 12. git-fit 设计问题清单

以下问题从本次集成实践中发现。部分已提交 issue，部分已在 v0.5.9 解决。

### Issue 1（已解决）：`db-store/save` 输出命名 `save-required` → `db-changed`

**状态：** v0.5.9 已将输出从 `save-required` 重命名为 `db-changed`。✅ 已解决。

原描述：输出名 `save-required` 采用反问式命名（"需要保存吗？"），不如陈述式命名直观。

---

### Issue 2（待跟进）：`shall-commit-db` 在 restore/save 中语义相反

**严重程度：** Medium（影响可读性和安全性）

**描述：** `shall-commit-db` 在 `db-store/save` 中语义正确（是否提交到 git），但在 `db-store/restore` 中语义相反（是否从 git 恢复）。用户在 restore 上下文中看到 `shall-commit-db: true` 容易误以为该 action 会修改 git branch。

**已提交 issue：** https://github.com/Lax/git-fit/issues/10

**建议方案：**
- v0.5.10：在 restore action description 中澄清语义
- v0.6.0：新增 `use-git-branch` 参数，`shall-commit-db` 标记为 deprecated
- v1.0.0：移除 restore 中的 `shall-commit-db`

**当前 workaround：** workouts 项目中 `shall-commit-db: true` 传入 `db-store/restore` 的语义是"从 git branch 恢复"，代码和文档已明确此用法。

---

### Issue 2：`db-store/restore` 的 `clean` 输出未声明

**严重程度：** Low（当前不影响功能，因为 workout 不再引用它）

**描述：** restore action 的 "Verify DB restore" step 将 `clean=true/false` 写入 `$GITHUB_OUTPUT`，但 action 本身没有 `outputs:` 声明。这意味着：

- `clean` 是 step-internal 输出，无法被外部 workflow 引用
- 如果意图是暴露给调用方，需在 action 级别声明 `outputs:` 并映射

**当前影响：** 无。workouts 已不再引用 `db-restore-check.outputs.clean`。

**建议：** 若未来需要向调用方暴露 restore 状态，添加 `outputs:` 声明：
```yaml
outputs:
  clean:
    description: "Whether the restored DB passed SHA256 verification"
    value: ${{ steps.verify.outputs.clean }}
```

---

### Issue 3：`db-store` 默认值与 git-fit 自身项目强耦合

**严重程度：** Medium（影响作为 library 的可用性）

**状态：** 未解决。v0.5.9 仍使用 `git-fit-db` 和 `_/fit-db` 作为默认值。

**描述：** 以下默认值仅对 git-fit 自身项目有意义，对将 git-fit 作为 library 使用的项目（如 workouts）完全无效：

| 输入 | 当前默认值 | 问题 |
|---|---|---|
| `key-prefix` | `git-fit-db` | 暗示 action 属于 git-fit 项目 |
| `git-branch` | `_/fit-db` | 强制使用 `_/fit-db` branch 名 |

所有使用 git-fit 作为 library 的项目必须覆盖这两个值，否则：
- `key-prefix` 生成 `git-fit-db-v1-*` cache key（与其他项目共享 cache namespace）
- `git-branch` 写入 `_/fit-db` branch（可能冲突）

**建议：** 改为通用默认值或空默认值，要求调用方显式配置。

```yaml
# 方案 A：通用默认值
inputs:
  key-prefix:
    required: false
    default: db
  git-branch:
    required: false
    default: _/db

# 方案 B：空默认值 + 调用方必须指定
inputs:
  key-prefix:
    required: true
  git-branch:
    required: true
```

---

### Issue 4（已解决）：`Save DB git` 的 commit author 硬编码

**严重程度：** Low

**状态：** v0.5.9 已解决。✅ 新增 `commit-author-name` / `commit-author-email` inputs，调用方可覆盖。

原描述：save action 的 "Save DB git" step 使用硬编码的 git 身份 `git-fit-bot / bot@git-fit`，与调用方的 bot identity 不一致。

---

### Issue 5（已解决）：`db-store/save` 缺少 `saved` output

**严重程度：** Low

**状态：** v0.5.9 已解决。✅ 新增 `saved` output。

原描述：当前只有 `db-changed` 输出，表示"是否需要保存"。workflow 有时需要知道"是否实际执行了保存"。

---

### Issue 6（部分解决）：`install actions` 缺少版本化/校验机制

**严重程度：** Medium

**状态：** 部分解决。v0.5.9 新增 `--check` 选项。⚠️ `--dry-run` 和 `generated-by` 注释仍未实现。

**已解决：**
- `--check` 选项：检查现有文件是否与当前版本模板一致（`git-fit install actions --check` 已通过 CI 验证）

**仍未解决：**
- `--dry-run` 选项：显示将写入的内容，不实际写入
- action YAML 头部 `generated-by: git-fit vX.Y.Z` 注释

---

## 13. 实施后 git-fit 升级流程建议

每次 git-fit 版本升级时，需执行以下步骤：

```bash
# 1. bundle update git-fit（或手动修改 Gemfile.lock）
# 2. 重新生成 actions
GIT_FIT_DATABASE_PATH=data/workouts.db bundle exec git-fit install actions

# 3. 检查生成内容与已提交版本是否一致
git-fit install actions --check

# 4. 如有变更，一并 commit
git add .github/actions/db-store/
```

> v0.5.9 已新增 `--check` 子命令，在 CI 中自动检测 action 文件是否与 gem 版本一致。建议在 CI 中增加 `git-fit install actions --check` 步骤。
