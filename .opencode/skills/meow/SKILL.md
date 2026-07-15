---
name: meow
description: Structured multi-phase development workflow with 5 auto-orchestrated stages (require → plan → develop → QA → release). Each phase runs as independent subagent with handoff communication, QA auto-loop, strict role boundaries. Use for "bug fix", "new feature", "improvement", "implement" tasks.
---

# Meow — Multi-Agent Development Lifecycle 🐱

5-phase loop: **🧭 1/5 Require → 📐 2/5 Plan → 🛠️ 3/5 Develop → 🔬 4/5 QA → 🚀 5/5 Release**

```
skill("meow")
```

## Meow Anchor

Activate → announce: `🐱 Meow! Meow workflow active.`

## Pipeline Overview

```
🧭 1/5 Require ──→ 📐 2/5 Plan ──→ 🛠️ 3/5 Develop ──→ 🔬 4/5 QA ──→ 🚀 5/5 Release
     ↑                 ↑ [approval]      ↑                  ↑              ↑
   done             pending           done               passed         done + CI
```

Escalation path: any gate fail → root cause → return to matching phase. 3 retry limit per phase → escalate to user.

## Progress Display

Orchestrator uses `todowrite` to show live progress. Three levels:

### Level 1 — Phase todos (5 items, created at init)

| # | Item | Status transitions |
|---|---|---|
| 1/5 | 🧭 Require | pending → in_progress → completed |
| 2/5 | 📐 Plan | pending → in_progress → pending_approval → completed |
| 3/5 | 🛠️ Develop | pending → in_progress → completed |
| 4/5 | 🔬 QA | pending → in_progress → passed / escalated |
| 5/5 | 🚀 Release | pending → in_progress → completed |

### Level 2 — Sub-task todos (phase-dependent)

| Phase | Strategy | How it's generated |
|---|---|---|
| Require | Fixed | scan → write |
| Plan | Fixed | audit → design → approve |
| Develop | **Dynamic** | Read `02-plan.md` file change list → one todo per file |
| QA | Semi-fixed | test → verify → decide (+ dynamic from `03-dev.md`) |
| Release | Fixed | summary → commit → CI |

### Dynamic todo rules

- Orchestrator reads handoff after each phase → generates Level 2 items
- Retry: add `{phase} retry {N}` todo with high priority
- Agent output mentions unexpected extra work → orchestrator creates todo

## Principles

| Abbr | Full | Apply |
|---|---|---|
| BIF | Bug ships with test that reproduces it | Development |
| EPF | Error paths before happy path | Development |
| PFC | Prefer Flat over Clever — extract after 3+ repetitions | Plan, Development |
| SAP | Single Answer Principle — one standard answer per question | All phases |
| FAI | Fail-fast with Actionable Info — error + fix command | Development, QA |
| TDA | Test Duality Assertion — test normal + error path | Development |
| OHA | One Hour Ahead — validate approach before implementing | Plan gate |
| RUM | Read file fully before editing | Development |
| MVC | Modify only intended, don't fix tangental issues | Development |
| KISS | Simple > clever | All phases |
| DRY | Don't repeat existing logic | Plan, Development |
| YAGNI | Not implement what isn't needed | Plan |

## Phase Definitions

### Hard Rules

- Every phase runs as subagent via `task(subagent_type, prompt)`. Main session orchestrates only.
- Only main session reads phase output and decides next action.
- Gates must pass before transition (see each phase gate).
- Orchestrator maintains todowrite per Progress Display section.

### Phase 1/5: Require — 需求入口

| Field | Value |
|---|---|
| subagent_type | `explore` → `general` |
| skills | `grill-with-docs` |
| handoff | `01-req.md` |
| gate | handoff exists, Done Criteria are testable |

**Orchestrator prep** (before launching subagent):

```
MW_DIR=.opencode/meoworks/YYYY-MM-DD-desc
mkdir -p $MW_DIR
if ! grep -qxF '/.opencode/meoworks/' .gitignore; then
  echo '/.opencode/meoworks/' >> .gitignore
fi
write status.json with phases all pending

# Level 1 — 5 phase todos
todowrite("1/5 🧭 Require" → in_progress, priority high)
todowrite("2/5 📐 Plan" → pending, priority high)
todowrite("3/5 🛠️ Develop" → pending, priority high)
todowrite("4/5 🔬 QA" → pending, priority high)
todowrite("5/5 🚀 Release" → pending, priority high)

# Level 2 — Require sub-tasks (fixed)
todowrite("Require: scan" → in_progress)
todowrite("Require: write" → pending)
```

**explore probe:**
```
Scan the codebase at /path for relevant files:
{task description}
Return: file paths, brief descriptions, key types/functions.
```

