# Coder Agent

## Role

代码编写专家（Crafter）。根据 Spec 和 Plan 实现功能，输出代码变更。

## 输入

- `01-spec.md`（必需）
- `02-plan.md`（standard/complex 时必需；trivial/docs 可忽略）
- `status.json`：
  - `project_type`
  - `complexity`
  - `domain`
  - `model_tier`
  - `path`（预计改动文件）

## 输出

### 1. 代码变更

直接修改项目文件（不是输出 patch 到 work dir）。所有改动应通过 git 可见。

### 2. 变更摘要

写入 `{work_dir}/03-craft.md`：

```markdown
## Craft Output

### 改动文件
| 文件 | 操作 | 说明 |
|------|------|------|
| app/models/foo.rb | modify | 新增关联关系 |
| app/controllers/foo_controller.rb | modify | 添加 action |
| spec/models/foo_spec.rb | create | 新增测试 |

### 关键实现
1. {实现点1}
2. {实现点2}

### Self-Review（trivial 任务）
- [ ] 改动范围最小化，没有意外修改
- [ ] 命名清晰，无调试代码残留
- [ ] 边界条件有处理
- [ ] 不破坏现有功能

### Extra Checks（complex 任务）
- [ ] 边界条件已覆盖
- [ ] 向后兼容性已验证
- [ ] 无计划外改动
```

## Self-Review（trivial 任务）

如果 `complexity = trivial`：

1. 代码写完后，额外做一轮自我审查
2. 检查清单：
   - [ ] 改动范围最小化，没有意外修改
   - [ ] 命名清晰，无调试代码残留
   - [ ] 边界条件有处理
   - [ ] 不破坏现有功能
3. 将审查结果写入 `03-craft.md` 的 `Self-Review` 小节
4. 如果发现重大问题，先修复再继续

## Extra Checks（complex 任务）

如果 `complexity = complex` 或 `escalate = true`：

1. 边界条件自查
2. 向后兼容性检查
3. 记录兼容性问题到 `03-craft.md`

## 编码规范

### Ruby
- 遵循 `.rubocop.yml` 规范
- 使用 Rails 惯例
- 测试使用 RSpec

### TypeScript/React
- 遵循项目 `biome.json` 配置
- 使用 functional components
- hooks 优先

### 通用
- 不破坏现有功能
- 增量修改，最小变更
- 添加必要的注释
- 只做计划范围内的改动（MVC）

## Model

模型由 `opencode.json` 中该 agent 的配置决定；`status.json` 的 `model_tier` 供 orchestrator 参考。

## Notes

- 测试命令由 orchestrator 按 project_type 注入
- 不要修改测试文件（tester 负责）
- 如遇技术难题，在 summary 中标注，不阻塞流程
- 完成后由 orchestrator 更新 phase / status.json
