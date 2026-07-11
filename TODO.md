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
- 首启无 key 引导、`cx://` 深链一键导入（补丁 06 + 09）
- 账户面板两栏重设计（环形图 + 金色深色主题）
- **账户面板迁移到 app 包、复用原生 v2 Dialog（补丁 09）**：面板从 desktop 包迁入
  `packages/app/src/components/cx-account/`（`Cx` 前缀独立目录），外壳用原生
  `@opencode-ai/ui/v2/dialog-v2` + `useDialog()`；账户按钮（补丁 07 layout.tsx）点击
  `dialog.show(() => <CxDialogAccount/>)`；`cx://` 导入深链复用 opencode 既有 deep-link
  分发，在 layout.tsx 的 `handleDeepLinks` 内解析后经 `useCxImportDialog` 弹确认框。
  跨包类型缺口（`window.api.channelKeys*` / `import.meta.env.NEWAPI_*`）在 cx 目录内
  用局部声明 + 断言访问器解决，不碰上游类型文件。旧 desktop 面板 `balance-panel.tsx`
  与 `renderer/index.tsx` 挂载已删除（原补丁 01 作废）。双包 typecheck 通过、补丁可干净重放。
- cx 自动更新指向本仓库发布（补丁 08 + release.yml + brand 配置）
- macOS 分架构原生打包（修 pty.node 崩溃）

---

## 待办

### 1. 默认语言改中文（未完成）

App 默认 locale 设为中文（当前默认英文）。查 renderer 初始化 locale 逻辑（`packages/desktop/src/renderer/index.tsx` 的 `loadLocale` / `normalizeLocale`）。

### 2. new-api 后端接口（你负责，契约见 `brand/docs/api-app-profile.md`）

> 现状：客户端一半已完成——`cx-account` 面板已用 `sk-` API 令牌（`Authorization: Bearer sk-`）
> 调 `/api/app/profile`，无 access_token、无 `New-Api-User` 头，凭据来源正确。链路未闭合
> 处仅在后端：该端点尚未实现，客户端调用当前会拿到 404（面板显示「获取失败」，不崩溃）。

- [ ] 实现 `GET /api/app/profile`（走 token 鉴权中间件，由 `sk-` 定位本人 profile）。
- [ ] **`quota` 字段必须返回 `user.quota + user.used_quota`（剩余 + 已用 = 总额）**，不能直接返回原始 `user.quota`（那是剩余，前端环形图/使用率会算错）。
- [ ] 可选字段 `used_today`（账户级今日消耗，按 user_id 聚合当天日志）；未实现时省略，前端显示「—」。
- [ ] 确认 `/v1/models` 是否按 token `model_limits` 过滤返回该 key 可用模型；若不过滤，追加 `GET /api/app/models`（契约文档第 6 节）。

### 3. 自动更新端到端验证（未验证）

自更新链路（补丁 08 + publish 源 + latest*.yml 合并）代码已就位，但**从未实机验证**。需连发两个版本实测：装旧版 → 发新版 → 确认能检测、下载、安装。三平台分别验（mac 走 zip、win 走 exe、linux 走 AppImage）。

---

## 上游基线

> 仓库：`https://github.com/anomalyco/opencode.git`（submodule `opencode/`）
> 基线 tag / SHA：见 `brand/BASE_TAG` / `brand/BASE_SHA`
> 哲学：submodule 锁上游 + brand 薄叠加层 + 补丁不改源码
