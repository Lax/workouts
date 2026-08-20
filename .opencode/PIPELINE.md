# Meow + Auto-Pipeline 合并版指南

基于 [meow skill](.opencode/skills/meow/SKILL.md) 改进：
- 自动入口分类（classifier）
- 按 **project_type × complexity** 自动路由
- 只有 **2 个用户 checkpoint**：APPROVED + RELEASING
- 保留 meow 的 5 phase、handoff、retry、neat-freak

## 快速开始

### 1. 发起新任务

```bash
cd ~/checkouts/mine/workouts
opencode
# 输入: 我要做 XXX 功能
```

Classifier 自动分析：
- `project_type`: frontend / backend / docs / blog / wiki / comprehensive
- `complexity`: trivial / standard / complex
- `domain`: frontend / sync / export / generic / docs
- `subagent`: 入口阶段要调用的子代理
- `model_tier`: base / mid / mid-high / high / apex

### 2. Phase 流程

```
用户输入 → classifier（自动）
  → 📋 Spec
  → 📐 Plan → [APPROVED checkpoint]
  → 🔨 Craft
  → 🔬 Verify
  → 🚀 Deliver → [RELEASING checkpoint]
```

**只有 APPROVED 和 RELEASING 需要你确认。**

### 3. 项目类型路由

| project_type | Phase 流程 | APPROVED | RELEASING | Verify 深度 |
|--------------|-----------|----------|-----------|-------------|
| `frontend` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | 标准 |
| `backend` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | 标准 |
| `docs` | Spec → Craft → Verify → Deliver | **跳过** | ✅ | 轻量 |
| `blog` | Spec → Craft → Verify → Deliver | **跳过** | ✅ | 轻量 |
| `wiki` | Spec → Craft → Verify → Deliver | **跳过** | ✅ | 轻量 |
| `comprehensive` | Spec → Plan → Craft → Verify → Deliver | ✅ | ✅ | 标准 + neat-freak |

### 4. 复杂度路由

| complexity | 效果 |
|------------|------|
| `trivial` | 跳过 Plan；Craft 自审；Verify 只跑测试 |
| `standard` | 完整流程；标准审查 |
| `complex` | Plan 加 OHA；Craft 加边界/兼容检查；Deliver 加 postmortem + neat-freak |

### 5. 日常命令

```bash
# 查看所有 works
.opencode/pipeline/state.sh list

# 查看单个状态
.opencode/pipeline/state.sh status <feature-name>

# 批准 Plan，继续 pipeline
.opencode/pipeline/state.sh approve <feature-name>

# 确认发布
.opencode/pipeline/state.sh release <feature-name>

# 自动流转到下一阶段（通常 runner.sh 内部调用）
.opencode/pipeline/state.sh auto <feature-name>

# 查看测试命令
.opencode/pipeline/runner.sh test-cmd <feature-name>

# 继续 runner
.opencode/pipeline/runner.sh continue <feature-name>
```

### 6. 用户交互流程

```
你输入任务
  → classifier 自动分析
  → 显示 "Detected: backend/standard, domain=generic, model_tier=mid-high"
  → 流水线自动跑 Spec
  → Plan 完成后 APPROVED 停住:
    "Review plan at .opencode/works/xxx/02-plan.md"
    "运行: state.sh approve xxx"
  → 你 approve
  → 流水线继续自动跑 Craft → Verify
  → Verify 通过后 RELEASING 停住:
    "About to commit+push, confirm?"
    "运行: state.sh release xxx"
  → 你 release
  → Deliver 执行 commit + CI
  → Pipeline 完成
```

## Classifier 输出字段

```markdown
**type**: feature
**project_type**: backend
**complexity**: standard
**confidence**: medium
**escalate**: false
**domain**: generic
**subagent**: coder
**model_tier**: mid-high
**path**: ["lib/workouts/cli.rb", "spec/cli_spec.rb"]
**reason**: 用户要求新增 CLI 子命令，涉及 3-5 个文件改动和测试
```

## Subagent 角色

| 角色 | 职责 | 对应现有文件 |
|------|------|-------------|
| `explorer` | 代码扫描 | `agent/feature.md` |
| `planner` | 方案设计 | `agent/reviewer.md`（扩展） |
| `coder` | 实现 | `agent/coder.md` |
| `reviewer` | 审查 | `agent/reviewer.md` |
| `tester` | 验证 | `agent/tester.md` |
| `deliverer` | 交付+CI | `agent/releaser.md` |
| `writer` | 文档 | `agent/feature.md`（docs 项目） |

Domain 作为参数注入，不进 subagent 名。

## 目录结构

```
.opencode/works/{feature-name}/
├── status.json              # 状态、project_type、complexity、domain、model_tier
├── 01-spec.md               # Spec handoff
├── 02-plan.md               # Plan handoff
├── 03-craft.md              # Craft handoff
├── 04-verify.md             # Verify handoff
└── 05-deliver.md            # Deliver handoff
```

## 测试命令查找

runner.sh 根据 `project_type` 自动注入测试命令：

| project_type | 测试命令 |
|--------------|----------|
| `frontend` | `npm run test; npx biome ci .` |
| `backend` (Ruby) | `bundle exec rspec; bundle exec ruby -c lib/` |
| `backend` (Rust) | `cargo test; cargo clippy -- -D warnings` |
| `docs/blog/wiki` | 轻量检查（无测试） |
| `comprehensive` | 组合命令 |

## Retry 机制

- Craft / Verify 各有 3 次重试
- blocker 自动返回 Craft 重试
- 超过 3 次 → escalation 上报用户

## Model Tier 默认映射

| Tier | 默认模型 |
|------|----------|
| `base` | `muse-spark-1.2-contributor` |
| `mid` | `mimo-v2.5-pro` |
| `mid-high` | `hy3`（coder）/ `minimax-m2.7-highspeed`（tester/reviewer/planner） |
| `high` | `kimi-k2.7-code` |
| `apex` | `claude-opus-5` |

可通过 `status.json` 的 `model_override` 覆盖。
