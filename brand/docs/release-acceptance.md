# 全平台产物验收（US-010）

> 目标：恢复四平台矩阵后，一次发布流水线真实产出各平台可安装产物，
> GitHub Release 正确汇总（含 mac 双架构），`latest*.yml` 元数据正确合并，
> 且 macOS arm64 安装后启动不再出现 `pty.node` 崩溃。
>
> 本文档固化验收证据链，路径均已逐条核对。

---

## 1. 一次发布流水线产出四平台产物

**结论：`.github/workflows/release.yml` 的 `package` job 矩阵为 4 项，各出对应平台产物。**

矩阵（`release.yml` `package.strategy.matrix.include`）：

| runner | platform_flag | arch_flag | 产物 | artifact_name | meta_subdir |
| --- | --- | --- | --- | --- | --- |
| `macos-latest` | `--mac` | `--arm64` | `.dmg` + `.zip` | `cx-dmg-arm64` | `latest-yml-aarch64-apple-darwin` |
| `macos-15-intel` | `--mac` | `--x64` | `.dmg` + `.zip` | `cx-dmg-x64` | `latest-yml-x86_64-apple-darwin` |
| `windows-latest` | `--win` | — | `.exe` | `cx-exe` | `latest-yml-x86_64-pc-windows-msvc` |
| `ubuntu-latest` | `--linux` | — | `.AppImage` | `cx-appimage` | `latest-yml-x86_64-unknown-linux-gnu` |

产物覆盖 AC#1 要求：Windows exe、macOS x64 dmg+zip、macOS arm64 dmg+zip、Linux AppImage。

- macOS 双架构各出 `dmg`（人工下载）+ `zip`（electron-updater 自更新载体，macOS 只能用 zip 更新），
  target 由 `brand/electron-builder.brand.ts` 的 `mac.target: ["dmg","zip"]` 决定，架构由命令行 `--arm64`/`--x64` 指定。
- Linux 仅 `AppImage`（品牌配置 `linux.target: ["AppImage"]`，剔除上游 deb/rpm，聚焦验收产物）。
- Windows 出未签名 nsis `.exe`（`CX_UNSIGNED=1` 移除 Azure 签名回调）。

**平台严格对齐**：`.dmg`=macOS runner、`.exe`=windows runner、`.AppImage`=linux runner。

---

## 2. Release 汇总三平台产物 + `latest*.yml` 元数据正确合并

**结论：`release` job 下载全部 `cx-*` 安装包产物创建/更新 GitHub Release；
`finalize-latest-yml.ts` 按 `meta_subdir` 子目录名读取各架构 `latest*.yml`，
mac 双架构合并成单个 `latest-mac.yml`、win/linux 透传，`meta_subdir` 命名与脚本期望严格对齐。**

### 2.1 meta_subdir 与 finalize-latest-yml.ts 期望对齐

`release.yml` 上传的 `meta_subdir` ⇔ `finalize-latest-yml.ts` 的 `read(subdir, filename)`：

| meta_subdir（workflow 上传） | finalize 读取子目录 | 读取文件名 | 处理 |
| --- | --- | --- | --- |
| `latest-yml-aarch64-apple-darwin` | 同名 | `latest-mac.yml` | 与 x64 合并 |
| `latest-yml-x86_64-apple-darwin` | 同名 | `latest-mac.yml` | 与 arm64 合并 |
| `latest-yml-x86_64-pc-windows-msvc` | 同名 | `latest.yml` | （arm64 缺省）透传 |
| `latest-yml-x86_64-unknown-linux-gnu` | 同名 | `latest-linux.yml` | 透传 |

四个 `meta_subdir` 与脚本读取的子目录名逐字一致，无拼写偏差。脚本另兼容
`aarch64-pc-windows-msvc` / `aarch64-unknown-linux-gnu`（当前矩阵未产出，`read` 返回 undefined 跳过，不报错）。

### 2.2 mac 双架构合并逻辑（本地 dry-run 实测）

`finalize-latest-yml.ts` 的 mac 分支：
```
const macX64 = read("latest-yml-x86_64-apple-darwin", "latest-mac.yml")
const macArm64 = read("latest-yml-aarch64-apple-darwin", "latest-mac.yml")
output["latest-mac.yml"] = serialize({ files: [...macArm64.files, ...macX64.files], ... })
```

