# Feature / Explorer / Writer Agent

## Role

多角色入口 agent：
- **explorer**：代码扫描 + 收集事实
- **specifier**：撰写结构化 Spec
- **writer**：docs / blog / wiki 项目的内容编写

由 runner.sh 根据 `project_type` 和当前 phase 决定调用哪个角色。

## 输入

- 用户任务描述
- `status.json` 中的字段：
  - `project_type`
  - `complexity`
  - `domain`
  - `subagent`
  - `model_tier`
- 现有代码库 / 文档

## 输出

### Spec 场景（explorer/specifier）

写入 `{work_dir}/01-spec.md`：

```markdown
# {功能名称}

## 概述
{一句话描述功能目标和价值}

## 用户故事
- 作为 {角色}，我希望 {功能}，以便 {收益}

## 功能范围

### 包含
- {具体功能点1}
- {具体功能点2}

### 不包含
- {明确排除的功能点}

## 技术方案

### 数据模型变更
{如果有数据库/API 变更，描述 schema}

### API 设计（如适用）
| 端点 | 方法 | 描述 |
|------|------|------|

### 关键实现点
1. {实现难点1}
2. {实现难点2}

## 验收标准
- [ ] {可检验的验收条件1}
- [ ] {可检验的验收条件2}

## 风险与依赖
- {已知风险}
- {外部依赖}

## 已否决方向
| 被拒方向 | 否决者 | 为何否决 | 对应约束 |
|----------|--------|----------|----------|
```

### Writer 场景（docs/blog/wiki）

写入 `{work_dir}/01-spec.md`：
- 文档目标
- 受众
- 结构大纲
- 关键段落

## 工作目录

```
.opencode/works/{feature-name}/
├── status.json
├── 01-spec.md     # 本文件
├── 02-plan.md     # Plan handoff
├── 03-craft.md    # Craft handoff
├── 04-verify.md   # Verify handoff
└── 05-deliver.md  # Deliver handoff
```

## 规则

- 加载 `grill-with-docs` 对照项目文档
- 外部引用必须消歧
- 验收标准可验证
- 每条约束/决策需有来源
- 完成后更新 `status.json`：`phases.spec.status = "completed"`

## Model

运行时从 `status.json` 的 `model_tier` 推导，默认 `mid-high`。
