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
| `GarminBaseDI` | - | CI: token cache → auth_seed refresh | `garmin_base_di.rb` |
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

### Auth priority chain（GarminBaseDI#authenticate — CI only）

```
① DI token 缓存（data/cache/garmin_garmin_com_tokens.json, GH Cache）
   access_token 有效 → 直接用。过期 → di_refresh。
   refresh 失败 → 清除缓存 → 降级

② auth_seed（sync.garmin.auth_seed / SYNC__GARMIN__AUTH_SEED, GitHub Secret）
   Base64 DI OAuth2 JSON → decode → save_tokens → use / di_refresh
   refresh 失败 → 清空 @access_token → false

本地 MFA 登录通过 scripts/garmin_auth_local.sh 独立完成，
不在 Ruby authenticate 流程内。
```

### Token lifetimes

| Token | TTL | 续期方式 |
|---|---|---|
| DI access_token | ~18h | POST diauth.garmin.com refresh_token |
| DI refresh_token | 30d 滑动窗口 | 每次 refresh 旋转续期，每日 CI 运行即可无限延续 |

### 凭据来源

| 来源 | CI 可用？ |
|---|---|
| `SYNC__GARMIN__AUTH_SEED`（GitHub Secret） | ✅ 唯一 CI 入口 |
| DI token（GH Cache） | ✅ 日常续期 |

本地 MFA 登录通过 `scripts/garmin_auth_local.sh` 独立于 Ruby 认证流程。

### 实测结果（2026-06-18 更新）

**Strategy B (Playwright) — primary**

- `context.request` Chrome TLS 指纹通过 mobile API 端点 CF
- 首次 SSO+MFA 后 Set-Cookie 返回 CASMFA `Max-Age=31536000`、`Expires=2027-06-18`（365 天）
- DI OAuth2 token payload 内 `mfa_expiration_timestamp` 同为 `2027-06-18` — 双证据确认
- 后续执行：GET signin → 302 redirect 直接返 ticket，无 MFA，秒级完成
- CASTGC（Ticket Granting Cookie）无显式 Max-Age，Garmin 可能服务端提前吊销 — 待时间验证

**Strategy A (curl_cffi) — fallback**

- `mobile+cffi` Safari TLS 穿透 CF，无 cookie 持久化，每次 30-45s 延时 + MFA
- `portal+cffi` 5 指纹中 safari_ios/chrome120 返回 403

**选 B 优先的原因：** (1) cookie 服务端声明 365 天有效；(2) 首次后零交互；(3) 纯 Python 依赖无 C 编译。A 作为已验证的 TLS 指纹降级路径。

### 首次设置（有 MFA）

```bash
./scripts/garmin_auth_local.sh
```
静态 `auth_seed` 引导 CI 完成第一次认证 → 后续 CI 使用 `data/cache/` 中的工作副本自旋。

脚本自动做：读 `config.yml` → `mobile+cffi` 穿透 CF（~60s）→ 提示输入 MFA → DI OAuth2 token 交换 → Base64 编码 → 写入 `config.yml`（`sync.garmin.auth_seed`）→ 尝试 `gh secret set SYNC_GARMIN_AUTH_SEED`

### 日常 token 同步

```bash
./scripts/garmin_auth_local.sh --sync
```

**为什么需要 `--sync`：**

1. 本地执行 `workouts sync --source garmin` 后，CI 中使用的 refresh_token **被旋转**（每次 refresh_token 调用旋转 token，旧 token 永久失效）。
2. 此时 `SYNC_GARMIN_AUTH_SEED` 中保存的旧 auth_seed 已包含被旋转过的 refresh_token。
3. 下一次 CI 运行，若 GH Cache miss（7 天缓存或 cache 全部失效），CI 回退到 `load_auth_seed` → `refresh_token()` → **失败**（refresh_token 已被本地旋转）→ 需重新运行 `scripts/garmin_auth_local.sh` 更新 auth_seed
4. `auth_seed` 是 CI 冷启动的最后防线；只要 auth_seed 中的 refresh_token 比 CI 的 cache 更新即可。

**`--sync` 解决的问题：** 在后续本地完成 sync（`data/cache/garmin_garmin_com_tokens.json` 已更新）后，调用 `--sync` 将最新的 cache token 升格为下一个 auth_seed。
这确保 CI 在任何 cache miss 时都能降级到最新的 refresh_token。