本地以假的分架构 `latest*.yml`（跳过 `gh release upload`）做 dry-run，确认输出单个
`latest-mac.yml` 含两架构全部 `files`（arm64 的 dmg+zip、x64 的 dmg+zip 共 4 条），
`latest.yml`（win）、`latest-linux.yml`（linux）原样透传。合并后 electron-updater
可从单个 `latest-mac.yml` 按运行架构匹配对应 zip 自更新。

### 2.3 Release 汇总

`release` job：
- `download-artifact` 以 `pattern: cx-*` + `merge-multiple: true` 下载四平台安装包到 `/tmp/artifacts`；
- `pattern: latest-yml-*` 分子目录下载各架构元数据到 `/tmp/latest-yml`（不合并，避免同名 `latest-mac.yml` 互相覆盖）；
- `gh release create/upload --latest`（`-cx.N` 会被判 prerelease，显式 `--latest` 正常标记）汇总三平台产物；
- `finalize-latest-yml.ts` 合并后 `gh release upload --clobber` 传回 `latest*.yml`。

---

## 3. macOS arm64 安装后启动不出现 `pty.node` 崩溃

**结论：node-pty 按平台拆分为独立子包，靠 `optionalDependencies` 只装当前 runner 架构那一个；
electron.vite 构建期把 `@lydell/node-pty` 收窄为 `@lydell/node-pty-<platform>-<arch>` 并 externalize；
arm64 包在 `macos-latest`（Apple Silicon）原生编译，装入 arm64 的 `pty.node`，运行时不跨架构。**

证据链：
1. **子包在 optionalDependencies**（`opencode/packages/desktop/package.json`）：
   `@lydell/node-pty-darwin-arm64` / `-darwin-x64` / `-linux-*` / `-win32-*` 六个平台子包列在
   `optionalDependencies`，`bun install` 按 runner 平台/架构只装匹配的那一个（arm64 runner 只装
   `darwin-arm64`）。若列在 `dependencies` 会全装，导致跨架构 `pty.node` 混入。
2. **构建期收窄 + externalize**（补丁 `02-balance-newapi.patch` 改 `electron.vite.config.ts`）：
   `const nodePtyPkg = \`@lydell/node-pty-${process.platform}-${process.arch}\`` →
   `externalizeDeps: { include: [nodePtyPkg] }` + rollup 插件把 `@lydell/node-pty` 的
   import 重定向到 `nodePtyPkg`。构建产物只引用当前架构子包。
3. **CI 分两个原生 runner**：arm64 在 `macos-latest`（Apple Silicon）以 `--arm64` 出包、
   x64 在 `macos-15-intel` 以 `--x64` 出包，各自 `bun install` 只装本架构 node-pty。
   不在单台 arm64 runner 上跨架构出 x64（否则打进 arm64 的 `pty.node`，x64 运行时报
   `Cannot find ./prebuilds/darwin-x64/pty.node`）。反之亦然，保证 arm64 包内是 arm64 `pty.node`。
4. **brand 配置不写死架构**（`brand/electron-builder.brand.ts` `mac` 段注释）：
   `mac.target: ["dmg","zip"]`，架构由命令行 `--arm64`/`--x64` 指定，不在配置里写死，
   避免单 runner 跨架构打包。

此即 TODO.md「macOS 分架构原生打包（修 pty.node 崩溃）」记录的既有修复，US-010 回归确认其仍生效。

---

## 4. 补丁重放 + 编译验证（产物生成前置）

「产物真实生成」依赖补丁能干净重放且 desktop 构建通过。本地按 CI 同款流程验证：

- 从 `brand/BASE_SHA`（`5fb0d1cdb363...`）干净基线，按 `brand/patches/*.patch` glob 顺序（01-08+10，无 09）
  逐个 `git apply --check` + 实际 `git apply`，**全部干净应用无冲突**。
- 应用后双包 `bun run typecheck`（tsgo -b）：**desktop rc=0 / app rc=0**。
- 验证后 `git -C opencode reset --hard $(cat brand/BASE_SHA) && clean -fd` 复原 gitlink 跟随基线。

磁盘补丁集与 HEAD `brand/patches.manifest`（引用 01-08+10）一致；CI 用 `for p in brand/patches/*.patch`
glob 应用，与本地验证同源，故 CI 各平台 build 步骤可复现该重放。

---

## 变更记录

| 故事 | 变更 |
| --- | --- |
| US-009 | 恢复 `release.yml` 四平台矩阵（取消注释 arm64 mac + linux）。 |
| US-010 | 全平台产物验收：核对四平台矩阵、`latest*.yml` 合并对齐（dry-run 实测）、arm64 `pty.node` 回归；固化本审计文档。 |
