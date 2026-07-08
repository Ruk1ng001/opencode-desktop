# brand/ — 品牌叠加层

本目录承载所有对 opencode 的定制内容，与上游源码（`opencode/` submodule）**物理隔离**。
上游更新只需同步 submodule，本目录不受影响；本目录的改动也不会污染上游源码，便于跟踪与重放。

## 目录结构

| 路径 | 作用 | 是否含真实值 |
|---|---|---|
| `BASE_TAG` / `BASE_SHA` | 上游基线双文件：锁定的上游 tag 与对应 commit SHA，二者同步更新。 | 否 |
| `brand.json` | 品牌配置：产品名、命令名、渠道展示名、默认模型等**非密钥**定制值。 | 否 |
| `opencode.template.json` | 渠道配置模板：opencode.json 格式，含 `__BASE_URL__` / `__API_KEY__` / `__MODEL__` 占位符，打包期由渲染脚本注入真实值。 | 否（仅占位符） |
| `channel.env.example` | 渠道环境变量**示例**：列出所需变量名与假值，复制为 `channel.env` 后填真实值本地使用。 | 否（仅示例值） |
| `icons/` | 品牌图标资源。 | 否 |

## 真实值从哪来

渠道真实值（API 地址、token）**绝不进 git**：

- **本地打包**：复制 `channel.env.example` → `channel.env`，填入真实值。`channel.env` 已被根 `.gitignore` 忽略。
- **CI 打包**：由 GitHub Actions Secret 以同名环境变量注入，同样不落 git、不进日志。

渲染脚本（后续 story）读取优先级：进程环境变量（CI Secret）> 本地 `channel.env`，
把 `opencode.template.json` 里的 `__BASE_URL__` / `__API_KEY__` / `__MODEL__` 占位符替换成真实值，生成本地 `opencode.json`（也被忽略）。

## 安全约束

- 本目录**不含任何真实密钥或个人 baseURL**——只有占位符与假值示例。
- 换渠道 / 换 key：只改 `channel.env`（本地）或 CI Secret（线上），模板与源码都不动。
