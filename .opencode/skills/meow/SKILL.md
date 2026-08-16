---
name: meow
description: Structured multi-phase development workflow with 5 auto-orchestrated stages (spec → plan → craft → verify → deliver). Each phase runs as independent subagent with handoff communication, verify auto-loop, strict role boundaries. Use for "bug fix", "new feature", "improvement", "implement" tasks.
---

# Meow — Multi-Agent Development Lifecycle 🐱

5-phase loop: **📋 1/5 Spec → 📐 2/5 Plan → 🔨 3/5 Craft → 🔬 4/5 Verify → 🚀 5/5 Deliver**

```
skill("meow")
```

## Meow Anchor

Activate → announce: `🐱 Meow! Meow workflow active.`

## Pipeline Overview

```
📋 1/5 Spec ──→ 📐 2/5 Plan ──→ 🔨 3/5 Craft ──→ 🔬 4/5 Verify ──→ 🚀 5/5 Deliver
     ↑                 ↑ [approval]      ↑                  ↑              ↑
   done             pending           done               passed         done + CI
```

Escalation path: any gate fail → root cause → return to matching phase. 3 retry limit per phase → escalate to user.

## Progress Display

Orchestrator uses `todowrite` to show live progress. Three levels:

### Level 1 — Phase todos (5 items, created at init)

| # | Item | Status transitions |
|---|---|---|
| 1/5 | 📋 Spec | pending → in_progress → completed |
| 2/5 | 📐 Plan | pending → in_progress → pending_approval → completed |
| 3/5 | 🔨 Craft | pending → in_progress → completed |
| 4/5 | 🔬 Verify | pending → in_progress → passed / escalated |
| 5/5 | 🚀 Deliver | pending → in_progress → completed |

### Level 2 — Sub-task todos (phase-dependent)

| Phase | Strategy | How it's generated |
|---|---|---|
| Spec | Fixed | scan → write |
| Plan | Fixed | audit → design → approve |
| Craft | **Dynamic** | Read `02-plan.md` file change list → one todo per file |
| Verify | Semi-fixed | test → check → decide (+ dynamic from `03-craft.md`) |
| Deliver | Fixed | summary → commit → CI |

### Dynamic todo rules

- Orchestrator reads handoff after each phase → generates Level 2 items
- Retry: add `{phase} retry {N}` todo with high priority
- Agent output mentions unexpected extra work → orchestrator creates todo

## Principles

| Abbr | Full | Apply |
|---|---|---|
| BIF | Bug ships with test that reproduces it | Craft |
| EPF | Error paths before happy path | Craft |
| PFC | Prefer Flat over Clever — extract after 3+ repetitions | Plan, Craft |
| SAP | Single Answer Principle — one standard answer per question | All phases |
| FAI | Fail-fast with Actionable Info — error + fix command | Craft, Verify |
| TDA | Test Duality Assertion — test normal + error path | Craft |
| OHA | One Hour Ahead — validate approach before implementing | Plan gate |
| RUM | Read file fully before editing | Craft |
| MVC | Modify only intended, don't fix tangental issues | Craft |
| KISS | Simple > clever | All phases |
| DRY | Don't repeat existing logic | Plan, Craft |
| YAGNI | Not implement what isn't needed | Plan |

## Phase Definitions

### Hard Rules

- Every phase runs as subagent via `task(subagent_type, prompt)`. Main session orchestrates only.
- Only main session reads phase output and decides next action.
- Gates must pass before transition (see each phase gate).
- Orchestrator maintains todowrite per Progress Display section.

## Available Subagents

