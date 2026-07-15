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

## Ambiguity Rule — 通用消歧

模型默认行为是将模糊概念解析为字面最相似的值，而不通知用户。
这在项目上下文中有多义性的术语上会导致方向性错误。

**必须在以下场景执行消歧：**

| 场景 | 示例 | 行为 |
|------|------|------|
| 用户引用"上游"/"upstream"/"参考"/"源头" | "与上游不一致" | 列出 CONTEXT.md 中所有声明上游（每个 theme 不同），请求确认 |
| 用户说出项目内的名字但可能指不同实体 | "和 overview 一样" | 区分 theme-overview 还是 overview 视图 |
| 模型自己引入一个比较对象 | "对比 theme-overview 的做法" | 先确认"你同意用 theme-overview 作为参考？" |
| 用户输入中有未指定的第三方引用 | "按原来的方式" | 问清楚"原来的方式"指向哪个实现 |

**执行规则：**

1. **发现歧义 → 停止**。不要猜，不要继续推进。
2. **列出所有可能解析**。每个选项附上来源（CONTEXT.md 哪一行/哪个声明）。
3. **请求确认**后才继续。在用户确认之前，不做任何方向性决策。
4. **记录消歧结果**。如果后续操作依赖这个决策，引用确认记录。
5. **单答案原则（SAP）** 适用：一个问题只能有一个答案。如果多个答案同时存在 → 是歧义，需要消歧。

例外：用户明确指定了精确匹配（"用 running_page 的布局"） → 不需要消歧，直接执行。
No assumptions — confirm when uncertain.

## Git Editor Avoidance

AI 环境无终端交互，弹编辑器会导致超时。所有 git 命令必须避免交互式编辑器：

- **commit**: 永远使用 `git commit -m "msg"`（禁止裸 `git commit`）
- **amend**: `git commit --amend -m "new msg"` 或 `git commit --amend --no-edit`
- **rebase**: `EDITOR=true git rebase -i HEAD~N` 或 `GIT_SEQUENCE_EDITOR=true git rebase -i HEAD~N`
- **tag**: `git tag -a v1.0 -m "msg"`
