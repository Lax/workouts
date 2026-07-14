---
name: meow
description: Structured multi-phase development workflow with 5 auto-orchestrated stages (requirement → plan → development → QA → release). Each phase runs as an independent subagent with handoff communication, QA auto-loop with escalation, strict role boundaries, and 12 development principles. Use when user says "bug fix", "new feature", "improvement", "implement" or describes a task needing structured execution.
---

# Meow — Multi-Agent Development Lifecycle 🐱

5-phase loop: **requirement → plan → development → qa → release**

```
skill("meow")
```

---

## Meow Anchor

When activated, announce with a meow:

```
🐱 Meow! Moew workflow active.
```

Serves as a heartbeat — confirms the skill loaded successfully. Not required on every output, just the initial activation.

---

## Principles

| Abbr | Full | Apply |
|---|---|---|
| BIF | Bug ships with test that reproduces it | Development |
| EPF | Error paths before happy path | Development |
| PFC | Prefer Flat over Clever — no premature abstraction | Plan, Development |
| SAP | Single Answer Principle — one standard answer per question | All phases |
| FAI | Fail-fast with Actionable Info — every error includes fix command | Development, QA |
| TDA | Test Duality Assertion — test both normal and error paths | Development |
| OHA | One Hour Ahead — validate approach before implementing | Plan gate |
| RUM | Read file fully before editing | Development |
| MVC | Modify only what's intended, don't fix tangental issues | Development |
| KISS | Simple > clever | All phases |
| DRY | Don't repeat existing logic | Plan, Development |
| YAGNI | Don't implement what isn't needed | Plan |

---

## Meow Anchor

When invoked, the very first output line MUST be:

```
🐱 Meow! Moew workflow active.
```

This confirms the skill is loaded and context is intact. If this line is missing, context may have been lost — re-invoke the skill.

## Workflow Loop

```
                         ┌──────────────────┐
                         │   requirement    │ explore + general
                         └────────┬─────────┘
                                  │ completed
                         ┌────────▼─────────┐
                         │      plan        │ code-review + general
                         └────────┬─────────┘
                                  │ completed
      user: n ◄──────────┌────────▼──────────┐
                         │ pending_approval  │
      user: y ─────────►└────────┬──────────┘
                                  │
                         ┌────────▼─────────┐
                         │   development    │ per-task agent
                         └────────┬─────────┘
                                  │ completed
                         ┌────────▼─────────┐
                         │       qa         │ spec-runner + general
                         └────────┬─────────┘
                  ┌────────┬───────┼───────┬──────────────┐
                  │        │       │       │              │
              pass     minor   blocker/  inconsistent  dev/qa over
                              major      + no root   retry_limit
                  │        │       │       │              │
                  ▼        ▼       ▼       ▼              ▼
              release  continue  ┌──┴───┐  escalated ──────┐
                  │        │     │ root │     │            │
                  ▼        │     │cause │  user decide     │
               DONE        │     │   ┌──┤  which phase     │
                           │     │   │  │                  │
                           │     │   │  │       ◄──────────┘
                           │     │   │  ▼
                           │     │   │ ┌──────────┐
                           │     │   │ │ 回相符   │
                           │     │   │ │ 阶段     │
                           │     │   │ └────┬─────┘
                           │     │   └──┬───┘
                           │     │      │
                           │     │  ┌───▼────┐
                           │     │  │ 没有    │
                           │     │  │ 匹配的  │
                           │     │  │ → esc   │
                           │     │  └────────┘
                           │     │
                           └─────┤

escalated → user picks phase → resume
```

## Phase Definitions

### Hard Rule: All Phases Run as Subagents

Every phase MUST be executed via `task(subagent_type, prompt)`.
The main session NEVER executes a phase directly — it only orchestrates.

Exception: only the main session can read phase output and decide next action.
This ensures: (a) role boundaries are enforced, (b) handoff documents are produced,
(c) no step can be skipped.

### Phase Transition Gates

Between each phase transition, the main session MUST verify:

| Transition | Gate |
|---|---|
| req → plan | handoffs/01-req.md exists, Done Criteria are testable |
| plan → dev | status.json phase=plan status=pending_approval, user confirmed y |
| dev → qa | npm run typecheck passes, npm run test passes, npx biome ci passes, build passes |
| qa → release | handoffs/04-qa.md status=passed, all tests green |
| release → done | CI run on committed SHA returns success |

If any gate fails → return to the phase that produced the failing output.

### Phase 1: Requirement