| Agent | Type | 职责 | Used In |
|---|---|---|---|
| `explore` | built-in | 快速扫描代码库，收集原始事实 | Spec probe |
| `general` | built-in | 通用 agent，无领域限定 | Spec, Plan, Craft, Deliver |
| `code-review` | `.opencode/agents/code-review.md` | 只读代码审查，对照约定检查 | Plan audit |
| `verify` | `.opencode/agents/verify.md` | 运行测试、一致性检查、修 minor 问题 | Verify |
| `docs-writer` | `.opencode/agents/docs-writer.md` | 撰写和维护文档 | Deliver |
| `sync-dev` | `.opencode/agents/sync-dev.md` | 同步适配器开发调试 | Craft (sync domain) |
| `export-helper` | `.opencode/agents/export-helper.md` | 导出功能开发调试 | Craft (export domain) |
| `frontend-dev` | `.opencode/agents/frontend-dev.md` | 前端开发调试 | Craft (frontend domain) |
| `spec-runner` | `.opencode/agents/spec-runner.md` | 运行 RSpec 测试，报告结果 | Craft (test domain) |
| `ci-debug` | `.opencode/agents/ci-debug.md` | CI/CD 调试，cache、cron | Craft (CI domain) |

## Role Boundaries

| Agent | Scope | Prohibited |
|---|---|---|
| Specifier | 理解问题，定义完成标准 | 设计方案，估算时间 |
| Planner | 设计方案，评估影响 | 改变需求，写代码 |
| Crafter | 按计划实现，写测试 | 改变需求，重设计架构 |
| Verifier | 运行测试、检查一致性、分类问题、修 minor | 修 bug、改架构 |
| Deliverer | 写摘要、提交、推送、监控 CI | 改代码或需求 |

### Phase 1/5: Spec

| Field | Value |
|---|---|
| subagent_type | `explore` → `general` (消歧员) → `general` (规格员) |
| skills | `grill-with-docs` |
| handoff | `01-spec.md` |
| gate | handoff exists, Done Criteria are testable, ambiguity resolved |

**Orchestrator prep** (before launching subagent):

```
MW_DIR=.opencode/meoworks/YYYY-MM-DD-desc
mkdir -p $MW_DIR
if ! grep -qxF '/.opencode/meoworks/' .gitignore; then
  echo '/.opencode/meoworks/' >> .gitignore
fi
write status.json with phases all pending

# Level 1 — 5 phase todos
todowrite("1/5 📋 Spec" → in_progress, priority high)
todowrite("2/5 📐 Plan" → pending, priority high)
todowrite("3/5 🔨 Craft" → pending, priority high)
todowrite("4/5 🔬 Verify" → pending, priority high)
todowrite("5/5 🚀 Deliver" → pending, priority high)

# Level 2 — Spec sub-tasks (fixed)
todowrite("Spec: scan" → in_progress)
todowrite("Spec: disambiguate" → pending)
todowrite("Spec: write" → pending)
```

**Veto context**（spec 启动前）：
长对话/任务描述中已出现的用户否决（方向+原因），orchestrator 先行写入 `{workflow_dir}/01-ambiguity.md` 的 `vetoes` 块：
```
## Vetoes
| 被拒方向 | 否决者 | 为何否决 |
```
规格员以 `01-ambiguity.md` 为唯一否决事实来源；否决只存在于对话而未落盘 → 视为未消歧。

**explore probe:**
```
你能扫描代码库，找出所有相关的文件吗？

任务描述：{task}

请告诉我：
- 找到了哪些文件？
- 它们各自的功能是什么？
- 涉及哪些关键类型和函数？

注意：只返回原始事实，不要解释 "upstream" 或 "reference"——只描述文件中实际的内容。
```

**Pre-flight Ambiguity Scan (PFAS):**

Orchestrator 先启动一个 general agent 做消歧，再启动 spec writer：

