# Garmin OAuth Auth — Design

> **已迁移至 git-fit gem（`git fit sync` / `git fit auth garmin`）。** 本地薄壳仅保留 `GarminBase` / `GarminCN` / XOSS / XingZhe 用于交互式 auth；Garmin Intl 认证（`GarminBaseDI` / `Garmin`）与 token 管理（`Auth::GarminToken`）位于 git-fit 的 `lib/git_fit/sync/` / `lib/git_fit/auth/`。以下为设计摘要。

> **2026-08-09：** workouts 侧 Python 认证脚本（`scripts/garmin_auth_local.sh` / `garmin_auth.py` / `garmin_auth_playwright.py`）已删除，由 git-fit `Auth::Garmin`（StrategyA/B，全 Ruby）取代（git-fit #66）。本文保留 DI OAuth2 协议设计（token 格式、传输链、故障排查）作为权威参考，Python 实现细节段落已移除。

## Architecture overview

```
GarminBase（OAuth1 纯基类）
  ├── GarminBaseDI（DI OAuth2 基类）── Garmin（garmin.com）
  └──────────────────────────────── GarminCN（garmin.cn）
```

| 类 | 域 | 认证路径 | 代码文件 |
|---|---|---|---|
| `GarminBase` | - | 共享基类方法（parse_secret_string、dump_secret、api_get 等） | 本地 `garmin_base.rb` + git-fit `garmin_base.rb` |
| `GarminBaseDI` | - | CI: token cache → auth_seed refresh | git-fit `garmin_base_di.rb` |
| `Garmin` | garmin.com | authenticate_di → DI OAuth2 | git-fit `garmin.rb`（12 行） |
| `GarminCN` | garmin.cn | authenticate → OAuth1→OAuth2 | 本地 `garmin_cn.rb` + git-fit `garmin_cn.rb` |

---

## garmin_cn: OAuth1→OAuth2 Chain

garmin.cn 未受 CF 封锁影响，SSO 登录可正常工作。

### Auth priority chain

```
① secret (config.yml / env SYNC__GARMIN_CN__SECRET)
   Base64([OAuth1 JSON, OAuth2 JSON]) — garth dumps() 兼容
   Parse → OAuth2 valid? → 直接用。过期 → OAuth1 refresh → 新 OAuth2
   Fail → 降级

② token 文件（data/auth/garmin_cn/tokens.json, GH Cache）
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
| 缓存 | `data/auth/garmin_cn/tokens.json`（GH Cache） | ✅ |
| 降级 | SSO 登录（email+password） | ❌ 交互式 |

---

## garmin_intl: DI OAuth2 Flow

garmin.com 的 SSO 端点 `/mobile/api/login` 已被 Garmin 关闭（返回 400），OAuth1 `/preauthorized` 端点也返回 401。CF 对 TLS 指纹严格检测，普通 HTTP 库全部 429/403。

### Auth priority chain（GarminBaseDI#authenticate — CI only）

```
① DI token 缓存（data/auth/garmin/tokens.json, GH Cache）
   access_token 有效 → 直接用。过期 → di_refresh。
   refresh 失败 → 清除缓存 → 降级

② auth_seed（sync.garmin.auth_seed / SYNC__GARMIN__AUTH_SEED, GitHub Secret）
   Base64 DI OAuth2 JSON → decode → save_tokens → use / di_refresh
   refresh 失败 → 清空 @access_token → false

本地 MFA 登录通过 `git fit auth garmin`（Ruby StrategyA/B）独立完成，
不在 Ruby authenticate（sync）流程内。
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

本地 MFA 登录通过 `git fit auth garmin` 独立于 Ruby 认证（sync）流程。

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

### git fit auth garmin CLI（设计：git-fit #63）

