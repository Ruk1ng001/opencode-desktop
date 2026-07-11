# 自动更新三平台端到端验证（US-011）

> 目标：连发两个版本（旧 → 新），三平台各做一次实机——装旧版 → 发新版 →
> 应用检测到更新 → 下载 → 安装成功启动新版本。macOS 走 zip、Windows 走 exe、
> Linux 走 AppImage；更新源指向本仓库 Release，不弹官方 opencode 更新提示。
>
> 本文档由两部分组成：
> 1. **程序化预检（已在 CI/服务器侧执行、全部通过）**——把实机验证前所有可自动核验的
>    链路点钉死，缩小人工验证的怀疑面。
> 2. **人工实机验证手册（需在三平台真机执行）**——AC#1/#2/#5 本质是人工 QA，
>    无法在无头服务器自动完成；本手册给出逐步操作 + 记录模板，执行后回填结论。

---

## A. 程序化预检（已执行，✅ 全绿）

> 环境：无头 aarch64 Linux（无 GUI/Electron 运行时），故只能验证「源指向 / feed 解析 /
> 载体可达 / 元数据完整」这些可脚本化的链路点；「装 → 检测 → 下载 → 安装 → 启动」
> 需真机，见 B 节。

### A.1 更新源指向本仓库、无官方 opencode 残留（AC#3）

- `brand/electron-builder.brand.ts` 的 `publish` 覆盖上游官方源：
  `{ provider: "github", owner: "Ruk1ng001", repo: "opencode-desktop", channel: "latest" }`。
  这份 `publish` 在打包时写进产物内的 `app-update.yml`，是 electron-updater 查更新的唯一来源。
- 上游 base 配置的官方源（`anomalyco/opencode`、`anomalyco/opencode-beta`）仅存在于
  `opencode/packages/desktop/electron-builder.config.ts`，被品牌覆盖层 spread 覆盖，**不进产物**。
- 全仓 grep 确认无其它代码路径引用官方更新源（唯一命中是 brand 覆盖层的注释说明）。
- `updater.ts` 的 `autoUpdater.channel = "latest"` 与 publish 的 `channel:"latest"` 对齐
  （查 `latest*.yml`）。`UPDATER_ENABLED = app.isPackaged && CHANNEL !== "dev"`——仅打包产物启用，
  dev 不弹更新。

### A.2 prerelease feed 解析选中最新 -cx.N（检测环节）

- 补丁 `08-self-update-prerelease.patch`：`allowPrerelease = false → true`。
  cx 版本号 `<opencode版本>-cx.N` 在 semver 里属 prerelease；不放行则 electron-updater 走
  `/releases/latest`（GitHub 把带 `-` 的 release 排除在 Latest 外）→ 永远查不到 cx 版本。
- 放行后走 `releases.atom` 分支，按当前版本的 prerelease 分量 `cx` 匹配 release 的 `-cx.N`。
- **实测**（拉本仓库真实 `releases.atom`）：feed 顺序为 `cx.9 > cx.8 > … > cx.1`，
  装旧版（如 cx.6）时按 `-cx.N` 数值递增可正确检出最新 cx tag → 判定「有可更新」。

### A.3 三平台自更新载体齐全、元数据完整、HEAD 可达（下载环节）

以 `v1.17.15-cx.7`（当前唯一四产物齐全的完整 release）为例，实测：

| 平台 | 自更新载体 | `latest*.yml` | sha512/size | HEAD 可达 |
| --- | --- | --- | --- | --- |
| macOS arm64 | `opencode-desktop-mac-arm64.zip` | `latest-mac.yml`（含 arm64+x64 4 条 files） | ✅ | 200 |
| macOS x64 | `opencode-desktop-mac-x64.zip` | 同上 | ✅ | 200 |
| Windows x64 | `opencode-desktop-win-x64.exe` | `latest.yml` | ✅ | 200 |
| Linux x64 | `opencode-desktop-linux-x86_64.AppImage` | `latest-linux.yml`（含 blockMapSize） | ✅ | 200 |

平台↔载体严格对齐 AC#2：mac=zip、win=exe、linux=AppImage。macOS 不用 dmg 更新
（electron-updater 只能用 zip；只出 dmg 不生成可用 `latest-mac.yml`）。

### A.4 ⚠️ 发布态阻塞：最新两版（cx.8 / cx.9）不完整，不能作为实机验证对象

- **现状**：`cx.8` / `cx.9` 是「CI 临时只打 Windows + macOS Intel」时期（提交 `f2a8098`）的产物，
  **缺 Linux AppImage 与 macOS arm64**。实测 `cx.9` 的 `latest-linux.yml` 返回 **404**。
- **影响**：此刻 Linux / macOS-arm64 用户做真实更新检查，会经 atom feed 解析到最新的 `cx.9`，
  却因对应 `latest-linux.yml` / arm64 files 缺失而**下载环节失败**。