```
你是消歧员。唯一任务：找到模糊的引用。
不要设计方案、不写规格、不估算工作量。

输入：
- 用户任务：{task description}
- 代码库扫描结果：{explore output}
- CONTEXT.md：CONTEXT.md

请按以下步骤处理：

1. 从用户任务中提取所有"被引用的外部概念"。
   外部概念包括："上游"、"upstream"、"reference implementation"、
   "来源"、"参考"、"源头"、"original"、"like X"、"similar to X"。
   也包括提到的具体项目、框架或主题名。

2. 对每个外部概念，在 CONTEXT.md 中找到所有声明：
   每个项目/主题可能声明自己的上游来源。如果用户说"上游"但存在多个上游声明，那就是模糊。

3. 交叉对照：用户的表述和 CONTEXT.md 的一致吗？
   - 用户说 X → CONTEXT.md 说 Y → ⛔ 模糊
   - 用户没说具体 → CONTEXT.md 对当前上下文明确定义了 Y → ✅ 隐含（用 Y）
   - 用户说 X → CONTEXT.md 也说 X → ✅ 清晰

4. 如果发现任何模糊：
   - 写入 {workflow_dir}/01-ambiguity.md，包含：
     - 每个模糊术语
     - 冲突定义（用户 vs CONTEXT.md）
     - 需要澄清的问题
   - 设置 status.json spec.status = "blocked"
   - 停止。不要继续写 spec。

5. 如果没有模糊：
   - 写入 {workflow_dir}/01-ambiguity.md，包含：
     - "status": "clear"
     - 已确认的术语列表和定义
   - 设置 status.json spec.status = "in_progress"（让 spec writer 继续）
   - 返回 "CLEAR"

严格规则：
- 不要猜测。不确定就标记模糊。
- 不要假设用户意图等于某个方便的比较对象。
- 不要静默合并多个上游定义。
- SAP：每个概念只有一个答案。有多个就阻塞。
```

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
- 代码库扫描：{explore output}
- 模糊消歧结果：{workflow_dir}/01-ambiguity.md

请做以下事情：
1. 你能加载 grill-with-docs，对照现有文档理解需求吗？
2. 请定义：范围（做什么）、价值（为什么做）、完成标准（可验证）、边界情况（至少 3 个）、约束条件。
3. 请定义「已否决方向」表格并写入 01-spec.md。表列：`被拒方向 | 否决者（用户/现状约束/性能等） | 为何否决 | 对应约束/结论`。范围：只记有真实替代方案或用户明确否决的项（含 01-ambiguity.md 的 vetoes）；平凡回落默认（如非法配置值→默认）不记，否则噪音。每条否决必须有 why；某条约束/决策无 why 且查不到否决来源 → 标记未消歧写入开放问题，不得猜。
4. 所有外部引用必须使用 01-ambiguity.md 中消歧后的定义。不要引入未经消歧的新外部引用。
5. 写入 handoff 到 {workflow_dir}/01-spec.md
6. 更新 {workflow_dir}/status.json phase=completed

遵守 SAP、KISS。不要提案解决方案，不要估算时间。
```

**Orchestrator transition** (after spec writer returns):

```
# Consistency Gate — 确保 spec→plan 一致性
# 1. 读取 01-spec.md
# 2. 读取 01-ambiguity.md，确认所有引用都正确使用
# 3. 验证 spec 的"约束条件"部分是否与 CONTEXT.md 一致
# 4. 如果 spec 引入了消歧结果中没有的引用 → 阻塞
# 5. 如果 spec 与 CONTEXT.md 中任何项目声明矛盾 → 阻塞
# 6. 验证 spec 的"已否决方向"表格：
#    - 每条否决都有 why
#    - 每条"约束/结论"都能追溯到一条已否决方向或明确决策（非平凡默认）
#    缺失 why 或约束无来源 → 阻塞

if gate passes:
  todowrite("Spec: scan" → completed)
  todowrite("Spec: disambiguate" → completed)
  todowrite("Spec: write" → completed)
  todowrite("1/5 📋 Spec" → completed)
  todowrite("2/5 📐 Plan" → in_progress)

  # Level 2 — Plan sub-tasks (fixed: 3 steps)
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
| subagent_type | `code-review` → `general` |
| skills | `caveman`, `grill-with-docs` |
| handoff | `02-plan.md` |
| gate | status=pending_approval, user confirmed y |

**code-review audit:**
```
你能对 {workflow_dir}/01-spec.md 做只读审计吗？

请读取 spec 中提到的所有文件（如果有影响文件列表的话）。
请检查：
- 在当前代码库中可以实现吗？
- 会影响哪些文件？
- 需要遵循什么模式？

返回：审计笔记 + 读取的文件内容（供 planner 参考）。
```

