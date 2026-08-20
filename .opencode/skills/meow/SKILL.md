---
name: meow
description: Structured multi-phase development workflow with 5 auto-orchestrated stages (spec → plan → craft → verify → deliver). Auto-routes by project_type and complexity. Only 2 user checkpoints (APPROVED + RELEASING). Each phase runs as independent subagent with handoff communication, verify auto-loop, strict role boundaries.
---

# Meow — Multi-Agent Development Lifecycle 🐱

5-phase loop: **📋 1/5 Spec → 📐 2/5 Plan → 🔨 3/5 Craft → 🔬 4/5 Verify → 🚀 5/5 Deliver**

Auto-routed by **project_type × complexity**.

```
skill("meow")
```

## Meow Anchor

Activate → announce: `🐱 Meow! Meow workflow active.`

## Pipeline Overview

```
📋 1/5 Spec ──→ 📐 2/5 Plan ──→ 🔨 3/5 Craft ──→ 🔬 4/5 Verify ──→ 🚀 5/5 Deliver
      │               ↑ [APPROVED]   ↑                  │              ↑
   done           pending_approval  done             passed/          [RELEASING]
                                                       blocker
```

**Only 2 user checkpoints:**
- **APPROVED** after Plan (before Craft)
- **RELEASING** before Deliver commits

Everything else auto-runs.

## Routing by Project Type

| project_type | Phase sequence | APPROVED checkpoint | RELEASING checkpoint | Verify depth |
|--------------|----------------|---------------------|----------------------|--------------|
| `frontend` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | standard |
| `backend` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | standard |
| `docs` | Spec → Craft → Verify → Deliver | **skip** | ✅ | lightweight |
| `blog` | Spec → Craft → Verify → Deliver | **skip** | ✅ | lightweight |
| `wiki` | Spec → Craft → Verify → Deliver | **skip** | ✅ | lightweight |
| `comprehensive` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | standard + neat-freak |

**Docs/blog/wiki** skip Plan because the user intent is the spec.

## Routing by Complexity

| complexity | Effect |
|------------|--------|
| `trivial` | Skip Plan; Craft uses self-review; Verify runs tests only |
| `standard` | Full flow; standard audit |
| `complex` | Enhanced Plan (OHA); extra Craft checks; neat-freak in Deliver |

## Progress Display

Orchestrator uses `todowrite` to show live progress.

### Level 1 — Phase todos

| # | Item | Status transitions |
|---|---|---|
| 1/5 | 📋 Spec | pending → in_progress → completed |
| 2/5 | 📐 Plan | pending → in_progress → pending_approval → completed |
| 3/5 | 🔨 Craft | pending → in_progress → completed |
| 4/5 | 🔬 Verify | pending → in_progress → passed / blocker / escalated |
| 5/5 | 🚀 Deliver | pending → in_progress → completed |

### Level 2 — Sub-task todos

| Phase | Strategy | How it's generated |
|---|---|---|
| Spec | Fixed | scan → disambiguate → write |
| Plan | Fixed | audit → design → approve |
| Craft | **Dynamic** | Read `02-plan.md` file change list → one todo per file |
| Verify | Semi-fixed | test → check → decide (+ dynamic from `03-craft.md`) |
| Deliver | Fixed | summary → commit → CI → postmortem (complex only) |

## Subagent Taxonomy

7 role-based subagents. Domain is passed as parameter, not encoded in name.

| Subagent | Role | Domain param | Used In |
|---|---|---|---|
| `explorer` | Codebase scanning | — | Spec probe |
| `planner` | Spec audit + design | `domain` | Plan |
| `coder` | Implementation | `domain` | Craft |
| `reviewer` | Code review | `domain` | Plan audit / Craft review |
| `tester` | Test execution + verification | — | Verify |
| `deliverer` | Commit + CI + postmortem | — | Deliver |
| `writer` | Documentation | — | Spec/Craft/Deliver for docs projects |

### Mapping to existing agent files

| New role | Existing file | Notes |
|----------|--------------|-------|
| `explorer` | `agent/feature.md` | Feature agent already scans + writes spec |
| `planner` | `agent/reviewer.md` | Reviewer does audit; planner extends with design |
| `coder` | `agent/coder.md` | Unchanged role |
| `reviewer` | `agent/reviewer.md` | Used in Craft review when not trivial |
| `tester` | `agent/tester.md` | Unchanged |
| `deliverer` | `agent/releaser.md` | Releaser becomes deliverer |
| `writer` | `agent/feature.md` | For docs projects |

## Domain Parameter

Domain is injected into subagent prompt as context, not a separate agent:

- `frontend` — React/Vue/TypeScript/CSS conventions
- `sync` — workout sync adapters, auth, API clients
- `export` — JSON/CSV/GPX export logic
- `generic` — general backend/CLI logic
- `docs` — markdown, wiki, blog writing

Example call:
```
task("general", prompt="You are coder with domain=frontend. ...")
```

## Principles

| Abbr | Full | Apply |
|---|---|---|
| BIF | Bug ships with test that reproduces it | Craft |
| EPF | Error paths before happy path | Craft |
| PFC | Prefer Flat over Clever — extract after 3+ repetitions | Plan, Craft |
| SAP | Single Answer Principle — one standard answer per question | All phases |
| FAI | Fail-fast with Actionable Info — error + fix command | Craft, Verify |
| TDA | Test Duality Assertion — test normal + error path | Craft |
| OHA | One Hour Ahead — validate approach before implementing | Plan gate (complex) |
| RUM | Read file fully before editing | Craft |
| MVC | Modify only intended, don't fix tangental issues | Craft |
| KISS | Simple > clever | All phases |
| DRY | Don't repeat existing logic | Plan, Craft |
| YAGNI | Not implement what isn't needed | Plan |
| PTA | Project Type Auto-detect — check Gemfile/Cargo.toml/package.json at root | Craft, Verify |

## Phase Definitions

### Hard Rules

- Every phase runs as subagent via `task(subagent_type, prompt)`. Main session orchestrates only.
- Only main session reads phase output and decides next action.
- Gates must pass before transition.
- Orchestrator maintains todowrite per Progress Display section.

### Phase 1/5: Spec

| Field | Value |
|---|---|
| subagent_type | `explorer` → `writer` (docs projects) / `general` (disambiguator) → `general` (specifier) |
| skills | `grill-with-docs` |
| handoff | `01-spec.md` |
| gate | handoff exists, Done Criteria are testable, ambiguity resolved |

**Orchestrator prep:**

```
WORK_DIR=.opencode/works/YYYY-MM-DD-desc
mkdir -p $WORK_DIR
if ! grep -qxF '/.opencode/works/' .gitignore; then
  echo '/.opencode/works/' >> .gitignore
fi
write status.json with phases all pending + classifier output

# Level 1 — 5 phase todos
todowrite("1/5 📋 Spec" → in_progress, priority high)
todowrite("2/5 📐 Plan" → pending, priority high)
todowrite("3/5 🔨 Craft" → pending, priority high)
todowrite("4/5 🔬 Verify" → pending, priority high)
todowrite("5/5 🚀 Deliver" → pending, priority high)

# Level 2 — Spec sub-tasks
todowrite("Spec: scan" → in_progress)
todowrite("Spec: disambiguate" → pending)
todowrite("Spec: write" → pending)
```

**Fast-lane gate:**

以下全真 → 跳过 PFAS + spec writer，直接按任务写 01-spec.md：
- 变更文件 < 5
- 任务无外部引用（upstream/source/reference/original/similar）
- 用户未提及外部项目或框架名
- project_type ∈ {docs, blog, wiki}

**Pre-flight Ambiguity Scan (PFAS):**

仅在 fast-lane gate 不满足时运行。规则同原版 meow。

**Orchestrator transition after PFAS:**

```
if ambiguity found (spec.status === "blocked"):
  - Read 01-ambiguity.md
  - Present ambiguity to user for clarification
  - Wait for user response
  - Update ambiguity file with user's resolution
  - Re-launch PFAS to verify resolution
  - Only proceed to spec writer when spec.status === "in_progress"

if clear (spec.status === "in_progress"):
  - Proceed to spec writer
```

**spec writer prompt:**

```
你是规格员。

输入：
- 任务：{task description}
- 项目类型：{project_type}
- 领域上下文：{domain}
- 代码库扫描：{explore output}
- 模糊消歧结果：{workflow_dir}/01-ambiguity.md

请做以下事情：
1. 加载 grill-with-docs，对照现有文档理解需求。
2. 定义：范围（做什么）、价值（为什么做）、完成标准（可验证）、边界情况（至少 3 个）、约束条件。
3. 定义「已否决方向」表格并写入 01-spec.md。
4. 所有外部引用必须使用 01-ambiguity.md 中消歧后的定义。
5. 写入 handoff 到 {workflow_dir}/01-spec.md
6. 更新 {workflow_dir}/status.json phase=completed

遵守 SAP、KISS。不要提案解决方案，不要估算时间。
```

**Orchestrator transition** (after spec writer returns):

