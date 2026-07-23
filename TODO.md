# cx 待办清单

> 项目：基于 opencode 桌面端（Electron + SolidJS）的定制跟随版 cx。
> submodule 锁上游 tag，所有定制走 `brand/patches/*.patch`，不改上游源码。
> 本文档只记**尚未完成**的事；已完成的工作见 git 提交历史与 `brand/patches/`。

---

## 已完成（git 历史为准，仅作背景，不再列为待办）

- 多 key 本地存储 + 增删改 + 手动切换（补丁 04/05）
- 每个 key = 一个独立 opencode provider；切换已注册 key 零重启、零打断（走 `cx:select-provider` 事件桥 → `useLocal().model.set`）
- 加/删 key 热重载生效：主进程重写 `OPENCODE_CONFIG` 文件 + `POST /global/dispose`，内核重建 instance，不重启进程（补丁 03/05）
- 内置默认 baseURL、构建期渠道注入（补丁 02/03）
- 首启无 key 引导、`dokng://` 深链一键导入（补丁 06 + 09）
- **账户面板迁入 app 包、改用原生 v2 设计系统（补丁 09）**：面板从 desktop 包迁入
  `packages/app/src/components/cx-account/`（`Cx` 前缀独立目录），外壳用原生
  `@opencode-ai/ui/v2/dialog-v2` + `useDialog()`，配色全走 v2 语义变量（`--v2-*`）、
  跟随明暗主题、与原生设置页视觉统一（不再自绘浮层 / 不再硬编码颜色）。账户按钮
  （补丁 07 layout.tsx）点击 `dialog.show(() => <CxDialogAccount/>)`；首启无 key 时
  （补丁 07 FR-3.6）自动弹出面板并展开 `AddKeyForm`（仅 desktop、仅一次）；`dokng://`
  导入深链复用 opencode 既有 deep-link 分发，在 layout.tsx 的 `handleDeepLinks` 内解析后
  弹 `CxDialogImport` 确认框（自闭合，走 `useDialog().close()`）。`AddKeyForm` 隐藏可选
  baseURL 输入（FR-3.5），新增 key 的 `baseURL` 固定空串、走构建期内置 `NEWAPI_BASE_URL`
  回退。跨包类型缺口（`window.api.channelKeys*` / `import.meta.env.NEWAPI_*`）在 cx 目录内
  用局部声明 + 断言访问器解决，不碰上游类型文件。旧 desktop 面板 `balance-panel.tsx`
  与 `renderer/index.tsx` 挂载已删除（原补丁 01 作废）。双包 typecheck 通过、补丁可干净重放。
- cx 自动更新指向本仓库发布（补丁 08 + release.yml + brand 配置）
- macOS 分架构原生打包（修 pty.node 崩溃）
- **默认语言改中文（补丁 10 + `brand.json` `defaultLocale`）**：desktop renderer 入口
  `loadLocale` 在本地无语言存储时加载并返回品牌配置的默认 locale（缺省 `"zh"`），
  经 `electron.vite.config.ts` 构建期注入 `import.meta.env.DEFAULT_LOCALE`；已存储语言时
  行为不变，用户选择不被覆盖（US-001 / US-002 / US-003）。
- **new-api `GET /api/app/profile` 后端端点（new-api 仓库，非 opencode 补丁层）**：走 token
  鉴权中间件由 `sk-` 定位本人 profile，`user_id` 只从 token 记录派生、不读任何入参；返回
  `username`/`avatar`/`quota`（=`user.quota + user.used_quota`）/`used_quota`/`token_remain`/
  `token_used`/`token_used_today`/`unlimited`，可选 `used_today`（聚合失败时省略，App 端显示「—」）。
  客户端 `cx-account` 面板已联调闭合链路（US-004 / US-005 / US-006 / US-007）。
- **`/v1/models` 已按 token `model_limits` 过滤**：经查 new-api 源码确认 `GET /v1/models` 按
  key 返回该 key 可用模型（`TokenAuth` 注入 model_limits → `ListModels` 过滤），App 端切换 key
  直接用 `/v1/models`，无需新增 `/api/app/models`（US-008）。
- **账户面板 UI 审查（US-012.5，无头可查项已完成）**：修复三处实缺陷——① CSS 选择器与
  TSX 的 `data-slot` 全面对齐（此前 CSS 全用类选择器、TSX 用 data-slot，几乎全部规则失配，
  面板近乎无样式）；② `AddKeyForm` 隐藏 baseURL 输入（FR-3.5）；③ 补齐首启无 key 自动弹出
  （FR-3.6）。并核对：`aria-label` 全覆盖、状态分支（加载/错误/就绪/切换/空态）齐全、
  可视文案无英文残留、15 个 `--v2-*` 变量与 `progress-circle-v2` / `dialog-body` 的
  data-slot 均在上游 v2 定义中实在。**实机目视项待跑**（见待办第 2 节）。