| Field | Value |
|---|---|
| subagent_type | `explore` → `general` |
| skill | `grill-with-docs` |
| handoff | `handoffs/01-req.md` |
| status | `completed / blocked` |

**explore probe:**
```
Scan the codebase at /path for relevant files matching the task:
{task description}
Return: file paths, brief descriptions, key types/functions relevant.
```

**general prompt:**
```
You are the workflow Requirement Analyst. Your input is:

Task: {task description}
Codebase scan: {explore output}

Your job:
1. Understand the problem by grilling it against existing docs (load grill-with-docs)
2. Define:
   - What — scope
   - Why — value
   - Done Criteria — verifiable conditions (must be testable)
   - Edge Cases — at least 3
   - Constraints — non-functional limits
3. Write handoff to {workflow_dir}/handoffs/01-req.md
4. Update {workflow_dir}/status.json phase to completed

Follow: SAP (single answer per question), KISS
Do NOT: propose solutions, estimate time, mention implementation
```

### Phase 2: Plan

| Field | Value |
|---|---|
| subagent_type | `code-review` → `general` |
| skill | `caveman`, `grill-with-docs` |
| handoff | `handoffs/02-plan.md` |
| status | `completed → pending_approval` |

**code-review audit:**
```
Read-only audit for:
{workflow_dir}/handoffs/01-req.md

Check: are the requirements achievable with current codebase structure?
Identify: files that will be affected, patterns to follow.
Return: audit notes.
```

**general prompt:**
```
You are the workflow Architect. Input:

Requirement: {workflow_dir}/handoffs/01-req.md
Audit: {code-review output}

Design the solution:

1. File change list — add / modify / delete
2. Architecture decisions — why this approach, alternatives considered
3. Implementation steps — ordered by dependency
4. Test strategy — what to test at each level

Grill your plan against the requirements (load grill-with-docs).
Compress your reasoning (load caveman).

Verify against:
- KISS: what's the simplest?
- DRY: does this repeat existing logic?
- YAGNI: is this needed now?
- PFC: is this abstraction justified?
- OHA: can the implementer start within an hour?

DO NOT: change requirements, write code.
After writing handoff, update status.json to pending_approval.
Exit and wait for user confirmation.
```

### Phase 3: Development

| Field | Value |
|---|---|
| subagent_type | per task: `sync-dev` / `export-helper` / `spec-runner` / `general` |
| skill | `caveman` |
| handoff | `handoffs/03-dev.md` |
| status | `pending → completed` |

**general prompt:**
```
You are the workflow Developer. Input:

Plan: {workflow_dir}/handoffs/02-plan.md
User approved: yes

For each step in the plan:

1. Read the file to modify (RUM)
2. Understand conventions by reading neighboring files
3. Implement:
   a. Types / data structures first
   b. Pure functions / utilities
   c. Components / business logic
   d. Tests (BIF, TDA)
4. Handle error paths before happy path (EPF)
5. Only change what's in the plan (MVC)

Integrity checks:
- BIF: every fix has a reproducing test
- FAI: every error message includes actionable fix
- SAP: same patterns as existing code
- PFC: flat code preferred, extract only after 3+ repetitions

After implementing all steps:
1. Run: npm run typecheck
2. Run: npx biome check --write .
3. Run: npm run test -w packages/web
4. Write handoff to {workflow_dir}/handoffs/03-dev.md
5. Update status.json
```

### Phase 4: QA

| Field | Value |
|---|---|
| subagent_type | `spec-runner` → `general` |
| skill | `grillme` |
| handoff | `handoffs/04-qa.md` |
| status | `passed / failed / escalated` |

**spec-runner probe:**
```
Run all tests and checks:
1. npm run test -w packages/web    (vitest)
2. npx tsc --noEmit                (typecheck)
3. npx biome ci .                  (lint)
4. npm run build                   (build)
Return: raw output of each, exit codes.
```

