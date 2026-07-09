# cx 桌面客户端 —— 重建计划

> 项目转向：从「codex CLI + 补丁」重建为「基于 **opencode** 桌面端的定制跟随版」。
> 产物是 Electron 桌面客户端（`.dmg` / `.exe` / `.AppImage`），内置自定义渠道、
> 中文界面、自有品牌，跟随 opencode 稳定 release 自动发布。

## 为什么换到 opencode

官方 codex 的桌面 App / IDE 扩展都**闭源且锁死 OpenAI 官方后端**，无法接自定义渠道、
无法改名中文化。opencode（[anomalyco/opencode](https://github.com/anomalyco/opencode)，
MIT，18 万 star）桌面端**开源可改**，且定制成本远低于 codex：

| 定制点 | codex 旧方案 | opencode 新方案 |
|------|------|------|
| 渠道配置 | 模板渲染 + 占位符替换 | **纯 JSON `provider` 段，`{env:VAR}` 注入，零补丁** |
| 中文化 | 打补丁改 4 个 Rust 文件 | **官方自带 `zh.ts`，零工作量** |
| 改名 / 品牌 | 改 Rust 常量 + 补丁 | 改 `electron-builder` 配置（`--config` 覆盖，不碰源码） |
| 产物 | `.pkg` / `.msi`（CLI 装 PATH） | **`.dmg` / `.exe` / `.AppImage`（真桌面 App）** |

沿用现有哲学：**submodule 锁上游 + 薄叠加层 + 不改源码**。补丁层几乎用不到了。

## 上游基线

- 仓库：`https://github.com/anomalyco/opencode.git`
- 稳定 release：`v1.17.15`（SHA `5fb0d1cdb363ecafd55402c451c6634ed15b74b1`，2026-07-07）
- 桌面端位置：`packages/desktop`（Electron 42 + SolidJS，`electron-builder` 打包）
- 跟随策略：跟 `vX.Y.Z` tag，**排除 `vscode-v*`**（那是 VS Code 扩展的 tag）

## 关键技术事实（已核实）

- **渠道**：`opencode.json` 的 `provider` 段，OpenAI 兼容用 `@ai-sdk/openai-compatible`
  （命中 `/v1/chat/completions`）或 `@ai-sdk/openai`（命中 `/v1/responses`）。
  密钥用 `{env:VAR}` / `{file:path}` 注入，不硬编码。
- **内置配置注入**：opencode 原生支持 managed config 路径（macOS
  `/Library/Application Support/opencode/`、Linux `/etc/opencode/`、Win
  `%ProgramData%\opencode`），可由安装器写入——**原生特性，零源码改动**（待实测确认最干净的落地方式）。
- **中文**：`packages/ui/src/i18n/zh.ts`（简体）+ `zht.ts`（繁体）官方已内置。
- **品牌**：`electron-builder.config.ts` 已有 dev/beta/prod 三通道，含 `appId`
  / `productName` / `publish` / 图标（`resources/icons/`）。改名走 `--config` 覆盖。
- **构建**：`bun install && bun run build && bun run package`，产物落 `dist/`。

## 执行步骤（清理已完成 ✅）

- [x] **清理 codex 那套**：移除 `codex` submodule、`brand/`、`installer/`、
  `packaging/`、`scripts/`、旧 CI、旧文档。保留 `.git` / `.chief` / `.claude`。
- [ ] **引入 opencode submodule**：`git submodule add … opencode`，锁到 `v1.17.15`，
  写入 `brand/BASE_SHA` + `brand/BASE_TAG`（双文件基线，沿用旧机制）。
- [ ] **建立 brand 叠加层**：
  - `brand/opencode.template.json` —— `provider.newapi` 渠道模板（占位或原生 `{env:}` 语法）
  - `brand/electron-builder.brand.ts` —— import 原配置 spread 覆盖品牌字段，不碰源码
  - `brand/channel.env.example` + `.gitignore` 忽略真实值（沿用安全策略）
  - `brand/icons/` —— 品牌图标（`.icns` / `.ico`，当前占位）
- [ ] **重建 scripts**：
  - `update.sh` —— 跟随 opencode 最新 `vX.Y.Z`（排除 `vscode-v*`），更新基线
  - 渠道注入脚本（若用原生 `{env:}` 语法可能可省）
- [ ] **重建 CI**：`release.yml` = detect（查新 tag）→ build（`bun run build`）→
  package（`electron-builder --config brand/…` 出三平台包）→ release（版本号
  `<opencode版本>-cx.N`）。渠道值经 Secret 注入 + `::add-mask::`，绝不进 git / 日志。
- [ ] **重写文档**：`README.md`（安装 / 使用 / 卸载）+ `CUSTOMIZATION.md`（新替换点清单）。

## 实施中需边做边验证的风险点

1. **内置渠道注入的确切落地方式** —— managed config 路径 vs `extraResources` bundle
   vs 首启动写入。实测哪种在 Electron 打包下最干净且不碰源码。
2. **`electron-builder --config` 能否干净覆盖** —— 若 build 脚本写死了配置路径，
   可能需要一个极小补丁（届时明确说明）。
3. **本地打包验证** —— 环境是 Linux，可打 `.AppImage` 验证；`.dmg` 需 macOS runner，
   只能靠 CI 验证。

## 决策记录

- 清理方式：**彻底删除** codex 那套（不保留、不归档）。
- 骨架组织：**submodule + 薄叠加层**（沿用现有哲学）。
- 集成对象：**opencode**（非 codex 内核，换赛道）。