---

## 待办

### 1. 自动更新端到端验证（程序化预检已过；三平台实机待跑）

自更新链路（补丁 08 + publish 源 + latest*.yml 合并）代码已就位，全链路程序化预检全绿：

- ✅ 更新源指向本仓库：`brand/electron-builder.brand.ts` 的 `publish` 覆盖上游 `anomalyco/opencode` → `Ruk1ng001/opencode-desktop`（打进产物 `app-update.yml`）；全仓无残留官方更新源引用 → 不弹官方 opencode 更新。
- ✅ feed 解析：`updater.ts` `allowPrerelease=true` 走 releases.atom 按 `dokng` 分量匹配 `-dokng.N`；线上 atom feed 实测可解出最新 dokng tag，旧→新数值递增可检出。
- ✅ 自更新载体：完整三平台 release 的 mac=zip / win=exe / linux=AppImage 全部可达，`latest*.yml`（sha512/size）完整。
- ⚠️ **发布态注意**：早期 cx.8/cx.9 是「临时只打 Windows+mac-x64」时期产物，缺 linux / mac-arm64。实机验证必须用恢复四平台矩阵后**连发的两个完整三平台版本**。

**仍未完成（不可在无头 CI/服务器环境替代）**：三平台真机实测（装旧版 → 发新版 → 肉眼确认检测/下载/安装/启动新版本；mac 走 zip、win 走 exe、linux 走 AppImage）。三平台全部通过前不推正式发布。

### 2. 账户面板实机目视审查（US-012.5 剩余项）

无头环境可机检的项已在「已完成」段完成。剩余需真机 `npm run dev` 目视确认：

- **本次全面重构了 CSS**（类选择器 → data-slot），务必目视确认面板两栏布局、环形图、
  key 卡片列表在真机正确渲染、无错位。
- 对比度、窄窗口/最小窗口下文案换行与不溢出、滚动正常。
- 首启自动弹出（FR-3.6）、隐藏 baseURL 后表单无残留空隙（FR-3.5）在真机的实际观感。
- 各交互状态（加载 / 空态 / 错误 404·401·500 / `unlimited` / `used_today` 缺失显「—」）在真实或模拟数据下的渲染。

### 3. 推送发布（前置门槛未全过，暂不推送正式版）

推送前置门槛：双包 typecheck ✅（desktop/app 各 rc=0）/ 补丁 0 冲突重放 ✅ / CI 4 平台矩阵 ✅ / 敏感值不入库 ✅ 均已通过。未过两项：**账户面板实机目视审查（待办第 2 节）**、**自动更新三平台实机验证（待办第 1 节）**——两者都需真机、无头服务器无法替代完成。两项门槛过关后方可走特性分支推送 + CI 自动合并发布正式版流程。

---

## 集成第二上游：infinite-canvas 画布（新工作，尚未动工）

> 目标：把 `basketikun/infinite-canvas`（纯前端 Vite + React 19 SPA）作为**第二个上游**引进，
> 内嵌进 cx 桌面客户端，让用户在客户端里用**已管理好的渠道 key** 直接作图 / 作图对话，
> 并能在 opencode 原界面和画布之间来回切换。
>
> 已完成可行性调研（本节所有结论均基于对两仓库源码的实读，非推测）：
> - **infinite-canvas 是纯客户端 SPA**：`vite build` 出纯静态 `dist/`，运行时无自带后端，
>   数据全在浏览器 IndexedDB/localStorage，AI 请求由前端直连用户配置的 OpenAI 兼容接口。
>   canvas-agent、Codex 插件都是可选外挂，本集成一律忽略。
> - **两边框架异构**：宿主是 SolidJS + `@solidjs/router`，画布是 React 19 + `react-router@7`，
>   **不能当组件嵌，只能 `<iframe>` 隔离**。opencode 桌面壳的 `oc://renderer/` 特权协议
>   已白名单整个 `out/renderer` 子树，把画布产物拷进 `renderer/canvas/` 子目录即可
>   `<iframe src="oc://renderer/canvas/index.html">` 加载，**主进程 / preload / 协议零改**。
> - **key 投递两端各有现成接口**：宿主侧 `cx-account-api.ts` 的 `resolveKeyList()` 已把每个 key
>   规整成 `{id,label,key,baseURL,isActive,builtin,models[]}`（`models[]` 来自主进程缓存的该 key
>   `/v1/models` 结果，**非** `keyModelLimits`——后者是另一 profile 字段，只用于卡片显示模型数）；
>   画布侧 `web/src/components/layout/client-root-init.tsx` 本就有一条「外部注入 → 写
>   `config.channels[0]` → 落地」的链路（现走 `?baseUrl=&apiKey=` query，且只写单个 `channels[0]`）。
>   除画布路由 basename 需一行修正（见待办 5——`createBrowserRouter` 未设 basename，iframe 以
>   `/canvas/index.html` 加载会落到 NotFound），两端内核逻辑不用改，只需把宿主选中的 key 通过
>   **同源 `postMessage`** 投给画布，画布 `resolveModelRequestConfig` 会按 `channelId::modelName` 自动用上。

