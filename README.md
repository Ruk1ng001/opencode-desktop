# cx

`cx` 是基于 [`anomalyco/opencode`](https://github.com/anomalyco/opencode) 的定制跟随版**桌面客户端**：
开源 AI 编码助手，中文界面，内置渠道开箱即用，附带独立的余额 / 充值面板。
跟随 opencode 官方最新稳定 release 自动编译、打包、发布。

产物是真正的桌面应用：macOS `.dmg`、Windows `.exe`、Linux `.AppImage`。

> 上游源码以 git submodule 形式引入（`opencode/`，锁定在稳定 tag），本仓库只在
> `brand/` 叠加层里叠加品牌 / 渠道 / 补丁与打包配置，**不手改上游源码**。
> 维护者定制说明见 [CUSTOMIZATION.md](CUSTOMIZATION.md)。

---

## 安装

**推荐方式：从 [GitHub Releases](../../releases) 下载对应平台的安装包，双击安装。**
装好后打开 `cx`，内置渠道已经配置好，直接开始对话即可，无需任何手动配置。

| 平台 | 安装包 | 说明 |
|------|--------|------|
| macOS | `cx-<版本>.dmg`（Apple Silicon / Intel） | 双击挂载，把 `cx` 拖入「应用程序」 |
| Windows | `cx-Setup-<版本>.exe`（NSIS 安装器） | 双击按向导安装（per-user，无需管理员） |
| Linux | `cx-<版本>.AppImage` | `chmod +x` 后直接运行，无需安装 |

其中 `<版本>` 形如 `1.17.15-cx.1`：`1.17.15` 是跟随的 opencode 上游版本，`cx.N` 是
本项目的定制发布序号（见[跟随升级](#跟随升级)）。

### macOS

1. 下载 `cx-<版本>.dmg`，双击挂载。
2. 把 `cx` 图标拖入「应用程序」文件夹。
3. 打开「启动台」或「应用程序」，运行 `cx`。

如果安装包未签名（无 Apple 开发者证书时的降级产物），首次打开 macOS **Gatekeeper**
会提示「无法打开，因为它来自身份不明的开发者」。绕过方法（二选一）：

- **右键打开**（推荐）：在「应用程序」里右键点击（或 Control + 单击）`cx` → 选「打开」→
  弹窗里再点「打开」。此后可正常双击启动。
- **命令行去隔离属性**：
  ```sh
  xattr -dr com.apple.quarantine /Applications/cx.app
  ```

### Windows

1. 下载 `cx-Setup-<版本>.exe`，双击运行。
2. 按向导完成安装（per-user 安装，默认不需要管理员权限）。
3. 从开始菜单启动 `cx`。

如果安装包未签名，Windows **SmartScreen** 可能提示「已保护你的电脑」。点「更多信息」→
「仍要运行」即可。

### Linux

`.AppImage` 是自包含可执行文件，无需安装：

```sh
chmod +x cx-<版本>.AppImage
./cx-<版本>.AppImage
```

若系统缺少 FUSE，可用 `--appimage-extract-and-run` 参数运行，或安装 `libfuse2`。

---

## 使用

- **对话**：打开 `cx` 直接开始。内置渠道已随包配置好，无需登录官方后端、无需填 API Key。
- **切换模型**：在对话界面用 `/models` 查看并切换内置渠道下的可用模型。
- **账户工作台**：从主界面侧边栏打开「账户」，可查看账户余额、账户额度使用率、今日实际模型
  Token 用量（输入 + 输出，自动格式化为 K / M / B）以及今日 / 累计费用。API Key 条数与模型 Token
  用量严格分开；某个 Key 的“不限额”状态不会再覆盖账户余额或账户额度环。
- **API Keys 管理**：Keys 区域采用一行一个 Key 的紧凑列表，不再设置内部滚动层；名称、今日 Tokens、
  今日 / 累计费用、可用模型、额度状态和操作可在同一行查看。支持新增、改名、删除和切换激活 Key；未填写
  本地名称时使用 `/api/app/profile` 返回的 new-api `token.Name`。新增后立即显示本地结果，远端名称、模型和
  账户数据在后台同步；窄屏会自动折行为多行，避免内容或操作按钮溢出。
- **充值**：点账户工作台里的「充值」按钮，会在**系统默认浏览器**打开渠道充值页面。
  客户端本身不处理任何支付逻辑。

> 余额 / 充值面板依赖打包时注入的渠道凭据（见[如何配置 new-api 渠道](#如何配置-new-api-渠道)）。
> 官方发布的安装包已由 CI 注入好；若你自行打包但未注入凭据，面板会显示「未配置凭据」。

---

## 卸载

| 平台 | 卸载方式 |
|------|----------|
| macOS | 把「应用程序」里的 `cx` 拖到废纸篓。清残留配置：删除 `~/Library/Application Support/opencode/` 与 `~/.config/opencode/` |
| Windows | 「设置 → 应用 → 已安装的应用」找到 `cx` → 卸载（NSIS 自带卸载器）。清残留配置：删除 `%APPDATA%\opencode\` |
| Linux | 直接删除 `.AppImage` 文件即可。清残留配置：删除 `~/.config/opencode/` |

> 卸载只移除应用本体；如需彻底清理，按上表删除对应的配置 / 缓存目录。

---

## 如何配置 new-api 渠道

内置渠道走 opencode 的 `provider` 配置 + [new-api](https://github.com/QuantumNous/new-api)
兼容端点（OpenAI 兼容 `/v1/chat/completions`）。渠道**真实值绝不进 git**，只在打包期由
环境变量 / CI Secret 注入。

### 渠道配置的三个来源文件（都在 `brand/`）

| 文件 | 作用 |
|------|------|
| `brand/opencode.template.json` | 渠道模板：`provider.newapi` 走 `@ai-sdk/openai-compatible`，用 opencode 原生 `{env:VAR}` 占位，不含真实值 |
| `brand/channel.env.example` | 渠道环境变量**示例**：列出所需变量名与假值 |
| `brand/channel.env` | 你的真实值（复制 example 得到，已被 `.gitignore` 忽略，绝不提交） |

### 四个渠道变量

模板里的三个 `{env:VAR}` 占位 + 桌面余额面板用的充值地址：

| 变量 | 含义 |
|------|------|
| `NEWAPI_BASE_URL` | 渠道 API 地址（OpenAI 兼容端点，命中 `/v1/chat/completions`） |
| `NEWAPI_API_KEY` | 渠道 bearer token / API key |
| `NEWAPI_MODEL` | 默认模型名 |
| `NEWAPI_TOPUP_URL` | 余额面板「充值」按钮打开的充值页面地址（缺省回退到由 `NEWAPI_BASE_URL` 推导的站点根） |

### 本机验证（不打包，直接用模板启动）

opencode 运行时会在加载配置时把 `{env:VAR}` 原生替换成对应环境变量的值，无需渲染脚本：

```sh
# 1. 复制示例并填入真实值（channel.env 已被 .gitignore 忽略）
cp brand/channel.env.example brand/channel.env

# 2. 把变量导出到当前 shell
set -a && . brand/channel.env && set +a

# 3. 用 OPENCODE_CONFIG 指向模板启动
OPENCODE_CONFIG="$PWD/brand/opencode.template.json" opencode
```

启动后 `/models` 应能看到内置渠道与默认模型。

### 打包时如何注入

- **本地打包**：把 `brand/channel.env` 里的变量 `export` 到打包用的 shell（余额面板凭据
  在构建期由 `electron.vite` 的 `renderer.define` 内联进 renderer bundle）。
- **CI 打包**：在仓库 Settings → Secrets 里配置 `NEWAPI_BASE_URL` / `NEWAPI_API_KEY` /
  `NEWAPI_MODEL` / `NEWAPI_TOPUP_URL` 四个 Repository Secret，CI 以同名环境变量注入，
  并用 `::add-mask::` 屏蔽日志，绝不进 git、不进日志。

> **换渠道 / 换 key**：只改 `brand/channel.env`（本地）或 CI Secret（线上），
> 模板与上游源码都不动。

---

## 跟随升级

本项目跟随 opencode 上游稳定 release。升级 = 更新 submodule 到新 tag → 由 CI 打包发布。

### 1. 更新到上游最新稳定版

```sh
scripts/update.sh
```

`scripts/update.sh` 会：

- 查询上游最新稳定 `vX.Y.Z` tag（**排除 `vscode-v*`** 与预发布 `-rc/-beta/-alpha`）；
- 把 `opencode/` submodule 切到该 tag；
- 刷新基线双文件 `brand/BASE_TAG` / `brand/BASE_SHA`；
- 暂存父仓库的 submodule 指向（gitlink），但**不自动提交**。

无新版本时脚本幂等退出、不产生任何改动。也可指定目标 tag 便于回滚 / 复现：

```sh
scripts/update.sh v1.17.15
```

确认版本对比输出无误后提交：

```sh
git commit brand/BASE_TAG brand/BASE_SHA opencode -m "chore: 跟随 opencode <新版本>"
```

> `brand/patches/*.patch` 是相对 `opencode/` 的定制补丁，编译发布前需在新基线上重放
> （CI 的 package job 已在编译前自动重放，见下）。若上游改动导致补丁冲突，需按
> [CUSTOMIZATION.md](CUSTOMIZATION.md#补丁工作流) 更新补丁。

### 2. CI 发布

推送升级提交后，由 `.github/workflows/release.yml` 完成发布，三段 job 串联：

1. **detect**：读 `brand/BASE_TAG` + 已有 GitHub Release，算出下一个版本号
   `<opencode版本>-cx.N`；登记渠道 Secret 为日志掩码。
2. **package**（三平台矩阵）：checkout（含 submodule）→ 重放 `brand/patches/` →
   `bun install` → `bun run build` → `electron-builder --config brand/electron-builder.brand.ts`
   出包（`.dmg` = macOS runner，`.exe` = Windows runner，`.AppImage` = Linux runner）。
3. **release**：汇总三平台产物，创建 / 更新对应 tag 的 GitHub Release。

**触发方式**：

- 推送 tag `v*-cx.*`（如 `v1.17.15-cx.1`）即触发发布；
- 或在 Actions 页手动 `workflow_dispatch`（可强制指定版本 / 强制发布）。

发布前置：目标仓库已配置 4 个 `NEWAPI_*` Repository Secret（见上一节）。

---

## 许可证

上游 opencode 采用 MIT 许可证。本仓库的 `brand/` 叠加层同样以 MIT 分发。
