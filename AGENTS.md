# Workouts — AI 开发规则

> 多工具联合开发共用本文件（opencode / codex 等）。
> 项目事实与设计细节的唯一真源是 `CONTEXT.md`；本文件只写行为规则。

## 会话开始

1. 先读 `CONTEXT.md` — 项目概述、仓库族、数据库 schema、配置体系、CI/CD 现状。
2. 产品/开发文档在两个 wiki：`workouts.wiki`（本仓库集成层）、`git-fit.wiki`（git-fit gem）；关键页面指针表见 CONTEXT.md 文末。
3. opencode 会话可使用 `.opencode/` 下的 agent 编排与 meow skill；其他工具手动遵循同样的 phase 与 checkpoint，不要跳过 verify。

## 模型分级使用规则

> 单一真源：`~/.config/opencode/opencode.json`（历史 `opencode.jsonc` 已归档为 `.bak-*`；`model-router` 动态路由插件已移入 `plugins-disabled/`）。ollama 位于 `/srv/ollama`（docker compose，模型 `qwen2.5:3b/7b`，32k ctx）。

### 状态 A（当前：opencode-go 烧月期，不续费）

| 档 | 任务 | 模型 |
|---|---|---|
| 主力 | main / Craft / Plan / 日常问答 | `opencode-go/deepseek-v4-flash`（配额用完为止，不设节约纪律） |
| L1 | verify / docs / CI YAML | `zhipuai glm-5.3-flash`（bigmodel Lite 周 10k 积分，周清零不用白不用） |
| L0 | small_model（title/摘要） | `ollama qwen2.5:3b` |
| 兜底 | explore 等云端便宜任务 | `opencode/deepseek-v4-flash-free` |

### 状态 B（opencode-go 用尽后，一次性切换）

| 档 | 模型 |
|---|---|
| 主力 main / Craft | `minimax-cn-coding-plan/MiniMax-M2.7`（年付大池） |
| 深设计 / 大范围 audit | `MiniMax-M3`（1M ctx） |
| L1 verify / docs | `glm-5.3-flash`（周配额） |
| L0 small_model | `ollama qwen2.5:3b` |
| 兜底 explore | `opencode/deepseek-v4-flash-free` |

**切换动作**：opencode-go 报配额错或用户确认用完 → 删除 `opencode-go` provider 块 + `model` 改 `minimax-cn-coding-plan/MiniMax-M2.7`。

**L0 纪律**：ollama 只承担 small_model；小模型不做 agentic explore（工具调用不可靠）；compaction 走主模型，与 small_model 无关。

## Principles

| 缩写 | 全称 | 说明 |
|---|---|---|
| KISS | Simple > clever | 不做早期抽象 |
| DRY | Don't Repeat Yourself | 提取重复模式 |
| TDD | Test with code | `bundle exec rspec` green = done 信号 |
| MVC | Modify only intended | 只修目标问题，不夹带顺手修 |
| RUM | Read file fully before editing | 编辑前完整读文件，理解 imports/风格/模式 |
| EPF | Error cases before happy path | 文件缺失？认证失败？断网？ |
| BIF | Bug ships with test | 每个 bug 修复附带复现测试；旧代码 fail、新代码 pass；「修复即验证」 |
| SAP | Single Answer Principle | 每个关注点只有一种标准做法，不发明新花样 |
| PFC | Prefer Flat over Clever | 3+ 次重复才提取 |
| FAI | Fail-fast with Actionable Info | 每个错误附带可复制粘贴的修复命令 |
| TDA | Test Duality Assertion | 每个测试同时断言正常路径和错误路径 |
| OHA | One Hour Ahead | 实现前先验证思路；草图超 1h 说明理解不够 |

## Workflow（5 phase）

```
spec → plan（APPROVED 检查点，用户批准）→ craft → verify（测试全绿）→ deliver（RELEASING 检查点，用户确认后 commit/push）
```