- **结论**：实机验证的「旧 → 新」两个版本**必须都是四平台矩阵恢复（US-009，提交 `12343e6`）之后
  产出的完整 release**（每个都含 mac-arm64.zip + mac-x64.zip + win.exe + linux.AppImage
  及各自 `latest*.yml`）。**不能用 cx.7 及更早、也不能用 cx.8/cx.9 做验证。**
  正确做法：连发两个全新完整版本（记为 `OLD` = 先发、`NEW` = 后发）。

---

## B. 人工实机验证手册（三平台真机执行，回填结论后去「未验证」标记）

> 前置：US-009 已恢复四平台矩阵。按下述连发两个**完整**版本，再三平台各验一次。
> 任一平台未过 → 不推正式发布（AC#5）。

### B.0 连发两个完整版本（OLD → NEW）

1. 触发发布流水线产出第一个完整版本 `OLD`（如 `v1.17.15-cx.10`）：
   - `push` 到 `main`，或 `workflow_dispatch`（可 `force_version` 指定）。
   - 等 `release` job 完成，确认该 tag 的 assets **同时含** 4 个安装包
     （`*-mac-arm64.zip/.dmg`、`*-mac-x64.zip/.dmg`、`*-win-x64.exe`、`*-linux-x86_64.AppImage`）
     与 `latest-mac.yml` / `latest.yml` / `latest-linux.yml`。缺任一 → 修复 CI 再重发。
2. 再触发一次产出 `NEW`（如 `v1.17.15-cx.11`），同样确认四产物 + 三 `latest*.yml` 齐全。
3. 校验版本号严格递增：`next-cx-version.sh` 按已有 release 自增 `-cx.N`，`NEW` 的 N 大于 `OLD`。

### B.1 macOS（arm64 与 x64 各一次，走 zip）

1. 下载 `OLD` 的对应架构 `.dmg`，安装并首启 cx（确认版本号 = OLD）。
2. 保持网络可达 github.com。触发应用内「检查更新」（或等自动检查）。
3. **预期**：检测到 `NEW` → 后台下载对应架构 `.zip` → 弹「Update <NEW> downloaded. Restart now?」。
4. 点 Restart → 应用退出重装 → 重新启动，确认版本号 = NEW、正常进入主界面（无 `pty.node` 崩溃）。
5. **不应**出现任何官方 opencode 的更新提示。
6. 记录：架构、OLD→NEW 版本号、结论（通过 / 失败 + 现象）。

### B.2 Windows x64（走 exe）

1. 下载 `OLD` 的 `.exe`（nsis 安装器），安装并首启（确认版本号 = OLD）。
2. 触发检查更新。
3. **预期**：检测到 `NEW` → 下载 `.exe` → 弹重启提示 → Restart 后静默安装 → 启动 NEW。
4. 确认版本号 = NEW、无官方 opencode 更新提示。
5. 记录：OLD→NEW 版本号、结论。

### B.3 Linux x64（走 AppImage）

1. 下载 `OLD` 的 `.AppImage`，`chmod +x` 后运行（确认版本号 = OLD）。
   - 注：AppImage 自更新要求当前是从可写位置运行的 AppImage 且 electron-updater 能就地替换；
     若通过包管理器/解包运行则不走自更新，需用原始 AppImage 文件验证。
2. 触发检查更新。
3. **预期**：检测到 `NEW` → 下载 `NEW` 的 `.AppImage` → 弹重启提示 → Restart 后替换 → 启动 NEW。
4. 确认版本号 = NEW、无官方 opencode 更新提示。
5. 记录：OLD→NEW 版本号、结论。

### B.4 结论汇总模板（回填后据此决定是否推正式发布）

| 平台 | 载体 | OLD → NEW | 检测 | 下载 | 安装启动 | 无官方提示 | 结论 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| macOS arm64 | zip | vX-cx.A → vX-cx.B | ☐ | ☐ | ☐ | ☐ | 待验 |
| macOS x64 | zip | vX-cx.A → vX-cx.B | ☐ | ☐ | ☐ | ☐ | 待验 |
| Windows x64 | exe | vX-cx.A → vX-cx.B | ☐ | ☐ | ☐ | ☐ | 待验 |
| Linux x64 | AppImage | vX-cx.A → vX-cx.B | ☐ | ☐ | ☐ | ☐ | 待验 |

**推正式发布判据（AC#5）**：四行全部「通过」→ 才把 OLD/NEW 作为正式发布推送；
任一「失败」→ 不推，先修复对应平台再重跑本手册。

---

## 变更记录

| 故事 | 变更 |
| --- | --- |
| US-011 | 固化自更新三平台端到端验证：程序化预检（源指向 / prerelease feed 解析 / 三平台载体可达 + 元数据完整）全绿并记录；发现并记录 cx.8/cx.9 不完整、实机须用四平台矩阵恢复后的完整连发版本；产出人工实机验证手册与结论模板。实机三平台验证与正式发布推送为人工 QA 环节，待真机执行回填。 |