```
# Consistency Gate
if gate passes:
  todowrite("Spec: scan" → completed)
  todowrite("Spec: disambiguate" → completed)
  todowrite("Spec: write" → completed)
  todowrite("1/5 📋 Spec" → completed)

  if complexity == "trivial" or project_type ∈ {docs, blog, wiki}:
    todowrite("2/5 📐 Plan" → skipped)
    todowrite("Plan: audit" → skipped)
    todowrite("Plan: design" → skipped)
    todowrite("Plan: approve" → skipped)
    todowrite("3/5 🔨 Craft" → in_progress)
  else:
    todowrite("2/5 📐 Plan" → in_progress)
    todowrite("Plan: audit" → in_progress)
    todowrite("Plan: design" → pending)
    todowrite("Plan: approve" → pending)

if gate blocks:
  todowrite("1/5 📋 Spec" → blocked)
  Report: "SPEC GATE: spec references {X} not in ambiguity resolution"
  Present to user for resolution.
```

### Phase 2/5: Plan

| Field | Value |
|---|---|
| subagent_type | `reviewer` (audit) → `planner` (design) |
| skills | `caveman`, `grill-with-docs` |
| handoff | `02-plan.md` |
| gate | status=pending_approval, user confirmed y |

**audit prompt:**

```
你能对 {workflow_dir}/01-spec.md 做只读审计吗？

请读取 spec 中提到的所有文件（如果有影响文件列表的话）。
请检查：
- 在当前代码库中可以实现吗？
- 会影响哪些文件？
- 需要遵循什么模式？

返回：审计笔记 + 读取的文件内容（供 planner 参考）。
```

**planner prompt:**

```
你是方案员。项目类型：{project_type}，领域：{domain}。

输入：
- Spec：{workflow_dir}/01-spec.md
- 审计结果：{reviewer output}

请设计方案，回答以下问题：
1. 需要新增、修改、删除哪些文件？
2. 架构决策：为什么选这个方案？拒绝了哪些替代方案？
3. 实现步骤：按依赖关系排序，每步应该是可独立交付的单元。
4. 测试策略：每层应该测试什么？

如果 complexity == "complex"，额外验证 OHA（实现不超过 1 小时）。
如果 OHA 不通过 → 标记 escalate，停止 plan，上报 orchestrator。

不要改变需求，不要写代码。
写入 handoff，更新 status.json 为 pending_approval，等待用户确认。
```

**Orchestrator transition** (after planner returns):

```
if status == "pending_approval":
  todowrite("Plan: audit" → completed)
  todowrite("Plan: design" → completed)
  todowrite("Plan: approve" → completed)
  todowrite("2/5 📐 Plan" → pending_approval)
  
  # APPROVED checkpoint — only user stop
  Prompt user: "Plan ready. Approve to continue? (y/n)"
  if y:
    state.sh approve <feature>
    todowrite("2/5 📐 Plan" → completed)
    todowrite("3/5 🔨 Craft" → in_progress)
    # Level 2 — Craft sub-tasks dynamic from 02-plan.md file list
  else:
    todowrite("2/5 📐 Plan" → in_progress)
    todowrite("Plan: design" → in_progress)

if status == "escalated":
  todowrite("2/5 📐 Plan" → escalated)
  Report to user: "OHA failed / plan too large. Need user decision."
```

### Phase 3/5: Craft

| Field | Value |
|---|---|
| subagent_type | `coder` (with domain param) |
| skills | `caveman` |
| handoff | `03-craft.md` |
| gate | tests + build pass |

**Orchestrator prep:**

```
# Level 2 craft todos already created in Phase 2 transition
# For trivial: create single "Craft: implement" todo
```

**coder prompt:**

```
你是实现员。项目类型：{project_type}，领域：{domain}，复杂度：{complexity}。

输入：
- 计划：{workflow_dir}/02-plan.md（standard/complex）或 Spec：{workflow_dir}/01-spec.md（trivial/docs）

请按步骤实现：
1. 先完全读取文件，理解周围的代码约定（RUM）。
2. 实现顺序：类型 → 纯函数 → 组件 + 测试（BIF、TDA）。
3. 错误路径优先于正常路径（EPF），只做计划范围内的改动（MVC）。

如果 complexity == "complex"：
- 额外检查边界条件
- 额外检查向后兼容性
- 记录所有兼容性问题到 03-craft.md

所有步骤完成后：
1. runner.sh 会注入正确的 test command（基于 project_type）。
2. 如果 complexity == "trivial"，执行 self-review checklist，写入 03-craft.md。
3. 写入 handoff 到 {workflow_dir}/03-craft.md
4. 更新 status.json
```

