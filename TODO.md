# cx 桌面客户端 —— 多 Key 内置渠道方案

> 项目形态：基于 **opencode** 桌面端（Electron + SolidJS）的定制跟随版。
> 产物是桌面客户端（`.dmg` / `.exe` / `.AppImage`），内置自定义渠道、自有品牌。
> 本文档记录「多 key 管理 + 内置渠道 + 余额/充值」这一核心功能的完整方案与进度。

---

## 一、目标

让用户尽量少配置地用上内置渠道，并能管理多个 key：

- App 内置好渠道 key，用户开箱即用，不手动填 base_url / token
- 用户可在一个 **key 列表**里管理多个 key，随时切换
- 每个 key **模型列表可能不同**，切换 key 时自动更新可选模型
- 每个 key 显示各自的 **用户名、头像、已消耗、总额**
- 可跳转到 **充值** 页面
- key 额度耗尽 / 失效时可自动切换到下一个（二期）

---

## 二、已确认的产品决策

| 项目 | 决定 |
|---|---|
| 模型列表 | **动态拉取**（切 key 时自动更新该 key 可用模型） |
| key 列表展示 | 卡片列表，每项含：名字(label)、key(打码)、已消耗、总额、用户名、头像 |
| 总额语义 | 待最终确认：倾向「账号总额度」（多 key 同账号时自然相等），消耗取「各 key 各自消耗」 |
| 自动切换 key | **二期**做；一期先做「手动切换 + 列表展示」 |
| 后端 | **二开 new-api**，直接在其中加接口，不另起独立服务 |
| 注入内核 | 复用已完成的 `OPENCODE_CONFIG_CONTENT` 注入机制（见下） |

---

## 三、凭据模型（安全底线，不可违背）

new-api 三类凭据，权限从大到小，**只有 API Token 能进 App**：

| 凭据 | 权限 | 放哪 |
|---|---|---|
| passkey / 密码 | 登录账号、做一切 | 用户设备，永不出门 |
| 系统访问令牌 | 管理账号、增删 token | **只在 new-api 服务端**，永不进 App |
| **API Token（`sk-…`）** | 只能调 AI、消耗额度 | ✅ 存进 App、注入内核 |

原则：App 只持有 `sk-…` API Token。查余额 / 拿用户名头像 / 拉模型，都用 `sk-` 调
**二开 new-api 新增的只读接口**，接口内部只返回该 token 本人的信息，不接受任意 user_id。

---

## 四、架构与数据流

```
① 导入 key
   用户拿到 sk-… → 存进 App 的 key 列表（本地）
   （一期：手动粘贴；二期可选：cx:// 深链一键导入）

② 调 AI
   当前激活 key 的 sk- → 经【注入机制】写入 OPENCODE_CONFIG_CONTENT
   → 内核用该 key + 该 key 的模型 发请求，消耗对应额度

③ 看余额 / 用户名 / 头像
   App 带 sk- 调 new-api 新接口 /api/app/profile → 展示

④ 拉模型列表
   App 带 sk- 调 /v1/models（或新接口）→ 得该 key 可用模型

⑤ 充值
   App 打开该用户充值页
```

---

## 五、new-api 二开（你负责，我给接口契约）

> **正式接口契约见 [`brand/docs/api-app-profile.md`](brand/docs/api-app-profile.md)（US-005 产出）。**
> 该文档是 App 端与 new-api 二开之间的完整只读接口契约，标注「后端后续实现」，App 端按此对接。
> 下方为要点摘录，字段/语义/安全约束以契约文档为准。

**新增只读接口（建议合并为一个，减少接口数）：**

```
GET /api/app/profile
  鉴权：Authorization: Bearer sk-…   （走 token 鉴权中间件）
  逻辑：由 sk- 定位 token 记录 → 拿 user_id → 查 user 表
  返回：{
    username,          // 用户名
    avatar,            // 头像 URL
    quota,             // 账户总额度
    used_quota,        // 账户已用
    token_remain,      // 这个 key 自己的剩余额度
    token_used,        // 这个 key 自己的已用
    token_used_today,  // 这个 key 今日消耗
    unlimited          // 是否不限额
  }
  安全：只返回该 token 本人信息，不接受任意 user_id 入参
```

**模型列表：** 优先用 OpenAI 兼容的 `GET /v1/models`（带 sk-）。
- 待确认：你的 new-api `/v1/models` 是否**按 key 返回该 key 可用模型**（而非全站模型）。
- 若已按 token `model_limits` 过滤 → App 直接用 `/v1/models`，无需新增接口。
- 若不区分 → 二开追加 `GET /api/app/models` 返回「该 key 绑定的模型」（OpenAI 兼容形态，契约见文档第 6 节）。

**充值：** 后续细化（充值页免登录链接 / 带身份跳转）。

---

## 六、App 端改造（我负责，全部走 brand 补丁，不改上游源码）

