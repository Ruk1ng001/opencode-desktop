# 定制替换点清单

> 本文件供维护者使用：把本项目从占位品牌（产品名 `cx`、appId `ai.cx.desktop`、
> 内置示例渠道）替换成正式产品所需改动的**全部**替换点，逐项标明「改哪里、怎么改」。
>
> 核心原则：上游源码 `opencode/` 是 git **submodule**，锁定在稳定 tag，永远保持官方
> 原样、只 fetch 不手改。所有定制都在 `brand/` 叠加层里：品牌 / 打包配置走覆盖文件，
> 渠道值走纯配置注入（连补丁都不需要），必须改源码的少数改动才走
> [补丁工作流](#补丁工作流)。

---

## 目录：六个替换点

| # | 替换点 | 载体 | 改动方式 |
|---|--------|------|----------|
| 1 | [品牌名 / productName](#1-品牌名--productname) | `brand/brand.json` | 改一个 JSON 字段 |
| 2 | [appId](#2-appid) | `brand/brand.json` | 改一个 JSON 字段 |
| 3 | [图标](#3-图标) | `brand/icons/` | 替换同名图标文件 |
| 4 | [渠道变量（base_url / key / model）](#4-渠道变量base_url--key--model) | 环境变量 / CI Secret（无补丁） | 改 `channel.env` 或 Secret，不改源码 |
| 5 | [余额接口](#5-余额接口) | 补丁 `01` + `02` | 改余额面板组件 / 注入变量 |
| 6 | [充值 URL](#6-充值-url) | 环境变量 `NEWAPI_TOPUP_URL`（无补丁） | 改 `channel.env` 或 Secret |

所有品牌值集中在单一数据源 `brand/brand.json`，打包覆盖文件
`brand/electron-builder.brand.ts` 从中读取。

---

## 1. 品牌名 / productName

产品显示名当前为占位短名 `cx`（上游为 `OpenCode`）。

**改动点：`brand/brand.json` 的 `productName` 字段。**

```json
{ "productName": "cx" }
```

`brand/electron-builder.brand.ts` import 上游已解析的 `electron-builder.config.ts` 后，
用**前缀替换**把上游 `OpenCode` / `OpenCode Dev` / `OpenCode Beta` 平移到 `productName`
并保留 dev/beta/prod 通道后缀。改这一个字段即可，无需碰源码。

`brand.json` 里另有 `binName`（命令名）、`channelName`（渠道展示名）、`defaultModel`
（默认模型）等非密钥定制值，按需一并调整。

---

## 2. appId

应用标识符当前为占位值 `ai.cx.desktop`（上游为 `ai.opencode.desktop`）。

**改动点：`brand/brand.json` 的 `appId` 字段。**

```json
{ "appId": "ai.cx.desktop" }
```

覆盖文件对 appId 同样走**前缀替换**（`ai.opencode.desktop` → `brand.appId`），并由新
appId 派生 Linux 桌面身份（`extraMetadata.desktopName` / `linux.executableName` /
`StartupWMClass`），保证窗口类与启动器一致。改这一个字段即可。

---

## 3. 图标

**改动点：替换 `brand/icons/` 下的同名文件。**

| 文件 | 用途 |
|------|------|
| `brand/icons/icon.icns` | macOS 图标 |
| `brand/icons/icon.ico` | Windows 图标（`win.icon` / NSIS 安装器图标） |
| `brand/icons/icon.png` | Linux 图标（放目录，electron-builder 自行挑尺寸） |

当前为占位图标（1024×1024）。替换为正式品牌图标后**不用改任何配置**——覆盖文件用
`import.meta.url` 计算图标绝对路径，指向 `brand/icons/` 下固定文件名。

---

## 4. 渠道变量（base_url / key / model）

**改动方式：改环境变量 / `brand/channel.env`（本地）或 CI Secret（线上），不改源码。**

渠道模板 `brand/opencode.template.json` 用 opencode 原生 `{env:VAR}` 占位，运行时替换：

| 占位 | 变量 |
|------|------|
| `{env:NEWAPI_BASE_URL}` | 渠道 API 地址（OpenAI 兼容端点） |
| `{env:NEWAPI_API_KEY}` | 渠道 bearer token / API key |
| `{env:NEWAPI_MODEL}` | 默认模型名 |

换渠道 / 换 key 只改这些变量的值，模板与源码都不动。变量来源见
[README 的「如何配置 new-api 渠道」](README.md#如何配置-new-api-渠道)。

> 桌面余额面板另需在**构建期**把 `NEWAPI_BASE_URL` / `NEWAPI_API_KEY` 注入 renderer
> （浏览器上下文读不到 `process.env`），这由补丁 `02` 的 `renderer.define` 完成，见下。

---

## 5. 余额接口

桌面端右下角的独立余额 / 用量面板向 new-api 拉取真实数据。**改动点在两个补丁：**

- **补丁 `01-balance-panel`**（`brand/patches/01-balance-panel.patch`）：
  - 新增 `packages/desktop/src/renderer/balance/balance-panel.tsx` —— 自包含面板组件
    （仅依赖 solid-js），打开时 `GET {站点根}/api/user/self`，解析 `data.quota` /
    `data.used_quota` 做单位换算，含加载中 / 未配置凭据 / 请求失败 / 就绪四态；
  - 改 `packages/desktop/src/renderer/index.tsx` —— 在渲染入口挂载独立悬浮入口，
    位于聊天 UI 树之外。
- **补丁 `02-balance-newapi`**（`brand/patches/02-balance-newapi.patch`）：
  - 改 `packages/desktop/electron.vite.config.ts` —— `renderer.define` 把
    `NEWAPI_BASE_URL` / `NEWAPI_API_KEY` / `NEWAPI_TOPUP_URL` 注入 `import.meta.env`；
  - 改 `packages/desktop/src/renderer/env.d.ts` —— 补 `ImportMetaEnv` 类型声明。

要改余额接口路径 / 单位换算 / 展示，改补丁 `01` 覆盖的 `balance-panel.tsx`；要改注入的
变量集合，改补丁 `02`（并同步 `brand/channel.env.example` 与 `env.d.ts` 声明）。修改后
按[补丁工作流](#补丁工作流)重新导出补丁。

> new-api 用户接口挂**站点根 `/api`** 下（不是 `/v1` 渠道端点），从渠道 `baseURL` 去掉
> 尾部 `/v1` 推导站点根。鉴权方式（session vs access token + `New-Api-User` 头）随站点
> 配置而异，面板对失败态做了中文降级提示，不崩溃、不阻塞主程序。

---

## 6. 充值 URL

余额面板「充值」按钮点击后经 `window.api.openLink(url)`（→ 主进程 `shell.openExternal`）
在系统默认浏览器打开充值页面。**改动方式：改环境变量 `NEWAPI_TOPUP_URL`，无需补丁。**

- 优先读注入的 `NEWAPI_TOPUP_URL`；
- 缺省时回退到由 `NEWAPI_BASE_URL` 推导的 new-api 站点根；
- 两者都缺失时按钮禁用并提示「未配置充值地址」。

改充值地址只改 `brand/channel.env`（本地）或 CI Secret（线上）。客户端内不实现任何
支付逻辑。

---

## 补丁工作流

`opencode/` 以 git submodule 锁定在上游 tag，gitlink 必须保持干净才能干净跟随上游
release。凡是必须改动 submodule 内源码的定制，都导出为 `brand/patches/NN-<name>.patch`
（相对 `opencode/` 的 diff），由 CI / 本机在 checkout 后重放。

`brand/patches.manifest` 登记每个补丁覆盖的文件。当前补丁：

| 补丁 | 覆盖文件 |
|------|----------|
| `01-balance-panel` | `renderer/balance/balance-panel.tsx`（新增）、`renderer/index.tsx` |
| `02-balance-newapi` | `electron.vite.config.ts`、`renderer/env.d.ts` |

### 应用补丁（在干净基线上）

CI 的 package job 会在编译前自动重放：

```sh
for p in brand/patches/*.patch; do
  git -C opencode apply "../$p"
done
```

本机手动应用同理（按 `NN-` 前缀顺序）：

```sh
git -C opencode apply brand/patches/01-balance-panel.patch
git -C opencode apply brand/patches/02-balance-newapi.patch
```

### 导出补丁（改了 `opencode/` 内源码后）

```sh
# 新增文件先 intent-to-add，否则 git diff 不含 untracked 文件
git -C opencode add -N packages/desktop/src/renderer/balance/balance-panel.tsx

# 导出为补丁
git -C opencode diff -- <文件...> > brand/patches/NN-<name>.patch
```

导出后**务必把 submodule 工作区 reset / clean 回 tag**，只提交父仓库里的补丁与 manifest：

```sh
git -C opencode reset --hard "$(tr -d '[:space:]' < brand/BASE_SHA)"
git -C opencode clean -fd
```

### 升级时的补丁冲突

`scripts/update.sh` 切到新 tag 后，若上游改动了补丁覆盖的文件，重放可能冲突。此时：

1. 在新基线上手动 `git -C opencode apply --3way brand/patches/NN.patch` 定位冲突；
2. 手工改好 `opencode/` 内文件；
3. 按上面「导出补丁」重新生成 `.patch`；
4. reset / clean submodule 回 tag，提交更新后的补丁。

> 上游文件的每处改动建议加 `[cx] US-XXX` 注释，便于升级时快速定位并合并。

---

## 打包命令

绕过上游写死 `--config` 的 npm script，直接调 electron-builder 指定品牌覆盖配置：

```sh
cd opencode/packages/desktop
OPENCODE_CHANNEL=prod bun run electron-builder \
  --config ../../../brand/electron-builder.brand.ts
```

无签名凭据时设 `CX_UNSIGNED=1` 出未签名包（关公证 / 移除签名回调）。真实签名待有
证书时去掉该 env 即可。CI 已把这些编排在 `.github/workflows/release.yml` 里。

---

## 发布托管（Cloudflare R2）

默认产物只发 GitHub Release。可额外把产物 + 自更新元数据双写到 Cloudflare R2（出站免费
+ CDN，国内下载快），作主分发源；GitHub Release 保留作存档。

### 涉及的改动点（都已就位）

| 位置 | 作用 |
|------|------|
| `brand/brand.json` 的 `updateBaseUrl` | R2 自定义域 + `/latest` 路径。当前是占位 `https://dl.example.com/latest`，改成真实域即启用 |
| `brand/electron-builder.brand.ts` | `publish` 为 `[generic, github]` 双源数组：`updateBaseUrl` 是有效真实域（非空、非 `example.com`）时把 generic 作主源写进 `app-update.yml`，否则回退纯 github |
| `.github/workflows/release.yml` 的 release job | finalize `latest*.yml` 后新增 R2 上传步：把安装包 + 合并后的 yml 推到 R2 `latest/`。以 `if: env.R2_ACCESS_KEY_ID != ''` 守卫，未配 Secret 时跳过 |
| `brand/download-page/` | Cloudflare Pages 下载落地页（静态，读 R2 的 yml 渲染各平台最新版下载按钮），见其 README |

### 自更新原理

`electron-updater` generic provider 从固定 URL（`updateBaseUrl`）读 `latest*.yml`，按
`version` 字段比对——不经过 GitHub 的 Latest/prerelease 判定，所以 `-cx.N` 版本能被正常
选中（补丁 `08` 的 prerelease hack 对 generic 是冗余但无害，保留以便回退纯 github 源时仍有效）。
`latest*.yml` 里的 `url` 是相对文件名，客户端用「`updateBaseUrl` + 文件名」拼下载地址，故
安装包与 yml 必须放 R2 同一 `latest/` 目录。

### 启用步骤（Cloudflare 侧手动，本仓库无法代做）

1. **建 R2 桶**（如 `dokng-releases`），在桶设置里开启自定义域，绑 `dl.你的域名`。
2. **建 R2 API Token**（Object Read & Write 权限），记下 Account ID / Access Key ID /
   Secret Access Key。
3. **配 GitHub Secret**（仓库 Settings → Secrets and variables → Actions）：
   - `R2_ACCOUNT_ID`：R2 的 account id
   - `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`：上一步的 token 凭据
   - `R2_BUCKET`：桶名（如 `dokng-releases`）
4. **改 `brand/brand.json`** 的 `updateBaseUrl` 为 `https://dl.你的域名/latest`，提交。
5. **（下载页）** 建 Cloudflare Pages 项目连本仓库、构建目录设 `brand/download-page/`，
   绑下载页子域；若下载页与 `dl` 不同域，按 `brand/download-page/README.md` 给 R2 桶加
   CORS 规则允许下载页域 `GET`。

配好后 push 触发一次 release，即可在 R2 桶看到 `latest/` 下的产物，下载页能解析出最新版。
