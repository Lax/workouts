# Garmin OAuth Auth — Design

## Architecture overview

```
GarminBase（OAuth1 纯基类）
  ├── GarminBaseDI（DI OAuth2 基类）── Garmin（garmin.com）
  └──────────────────────────────── GarminCN（garmin.cn）
```

| 类 | 域 | 认证路径 | 代码文件 |
|---|---|---|---|
| `GarminBase` | - | 共享基类方法（parse_secret_string、dump_secret、api_get 等） | `garmin_base.rb` |
| `GarminBaseDI` | - | DI OAuth2 方法（refresh_token、strategy_a/b_login） | `garmin_base_di.rb` |
| `Garmin` | garmin.com | authenticate_di → DI OAuth2 | `garmin.rb`（12 行） |
| `GarminCN` | garmin.cn | authenticate → OAuth1→OAuth2 | `garmin_cn.rb`（13 行） |

---

## garmin_cn: OAuth1→OAuth2 Chain

garmin.cn 未受 CF 封锁影响，SSO 登录可正常工作。

### Auth priority chain

```
① secret (config.yml / env SYNC__GARMIN_CN__SECRET)
   Base64([OAuth1 JSON, OAuth2 JSON]) — garth dumps() 兼容
   Parse → OAuth2 valid? → 直接用。过期 → OAuth1 refresh → 新 OAuth2
   Fail → 降级

② token 文件（data/cache/garmin_garmin_cn_tokens.json, GH Cache）
   同 ①。Fail → 删除陈旧文件 → 降级

③ SSO 登录（email+password，支持 MFA）
   成功后 → dump_secret → save_secret_to_config + save_tokens
```

### Token lifetimes

| Token | TTL | 续期方式 |
|---|---|---|
| OAuth1 token+secret | months~years | 一次性获取 |
| OAuth2 access_token | ~6h | OAuth1 refresh |
| OAuth2 refresh_token | ~90d | OAuth1 重新签名 |

### 凭据来源

| 优先级 | 来源 | CI 可用？ |
|---|---|---|
| 权威 | `SYNC__GARMIN_CN__SECRET`（GitHub Secret） | ✅ |
| 缓存 | `data/cache/garmin_garmin_cn_tokens.json`（GH Cache） | ✅ |
| 降级 | SSO 登录（email+password） | ❌ 交互式 |

---

## garmin_intl: DI OAuth2 Flow

garmin.com 的 SSO 端点 `/mobile/api/login` 已被 Garmin 关闭（返回 400），OAuth1 `/preauthorized` 端点也返回 401。CF 对 TLS 指纹严格检测，普通 HTTP 库全部 429/403。

### Auth priority chain（GarminBaseDI#authenticate）

```
① DI token 缓存（data/cache/garmin_garmin_com_tokens.json, GH Cache）
   access_token 有效 → 直接用。过期 → di_refresh（30d 滑动）。
   refresh 失败 → 清除缓存 → 降级

② Strategy A: curl_cffi subprocess（scripts/garmin_auth.py）
   两步： portal+cffi（5 TLS 指纹, 30-45s 反爬延迟）
         mobile+cffi（Safari TLS, 降级）
   → CAS ticket → DI OAuth2 交换 → 存缓存
   限制：账号有 MFA 时需要实时验证码（一次性，CI 不支持）

③ Strategy B: Playwright subprocess（scripts/garmin_auth_playwright.py）
   Headless Chromium → SSO form 登录 → ticket → DI 交换
   首次 MFA 交互，session cookies 持久化 ~1 年（data/cache/）
   后续运行从 cookies 恢复，跳过 SSO

④ 全部失败 → false（无交互式 SSO）
```

### Token lifetimes

| Token | TTL | 续期方式 |
|---|---|---|
| DI access_token | ~18h | POST diauth.garmin.com refresh_token |
| DI refresh_token | 30d 滑动窗口 | 每次 refresh 旋转续期，每日 CI 运行即可无限延续 |

### 凭据来源

| 来源 | CI 可用？ |
|---|---|
| `SYNC__GARMIN__EMAIL` + `SYNC__GARMIN__PASSWORD`（GitHub Secrets） | ✅ Strategy A/B 入口 |
| DI token（GH Cache） | ✅ 日常续期 |
| MFA code（`SYNC__GARMIN__MFA_CODE` env var） | ⚠️ 一次性码，无法预置。推荐用 Strategy B 缓存 session |

### 实测结果（2026-06-17）

- curl_cffi `mobile+cffi` Safari TLS 成功穿透 CF
- 账号 MFA 已启用 → 认证在 MFA 步骤中断
- `portal+cffi` 5 指纹中 Safari/Edge/Chrome 返回无响应（疑似 TCP 层阻断），safari_ios/chrome120 返回 403
- 结论：curl_cffi 对无 MFA 账号可全自动；有 MFA 账号需 Playwright 缓存 session

### MFA 处理

MFA 验证码通过 env var `SYNC__GARMIN__MFA_CODE` 传入 Python 脚本。**此做法仅适用于本地调试或已知验证码的有效期内**，不适合 CI 自动化。

**推荐路径：** Strategy B（Playwright）首次运行交互式 MFA 后，session cookies 缓存至 `data/cache/`，后续从 cookies 恢复无需 MFA。首次 requires 人工在 CI 中手动触发带 Secrets 的 workflow_dispatch。

### CI cache

| 缓存 | GH Cache Key | 路径 |
|---|---|---|
| DI token | `garmin-tokens-v1-garmin-{run_id}` | `data/cache/garmin_garmin_com_tokens.json` |
| CN token | `garmin-tokens-v1-garmin_cn-{run_id}` | `data/cache/garmin_garmin_cn_tokens.json` |
| Playwright browser（可选） | `garmin-playwright-browser-v1-{os}` | `~/.cache/ms-playwright` |