### 需求定稿（每个 key 两个按钮，双槽位，互不干扰）

账户弹窗里**每个 key 卡片**加两个按钮：**① 启动作图**、**② 启动作图对话**。宿主维护两个独立槽位：

- **作图槽** `imageKeyId` ← 哪个 key 点了「启动作图」
- **对话槽** `chatKeyId` ← 哪个 key 点了「启动作图对话」

用户可自由组合，互不干扰：分开选两个 key（A 作图、B 对话）、只用一个 key 两个按钮都点、只点一个只作图不聊都合法。投递给画布时：每个被选中的 key → 一个画布 `ModelChannel`（`baseURL`+`apiKey`+该 key 的 `models[]`），作图槽的 key 供 `image`/`video` 类模型、对话槽的 key 供 `text` 类模型；两槽同一个 key 时就是一个 channel 供两类，不同 key 时就是两个 channel。

### 待办 4：opencode 侧集成（新增 1 个补丁 `17-canvas-embed.patch`，主进程/协议零改）

全部落在 `brand/patches/`，编号接现有 16 之后。改动集中在 app 包：

- **新增** `packages/app/src/pages/canvas-embed.tsx`：画布路由页，含 `<iframe src="oc://renderer/canvas/index.html">` + 向 iframe `postMessage` 投递选中 key 的逻辑（监听槽位变化即重推；`targetOrigin` 限 `oc://renderer`）。
- **新增** `packages/app/src/components/cx-account/cx-canvas-slots.ts`：两槽位状态（`imageKeyId`/`chatKeyId`）+ 由槽位合成投递 payload 的纯函数（复用 `resolveKeyList`）。合成 `ModelChannel.models[]` 时**显式给每个 model 标 `capability`**——画布 `ModelCapability` 实为**四类** `"image"|"video"|"text"|"audio"`（不止三类）；作图槽 key 的模型标 `image`/`video`（含 `audio` 若有 tts/语音模型），对话槽标 `text`。显式标类型比让画布 `guessCapability(name)` 按关键字猜更稳（new-api 自定义模型名易猜错）。
- **改** `packages/app/src/app.tsx` 的 `Routes()`：加 `<Route path="/canvas" component={CanvasEmbed}/>`（+1 行）。
- **改** `cx-account-dialog.tsx`（09 补丁基础上）：每个 key 卡片加「① 启动作图 / ② 启动作图对话」两个按钮，点击写对应槽位（含高亮当前已选 / 取消选择）。
- **改** `layout-new.tsx` + `cx-account-launcher.tsx`：顶栏 `#opencode-titlebar-right` portal 加一个「画布」入口按钮（与账户按钮同排），点击 `navigate("/canvas")`；同理可选加菜单项。

**构建侧新增一步（新增脚本，非改上游）**：用 `VITE_BASE=/canvas/` 构建 infinite-canvas，把 `dist/` 拷进 desktop 的 renderer 产物子目录。因 `oc://` 已白名单 `out/renderer` 全子树，协议层不动。**产出路径要点（核实纠偏）**：协议根是 `out/renderer`（`windows.ts:18` `join(root,"../renderer")`）。electron-vite 的 renderer `publicDir` 指向 `../../app/public`（非 `src/renderer`）、入口只有 `index.html`，故把 canvas dist 丢进 `src/renderer/canvas/` **不保证**被 vite 纳入 `out/renderer`。最可靠：**仿现成的 `opencode:copy-server-assets` writeBundle 钩子（`electron.vite.config.ts:107-115`）直接把 canvas dist 拷进 `out/renderer/canvas/`**。`prebuild.ts` 虽存在，但当前只做 icons/metainfo/build-node（不碰 renderer 资源），若走 prebuild 需自行确保产物最终落到 `out/renderer/canvas/`。此外 infinite-canvas 的 `vite.config.ts` 会 `readFileSync` 读 `infinite-canvas/VERSION` 与 `CHANGELOG.md`（**无 try/catch**，缺文件直接 build 失败），拷贝/构建时两文件必须在位。

### 待办 5：infinite-canvas 侧集成（新建独立补丁层，仅 1 处小改）

infinite-canvas 作为 submodule，源码零手改，定制走它自己的补丁层（见待办 6）。画布补丁层共 **3 处改动**：