**general prompt:**
```
You are the workflow QA Engineer. Input:

Requirement: {workflow_dir}/handoffs/01-req.md
Plan: {workflow_dir}/handoffs/02-plan.md
Dev output: {workflow_dir}/handoffs/03-dev.md
Test results: {spec-runner output}

Your job (strict role boundary — DO NOT propose fixes):

1. Verify Done Criteria from 01-req.md — check each
2. Plan consistency — diff dev output vs plan (files changed? scope correct?)
3. Requirement consistency — diff dev output vs done criteria
4. Quality check — FAI compliance? Error paths? Hardcoded values?

Severity classification:
- blocker:  test failure / type error / build failure
- major:    done criteria missed / plan deviation
- minor:    style / naming / non-functional polish

Decision matrix:

| Tests | Plan match | Req match | Result |
|---|---|---|---|
| pass   | yes        | yes       | passed → release |
| pass   | yes        | no        | inconsistent → escalated |
| pass   | no         | yes       | root cause →回 matching phase |
| pass   | no         | no        | escalated |
| fail   | any        | any       | blocker/major →回 development |
| fail x3 retry | -- | --        | escalated |

Root cause routing for inconsistencies:
- dev ≠ plan → return to development
- plan ≠ req → return to plan
- req unclear/insufficient → return to requirement
- multi-phase mismatch → escalated

Escalated = pause all auto-flow, handoff marked escalated, wait for user.

Write handoff to {workflow_dir}/handoffs/04-qa.md.
Update status.json with result and target_phase if returning.
```

### Phase 5: Release

| Field | Value |
|---|---|
| subagent_type | `docs-writer` → `general` |
| skill | `caveman` |
| handoff | `handoffs/05-release.md` |
| status | `completed / terminated` |
| depends_on | `handoffs/04-qa.md status=passed` |

**general prompt:**
```
You are the workflow Release Manager. Input:

Requirement: {workflow_dir}/handoffs/01-req.md
QA report: {workflow_dir}/handoffs/04-qa.md

IMPORTANT — Check QA status first:
- QA report status MUST equal "passed". If not, DO NOT commit.
  Return to QA phase with message: "QA not passed, release aborted."

Your job:

1. Generate release summary:
   - Change summary
   - Scope / affected files
   - Test results from QA
   - Known minor issues (from QA, only if approved)
   - Rollback plan

2. Stage and commit:
   - Check git status — only intended files staged
   - Write commit message explaining WHY (not WHAT)
   - Push

3. Monitor CI:
   - After push, run: gh run list --limit 1 --json conclusion,displayTitle
   - Wait for CI to complete (up to 90s, check every 15s)
   - If CI returns "failure": log the error, recommend rollback
   - If CI returns "success": confirm release complete

4. Write handoff to {workflow_dir}/handoffs/05-release.md
5. Update status.json to completed
6. Present final report to user

Failure to check CI → risk of merging broken code. This is a non-negotiable gate.
```

---

## Status.json

```json
{
  "id": "YYYY-MM-DD-desc",
  "status": "in_progress / completed / escalated / terminated",
  "current_phase": "phase_name",
  "created": "ISO datetime",
  "updated": "ISO datetime",
  "phases": {
    "requirement": { "status": "pending / completed / blocked", "handoff": "handoffs/01-req.md", "attempts": 0 },
    "plan":        { "status": "pending / completed / pending_approval", "handoff": "handoffs/02-plan.md", "attempts": 0 },
    "development": { "status": "pending / completed / failed", "handoff": "handoffs/03-dev.md", "attempts": 0 },
    "qa":          { "status": "pending / passed / failed / escalated", "handoff": "handoffs/04-qa.md", "attempts": 0 },
    "release":     { "status": "pending / completed", "handoff": "handoffs/05-release.md", "attempts": 0 }
  },
  "escalations": [],
  "retry_limits": { "development": 3, "qa": 3 }
}
```

---

## Role Boundaries (May Not Cross)

| Agent | Scope | Prohibited |
|---|---|---|
| Requirement | Understand problem, clarify constraints, write done criteria | Design solutions, estimate time |
| Plan | Design solution, assess impact, define steps | Change requirements, write code |
| Development | Implement per plan, write tests | Change requirements, redesign architecture |
| QA | Run tests, check consistency, classify severity | Fix bugs, propose solutions |
| Release | Write summary, commit, push | Change code or requirements |

---

## Handoff Template

Each handoff follows this structure:

```markdown
# {workflow_dir}/handoffs/NN-phase.md

## Status
- Phase: {phase_name}
- Status: {completed / failed / escalated / pending_approval}
- Attempt: {N}

## Decisions
- {decision 1}
- {decision 2}

## Artifacts
- {path/to/file} — what changed
- {path/to/file}

## Consistency Check
- Plan match: {yes / no / n/a}
- Req match: {yes / no / n/a}

## Open Issues
- {issue 1}
- {issue 2}

## Notes
{free text for next phase agent}
```

---

## Workflow Directory Convention

```
workflows/YYYY-MM-DD-task-desc/
  status.json
  handoffs/
    01-req.md
    02-plan.md
    03-dev.md
    04-qa.md
    05-release.md
```

Created once at the start. All agents read/write from this directory.