**用法：** 本地 sync 后执行 `--sync`

```
scripts/garmin_auth_local.sh --sync
# 读取 data/cache/garmin_garmin_com_tokens.json
# Base64 编码 → 写 config.yml（sync.garmin.auth_seed）
# → gh secret set SYNC_GARMIN_AUTH_SEED
```

### 本地 MFA 登录脚本

本地 MFA 登录通过 `scripts/` 下的 Python 脚本独立完成，**不在 Ruby authenticate 流程内**。
Ruby 只消费脚本产出的 token（`data/cache/garmin_garmin_com_tokens.json`）+ 已编码的 `auth_seed`。
CI 不与 MFA 交互——仅使用 auth_seed + token 缓存自旋。

#### 调用关系

```
garmin_auth_local.sh               # Shell orchestrator, reads config.yml → dispatches
  ├── --sync 模式                   # reads cache token → Base64 → writes auth_seed
  └── SSO 模式 (without --sync)     # environment: SYNC__GARMIN__EMAIL + PASSWORD
        ├── Strategy B (primary)    # garmin_auth_playwright.py (Playwright, ~1yr session cookies)
        │     └── mobile API        # context.request → /mobile/api/login → /mobile/api/mfa/verifyCode
        └── Strategy A (fallback)   # garmin_auth.py (curl_cffi, TLS impersonation)
              ├── mobile+cffi       # Safari TLS, /mobile/api/login
              └── portal+cffi       # 5 TLS fingerprints, /portal/api/login
```

两种策略都是**独立的本地工具**，各打印 JSON DI OAuth2 token 到 stdout。
脚本成功后自动完成：DI exchange → token JSON → Base64 → 写入 `config.yml`(`sync.garmin.auth_seed`) → 尝试 `gh secret set`。

#### Strategy A: curl_cffi（`scripts/garmin_auth.py:258-284`）

依赖 `curl_cffi` Python 包。通过对 TLS 指纹的精确模拟绕过 Cloudflare 检测。

| 子策略 | 端点 | TLS 模拟 | 调用路径 |
|---|---|---|---|
| `mobile+cffi`（主） | `/mobile/api/login` | `safari` | Android WebView UA, 30-45s 随机延迟 |
| `portal+cffi`（降级） | `/portal/api/login` | 5 指纹轮换：`safari`, `safari_ios`, `chrome120`, `edge101`, `chrome` | 桌面 UA, 每个指纹 30-45s 延迟 |

流程：
```
mobile+cffi: GET signin page → random delay(30-45s) → POST credentials
  → success: return serviceTicketId
  → MFA_REQUIRED: stdin prompt "Enter MFA code:" → POST /mobile/api/mfa/verifyCode
  → success: return serviceTicketId
  → 429/error → fall to portal+cffi

portal+cffi: for each of 5 TLS fingerprints:
  GET signin → delay(30-45s) → POST credentials
  → success: return serviceTicketId
  → MFA_REQUIRED: stdin prompt → POST /portal/api/mfa/verifyCode
  → 429 → continue to next fingerprint

After ticket: _di_exchange(domain, ticket, service_url)
  → POST diauth.garmin.com/di-oauth2-service/oauth/token
  → 3 DI_CLIENT_IDS retry (quarterly rotation: 2025Q2, 2024Q4, base)
```

MFA 处理 (`_handle_mfa`, line 96-130):
- 优先读 env var `SYNC__GARMIN__MFA_CODE`（自动化场景）
- 否则 `stdin` 交互式提示 "Enter MFA code:"（交互式场景）
- 先试 `portal/api/mfa/verifyCode`，失败再试 `mobile/api/mfa/verifyCode`

实测结论 (2026-06-17):
- `mobile+cffi` Safari TLS 成功穿透 CF（有/无 MFA 均可用）
- `portal+cffi` 中 `safari_ios`/`chrome120` 返回 403，`safari`/`edge101`/`chrome` 无响应
- 30-45s 随机延迟对 CF WAF bypass 至关重要

#### Strategy B: Playwright（`scripts/garmin_auth_playwright.py`）

依赖 `playwright` Python 包 + Chromium 浏览器。使用真实浏览器的 APIRequestContext 调用 mobile API 端点绕过 Cloudflare。