**general prompt:**
```
You are Requirement Analyst. Input:
Task: {task description}
Codebase scan: {explore output}

1. Load grill-with-docs, understand against existing docs.
2. Define: What (scope), Why (value), Done Criteria (testable), Edge Cases (≥3), Constraints.
3. Write handoff to {workflow_dir}/01-req.md
4. Update {workflow_dir}/status.json phase=completed

SAP, KISS. Do NOT: propose solutions, estimate time.
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Require: scan" → completed)
todowrite("Require: write" → completed)
todowrite("1/5 🧭 Require" → completed)
todowrite("2/5 📐 Plan" → in_progress)

# Level 2 — Plan sub-tasks (fixed: 3 steps)
todowrite("Plan: audit" → in_progress)
todowrite("Plan: design" → pending)
todowrite("Plan: approve" → pending)
```

### Phase 2/5: Plan — 方案设计 · 需审批

| Field | Value |
|---|---|
| subagent_type | `code-review` → `general` |
| skills | `caveman`, `grill-with-docs` |
| handoff | `02-plan.md` |
| gate | status=pending_approval, user confirmed y |

**code-review audit:**
```
Read-only audit of {workflow_dir}/01-req.md.
Read all files mentioned in the requirement's affected file list (if any).
Check: achievable with current codebase? Files affected? Patterns?
Return: audit notes + file contents read (for architect reference).
```

**general prompt:**
```
You are Architect. Input:
Requirement: {workflow_dir}/01-req.md
Audit: {code-review output}

Design:
1. File change list — add/modify/delete
2. Architecture decisions — why this, alternatives rejected
3. Implementation steps — ordered by dependency
4. Test strategy — what to test at each level

Grill against req (grill-with-docs). Compress (caveman).

Verify: KISS, DRY, YAGNI, PFC, OHA (<1h implementation).
Do NOT: change requirements, write code.
NOTE: If plan lists >5 files, orchestrator will split into multiple cycles.
Design each step as an independently deliverable unit.
Write handoff, update status.json to pending_approval. Wait for user.
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Plan: audit" → completed)
todowrite("Plan: design" → completed)
todowrite("Plan: approve" → completed)
todowrite("2/5 📐 Plan" → completed)
todowrite("3/5 🛠️ Develop" → in_progress)

# Level 2 — Develop sub-tasks (dynamic from 02-plan.md file change list)
# Parse each file change entry → one todo per entry
# Set first item in_progress, rest pending
# Example:
#   todowrite("+ lib/workouts/cli/export.rb" → in_progress)
#   todowrite("~ spec/export_spec.rb" → pending)
```

### Phase 3/5: Develop — 编码实现

| Field | Value |
|---|---|
| subagent_type | per task: `sync-dev` / `export-helper` / `spec-runner` / `frontend-dev` / `general` |
| skill | `caveman` |
| handoff | `03-dev.md` |
| gate | biome + test + build pass |

**Orchestrator prep** (before launching subagent):

```
# Level 2 dev todos already created in Phase 2 transition
# Process them sequentially as subagent completes each step
```

**general prompt:**
```
You are Developer. Input:
Plan: {workflow_dir}/02-plan.md
Approved: yes

Per step:
1. Read file (RUM), understand conventions from neighbors.
2. Implement: types → pure functions → components + tests (BIF, TDA).
3. Error paths before happy (EPF). Only plan scope (MVC).

After all steps:
1. npx biome check --write .
2. npm run typecheck
3. npm run test -w packages/web
4. Write handoff to {workflow_dir}/03-dev.md
5. Update status.json
```

**Orchestrator transition** (after subagent returns):

```
# Mark dev sub-tasks completed (orchestrator tracks per-step progress)
todowrite("3/5 🛠️ Develop" → completed)
todowrite("4/5 🔬 QA" → in_progress)

# Level 2 — QA sub-tasks (semi-fixed skeleton)
todowrite("QA: run tests" → in_progress)
todowrite("QA: verify" → pending)
todowrite("QA: decide" → pending)

# Dynamic: if 03-dev.md mentions extra concerns
# todowrite("QA: verify {specific concern}" → pending)
```

### Phase 4/5: QA — 质量检验

| Field | Value |
|---|---|
| subagent_type | `frontend-dev` → `general` |
| skill | `grillme` |
| handoff | `04-qa.md` |
| decision | passed / blocker→dev / escalated |

**spec-runner probe:**
```
Run:
1. npm run test -w packages/web -- --reporter verbose
2. npx tsc --noEmit
3. npx biome ci .
4. npm run build
Return: raw output + exit codes.
```

**general prompt:**
```
You are QA Engineer. DO NOT propose fixes.
Input: all handoffs + test results.

Verify:
1. Done Criteria from 01-req.md — check each.
2. Plan consistency — dev output vs plan (files? scope?).
3. Requirement consistency — dev output vs done criteria.
4. Quality: FAI? Error paths? Hardcoded values?

Severity: blocker (test/type/build failure) | major (criteria missed) | minor (style/naming)

With minor issues: "passed → release" only if zero minors.
If minors exist and plan+req match → "continue" (回 development
to fix minors, no re-run QA. Orchestrator applies fixes directly).

Decision:
| Tests | Plan match | Req match | Result |
|---|---|---|---|
| pass | yes | yes | passed → release |
| pass | yes | no | escalated |
| pass | no | yes | 回 development |
| pass | no | no | escalated |
| fail | any | any | blocker → dev |
| fail x3 | any | any | escalated |

Root cause routing: dev≠plan → dev; plan≠req → plan; multi-phase → escalated.

Write handoff, update status.json.
```

