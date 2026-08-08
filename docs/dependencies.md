# Dependencies — Ruby + Node

Ruby 运行时、Node workspace 依赖引用一览。新增/改依赖时先查此表。

## Ruby

### 入口

| 文件 | 作用 |
|---|---|
| `Gemfile` | 入口，加载 gemspec + 外部 gem（git-fit） + dev group |
| `workouts-cli.gemspec` | CLI 运行时依赖（ Bundler 安装此表） |

### 运行时（workouts-cli.gemspec）

| 依赖 | 声明 | 使用位置 |
|---|---|---|
| thor | `~> 1.3` | cli/*.rb |
| sequel | `~> 5.0` | db/connection.rb, db/rebuild.rb |
| sqlite3 | `~> 2.0` | workouts.rb（require "sqlite3"） |
| faraday | `~> 2.0` | auth/strava.rb |
| base64 | `~> 0.2` | sync/keep.rb, sync/garmin_base.rb |
| zlib | `~> 3.0` | sync/keep.rb（deflate） |
| openssl | `~> 3.0` | sync/keep.rb, sync/xingzhe.rb（HMAC/RSA） |
| nokogiri | `~> 1.16` | parser/gpx.rb, parser/tcx.rb |
| oauth | `~> 1.0` | sync/garmin_base.rb（OAuth1 签名） |
| mini_racer | `~> 0.16` | fit/decoder.rb（V8 执行 vendored @garmin/fitsdk） |
| webrick | `~> 1.8` | auth/strava.rb（本地 HTTP 回调） |
| ostruct | `~> 0.6` | sync/garmin_base.rb（OpenStruct 转 hash） |
| rubyzip | `~> 2.3` | sync/garmin_base.rb（require "zip"） |
| timezone_finder | `~> 1.5` | timezone/resolver.rb |
| tzinfo | `~> 2.0` | sync/keep/xoss/xingzhe/garmin_base |

### Dev group（Gemfile）

| 依赖 | 用途 |
|---|---|
| rake ~> 13.0 | Rakefile（rspec task） |
| rspec ~> 3.12 | 测试框架 |
| pry | 本地调试（代码中零使用） |
| standard ~> 1.0 | 本地 lint（ci.yml 不执行） |

### 约定

- 运行时依赖全在 gemspec，Gemfile 只加 `gemspec` + 外部 gem（git-fit）。
- Gemfile dev group **不再重复** gemspec 已有的 runtime gem（mini_racer、webrick 等）。
- Strava 网页抓取客户端已独立为 `stravaweblib` gem（Lax/stravaweblib），由 git-fit 依赖。
- default gem（securerandom, date, time, json, zlib, openssl, ostruct, base64）无需额外声明。

## Node

### Workspace 依赖图

```
shared              无依赖（纯类型）
  └─ core           peer: react, react-dom
       └─ plugin-data-source   peer: react
       └─ plugin-map           peer: react, leaflet; dep: leaflet
       └─ plugin-ui            peer: react
       └─ plugin-chart         peer: react, echarts ^6.0.0; dep: echarts ^6.1.0
       └─ theme-hello-world    peer: react
       └─ theme-simple         peer: react; dep: zustand
       └─ theme-overview       peer: react; dep: leaflet, zustand
  └─ web            dep: 全部 9 workspace + echarts + leaflet + react + react-dom + zustand
```

### Workspace 依赖矩阵

| 包 | peerDependencies | dependencies | devDependencies |
|---|---|---|---|
| shared | — | — | — |
| core | react ^19, react-dom ^19 | @workouts/shared | @types/react, @types/react-dom, react, react-dom |
| plugin-data-source | react ^19 | @workouts/core, @workouts/shared | react |
| plugin-map | react ^19, leaflet ^1.9.4 | @workouts/core, @workouts/shared, leaflet | react, @types/leaflet |
| plugin-chart | react ^19, **echarts ^6.0.0** | @workouts/core, @workouts/shared, echarts ^6.1.0 | react, echarts |
| plugin-ui | react ^19 | @workouts/core, @workouts/shared | react |
| theme-hello-world | react ^19 | @workouts/core | react |
| theme-simple | react ^19 | @workouts/core, @workouts/plugin-chart, @workouts/plugin-data-source, @workouts/plugin-map, @workouts/shared, zustand | react, zustand |
| theme-overview | react ^19 | @workouts/core, @workouts/plugin-chart, @workouts/plugin-data-source, @workouts/plugin-map, @workouts/plugin-ui, zustand, leaflet | react, @types/leaflet, zustand |
| web | — | 全部 9 workspace + echarts + leaflet + react + react-dom + zustand | @playwright/test, @types/leaflet, @types/node, @types/react, @types/react-dom, @vitejs/plugin-react, jsdom, typescript, vite, vitest |

### 约定

- **peer + dev react 双声明**：标准做法，不动。consumer 通过 peer 提供 react，本地开发/测试通过 dev 安装。
- **internal workspace 只在 dependencies 声明一次**，devDependencies 不再重复（workspace symlink 下可解析）。
- **echarts peer 版本**必须与 dep 主版本对齐（当前 ^6.0.0）。
- `@types/*` 仅放 devDependencies，不污染依赖图。
- web 的 `leaflet`、`zustand` 为手动 chunk 和测试所需，保留显式声明。
