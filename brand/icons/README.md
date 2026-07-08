# brand/icons — 品牌图标

本目录承载替换上游 opencode 的品牌图标资源（应用图标、安装器图标等），
与上游源码物理隔离。打包脚本从这里取图标覆盖 `opencode/packages/desktop/icons/`
等上游位置。

## 预期文件

| 文件 | 用途 | 平台 |
|---|---|---|
| `icon.icns` | 应用图标 | macOS |
| `icon.ico` | 应用图标 | Windows |
| `icon.png` | 应用图标（1024×1024 源图） | 通用 / Linux |

> 当前为**占位图标**（纯色 1024×1024，各格式自包含合法）：`icon.png` / `icon.ico`
> / `icon.icns` 均可被 electron-builder 直接消费，替换为正式品牌图标时保持文件名即可。
> 图标为二进制资源，不含任何密钥，可安全提交进 git。
>
> `brand/electron-builder.brand.ts` 用 `import.meta.url` 计算本目录的**绝对路径**再
> 覆盖 `mac.icon` / `win.icon` / `nsis.installerIcon` / `linux.icon`，因此不受打包
> 时工作目录影响。