Garmin SSO **网页**（portal / widget / connect 页面）受 CF WAF 严格保护，headless Chromium 返回 429 / "Access denied"。但 `/mobile/api/login` 等 **API 端点** 接受真实 Chrome TLS 指纹，Playwright 的 `context.request` 可正常调用。

| 特性 | 详情 |
|---|---|
| 引擎 | Playwright Chromium, headless |
| 通信方式 | `context.request`（APIRequestContext），非页面导航 |
| UA | Android WebView (same as mobile+cffi) |
| Session 缓存 | `data/cache/garmin_playwright_session_{domain}.json` — cookies 有助降低 CF 检测，但每次仍需重新 SSO 登录 |
| MFA 处理 | stdin 交互 + `SYNC__GARMIN__MFA_CODE` env var |
| 延时 | 30-45s 随机延时（与 Strategy A 一致） |

流程：
```
1. Launch Chromium (headless)
2. Restore session cookies from cache (optional — helps CF bypass)
3. GET /mobile/sso/en_US/sign-in (establish CF cookies)
4. 30-45s random delay
5. POST /mobile/api/login (credentials as JSON)
   → SUCCESS: return CAS ticket
   → MFA_REQUIRED: prompt code → POST /mobile/api/mfa/verifyCode
6. _di_exchange(domain, ticket) — POST diauth.garmin.com
7. Save session cookies + output DI OAuth2 JSON to stdout
```

与 Strategy A 的区别:
- Strategy A（curl_cffi）依赖 C 扩展的 TLS 指纹模拟，需编译 `curl_cffi` 包
- Strategy B（Playwright）纯 Python 依赖（pip install playwright），部署更简单
- 两者都使用相同的 mobile API 端点 + DI exchange 逻辑
- Playwright 的 `context.request` 在浏览器进程的上下文中发请求，CF 看到真实 Chrome TLS 指纹

#### 为什么不在 Ruby authenticate 中

| 原因 | 说明 |
|---|---|
| CF TLS 检测 | Ruby `Net::HTTP` 被 Cloudflare 429/403。Playwright（APIRequestContext，真实 Chrome TLS）/ curl_cffi（TLS 指纹模拟）才具备穿透能力 |
| 重依赖 | `curl_cffi` (C FFI + TLS 库) 和 `playwright` (Chromium 浏览器) 是 Python-only 的 |
| MFA 交互 | stdin 交互式输入（"Enter MFA code:"）不适合 CI 的无人值守环境 |
| 设计原则 | CI 通过 `auth_seed`（预先认证的 DI token）初始化，然后靠 token 缓存 + `refresh_token` 自旋。本地脚本一次性生成 `auth_seed`，编入 GitHub Secret |

### CI cache

| 缓存 | GH Cache Key | 路径 |
|---|---|---|
| DI token | `garmin-tokens-v1-garmin-{run_id}` | `data/cache/garmin_garmin_com_tokens.json` |
| CN token | `garmin-tokens-v1-garmin_cn-{run_id}` | `data/cache/garmin_garmin_cn_tokens.json` |
| Playwright browser（可选） | `garmin-playwright-browser-v1-{os}` | `~/.cache/ms-playwright` |

---

## 附录：数据传输链与关键格式

### 数据格式

#### ① CAS Service Ticket

| 属性 | 值 |
|---|---|
| 格式 | `ST-XXXXXXXXXXXXXXXXXXXXXXXXXXXX`（40+ 字符） |
| 来源 | SSO 登录成功：`response.serviceTicketId` |
| 去向 | 作为 `service_ticket` 参数 POST 到 DI token exchange |
| 有效期 | 一次性，换完即废 |
| 存储 | 仅内存，不落盘 |

#### ② DI OAuth2 Token JSON

```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "expires_in": 64800,
  "scope": "DI_COACHING_WRITE ...",
  "token_type": "Bearer",
  "di_client_id": "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2"
}
```

| 字段 | 来自 | 去向 | 设计原因 |
|---|---|---|---|
| `access_token` | `diauth.garmin.com` 响应 | `Authorization: Bearer` 请求头 | OAuth2 bearer token，~18h |
| `refresh_token` | 同一次响应 | refresh 请求 body | 30d 滑动窗口，每次 refresh 旋转续期 |
| `di_client_id` | JWT payload 的 `client_id` 声明 | refresh 的 `client_id` 参数 + Basic auth | **refresh 时必须用签发 token 的那个 client_id**（Garmin 季度轮换），用错返回 401 |
| `expires_at` | 脚本/Ruby 计算 | `access_token_valid?` 判断 | `time() + expires_in` |

