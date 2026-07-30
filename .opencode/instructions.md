# Workouts CLI — Dev Workflow

## Principles

KISS — Simple > clever. No early abstraction.
DRY — Extract repeated patterns.
TDD — Test with code. `bundle exec rspec` green = done signal.
MVC — Fix only what intended. Don't inline tangental fixes.
RUM — Read file fully before editing. Understand imports/style/patterns.
EPF — Error cases before happy path. File missing? Auth fails? Net down?

BIF — Every bug fix ships with a test that reproduces the bug.
  The test must fail on the old code and pass on the fix.
  "修复即验证" — 没有对应测试的修正是不可验收的。

SAP — Single Answer Principle. One standard way per concern. Don't invent new patterns.
PFC — Prefer Flat over Clever. No premature abstraction. Extract after 3+ repetitions.
FAI — Fail-fast with Actionable Info. Every error includes a copy-paste fix command.
TDA — Test Duality Assertion. Every test has both normal-path and error-path assertions.
OHA — One Hour Ahead. Validate approach before implementing. If the plan takes >1h to sketch, understanding is shallow.

## Workflow

For structured multi-phase development (bug fix / feature / improvement):

```
skill("meow")
```

5 phases: requirement → plan (wait approval) → development → qa (auto-loop) → release.
Each phase runs as an independent subagent. Status tracked in workflows/YYYY-MM-Desc/status.json.

See `.opencode/skills/meow/SKILL.md` for full workflow definition.

Verify callers before changing method behavior/return type/exception.
One concern per commit. Body explains WHY, not WHAT.
Propose verify method. Uncertain → offer options.
push → verify → fix → repeat until all pass.
No unsolicited files or actions.

## Git Conventions

**No interactive editors.** AI environment has no terminal interaction:

- commit: `git commit -m "msg"` only (never bare `git commit`)
- amend: `git commit --amend -m "new msg"` or `git commit --amend --no-edit`
- rebase: `EDITOR=true git rebase -i HEAD~N` or `GIT_SEQUENCE_EDITOR=true git rebase -i HEAD~N`
- tag: `git tag -a v1.0 -m "msg"`

**Skip CI.** Append `[skip ci]` to commit message when ALL staged changes are documentation or configuration only — code changes must always trigger CI:

| Type | Examples | Skip CI |
|------|----------|---------|
| Docs | `CONTEXT.md`, `docs/*`, `*.md` (except test/bench fixtures) | yes |
| Config | `.opencode/*`, `.github/*`, `config/*`, `Dockerfile`, `*.yml` | yes |
| Code | `lib/*`, `spec/*`, `packages/*`, `exe/*`, `assets/*` | no |

## External Repos

**Do NOT modify files in other project repositories without explicit permission.**

For changes needed in external repos:
1. File a **GitHub Issue** on that repo (use `gh issue create`)
2. Include: what needs to change, why, and the exact code modifications
3. Reference the issue URL in any related commits
4. Do NOT create Pull Requests

Changes to this project's own files (`lib/`, `spec/`, `config/`,
`.github/workflows/`, `docs/`, `ruby/stravaweblib/`) are unaffected.

## Ambiguity Rule

Model defaults to resolving fuzzy references to the most literally similar value.
This causes directional errors when terms are ambiguous in project context.

**Must disambiguate in these scenarios:**

| Scenario | Example | Action |
|----------|---------|--------|
| "upstream"/"original" references | "不一致与上游" | List all declared upstreams in CONTEXT.md (one per theme), ask confirmation |
| Project name with multiple entities | "和 overview 一样" | Distinguish theme-overview vs overview view |
| Model introduces a comparison | "对比 theme-overview 的做法" | Confirm "你同意用 theme-overview 作为参考？" first |
| Unspecified third-party reference | "按原来的方式" | Ask which implementation "原来的方式" points to |

**Rules:**

1. **Found ambiguity → stop.** Do not guess or proceed.
2. **List all possible resolutions.** Each option with source (CONTEXT.md line / statement).
3. **Wait for confirmation** before any directional decision.
4. **Record the result.** Reference the confirmation in subsequent operations.
5. **SAP applies:** one question, one answer. Multiple answers = ambiguity, needs resolution.

Exception: user specifies exact match ("用 running_page 的布局") → execute directly, no disambiguation needed.
