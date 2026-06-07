# Workouts CLI

运动数据聚合工具。从 Strava、Keep、iGPSPORT、XOSS、XingZhe、Garmin 同步运动记录，统一存入 SQLite，然后导出为 JSON、CSV 或 SVG 海报。

数据流：`多渠道同步 → SQLite → 导出`，全部在 CLI 里搞定，适合 CI 定时跑。

## 快速开始

需要 Ruby 3.4+ 和 Bundler。

```bash
git clone https://github.com/Lax/workouts.git
cd workouts
bundle install

# 生成配置模板，填入你的账号信息
bin/workouts init
# 编辑 config/config.yml... 或者设置环境变量

# 同步所有已配置的来源
bin/workouts sync

# 导出
bin/workouts export svg --style github
```

### Docker

```bash
docker compose run --rm workouts sync
docker compose run --rm workouts export svg --style github
```

## 支持的源

| 源 | 认证方式 | 同步 | 原始 GPS |
|---|---|---|---|
| Strava | OAuth2 refresh_token | ✅ | ✅ |
| Keep | 手机号 + 密码 | ✅ | ✅（AES 解密 + GCJ-02→WGS84） |
| iGPSPORT | 手机号 + 密码 | ✅ | ✅（FIT 原始格式） |
| XOSS | 邮箱 + JWT | ✅ | 摘要 |
| XingZhe | 邮箱 + RSA 加密密码 | ✅ | 摘要 |
| Garmin CN | SSO + OAuth | ✅ | 摘要 |
| Garmin 国际版 | SSO + OAuth | ⚠️ CF 429 封禁中 | — |

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
| `parse activity.gpx --save` | 解析本地 GPX/TCX 并写入 DB |
| `init` | 生成默认配置 |
| `migrate` | 运行数据库迁移 |
| `version` | 查看版本 |

SVG 支持 5 种风格：`github`、`grid`、`circular`、`month-of-life`、`year-summary`。

## 数据架构

```
L1: data/raw/{source}/{id}.ext    原始 API 响应（GPS 点阵备份）
L2: data/std/{source}/{id}.json   规整后的标准格式
L3: SQLite                        摘要库（polyline + 统计字段）
L4: build/                        导出制品（JSON / CSV / SVG / HTML）
L5: GitHub Pages                  运动数据展示页
```

## 配置

支持三层叠加（优先级从高到低）：

1. 环境变量（`SYNC__KEEP__PHONE`，双下划线做层级分隔）
2. `config/config.yml`
3. 代码内默认值

配置示例见 `.env.example`。

## 去重

两级机制：`run_id` 精确去重 + 跨源置信度打分（时间/距离/时长三维度），匹配结果在 SVG 上以标注显示。

## 项目状态

已同步 1100+ 条活动记录，覆盖 5 个运动平台，每日 CI 自动同步 + 发布 GitHub Pages。

详见 [CONTEXT.md](CONTEXT.md)。
