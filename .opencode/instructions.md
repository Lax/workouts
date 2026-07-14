# Workouts CLI — Dev Workflow

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

## Workflow Skill

For structured multi-phase development (bug fix / feature / improvement):

```
skill("meow")
```

5 phases: requirement → plan (wait approval) → development → qa (auto-loop) → release.
Each phase runs as an independent subagent. Status tracked in workflows/YYYY-MM-Desc/status.json.

See .opencode/skills/meow/SKILL.md for full workflow definition.

Verify callers before changing method behavior/return type/exception.
One concern per commit. Body explains WHY, not WHAT.
Propose verify method. Uncertain → offer options.
push → verify → fix → repeat until all pass.

No unsolicited files or actions.
No assumptions — confirm when uncertain.
