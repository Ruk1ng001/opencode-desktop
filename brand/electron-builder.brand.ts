import path from "node:path"
import { fileURLToPath } from "node:url"

import type { Configuration } from "electron-builder"

import baseConfig from "../opencode/packages/desktop/electron-builder.config.ts"
import brand from "./brand.json" with { type: "json" }

// 上游 `getConfig()` 未标注返回类型，`publish.provider` 等字面量被推断为宽泛的
// `string`，与 electron-builder 的 `Publish` 联合类型不兼容。断言回 `Configuration`
// 以对齐类型（运行时结构不变，仅收窄类型）。
const base = baseConfig as Configuration

// 品牌覆盖层：import 上游已解析的 electron-builder 配置后 spread 覆盖，
// 只改品牌相关字段（productName / appId / 图标路径 / 由 appId 派生的 Linux 身份），
// 不修改上游源码。上游按 OPENCODE_CHANNEL 输出 dev/beta/prod 三通道，
// 这里保留各通道后缀（用前缀替换而非写死单值）。

const brandDir = path.dirname(fileURLToPath(import.meta.url))
const iconsDir = path.join(brandDir, "icons")

// 上游 appId 恒以 "ai.opencode.desktop" 开头，可能带 ".dev" / ".beta" 后缀（prod 无后缀）。
// 替换前缀即可平移到品牌 appId 并保留通道后缀。
const UPSTREAM_APP_ID_PREFIX = "ai.opencode.desktop"
const UPSTREAM_PRODUCT_NAME = "OpenCode"

const brandedAppId = (base.appId ?? UPSTREAM_APP_ID_PREFIX).replace(UPSTREAM_APP_ID_PREFIX, brand.appId)
// 上游 productName 形如 "OpenCode" / "OpenCode Dev" / "OpenCode Beta"。
const brandedProductName = (base.productName ?? UPSTREAM_PRODUCT_NAME).replace(UPSTREAM_PRODUCT_NAME, brand.productName)

// 无签名凭据时的降级开关（CI 首跑 / 本地验证用）。CX_UNSIGNED=1 时：
//   - macOS：关闭公证（notarize）与 hardenedRuntime、不签名（identity:null），否则
//     无 Apple 证书 / API Key 会让 dmg 打包失败；
//   - dmg：关闭 sign；
//   - Windows：移除上游自定义 signtoolOptions（其内部会调 Azure Trusted Signing，
//     无 Azure 凭据必然失败），产出未签名 nsis .exe。
// 默认（未设该 env）行为与上游一致：走完整签名 / 公证链路（需相应凭据）。
const unsigned = process.env.CX_UNSIGNED === "1"

const config: Configuration = {
  ...base,
  appId: brandedAppId,
  productName: brandedProductName,
  // 由 appId 派生的 Linux 桌面身份需同步覆盖，否则窗口类 / 启动器与新 appId 不一致。
  extraMetadata: {
    ...base.extraMetadata,
    desktopName: `${brandedAppId}.desktop`,
  },
  mac: {
    ...base.mac,
    icon: path.join(iconsDir, "icon.icns"),
    // 验收标准要求产物是 .dmg；上游 mac target 还含 zip（用于自动更新）。
    // 只保留 dmg，聚焦验收产物、减少无凭据下的失败面。
    target: ["dmg"],
    // 无凭据降级：关公证 + 不签名 + 关 hardenedRuntime（hardenedRuntime 需签名配套）。
    ...(unsigned ? { notarize: false, hardenedRuntime: false, identity: null } : {}),
  },
  dmg: {
    ...base.dmg,
    // 上游 dmg.sign=true；无凭据时关掉，否则 dmg 签名步骤失败。
    ...(unsigned ? { sign: false } : {}),
  },
  win: {
    ...base.win,
    icon: path.join(iconsDir, "icon.ico"),
    // 上游 win.signtoolOptions.sign 是自定义回调，内部调 Azure Trusted Signing。
    // 无 Azure 凭据时移除，产出未签名 .exe（验收只要求出包，不要求签名）。
    ...(unsigned ? { signtoolOptions: undefined } : {}),
  },
  nsis: {
    ...base.nsis,
    installerIcon: path.join(iconsDir, "icon.ico"),
    installerHeaderIcon: path.join(iconsDir, "icon.ico"),
  },
  linux: {
    ...base.linux,
    // Linux 传目录，electron-builder 从中挑选各尺寸 png。
    icon: iconsDir,
    // 验收标准要求产物是 .AppImage；上游 linux target 还含 deb / rpm
    // （rpm 需 runner 装 rpmbuild 工具）。只保留 AppImage，聚焦验收产物、
    // 避免额外系统依赖。
    target: ["AppImage"],
    executableName: brandedAppId,
    desktop: {
      ...base.linux?.desktop,
      entry: {
        ...base.linux?.desktop?.entry,
        StartupWMClass: brandedAppId,
      },
    },
  },
}

export default config
