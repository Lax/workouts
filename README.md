# Workouts CLI

运动数据聚合工具。从 Strava、Keep、iGPSPORT、XOSS、XingZhe、Garmin CN、Garmin 国际版 同步，以及 Apple Health、GPX、FIT、TCX 本地导入，统一存入 SQLite，然后导出为 JSON、CSV 或 SVG 海报。

数据流：`多渠道同步 → SQLite → 导出`，全部在 CLI 里搞定，适合 CI 定时跑。

## 快速开始

需要 Ruby 3.4+ 和 Bundler。

```bash
git clone https://github.com/Lax/workouts.git
cd workouts
bundle install

# 生成配置模板，填入你的账号信息
exe/workouts init
# 编辑 config/config.yml... 或者设置环境变量

# 同步所有已配置的来源
exe/workouts sync

# 导出
exe/workouts export svg --style github
```

### Docker

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export svg --style github
```

## 支持的源

| 源 | 方式 | 认证方式 | 源数据格式L1 ( → L2 JSON → L3 DB) |
|---|---|---|---|
| Strava | 同步 | OAuth2 refresh_token | **JSON**，GPX，FIT，TCX |
| Keep | 同步 | 手机号 + 密码 | **JSON**（AES解密+GCJ-02→WGS84） |
| iGPSPORT | 同步 | 手机号 + 密码 | **FIT**，GPX，TCX |
| XOSS | 同步 | 邮箱 + JWT | **FIT** |
| XingZhe | 同步 | 邮箱 + RSA 加密密码 | **JSON** |
| Garmin CN | 同步 | SSO + OAuth1→OAuth2 (secret) | **FIT**，GPX，TCX，CSV |
| Garmin 国际版 | 同步 | DI OAuth2 (auth_seed) | **FIT**，GPX，TCX，CSV |
| Apple Health | 导入 | — | ✅ **export.zip**（XML + GPX） |
| GPX | 导入 | — | △ |
| FIT | 导入 | — | ○ |
| TCX | 导入 | — | △ |

> ✅ 已实现  △ 部分可用（parse CLI）  ○ 待实现

## 常用命令

| 命令 | 说明 |
|---|---|
| `sync` | 同步所有已配置的来源 |
| `sync --source strava` | 只同步特定来源 |
| `sync --act run` | 只同步某种运动类型 |
| `auth garmin_cn` | 交互式登录 |
| `export json` | 导出 JSON |
| `export csv` | 导出 CSV |
| `export svg --style github` | 生成 SVG 海报 |
| `export stats` | 导出统计摘要 |
| `export gpx` | 从 L2 重新导出 GPX |
| `export all` | 执行所有导出 |
| `parse activity.gpx --save` | 解析本地 GPX/TCX 并写入 DB |
| `init` | 生成默认配置 |
| `version` | 查看版本 |

SVG 支持 5 种风格：`github`、`grid`、`circular`、`month-of-life`、`year-summary`。

## 数据架构

详见 [docs/data-architecture.md](docs/data-architecture.md)。

## 配置

支持三层叠加（优先级从高到低）：

1. 环境变量（`SYNC__KEEP__PHONE`，双下划线做层级分隔）
2. `config/config.yml`
3. 代码内默认值

配置示例见 `.env.example`。

## 项目状态

覆盖 9 个数据源（Strava / Keep / iGPSPORT / XOSS / XingZhe / Garmin CN / Garmin 国际版 / Apple Health / 本地文件），支持 JSON / CSV / SVG 导出，通过 GitHub Actions 自动同步、去重、发布 GitHub Pages。

详见 [CONTEXT.md](CONTEXT.md)。
