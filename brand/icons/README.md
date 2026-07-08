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

> 尚未放入真实图标前，本目录仅含此说明。图标为二进制资源，不含任何密钥，
> 可安全提交进 git。