**Orchestrator transition** (after subagent returns):

```
todowrite("QA: run tests" → completed)
todowrite("QA: verify" → completed)
todowrite("QA: decide" → completed)

case {qa_decision}
when "passed"
  todowrite("4/5 🔬 QA" → passed)
  todowrite("5/5 🚀 Release" → in_progress)
  # Level 2 — Release sub-tasks (fixed)
  todowrite("Release: summary" → in_progress)
  todowrite("Release: commit" → pending)
  todowrite("Release: CI" → pending)
when "blocker"
  todowrite("4/5 🔬 QA" → escalated)
  todowrite("3/5 🛠️ Develop" → in_progress)
  todowrite("Develop retry 1" → in_progress, priority high)
when "escalated"
  todowrite("4/5 🔬 QA" → escalated)
end
```

### Phase 5/5: Release — 发布交付

| Field | Value |
|---|---|
| subagent_type | `docs-writer` → `general` |
| skill | `caveman` |
| handoff | `05-release.md` |
| depends_on | QA status=passed |

**general prompt:**
```
You are Release Manager. Input:
Requirement: {workflow_dir}/01-req.md
QA report: {workflow_dir}/04-qa.md

IMPORTANT: QA status MUST be "passed". If not, abort.

1. Generate summary: change summary, scope, test results, known issues, rollback.

2. Stage and commit:
   - git status — only intended files staged
   - npx biome check --write . && git add -u  ← ensure no lint CI failure
   - Check .gitignore contains '/.opencode/meoworks/' (report if missing)
   - Commit (WHY not WHAT), push

3. Monitor CI:
   - gh run-watch --compact --exit-status   ← requires gh-run-watch installed
   - If failure → log error, recommend rollback
   - If success → confirm release

4. Write handoff, update status.json to completed.
5. Present final report.

CI check is non-negotiable gate.
```

**Orchestrator transition** (after subagent returns):

```
todowrite("Release: summary" → completed)
todowrite("Release: commit" → completed)
todowrite("Release: CI" → completed)
todowrite("5/5 🚀 Release" → completed)
```

## Dependencies

| Tool | Phase | Install |
|---|---|---|
| `gh-run-watch` | 5/5 CI monitoring | `cp scripts/gh-run-watch ~/.local/share/gh/extensions/gh-run-watch/ && chmod +x ~/.local/share/gh/extensions/gh-run-watch/gh-run-watch` |

Predicts CI duration from recent runs (median), sleeps predictively, delegates to `gh run watch`. Supports `--compact`, `--exit-status`. Project script at `scripts/gh-run-watch`.

## Status.json

```json
{
  "id": "YYYY-MM-DD-desc",
  "status": "in_progress / completed / escalated / terminated",
  "current_phase": "phase_name",
  "created": "ISO datetime",
  "updated": "ISO datetime",
  "phases": {
    "require": { "status": "pending / completed / blocked", "handoff": "01-req.md", "attempts": 0 },
    "plan":        { "status": "pending / completed / pending_approval", "handoff": "02-plan.md", "attempts": 0 },
    "development": { "status": "pending / completed / failed", "handoff": "03-dev.md", "attempts": 0 },
    "qa":          { "status": "pending / passed / failed / escalated", "handoff": "04-qa.md", "attempts": 0 },
    "release":     { "status": "pending / completed", "handoff": "05-release.md", "attempts": 0 }
  },
  "escalations": [],
  "retry_limits": { "development": 3, "qa": 3 }
}
```

## Role Boundaries

| Agent | Scope | Prohibited |
|---|---|---|
| Require | Understand problem, define done criteria | Design solutions, estimate time |
| Plan | Design solution, assess impact | Change requirements, write code |
| Develop | Implement per plan, write tests | Change reqs, redesign architecture |
| QA | Run tests, check consistency, classify | Fix bugs, propose solutions |
| Release | Write summary, commit, push | Change code or requirements |

## Handoff Template

```markdown
# {workflow_dir}/NN-phase.md

## Status
- Phase: {phase_name}
- Status: {completed / failed / escalated / pending_approval}
- Attempt: {N}

## Decisions
- {decision 1}

## Artifacts
- {path} — what changed

## Consistency Check
- Plan match: {yes / no / n/a}
- Req match: {yes / no / n/a}

## Open Issues
- {issue}

## Notes
{free text for next phase agent}
```

## Workflow Directory Convention

```
.opencode/meoworks/YYYY-MM-DD-task-desc/
  status.json
  01-req.md
  02-plan.md
  03-dev.md
  04-qa.md
  05-release.md
```

Created at start. Agents read/write from `{workflow_dir}` = this directory. Automatically gitignored via `/.opencode/meoworks/` in `.gitignore`.