**Orchestrator transition** (after subagent returns):

```
# Mark craft sub-tasks completed
todowrite("3/5 🔨 Craft" → completed)
todowrite("4/5 🔬 Verify" → in_progress)

# Level 2 — Verify sub-tasks
todowrite("Verify: run tests" → in_progress)
todowrite("Verify: check" → pending)
todowrite("Verify: decide" → pending)
```

### Phase 4/5: Verify

| Field | Value |
|---|---|
| subagent_type | `tester` |
| skill | `grillme` |
| handoff | `04-verify.md` |
| decision | passed / blocker / escalated |

**verify prompt:**

```
你是验证员。项目类型：{project_type}，复杂度：{complexity}。

你的工作：
1. 运行所有测试，检查代码质量
2. 对照 spec 和 plan 做一致性检查
3. 对发现的问题分类并处理

runner.sh 已注入 test command：
{test_command}

如果 project_type ∈ {docs, blog, wiki}：
- 只做 lightweight verify：链接检查 + 语法检查
- 无需跑测试

然后回答：
1. 01-spec.md 中的完成标准是否都已满足？
2. 实现和 02-plan.md 是否一致？（文件列表、范围）
3. 实现是否引入了计划外的改动？
4. 质量方面：错误路径有处理吗？有硬编码值吗？有 FAI 错误信息吗？

问题分类与处理：
| 严重度 | 定义 | 处理方式 |
|---|---|---|
| blocker | 测试/类型/构建失败 | 标记 blocker，返回 craft 阶段重做 |
| major | 完成标准遗漏 | 标记 escalated，交给 orchestrator 决策 |
| minor | 风格/命名/小问题 | 直接修复，重跑相关测试确认 |

决策逻辑：
| 测试 | Plan 匹配 | Spec 匹配 | 结果 |
|---|---|---|---|
| 通过 | 是 | 是 | passed → 交付 |
| 通过 | 是 | 否 | escalated |
| 通过 | 否 | 是 | blocker → 回 craft |
| 通过 | 否 | 否 | escalated |
| 失败 | 任意 | 任意 | blocker → 回 craft |

完成后写入 04-verify.md，更新 status.json。
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Verify: run tests" → completed)
todowrite("Verify: check" → completed)
todowrite("Verify: decide" → completed)

case {verify_decision}
when "passed"
  todowrite("4/5 🔬 Verify" → passed)
  todowrite("5/5 🚀 Deliver" → in_progress)
  todowrite("Deliver: summary" → in_progress)
  todowrite("Deliver: commit" → pending)
  todowrite("Deliver: CI" → pending)
  if complexity == "complex" or project_type == "comprehensive":
    todowrite("Deliver: postmortem" → pending)
    todowrite("Deliver: neat-freak" → pending)
when "blocker"
  attempts = status.json phases.craft.attempts
  if attempts < 3:
    todowrite("4/5 🔬 Verify" → blocker)
    todowrite("3/5 🔨 Craft" → in_progress)
    todowrite("Craft retry {attempts+1}" → in_progress, priority high)
    increment craft.attempts
    return to Craft
  else:
    todowrite("4/5 🔬 Verify" → escalated)
    escalate to user
when "escalated"
  todowrite("4/5 🔬 Verify" → escalated)
  escalate to user
end
```

### Phase 5/5: Deliver

**Safety rule: 不确定 → STOP 上报，不留垃圾状态。**

| Field | Value |
|---|---|
| subagent_type | `deliverer` |
| skill | `caveman` |
| handoff | `05-deliver.md` |
| depends_on | Verify status=passed |

**RELEASING checkpoint** — only user stop in Deliver:

```
Deliver 阶段开始，orchestrator 先展示：
- 变更摘要
- 影响范围
- 测试结果
- 已知问题

Prompt user: "Release? (y/n)"
if y:
  state.sh release <feature>
  proceed with commit + CI
else:
  stop, return to Craft
```

**deliverer prompt:**