**general prompt:**
```
你是方案员。

输入：
- Spec：{workflow_dir}/01-spec.md
- 审计结果：{code-review output}

请设计方案，回答以下问题：
1. 需要新增、修改、删除哪些文件？
2. 架构决策：为什么选这个方案？拒绝了哪些替代方案？
3. 实现步骤：按依赖关系排序，每步应该是可独立交付的单元。
4. 测试策略：每层应该测试什么？

请用 grill-with-docs 对 spec 做交叉审查，用 caveman 风格压缩表达。

需要验证的原则：KISS、DRY、YAGNI、PFC、OHA（实现不超过 1 小时）。
如果计划涉及超过 5 个文件，orchestrator 会拆成多个周期，请确保每步独立可交付。

不要改变需求，不要写代码。
写入 handoff，更新 status.json 为 pending_approval，等待用户确认。
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Plan: audit" → completed)
todowrite("Plan: design" → completed)
todowrite("Plan: approve" → completed)
todowrite("2/5 📐 Plan" → completed)
todowrite("3/5 🔨 Craft" → in_progress)

# Level 2 — Craft sub-tasks (dynamic from 02-plan.md file change list)
# Parse each file change entry → one todo per entry
# Set first item in_progress, rest pending
# Example:
#   todowrite("+ lib/workouts/cli/export.rb" → in_progress)
#   todowrite("~ spec/export_spec.rb" → pending)
```

### Phase 3/5: Craft

| Field | Value |
|---|---|
| subagent_type | per task: `sync-dev` / `export-helper` / `spec-runner` / `frontend-dev` / `general` |
| skill | `caveman` |
| handoff | `03-craft.md` |
| gate | biome + test + build pass |

**Orchestrator prep** (before launching subagent):

```
# Level 2 craft todos already created in Phase 2 transition
# Process them sequentially as subagent completes each step
```

**general prompt:**
```
你是实现员。

输入：
- 计划：{workflow_dir}/02-plan.md
- 已批准

请按步骤实现：
1. 你能先完全读取文件，理解周围的代码约定吗？（RUM）
2. 实现顺序：类型 → 纯函数 → 组件 + 测试（BIF、TDA）
3. 错误路径优先于正常路径（EPF），只做计划范围内的改动（MVC）

所有步骤完成后：
1. npx biome check --write .
2. npm run typecheck
3. npm run test -w packages/web
4. 写入 handoff 到 {workflow_dir}/03-craft.md
5. 更新 status.json
```

**Orchestrator transition** (after subagent returns):

```
# Mark craft sub-tasks completed (orchestrator tracks per-step progress)
todowrite("3/5 🔨 Craft" → completed)
todowrite("4/5 🔬 Verify" → in_progress)

# Level 2 — Verify sub-tasks (semi-fixed skeleton)
todowrite("Verify: run tests" → in_progress)
todowrite("Verify: check" → pending)
todowrite("Verify: decide" → pending)

# Dynamic: if 03-craft.md mentions extra concerns
# todowrite("Verify: check {specific concern}" → pending)
```

### Phase 4/5: Verify

| Field | Value |
|---|---|
| subagent_type | `verify` |
| skill | `grillme` |
| handoff | `04-verify.md` |
| decision | passed / blocker / escalated |

**verify prompt:**
```
你是验证员。

你的工作是：
1. 运行所有测试，检查代码质量
2. 对照 spec 和 plan 做一致性检查
3. 对发现的问题分类并处理

请先运行以下命令收集结果：
- 后端测试：`bundle exec rspec`
- 前端测试：`npm run test -w packages/web -- --reporter verbose`
- 类型检查：`npx tsc --noEmit`
- 代码风格：`npx biome ci .`
- 构建验证：`npm run build`

然后回答以下问题：
1. 01-spec.md 中的完成标准是否都已满足？
2. 实现和 02-plan.md 是否一致？（文件列表、范围？）
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
| 失败 x3 | 任意 | 任意 | escalated |

根因路由：craft≠plan → 回 craft；plan≠spec → 升级；多阶段 → 升级。

完成后写入 04-verify.md handoff 文件，更新 status.json。
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
  # Level 2 — Deliver sub-tasks (fixed)
  todowrite("Deliver: summary" → in_progress)
  todowrite("Deliver: commit" → pending)
  todowrite("Deliver: CI" → pending)
when "blocker"
  todowrite("4/5 🔬 Verify" → escalated)
  todowrite("3/5 🔨 Craft" → in_progress)
  todowrite("Craft retry 1" → in_progress, priority high)
when "escalated"
  todowrite("4/5 🔬 Verify" → escalated)
end
```