- [ ] **内核注入机制**（`03-lock-channel.patch`）
  - `electron.vite.config.ts`：main 段 define 注入渠道值
  - `server.ts`：`createSidecarEnv()` 合成 config → `OPENCODE_CONFIG_CONTENT`
  - 状态：**已实现，typecheck 通过，待导出落盘**
  - 待改造：token 来源从「构建期内置单 key」→「读本地当前激活 key」
- [ ] **key 列表管理**：本地存 `[{ label, key, baseURL }]` + 当前激活项，UI 增删改
- [ ] **key 卡片展示**：头像 + 用户名 + 已消耗 / 总额（进度条），数据来自 `/api/app/profile`
- [ ] **切换 key 联动**：
  - 拉该 key 的模型列表（`/v1/models`）→ 更新可选模型
  - 重新生成内核 config → 让内核用新 key + 新模型
  - **已查证（US-002）**：内核无法热切换 key，**必须重启 sidecar**。详见第十一节。
- [ ] **充值入口**：打开充值页
- [ ] **首启引导**：无 key 时提示用户导入
- [ ] **自动切换 key**（二期）：调用失败（额度耗尽 / 失效）自动切下一个
- [ ] **深链一键导入**（可选）：注册 `cx://` 协议，网站一键把 key 灌进 App

---

## 七、必须先查证的技术风险

1. ~~**内核换 key 是否需重启 sidecar**（最大不确定点）~~ **已查证（US-002）：必须重启 sidecar，详见第十一节。**
   内核靠 `OPENCODE_CONFIG_CONTENT` 一次性注入启动。运行中切 key 意味着换 config。
   结论：**不支持热切换 key**——该变量只在 sidecar 进程启动（`utilityProcess.fork`）时随 env 冻结注入，
   进程运行期间无法改写；`Config.invalidate()` 只失效全局配置缓存，触碰不到读 `OPENCODE_CONFIG_CONTENT`
   的实例级缓存；即便 `InstanceStore.reload` 重建实例也仍从旧 `process.env` 读值。**故换 key 必须重启 sidecar。**
2. **`/v1/models` 是否按 key 区分可用模型**（需你确认或我查 new-api 源码）
3. **余额面板现有鉴权隐患**：现有 `01-balance-panel.patch` 用 `sk-` 调 `/api/user/self`
   大概率鉴权失败。改造后统一走新的 `/api/app/profile` 接口解决。

---

## 八、待你拍板的点

1. 头像 / 用户名是**使用者本人一份**，还是**每个 key 各自的用户**？（决定按 key 查 profile 的粒度）
2. 总额 = 账号额度、消耗 = 各 key 消耗，确认？
3. `/api/app/profile` 接口**你自己加还是我给代码**？（给的话告诉我 new-api 分支 / 版本）
4. `/v1/models` 是否按 key 返回可用模型？（不确定我帮你查）
5. 深链一键导入：一期做还是先手动粘贴跑通？

---

## 九、推进顺序（每步可独立验证）

1. **导出 `03` 注入补丁落盘**（防丢失、后续必复用）—— 不依赖任何产品决定，可立即做
2. **查证内核切 key 是否需重启 sidecar** —— 影响整个切换实现，先打地基
3. App 端：token 来源改为读本地当前激活 key
4. App 端：key 列表管理 + 卡片展示（接 `/api/app/profile`）
5. App 端：切换 key 联动模型列表
6. 充值入口 + 首启引导
7. （二期）自动切换 key、深链一键导入
8. 我产出 **new-api 接口契约文档** 交给你实现

---

## 十、上游基线

- 仓库：`https://github.com/anomalyco/opencode.git`（submodule `opencode/`）
- 基线 tag / SHA：见 `brand/BASE_TAG` / `brand/BASE_SHA`
- 桌面端位置：`packages/desktop`（Electron + SolidJS，`electron-builder` 打包）
- 哲学：**submodule 锁上游 + brand 薄叠加层 + 补丁不改源码**

---

## 十一、结论：内核切换 key 是否需重启 sidecar（US-002）

**结论：必须重启 sidecar，不支持热切换 key。** 这是切换功能（US-009）的实现地基。

### 1. 证据链（源码位置基于 `brand/BASE_SHA`）

- **`OPENCODE_CONFIG_CONTENT` 只在进程启动时从 `process.env` 读取一次**
  - `packages/opencode/src/config/config.ts:468` —— `if (process.env.OPENCODE_CONFIG_CONTENT) { ... loadConfig(...) }`，
    在 `loadInstanceState` 里执行，直接读 `process.env`，无文件监听、无轮询。
- **sidecar 是 fork 出的子进程，env 在 fork 时冻结**
  - `packages/desktop/src/main/server.ts` `spawnLocalServer()` 用 `utilityProcess.fork(sidecar, [], { env: createSidecarEnv() })`。
  - `createSidecarEnv()` 里 `env.OPENCODE_CONFIG_CONTENT = channelConfig`（03 补丁注入）。子进程 env 是快照，
    主进程运行中改自己的 `process.env` 不会传导到已 fork 的 sidecar。