```
你是交付员。项目类型：{project_type}，复杂度：{complexity}。

输入：
- Spec：{workflow_dir}/01-spec.md
- 验证报告：{workflow_dir}/04-verify.md

重要：Verify 状态必须是 "passed"，否则中止。

请按以下步骤操作：

1. 生成摘要：变更总结、影响范围、测试结果、已知问题、回滚方案。

2. 暂存和提交：
   - `git remote -v | grep origin` — 空则打印修复命令并中止交付
   - `git fetch` — 先检查远端状态
   - `git status` — 确认只有预期文件被暂存，没有合并冲突标记
   - 如果分支分叉或合并进行中 → 停止，升级
   - 检测 project_type：
     - frontend/package.json → `npx biome check --write . && git add -u`
     - 否则 → `git add -A`
   - 检查 .gitignore 是否包含 '/.opencode/works/'（没有就报告）
   - 分类暂存文件判断是否跳过 CI：
     - SAFE_PATTERNS="^(CONTEXT\.md|[^/]+\.md|\.opencode/)"
     - 如果所有文件都匹配 → SKIP_CI=true
     - 否则 → SKIP_CI=false
   - 提交（说 WHY 不是 WHAT），`git push`（SKIP_CI 时追加 "[skip ci]"）
   - 如果推送被拒 → 停止，报告分叉，升级。不要强制推送。

3. 监控 CI（SKIP_CI 时跳过）：
   - `gh run-watch --compact --exit-status`
   - 如果失败 → 记录错误，建议回滚
   - 如果成功 → 确认交付完成

4. 如果 complexity == "complex" or project_type == "comprehensive":
   - 写入 postmortem：实际 vs Plan 偏差、retry 记录、未预见边界、决策回顾
   - 调用 neat-freak（graduation only）：把本次会话中稳定的 memory 毕业进 docs

5. 写入 handoff，更新 status.json 为 completed。
6. 提交最终报告。

CI 检查是不可妥协的门禁。
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Deliver: summary" → completed)
todowrite("Deliver: commit" → completed)
todowrite("Deliver: CI" → completed)
if complexity == "complex" or project_type == "comprehensive":
  todowrite("Deliver: postmortem" → completed)
  todowrite("Deliver: neat-freak" → completed)
todowrite("5/5 🚀 Deliver" → completed)
```

## Test Command Lookup

runner.sh 根据 `project_type` + 根目录文件检测注入测试命令：

| project_type | 检测文件 | test_command |
|---|---|---|
| `frontend` | package.json | `npm run test; npx biome ci .` |
| `backend` (Ruby) | Gemfile | `bundle exec rspec; bundle exec ruby -c lib/` |
| `backend` (Rust) | Cargo.toml | `cargo test; cargo clippy -- -D warnings` |
| `backend` (Node) | package.json（无前端框架） | `npm run test` |
| `docs` | *.md | `echo "docs lightweight verify"` |
| `blog` | 博客生成器配置 | `echo "blog lightweight verify"` |
| `wiki` | wiki/ 或 *.md | `echo "wiki lightweight verify"` |
| `comprehensive` | 按主项目类型选择 | 组合命令 |

## Dependencies

| Tool | Phase | Install |
|---|---|---|
| `gh-run-watch` | 5/5 CI monitoring | 已安装为 gh extension |

## Status.json

```json
{
  "id": "YYYY-MM-DD-desc",
  "project_type": "backend",
  "complexity": "standard",
  "domain": "generic",
  "model_tier": "mid-high",
  "subagent": "coder",
  "status": "in_progress / completed / escalated / terminated",
  "current_phase": "spec",
  "approved": false,
  "released": false,
  "created": "ISO datetime",
  "updated": "ISO datetime",
  "phases": {
    "spec":     { "status": "pending / completed / blocked", "handoff": "01-spec.md", "attempts": 0 },
    "plan":     { "status": "pending / completed / pending_approval", "handoff": "02-plan.md", "attempts": 0 },
    "craft":    { "status": "pending / completed / failed", "handoff": "03-craft.md", "attempts": 0 },
    "verify":   { "status": "pending / passed / failed / escalated", "handoff": "04-verify.md", "attempts": 0 },
    "deliver":  { "status": "pending / completed", "handoff": "05-deliver.md", "attempts": 0 }
  },
  "escalations": [],
  "retry_limits": { "craft": 3, "verify": 3 }
}
```

## Handoff Template

```markdown
# {workflow_dir}/NN-phase.md

## Status
- Phase: {phase_name}
- Status: {completed / failed / escalated / pending_approval}
- Attempt: {N}

## Decisions
- {decision} — why {原因}
  - 被拒替代方案：{方向}（reason: {为何不可}）

## Artifacts
- {path} — what changed

## Consistency Check
- Plan match: {yes / no / n/a}
- Spec match: {yes / no / n/a}

## Open Issues
- {issue}

## Notes
{free text for next phase agent}
```

## Workflow Directory Convention

```
.opencode/works/YYYY-MM-DD-task-desc/
  status.json
  01-spec.md
  02-plan.md
  03-craft.md
  04-verify.md
  05-deliver.md
```

Created at start. Agents read/write from `{workflow_dir}` = this directory. Automatically gitignored via `/.opencode/works/` in `.gitignore`.
