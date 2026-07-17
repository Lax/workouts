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

### Phase 1/5: Spec — 规格定义

| Field | Value |
|---|---|
| subagent_type | `explore` → `general` → `general` (消歧) |
| skills | `grill-with-docs` |
| handoff | `01-spec.md` |
| gate | handoff exists, Done Criteria are testable, **零歧义确认** |

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

**explore probe:**
```
Scan the codebase at /path for relevant files:
{task description}
Return: file paths, brief descriptions, key types/functions.

IMPORTANT: Return raw facts only. Do NOT interpret "upstream" or "reference" —
just return what the files say.
```

**Pre-flight Ambiguity Scan (PFAS) — 在写需求之前强制消歧:**

Orchestrator launches a general agent with this prompt BEFORE the Spec writer:

```
You are Disambiguator. Your ONLY job is to find ambiguous references.
Do NOT design solutions, write specs, or estimate effort.

Input:
- User task: {task description}
- Codebase scan: {explore output}
- CONTEXT.md at CONTEXT.md

Instructions:

1. Extract all "referenced external concepts" from the user task.
   External concepts include: "上游", "upstream", "reference implementation",
   "来源", "参考", "源头", "original", "like X", "similar to X".
   Also include any named projects, frameworks, or themes mentioned.

2. For each external concept, find ALL declarations in CONTEXT.md:
   - Each project/theme may declare its own upstream in CONTEXT.md
   - Example: CONTEXT.md for this project says theme-simple is "faithful to running_page"
   - If the user says "上游" but multiple upstreams exist, that's ambiguity

3. Cross-reference: Does the user's statement match CONTEXT.md's declaration?
   - User says X → CONTEXT.md says Y → ⛔ AMBIGUITY
   - User says nothing specific → CONTEXT.md declares Y for this context → ✅ IMPLICIT (use Y)
   - User says X → CONTEXT.md also says X → ✅ CLEAR

4. If ANY ambiguity found:
   - Write {workflow_dir}/01-ambiguity.md with:
     - Each ambiguous term
     - Conflicting definitions (user statement vs CONTEXT.md)
     - Required clarification question
   - Set status.json spec.status = "blocked"
   - STOP. Do NOT proceed to write the spec.

5. If zero ambiguity:
   - Write {workflow_dir}/01-ambiguity.md with:
     - "status": "clear"
     - List of resolved terms and their confirmed definitions
   - Set status.json spec.status = "in_progress" (so spec writer can proceed)
   - Return "CLEAR" as final message.

Strict rules:
- Do NOT guess. If uncertain → flag as ambiguous.
- Do NOT assume user's intent matches a convenient comparison target.
- Do NOT merge multiple upstream definitions silently.
- SAP: one answer per concept. If multiple exist, block.
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

**spec writer (general) prompt:**
```
You are Specifier. Input:
Task: {task description}
Codebase scan: {explore output}
Ambiguity resolution: {workflow_dir}/01-ambiguity.md

1. Load grill-with-docs, understand against existing docs.
2. Define: What (scope), Why (value), Done Criteria (testable), Edge Cases (≥3), Constraints.
3. Use the disambiguated definitions from 01-ambiguity.md for ALL external references.
   Do NOT introduce new external references without disambiguation.
4. Write handoff to {workflow_dir}/01-spec.md
5. Update {workflow_dir}/status.json phase=completed

SAP, KISS. Do NOT: propose solutions, estimate time.
```

**Orchestrator transition** (after spec writer returns):

```
# The Consistency Gate — 在 Spec→Plan 之间强制执行
# 1. Read 01-spec.md
# 2. Read 01-ambiguity.md to confirm all references were used correctly
# 3. Verify spec's "Constraints" section matches CONTEXT.md declarations
# 4. If spec introduces a reference not in the ambiguity resolution → BLOCK
# 5. If spec contradicts CONTEXT.md on any project declaration → BLOCK

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

### Phase 2/5: Plan — 方案设计 · 需审批

| Field | Value |
|---|---|
| subagent_type | `code-review` → `general` |
| skills | `caveman`, `grill-with-docs` |
| handoff | `02-plan.md` |
| gate | status=pending_approval, user confirmed y |

**code-review audit:**
```
Read-only audit of {workflow_dir}/01-spec.md.
Read all files mentioned in the spec's affected file list (if any).
Check: achievable with current codebase? Files affected? Patterns?
Return: audit notes + file contents read (for planner reference).
```

