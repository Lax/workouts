# actions/checkout Auth Routing — Root Cause & Fix

## Problem

GitHub Actions 中，`git push` 修改 `.github/workflows/*.yml` 文件时报错：

```
! [remote rejected] main -> main (refusing to allow a GitHub App to create or update
  workflow `.github/workflows/sync.yml` without `workflows` permission)
```

即使 token 是 PAT（Personal Access Token）且拥有 `workflows: write` 权限，仍然被拒。

## Root Cause

### `actions/checkout` 的 Token 包装

`actions/checkout` 内部将 **任意 token**（GITHUB_TOKEN 或 PAT）统一包装为 `x-access-token:` 前缀，存储在 git config 的 extraheader 中：

```typescript
// src/git-auth-helper.ts (v4/v7)
const basicCredential = Buffer.from(
  `x-access-token:${this.settings.authToken}`,
  'utf8'
).toString('base64')
this.tokenConfigValue = `AUTHORIZATION: basic ${basicCredential}`
```

这写入 git local config：
```
[http "https://github.com/"]
  extraheader = AUTHORIZATION: basic <base64("x-access-token:<TOKEN>")>
```

### 服务器路由机制

GitHub 服务器通过 `x-access-token:` 前缀在 basic auth 中的存在与否，来决定认证路由：

| Auth 方式 | Basic Auth 内容 | 服务器判定 | 权限检查依据 |
|---|---|---|---|
| URL: `https://x-access-token:PAT@github.com/` | `base64("x-access-token:PAT")` | GitHub App | workflow YAML `permissions:` block |
| extraheader: `x-access-token:PAT` | same header | GitHub App | workflow YAML `permissions:` block |
| URL: `https://oauth2:PAT@github.com/` | `base64("oauth2:PAT")` | PAT | token 自身 scope |
| URL: `https://PAT@github.com/` | `base64("PAT:")` | PAT | token 自身 scope |

当服务器判定为 "GitHub App" 时，**不检查 token 自身的权限**，而是读取 workflow YAML 的 `permissions:` 块。因该 YAML 只有 `contents: write` 而无 `workflows: write`，故拒绝。

### 为什么 fine-grained PAT 也不行

Fine-grained PAT 即使有 `workflows: write` permission，当其被 `x-access-token:` 包装时，服务器仍将其视为 GitHub App token，走 GitHub App 路由 → 检查 YAML permissions block → 拒绝。

## Fix — 4 种方案对比

### 最终推荐：方案 C

`persist-credentials: false` 阻止 extraheader 写入 + 手动写入裸 PAT extraheader（不含 `x-access-token:` 前缀）

```yaml
- uses: actions/checkout@v4
  with:
    persist-credentials: false

# ... 中间步骤 ...

- name: Update cron (schedule only)
  if: github.event_name == 'schedule'
  env:
    NEW_N: ${{ steps.decide.outputs.new_n }}
    WORKOUTS_SYNC_PAT: ${{ secrets.WORKOUTS_SYNC_PAT }}
  run: |
    # persist-credentials: false → no extraheader written.
    # Write bare PAT extraheader (no x-access-token: prefix)
    # so server routes as PAT, not GitHub App.
    git config --add http.https://github.com/.extraheader \
      "AUTHORIZATION: basic $(printf '%s:' "$WORKOUTS_SYNC_PAT" | base64 -w0)"
    git add .github/workflows/sync.yml
    git diff --cached --quiet || \
      git commit -m "chore: sync interval N=$NEW_N"
    git pull --rebase
    git push
```

**优点：** `ps` 不可见、一步到位、安全。短板也已补齐。

### 全部 4 种方案

| # | 方案 | checkout 改动 | push 步骤 | `ps` 安全 | 已验证 |
|---|---|---|---|---|---|
| **C** | persist=false + 手动裸 PAT extraheader | +1 行 | `git config --add http.extraheader "base64($PAT:)"` | ✅ | ✅ |
| **A** | persist=false + URL 嵌入 PAT | +1 行 | `git remote set-url origin https://$PAT@github.com/` | ⚠️ | ✅ |
| **D** | persist=true + clear extraheader + URL PAT | 无 | `git config --unset-all` + set-url | ⚠️ | ✅ |
| **B** | persist=true + mutate extraheader | 无 | base64 decode → strip `x-access-token:` → re-encode | ✅ | ❌ |

> **`ps` 安全：** PAT 在 `ps aux` 中不出现在进程参数中。D 和 A 的 URL 嵌入方式在 `ps` 中可见（GitHub Actions 单租户 VM 风险极低，但属理论隐患）。

### 验证

| 尝试 | 结果 |
|---|---|
| `x-access-token:fine-grained-PAT` in URL（未清 extraheader） | ❌ rejected |
| `oauth2:fine-grained-PAT` in URL（未清 extraheader） | ❌ rejected |
| **D：** clear extraheader + classic PAT push | ✅ `N=4 → N=3` |
| **D：** clear extraheader + fine-grained PAT push | ✅ `N=4 → N=2` |
| **A：** persist=false + fine-grained URL push | ✅ `N=4 → N=3` |
| **C：** persist=false + 手动裸 PAT extraheader push | ✅ `N=4 → N=3` |

**结论：** 根源是 `x-access-token:` 包装导致服务器错误路由。四种方案都解决了这个问题，**方案 C** 在安全性和简洁性上最优。

### 为什么不直接用 GITHUB_TOKEN？

`GITHUB_TOKEN` **不能**被授予 `workflows: write` 权限。这是一个根本性限制：

| Token 类型 | `workflows: write` 可用 | 原因 |
|---|---|---|
| `GITHUB_TOKEN` | ❌ 不可用 | `workflows` scope 不在 GITHUB_TOKEN 可授予范围内，workflow 解析时即报错 |
| Fine-grained PAT | ✅ 可用 | 已验证 |
| Classic PAT | ✅ 可用 | 已验证 |

> *"`workflows: write` is not valid for GitHub Actions GITHUB_TOKEN in workflow files (only for PATs). GitHub fails the workflow at parse time when it is present."*
> — [SINTEF/ci-cd#410](https://github.com/SINTEF/ci-cd/pull/410)

因此 **PAT 方案是唯一可行路径**，不存在换成 `GITHUB_TOKEN` 的可能性。

### Secrets 命名

| Secret | 类型 | 用途 |
|---|---|---|---|
| `WORKOUTS_SYNC_PAT` | fine-grained | workflow push 专用，checkout 默认 GITHUB_TOKEN 即可 |

## 关键知识点

1. **`actions/checkout` 的 `token:` 参数会将所有 token 包成 `x-access-token:`** — 写入 extraheader，影响后续 git push
2. **`persist-credentials: false` 阻止 extraheader 写入** — 从源头消除问题
3. **GitHub 服务器通过 basic auth 中的用户名判断路由** — `x-access-token:` = GitHub App；裸 PAT = 标准 PAT 路由
4. **Fine-grained PAT 完全可用** — 清除 `x-access-token:` 包装后走标准 PAT 路由
5. **extraheader 优先于 URL 凭证** — URL 中即使有 PAT，extraheader 的 `x-access-token:` 仍会触发 GitHub App 路由

## References

- [actions/checkout source](https://github.com/actions/checkout/blob/main/src/git-auth-helper.ts) — `x-access-token:` wrapping in configureToken()
- [GitHub Docs: Managing PATs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) — classic vs fine-grained PAT
- [haydenk/homestead#81](https://github.com/haydenk/homestead/issues/81) — same error, resolved by PAT
