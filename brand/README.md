# brand/ — 品牌叠加层

本目录承载所有对 opencode 的定制内容，与上游源码（`opencode/` submodule）**物理隔离**。
上游更新只需同步 submodule，本目录不受影响；本目录的改动也不会污染上游源码，便于跟踪与重放。

## 目录结构

| 路径 | 作用 | 是否含真实值 |
|---|---|---|
| `BASE_TAG` / `BASE_SHA` | 上游基线双文件：锁定的上游 tag 与对应 commit SHA，二者同步更新。 | 否 |
| `brand.json` | 品牌配置：产品名、命令名、渠道展示名、默认模型等**非密钥**定制值。 | 否 |
| `opencode.template.json` | 内置渠道模板：opencode.json 格式，`provider.newapi` 走 `@ai-sdk/openai-compatible`（命中 `/v1/chat/completions`），含 opencode 原生 `{env:NEWAPI_BASE_URL}` / `{env:NEWAPI_API_KEY}` / `{env:NEWAPI_MODEL}` 占位，运行时替换。 | 否（仅占位符） |
| `channel.env.example` | 渠道环境变量**示例**：列出所需变量名与假值，复制为 `channel.env` 后填真实值本地使用。 | 否（仅示例值） |
| `icons/` | 品牌图标资源。 | 否 |

## 真实值从哪来

渠道真实值（API 地址、token）**绝不进 git**：

- **本地打包**：复制 `channel.env.example` → `channel.env`，填入真实值。`channel.env` 已被根 `.gitignore` 忽略。
- **CI 打包**：由 GitHub Actions Secret 以同名环境变量注入，同样不落 git、不进日志。

渠道模板 `opencode.template.json` 直接使用 opencode **原生** `{env:NEWAPI_BASE_URL}` /
`{env:NEWAPI_API_KEY}` / `{env:NEWAPI_MODEL}` 占位：opencode 运行时在加载配置时会把
`{env:VAR}` 就地替换成对应环境变量的值（见上游 `packages/opencode/src/config/variable.ts`），
**无需额外渲染脚本**。CI 打包时把这三个变量以 Secret 注入即可，模板本身不含任何真实值。

## 本机验证

模板可直接作为 opencode 配置使用，注入环境变量后启动即连上内置渠道：

```sh
# 1. 复制示例并填入真实值（channel.env 已被 .gitignore 忽略）
cp brand/channel.env.example brand/channel.env

# 2. 把 channel.env 里的变量导出到当前 shell
set -a && . brand/channel.env && set +a

# 3. 用 OPENCODE_CONFIG 指向模板启动；运行时会原生替换 {env:VAR}
OPENCODE_CONFIG="$PWD/brand/opencode.template.json" opencode
```

启动后 `/models` 应能看到内置渠道与默认模型，无需任何手动配置。

## 安全约束

- 本目录**不含任何真实密钥或个人 baseURL**——只有占位符与假值示例。
- 换渠道 / 换 key：只改 `channel.env`（本地）或 CI Secret（线上），模板与源码都不动。