> **状态：** **已实现（git-fit 0.10.7，[#63](https://github.com/Lax/git-fit/issues/63)）**。本地 `auth garmin` 已改为委托 `git fit auth garmin`（透传 `-A`/`-B`/`--auto`/`--sync`）。原 workouts `scripts/garmin_auth_*.sh/py` Python 参考实现已删除（git-fit #66），由 Ruby 策略取代。真实端点验证发现并修复两个运行时 bug（Playwright driver 路径、curl-impersonate 指纹名），MFA 登录验证待凭据可用时完成，**issue #63 在真实登录成功前保持 OPEN**。
> 本小节为设计文档（docs-first），历史结论（策略语义、实测时间戳、cookie 有效期）以原文「实测结果（2026-06-18 更新）」为准。

#### 策略参数接口

`git fit auth garmin` 通过三个互斥旗标选择认证策略：

| 命令 | 策略 | 行为 |
|---|---|---|
| `git fit auth garmin` | `--auto`（默认） | 先 B，失败降级 A |
| `git fit auth garmin --auto` | auto | 显式等价默认：B 失败自动降级 A |
| `git fit auth garmin -B` | B | Playwright 策略 B（`playwright-ruby-client`） |
| `git fit auth garmin -A` | A | 强制策略 A（`curl-impersonate` shellout） |

- `-A` / `-B` / `--auto` 互斥，同时给出报错
- 默认 `--auto`（B primary / A fallback），与下方「决策依据」中选 B 优先的三条原因一致；`-B` / `-A` 为显式覆盖旗标

#### Ruby 等价映射（对齐 git-fit #63 技术选项）

| 策略 | git-fit（Ruby，已落地 0.10.7） | 运行时依赖 |
|---|---|---|
| B（`--auto` 优先） | `playwright-ruby-client` gem（`Auth::Garmin::StrategyB`） | Node.js 运行时 |
| A（`--auto` 降级） | `curl-impersonate` 二进制 shellout（`Auth::Garmin::StrategyA`） | curl-impersonate（原生，零 gem 依赖） |

策略 B / A 的 TLS 穿透语义与上文「Strategy B (Playwright)」/「Strategy A (curl_cffi)」实测结论一致，仅运行时载体为 Ruby 实现（`git fit auth garmin` 编排：`Auth::Garmin` → `StrategyA/B` → `DIExchange`）。原 Python 脚本参考实现已删除（git-fit #66）。

#### 决策依据

依据上文「实测结果（2026-06-18 更新）」逐条对应：

| 旗标设计 | 依据 |
|---|---|
| 默认 `--auto` | B primary：`context.request` Chrome TLS 指纹穿透 mobile API CF；首次 SSO+MFA 后 cookie 365d（CASMFA `Max-Age=31536000` + DI token 内 `mfa_expiration_timestamp` 双证据）；后续零交互、秒级完成。A 作失败降级 |
| 选 B 优先的三条原因 | (1) cookie 服务端声明 365 天有效；(2) 首次后零交互；(3) 纯 Python 依赖无 C 编译 |
| `-A` 强制 | A fallback：`mobile+cffi` Safari TLS 穿透但无 cookie 持久化，每次 30-45s 延时 + MFA；`portal+cffi` 部分指纹返回 403。提供 Playwright 运行时（Node.js）不可用时的强制降级路径 |
| `--auto` | 默认策略：显式化 B primary / A fallback 链，B 优先，A 作已验证的 TLS 指纹降级路径 |

#### 历史保留说明

「实测结果（2026-06-18 更新）」段落原文保留不动，其策略语义、实测时间戳、cookie 有效期等历史结论以原文为准。本小节仅追加接口设计，不覆盖既有内容。

### 首次设置（有 MFA）

```bash
git fit auth garmin
```

静态 `auth_seed` 引导 CI 完成第一次认证 → 后续 CI 使用 `data/cache/` 中的工作副本自旋。

命令自动做：读 `config.yml` → 默认 `--auto`（Strategy B Playwright 优先，失败降级 Strategy A curl-impersonate）穿透 CF → 提示输入 MFA（或 `--mfa-code`）→ DI OAuth2 token 交换 → Base64 编码 → 写入 `config.yml`（`sync.garmin.auth_seed`）→ 尝试 `gh secret set SYNC_GARMIN_AUTH_SEED`。

### 日常 token 同步

```bash
git fit auth garmin --sync
```

**为什么需要 `--sync`：**

1. 本地执行 `git fit sync --source garmin` 后，CI 中使用的 refresh_token **被旋转**（每次 refresh_token 调用旋转 token，旧 token 永久失效）。
2. 此时 `SYNC_GARMIN_AUTH_SEED` 中保存的旧 auth_seed 已包含被旋转过的 refresh_token。
3. 下一次 CI 运行，若 GH Cache miss（7 天缓存或 cache 全部失效），CI 回退到 `load_auth_seed` → `refresh_token()` → **失败**（refresh_token 已被本地旋转）→ 需重新运行 `git fit auth garmin` 更新 auth_seed
4. `auth_seed` 是 CI 冷启动的最后防线；只要 auth_seed 中的 refresh_token 比 CI 的 cache 更新即可。

**`--sync` 解决的问题：** 在后续本地完成 sync（`data/auth/garmin/tokens.json` 已更新）后，调用 `--sync` 将最新的 cache token 升格为下一个 auth_seed。
这确保 CI 在任何 cache miss 时都能降级到最新的 refresh_token。

**用法：** 本地 sync 后执行 `--sync`

```
git fit auth garmin --sync
# 读取 data/auth/garmin/tokens.json
# Base64 编码 → 写 config.yml（sync.garmin.auth_seed）
# → gh secret set SYNC_GARMIN_AUTH_SEED
```

### 本地 MFA 登录

本地 MFA 登录通过 `git fit auth garmin` 的 Ruby 策略（`Auth::Garmin` → `StrategyA/B` → `DIExchange`）独立完成，**不在 Ruby authenticate（sync）流程内**。
sync 只消费产出的 token（`data/auth/garmin/tokens.json`）+ 已编码的 `auth_seed`。
CI 不与 MFA 交互——仅使用 auth_seed + token 缓存自旋。

策略 B / A 的端点流程、TLS 穿透语义与上文「实测结果（2026-06-18 更新）」结论一致；原 Python 参考实现（curl_cffi / playwright）已删除，由 git-fit `Auth::Garmin` Ruby 实现取代（git-fit #66）。

#### 为什么不在 Ruby authenticate 中

| 原因 | 说明 |
|---|---|
| CF TLS 检测 | Ruby `Net::HTTP` 被 Cloudflare 429/403。Playwright（APIRequestContext，真实 Chrome TLS）/ curl-impersonate（TLS 指纹模拟）才具备穿透能力 |
| MFA 交互 | MFA 需交互式输入（或 `--mfa-code`），不适合 CI 的无人值守环境 |
| 设计原则 | CI 通过 `auth_seed`（预先认证的 DI token）初始化，然后靠 token 缓存 + `refresh_token` 自旋。本地认证一次性生成 `auth_seed`，编入 GitHub Secret |

### CI cache

| 缓存 | GH Cache Key | 路径 |
|---|---|---|
| DI token | `tokens-v0-garmin-auth-{run_id}` | `data/auth/garmin/` |
| CN token | `tokens-v0-garmin_cn-auth-{run_id}` | `data/auth/garmin_cn/` |
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