### Phase 5/5: Deliver

**Safety rule: 不确定 → STOP 上报，不留垃圾状态。**

| Field | Value |
|---|---|
| subagent_type | `docs-writer` → `general` |
| skill | `caveman` |
| handoff | `05-deliver.md` |
| depends_on | Verify status=passed |

**general prompt:**
```
你是交付员。

输入：
- Spec：{workflow_dir}/01-spec.md
- 验证报告：{workflow_dir}/04-verify.md

重要：Verify 状态必须是 "passed"，否则中止。
重要：本阶段覆盖"永不提交"的通用规则。在以下条件满足时自动执行提交/推送/CI：
  - Verify 通过，无 blocker 问题
  - 无 git 冲突（远端未分叉，推送会成功）
如果有 git 冲突（推送被拒、历史分叉、需要合并）：
  → 停止。报告冲突详情，升级给用户。不要强制推送。
不要询问用户提交权限。
如果 CI 失败 → 记录错误，建议回滚。不要隐藏失败。

请按以下步骤操作：

1. 生成摘要：变更总结、影响范围、测试结果、已知问题、回滚方案。

2. 暂存和提交：
   - `git fetch` — 先检查远端状态
   - `git status` — 确认只有预期文件被暂存，没有合并冲突标记
   - 如果 `git status` 显示分支分叉或合并进行中 → 停止，升级
   - `npx biome check --write . && git add -u` — 确保 lint 不会导致 CI 失败
   - 检查 .gitignore 是否包含 '/.opencode/meoworks/'（没有就报告）
   - 分类暂存文件判断是否跳过 CI：
     - `git diff --name-only --cached` → 文件列表
      - SAFE_PATTERNS="^(CONTEXT\.md|[^/]+\.md|\.opencode/)"
     - 如果所有文件都匹配 → SKIP_CI=true
     - 否则 → SKIP_CI=false
   - 提交（说 WHY 不是 WHAT），`git push`（SKIP_CI 时追加 "[skip ci]"）
   - 如果推送被拒 → 停止，报告分叉，升级。不要强制推送。

3. 监控 CI（SKIP_CI 时跳过）：
   - `gh run-watch --compact --exit-status` ← gh extension（已装在用户目录）
   - 如果失败 → 记录错误，建议回滚
   - 如果成功 → 确认交付完成

4. 写入 handoff，更新 status.json 为 completed。
5. 提交最终报告。

CI 检查是不可妥协的门禁。
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Deliver: summary" → completed)
todowrite("Deliver: commit" → completed)
todowrite("Deliver: CI" → completed)
todowrite("5/5 🚀 Deliver" → completed)
```

## Dependencies

| Tool | Phase | Install |
|---|---|---|
| `gh-run-watch` | 5/5 CI monitoring | 已安装为 gh extension（`~/.local/share/gh/extensions/gh-run-watch/`），仓库内无副本 |

Predicts CI duration from recent runs (median), sleeps predictively, delegates to `gh run watch`. Supports `--compact`, `--exit-status`.

## Status.json

```json
{
  "id": "YYYY-MM-DD-desc",
  "status": "in_progress / completed / escalated / terminated",
  "current_phase": "phase_name",
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
.opencode/meoworks/YYYY-MM-DD-task-desc/
  status.json
  01-spec.md
  02-plan.md
  03-craft.md
  04-verify.md
  05-deliver.md
```

Created at start. Agents read/write from `{workflow_dir}` = this directory. Automatically gitignored via `/.opencode/meoworks/` in `.gitignore`.