#### ③ DI Token Exchange 请求

```
POST https://diauth.garmin.com/di-oauth2-service/oauth/token
Authorization: Basic base64(client_id + ":")   ← ""空 secret，DI 协议要求
Content-Type: application/x-www-form-urlencoded
Cache-Control: no-cache                          ← 阻止 CF 缓存 stale token
User-Agent: GCM-Android-5.23                    ← Android app UA

client_id=GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2
service_ticket=ST-XXXX                            ← 不是 "ticket"！
grant_type=https://connectapi.garmin.com/.../service_ticket
service_url=https://mobile.integration.garmin.com/gcm/android  ← 必须匹配 SSO 登录的 service
```

#### ④ auth_seed 编码链

```
DI Token JSON (来自 diauth.garmin.com)
  │  JSON.dump
  ▼
JSON 文本
  │  Base64.strict_encode64
  ▼
Base64 文本 → config.yml（sync.garmin.auth_seed）
           → GitHub Secret（SYNC_GARMIN_AUTH_SEED）
           → env var（SYNC__GARMIN__AUTH_SEED）

CI 中 decode:
  Base64.strict_decode64 → JSON.parse → @access_token → save_tokens(data/cache/)
```

### 传输链

```
用户邮箱+密码
  ▼
SSO: POST /mobile/api/login（或 /portal/api/login）
  │  ← MFA? stdin 输入验证码
  ▼
CAS Service Ticket (ST-XXXX)
  ▼
POST diauth.garmin.com/di-oauth2-service/oauth/token
  Headers: Authorization: Basic + Garmin-UA + Cache-Control
  Body: client_id + service_ticket + grant_type + service_url
  │  ← service_url 必须与 SSO 登录一致（混用返回 400）
  ▼
DI OAuth2 Token JSON
  ├─ access_token → data/cache/ → Ruby api_get
  ├─ refresh_token → refresh_token()
  └─ di_client_id → refresh Basic auth
  ▼
┌────────── 每日 CI ──────────┐
│ load_tokens(data/cache/)    │
│ access_token 有效?          │
│ ├─ 是 → api_get              │
│ └─ 否 → refresh_token() →   │
│      新 token → save_tokens │
│      30d 滑动窗口            │
└────────────────────────────┘
  ▼
Garmin API: Authorization: Bearer eyJ...
```

### 设计决策

| 决策 | 原因 |
|---|---|
| `Authorization: Basic base64(client_id:)` | DI OAuth2 协议，client_id 作用户名，空串作密码。与 OAuth1 consumer secret 签名无关 |
| `service_url` 必须匹配 SSO | Garmin 验证 ticket 和 exchange 来自同一流程。mobile 用 `mobile.integration.garmin.com`，portal 用 `connect.garmin.com/app` |
| `service_ticket` 不是 `ticket` | Garmin 的特定参数命名（与其他 SSO API 不一致） |
| `Cache-Control: no-cache` | 防止 Cloudflare 缓存过期 token |
| `di_client_id` 存入 token JSON | 刷新时**必须用签发 token 的那个 client_id**，不能写死 |
| 30d refresh_token 滑动窗口 | 每次 refresh 返回新 refresh_token 并旋转旧 token。连续 30 天未刷新则失效，需重新用 `auth_seed` 或 SSO 引导 |
| `auth_seed`（非 `refresh_token`）命名 | 因为它存的是**整个 DI OAuth2 token JSON 的 Base64**（access + refresh + client_id），不是单一 refresh_token 字符串。与 Strava 的 `refresh_token`（真刷新令牌）语义分离 |

### DI Exchange 故障排查

| HTTP | 可能原因 |
|---|---|
| 400 | `service_ticket` 参数名写错（写成了 `ticket`） |
| 400 | 缺失 `service_url` 参数 |
| 400 | 缺失 `Authorization: Basic` 请求头 |
| 401 | DI client_id 已作废（Garmin 季度轮换） |
| 401 | `service_url` 与 SSO 登录时使用的不一致 |
| 429 | CF 速率限制（增加 delay） |
