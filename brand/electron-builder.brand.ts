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
  },
  win: {
    ...base.win,
    icon: path.join(iconsDir, "icon.ico"),
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