- **config 经实例级缓存持有，`invalidate()` 触碰不到它**
  - `config.ts` 用 `InstanceState.make(...)`（`instance-state.ts`，底层 `ScopedCache`，容量 `Infinity`、TTL 无穷）缓存
    `loadInstanceState` 的结果，每个实例目录只 lookup 一次。
  - `Config.invalidate()`（`config.ts:633`）只调 `invalidateGlobal`，失效的是**全局配置**缓存，
    与读 `OPENCODE_CONFIG_CONTENT` 的**实例级** state 是两套缓存，互不影响。
- **provider 初始化同样一次性读 config**
  - `packages/opencode/src/provider/provider.ts:1317` provider state 也是 `InstanceState.make(...)`，
    初始化时 `config.get()`（:1320）一次性读入 provider/model，构建 SDK 实例后缓存。
- **即便走实例重载也换不了 key**
  - 存在 `InstanceStore.reload`（`instance-store.ts`）+ `markInstanceForReload` HTTP 中间件（`lifecycle.ts`）能销毁并重建实例级缓存，
    重建时会重跑 `loadInstanceState`——但那仍旧从**同一个已冻结的 `process.env`** 读 `OPENCODE_CONFIG_CONTENT`，
    值不会变。所以热重载实例对「换 key」无效，唯一出路是重启 sidecar 进程本身。

### 2. 重启链路可复用性（已确认）

- 已有 IPC：`kill-sidecar`（`src/main/ipc.ts:48` → `deps.killSidecar()`）。
- 主进程 `killSidecar()`（`src/main/index.ts:80`）→ `server.stop()` → sidecar 收 `{type:"stop"}`，
  `SIDECAR_STOP_TIMEOUT=6s` 内优雅退出，超时 `child.kill()`。
- 重新拉起：`spawnLocalServer()`（`server.ts:55`），`ready` 消息 + `/global/health` 双重就绪判定，
  `SIDECAR_START_STALL_TIMEOUT=60s`。
- **缺口**：renderer 现有的 `restart`（`src/renderer/index.tsx:244`）是 `killSidecar()` + `relaunch()`，
  即**整个 App 重启**（`app.relaunch()`+`app.exit(0)`）。当前**没有**「杀 sidecar → 原地重新 spawn、保留窗口/前端」的 IPC。
  US-009 需要新增一条 brand 补丁提供的 `restart-sidecar` IPC（stop 现有 listener → 用新 env 重新 `spawnLocalServer` → 更新 `server` 引用），避免整壳重启。

### 3. 重启耗时与会话中断影响评估

- **耗时**：优雅 stop（正常 < 数百 ms，最坏 6s 超时兜底）+ 重新 spawn 到 `ready`/health（正常约几百 ms ~ 1s，冷启含依赖检查可能更久，上限 60s）。典型场景整体约 **0.5 ~ 2s**。
- **会话中断**：sidecar 是 opencode server，重启会断开当前 HTTP/流式连接。进行中的对话（正在生成的回复）会被打断；已落库的会话历史不受影响（会话状态持久化在 XDG_STATE / DB，不在内存 env）。重启后前端需重连并恢复会话列表。
- **风险点**：若用户在流式生成中途切 key，会丢失未完成的这一轮输出。

### 4. 切换 key 的技术方案建议（US-009 实现依据）

采用 **「重启 sidecar」** 路线（热切换已被证否）：

1. **token 来源改造**：`createSidecarEnv()` / `buildChannelConfigContent()` 从「构建期内联单 key」改为「读本地当前激活 key」（本地 store），使重新 spawn 时能带新 key 生成新的 `OPENCODE_CONFIG_CONTENT`。
2. **新增 `restart-sidecar` IPC**（brand 补丁）：主进程 `killSidecar()` → 以新 env `spawnLocalServer()` → 重新 resolve `serverReady`。只重启 sidecar，不 `app.relaunch()`，保留窗口与前端状态。
3. **用户体验处理**：
   - **会话保护**：切 key 前检测是否有进行中的流式生成；若有，弹确认「切换将中断当前生成，确定？」，或等当前轮结束再切。
   - **防抖**：连续快速切 key 时对重启操作做防抖 / 串行化（上一轮重启未完成不触发下一轮），避免并发 spawn。
   - **提示**：切换期间前端显示「正在切换渠道…」loading 态，禁用输入；`ready`/health 通过后自动重连并恢复。
   - **失败兜底**：新 key 导致 sidecar 起不来（如 key 失效）时，回滚到上一个可用 key 或提示错误，不留在无 server 的死态。
4. **模型联动**：重启前先用新 key 拉 `/v1/models` 更新可选模型（见风险 #2），再写入新 config 一并重启，避免二次重启。

> 供 US-009（切换联动）直接落地：**热切换不可行 → 复用 kill-sidecar + 新增 restart-sidecar IPC 重新 spawn → 配合会话保护/防抖/loading 提示。**