**general prompt:**
```
You are Planner. Input:
Spec: {workflow_dir}/01-spec.md
Audit: {code-review output}

Design:
1. File change list — add/modify/delete
2. Architecture decisions — why this, alternatives rejected
3. Implementation steps — ordered by dependency
4. Test strategy — what to test at each level

Grill against spec (grill-with-docs). Compress (caveman).

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
todowrite("3/5 🔨 Craft" → in_progress)

# Level 2 — Craft sub-tasks (dynamic from 02-plan.md file change list)
# Parse each file change entry → one todo per entry
# Set first item in_progress, rest pending
# Example:
#   todowrite("+ lib/workouts/cli/export.rb" → in_progress)
#   todowrite("~ spec/export_spec.rb" → pending)
```

### Phase 3/5: Craft — 编码实现

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
You are Crafter. Input:
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
4. Write handoff to {workflow_dir}/03-craft.md
5. Update status.json
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

### Phase 4/5: Verify — 质量核验

| Field | Value |
|---|---|
| subagent_type | `frontend-dev` → `general` |
| skill | `grillme` |
| handoff | `04-verify.md` |
| decision | passed / blocker→craft / escalated |

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
You are Verifier. DO NOT propose fixes.
Input: all handoffs + test results.

Verify:
1. Done Criteria from 01-spec.md — check each.
2. Plan consistency — craft output vs plan (files? scope?).
3. Spec consistency — craft output vs done criteria.
4. Quality: FAI? Error paths? Hardcoded values?

Severity: blocker (test/type/build failure) | major (criteria missed) | minor (style/naming)

With minor issues: "passed → deliver" only if zero minors.
If minors exist and plan+spec match → "continue" (回 craft
to fix minors, no re-run Verify. Orchestrator applies fixes directly).

Decision:
| Tests | Plan match | Spec match | Result |
|---|---|---|---|
| pass | yes | yes | passed → deliver |
| pass | yes | no | escalated |
| pass | no | yes | 回 craft |
| pass | no | no | escalated |
| fail | any | any | blocker → craft |
| fail x3 | any | any | escalated |

Root cause routing: craft≠plan → craft; plan≠spec → plan; multi-phase → escalated.

Write handoff, update status.json.
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

### Phase 5/5: Deliver — 交付上线

**Safety rule: 任何不确定 → STOP 上报。不制造需要人工清理的后果。**

| Field | Value |
|---|---|
| subagent_type | `docs-writer` → `general` |
| skill | `caveman` |
| handoff | `05-deliver.md` |
| depends_on | Verify status=passed |

**general prompt:**
```
You are Deliverer. Input:
Spec: {workflow_dir}/01-spec.md
Verify report: {workflow_dir}/04-verify.md

IMPORTANT: Verify status MUST be "passed". If not, abort.
IMPORTANT: This phase overrides the "NEVER commit" general rule.
  Auto-execute commit/push/CI when:
    - Verify passed with no blocker issues
    - No git-level conflicts (remote not diverged, push will succeed)
  If git conflict detected (rejected push, divergent history, merge needed):
    → STOP. Report conflict details. Escalate to user. Do NOT force-push.
  Do NOT ask user for commit permission.
  If CI fails → report + recommend rollback. Do not hide failure.

1. Generate summary: change summary, scope, test results, known issues, rollback.

2. Stage and commit:
   - `git fetch` — check remote state before any write
   - `git status` — only intended files staged, no merge conflict markers
   - If `git status` shows diverged branches or merge in progress → STOP, escalate
    - npx biome check --write . && git add -u  ← ensure no lint CI failure
    - Check .gitignore contains '/.opencode/meoworks/' (report if missing)
    - Classify staged files for CI skip:
      - `git diff --name-only --cached` → file list
      - SAFE_PATTERNS="^(docs/|CONTEXT\.md|[^/]+\.md|\.opencode/)"
      - If ALL staged files match SAFE_PATTERNS → SKIP_CI=true
      - Else → SKIP_CI=false
    - Commit (WHY not WHAT), `git push` (append "[skip ci]" if SKIP_CI)
    - If push rejected → STOP, report divergence, escalate. Never force-push.

3. Monitor CI (skip if SKIP_CI):
    - gh run-watch --compact --exit-status   ← requires gh-run-watch installed
    - If failure → log error, recommend rollback
    - If success → confirm deliver

4. Write handoff, update status.json to completed.
5. Present final report.

CI check is non-negotiable gate.
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

## Role Boundaries

| Agent | Scope | Prohibited |
|---|---|---|
| Specifier | Understand problem, define done criteria | Design solutions, estimate time |
| Planner | Design solution, assess impact | Change requirements, write code |
| Crafter | Implement per plan, write tests | Change reqs, redesign architecture |
| Verifier | Run tests, check consistency, classify | Fix bugs, propose solutions |
| Deliverer | Write summary, commit, push | Change code or requirements |

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