- opencode：入口 `skill("meow")` 自动编排；工作目录 `.opencode/works/YYYY-MM-DD-desc/`（status.json + 各 phase handoff）。
- 其他工具：按同样顺序手动执行；保留 APPROVED / RELEASING 两个用户检查点。

Verify callers before changing method behavior/return type/exception.
One concern per commit. Body explains WHY, not WHAT.
Propose verify method. Uncertain → offer options.
push → verify → fix → repeat until all pass.
No unsolicited files or actions.

## Git Conventions

**No interactive editors.** AI 环境无终端交互：

- commit: `git commit -m "msg"` only（禁止裸 `git commit`）
- amend: `git commit --amend -m "new msg"` 或 `--no-edit`（**仅限未 push**）
- rebase: `EDITOR=true git rebase -i HEAD~N`
- tag: `git tag -a v1.0 -m "msg"`

**Gem 发版**：一律走 `gem-release` skill（bump → push → annotated tag 含**系列回顾**段 → `git ls-remote` 同步确认；rubygems publish 需 WebAuthn 浏览器确认，用 `setsid --fork script -qfec` 后台推送 + 轮询 API 验证）。已推 tag 永不重写，漏段自担。

**Push 纪律：**

- 已 push 的 commit 禁止 amend，需要修正就发新 commit
- force-push 仅在用户显式批准时执行；执行前输出 WARNING + 理由

**Skip CI.** 暂存变更全部为文档或配置时，commit message 追加 `[skip ci]`；代码改动必须触发 CI：

| 类型 | 例子 | Skip CI |
|------|----------|---------|
| Docs | `CONTEXT.md`、`AGENTS.md`、`*.md`（test/bench fixtures 除外） | yes |
| Config | `.opencode/*`、`.github/*`、`config/*`、`*.yml` | yes |
| Code | `spec/*`、`.github/git-fit-actions/` | no |

## External Repos

**未经明确许可，不得修改其他项目仓库的文件。**

| 仓库 | 角色 | 修改策略 |
|---|---|---|
| `Lax/git-fit` | 核心数据功能库（git-fit gem） | GitHub Issue（`gh issue create`），不提 PR |
| `Lax/git-fit-web` | 数据展示前端 | 同上 |
| `git-fit-actions/*` | 复用 GitHub Actions | 同上 |
| `Lax/running` | POC 验证仓，已逐渐迁往 git-fit/git-fit-web | 只读参考，不修改 |
| `yihong0618/running_page` | 早期上游参考项目 | 只读，不修改、不提 issue |

Issue 流程：写清改什么、为什么、具体代码修改；相关 commit 引用 issue URL。
本仓库自身文件（`spec/`、`config/`、`.github/`、`.opencode/`）不受此限制。

## Ambiguity Rule

模糊指代默认解析为字面最相似的值，在项目语境中容易造成方向性错误。

**必须先消歧的场景：**

| 场景 | 例子 | 动作 |
|----------|---------|--------|
| "upstream"/"original" 指代 | "不一致与上游" | 列出 CONTEXT.md 中全部声明的上游，请用户确认 |
| 多实体项目名 | "和 stats 一样" | 区分 theme-stats（包）vs 统计看板（stats 页面） |
| 模型引入的对比 | "对比 theme-stats 的做法" | 先确认「你同意用 theme-stats 作为参考？」 |
| 未指明的第三方指代 | "按原来的方式" | 问清"原来的方式"指向哪个实现 |

**规则：**

1. **发现歧义 → 停下。** 不猜测、不继续。
2. **列出全部可能解析。** 每项标注来源（CONTEXT.md 行 / 用户原话）。
3. **方向性决定前等用户确认。**
4. **记录结论。** 后续操作引用该确认。
5. **SAP 适用：** 一问一答。多个答案 = 存在歧义，需先解决。

例外：用户指定精确匹配（如「用 running_page 的布局」）→ 直接执行，无需消歧。