- **改** `web/src/router.tsx`（**必改，用 HashRouter**）：`createBrowserRouter([...])` 换成 `createHashRouter([...])`。**真机实测教训**：先前试过 `createBrowserRouter(routes, { basename: import.meta.env.BASE_URL })`（basename=`/canvas`），但 iframe 以 `oc://renderer/canvas/index.html` 静态加载时 `pathname=/canvas/index.html` 固定不可控，basename 剥掉 `/canvas` 后剩 `/index.html`，仍匹配不到任何路由 → 落 `path:"*"` NotFound（**真机实测 404**）。HashRouter 只认 `location.hash`：无 hash 时默认 `#/` 命中首页，导航写 `#/image` 等，**彻底绕开 pathname/basename**。构建仍用 `VITE_BASE=/canvas/`（asset/script 前缀需要），但路由不再依赖它。standalone web 部署同样适用（hash 路由在任意子路径都工作），对用户无感。
- **改** `web/src/components/layout/client-root-init.tsx`：把现有 query 参数注入段抽成共用内部函数（`event.origin` 白名单校验限 `oc://renderer`），新增 `window` `message` 监听（约 15–25 行）；收到宿主投来的 **key 数组**后，逐个 `createModelChannel({id,name,baseUrl,apiKey,models})` 合成，用 `updateConfig("channels", 数组)` 写入（现有链路只写单个 `channels[0]`，此处扩展为数组）。若要联动顶层 `imageModel`/`videoModel`/`textModel`/`audioModel`，用 `encodeChannelModel` 设成对应 `channelId::modelName`。
- **改** `web/src/stores/use-config-store.ts` 的 `persist.partialize`（**决策已定：apiKey 不落盘**）：现状 `partialize` 只排除 UI 瞬态字段，**完整保留 `config`**——所有 channel 的 `apiKey`、顶层 `apiKey`、`webdav.password` 全写进 iframe 的 localStorage。改为 `partialize` 里 map `channels` 时置空 `apiKey`（及顶层 `apiKey`），使**注入的 key 只驻留内存**；每次打开画布页由宿主重新 postMessage 投递（见待办 4，`canvas-embed.tsx` 在 iframe `load` / 路由进入时即推一次）。

> **apiKey 落盘决策（已拍板）**：不落盘，内存注入。iframe 内不留任何明文 key 副本，每次进作图页重新取。代价是画布 `partialize` 多改几行；换来 key 完全受主进程管控、无第二份明文。

### 待办 6：infinite-canvas 跟随上游更新机制（对齐现有 opencode 那套）

- **`.gitmodules`** 加第二个 submodule 条目（path=`infinite-canvas`，url=`https://github.com/basketikun/infinite-canvas.git`）。注意：当前 `infinite-canvas/` 是内嵌独立 git 仓库、且 `.gitignore` 未忽略它，需先决定「转为正式 submodule」还是沿用独立仓库模式。
- **`scripts/update-canvas.sh`**：复制 `scripts/update.sh`，只换上游 URL、BASE 文件（如 `brand/CANVAS_BASE_TAG` / `CANVAS_BASE_SHA`）、验证命令（`typecheck` → `cd web && bun install && bun run build`）。tag 筛选正则 `^v[0-9]+\.[0-9]+\.[0-9]+$` 不变——天然排除上游历史里的脏 tag `v.0.1.0`（多一个点）。
- **`scripts/apply-canvas-patches.sh`**：复制 `scripts/apply-patches.sh`，指向画布补丁层目录。
- **画布升级 CI**（原计划独立 `auto-upgrade-canvas.yml`，**现已合并进 `.github/workflows/release.yml` 的 `upgrade-canvas` job**——三条链路收敛为单文件，见该文件头说明）：cron 与 opencode 那条错开，验证步骤换成画布 build。**注意**：`web/vite.config.ts` 构建期 `readFileSync` 读的是 **`infinite-canvas/VERSION` 与 `infinite-canvas/CHANGELOG.md`**（`web/../`，即画布仓库根，**不是 open-code 仓库根**），注入到 `__AP_VERSION__`/`__APP_RELEASES__`；且**无 try/catch**，缺任一文件 build 直接失败。内嵌打包（待办 4 的构建步骤）与 CI 都必须保证这两个文件随 `infinite-canvas/` 在位。
- **注意**：infinite-canvas 自带 `.github/workflows/*`（docker / pages / publish 等），作为 submodule 时父仓库 CI 不会执行它们，但要确认不污染父仓库工作区与发布流程。

---

## 上游基线

> 仓库：`https://github.com/anomalyco/opencode.git`（submodule `opencode/`）
> 基线 tag / SHA：见 `brand/BASE_TAG` / `brand/BASE_SHA`
> 哲学：submodule 锁上游 + brand 薄叠加层 + 补丁不改源码
