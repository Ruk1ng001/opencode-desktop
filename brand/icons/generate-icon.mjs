// [cx] Dokng 品牌图标生成器：字母 D 圆角方块（蓝色渐变底 + 白色 D）。
//
// 依赖 opencode 的 node_modules 里的 sharp（仓库内已装），把内联 SVG 渲染成多尺寸 PNG，
// 再手工打包成 .ico（Windows）/ .icns（macOS）——二者都支持「嵌入 PNG」子图，无需额外的
// ico/icns 编码库。输出覆盖同目录下的 icon.png / icon.ico / icon.icns（保持文件名，
// electron-builder.brand.ts 直接消费这些路径）。
//
// 运行：node brand/icons/generate-icon.mjs
//   （sharp 从 opencode/node_modules 解析，见下方 require 路径处理）

import { createRequire } from "node:module"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import { writeFileSync } from "node:fs"

const here = dirname(fileURLToPath(import.meta.url))
// sharp 装在 opencode submodule 的 node_modules 下，用其 package.json 作为解析基点。
const require = createRequire(join(here, "../../opencode/package.json"))
const sharp = require("sharp")

// 品牌主色（取自参考 HTML 的 --primary #3b6ef5），渐变到更深的蓝做立体感。
const BLUE_TOP = "#4a7bff"
const BLUE_BOTTOM = "#3b6ef5"

// 圆角方块 + 居中白色字母 D 的 SVG。viewBox 1024，圆角比例贴近 macOS/现代应用图标观感。
// D 用路径绘制（竖线 + 右侧半圆弧组成的经典 D 造型），保证任意尺寸缩放清晰、无字体依赖。
function iconSvg(size) {
  const r = Math.round(size * 0.225) // 圆角半径（约 macOS squircle 观感）
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${BLUE_TOP}"/>
      <stop offset="1" stop-color="${BLUE_BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="1024" height="1024" rx="${Math.round((r / size) * 1024)}" ry="${Math.round((r / size) * 1024)}" fill="url(#bg)"/>
  <!-- 字母 D：外形为「竖直左边 + 右侧半圆」，用偶奇填充挖空内部形成字腔。 -->
  <path fill="#ffffff" fill-rule="evenodd"
        d="M320 260
           h190
           a252 252 0 0 1 0 504
           h-190
           z
           M420 360
           v304
           h90
           a152 152 0 0 0 0 -304
           z"/>
</svg>`
}

async function renderPng(size) {
  return await sharp(Buffer.from(iconSvg(size))).resize(size, size).png().toBuffer()
}

// ── ICO 打包（Windows）：ICONDIR + 每尺寸 ICONDIRENTRY，图像数据用 PNG 原样嵌入 ──
function buildIco(entries) {
  // entries: [{ size, png }]
  const count = entries.length
  const header = Buffer.alloc(6)
  header.writeUInt16LE(0, 0) // reserved
  header.writeUInt16LE(1, 2) // type: 1 = icon
  header.writeUInt16LE(count, 4)

  const dirEntries = []
  const images = []
  let offset = 6 + count * 16
  for (const { size, png } of entries) {
    const entry = Buffer.alloc(16)
    entry.writeUInt8(size >= 256 ? 0 : size, 0) // width（256 记为 0）
    entry.writeUInt8(size >= 256 ? 0 : size, 1) // height
    entry.writeUInt8(0, 2) // color palette
    entry.writeUInt8(0, 3) // reserved
    entry.writeUInt16LE(1, 4) // color planes
    entry.writeUInt16LE(32, 6) // bits per pixel
    entry.writeUInt32LE(png.length, 8) // image data size
    entry.writeUInt32LE(offset, 12) // image data offset
    offset += png.length
    dirEntries.push(entry)
    images.push(png)
  }
  return Buffer.concat([header, ...dirEntries, ...images])
}

// ── ICNS 打包（macOS）：magic 'icns' + 各尺寸 OSType chunk，用 PNG 嵌入型 OSType ──
// OSType 映射（PNG 嵌入型，现代 macOS 支持）：
//   ic07=128, ic08=256, ic09=512, ic10=1024, ic11=32(@2x of 16), ic12=64(@2x of 32),
//   ic13=256(@2x of 128), ic14=512(@2x of 256)
function buildIcns(map) {
  // map: { OSType(string): png }
  const chunks = []
  for (const [type, png] of Object.entries(map)) {
    const header = Buffer.alloc(8)
    header.write(type, 0, 4, "ascii")
    header.writeUInt32BE(png.length + 8, 4)
    chunks.push(Buffer.concat([header, png]))
  }
  const body = Buffer.concat(chunks)
  const fileHeader = Buffer.alloc(8)
  fileHeader.write("icns", 0, 4, "ascii")
  fileHeader.writeUInt32BE(body.length + 8, 4)
  return Buffer.concat([fileHeader, body])
}

async function main() {
  // 主 PNG（1024，通用 / Linux 源图）。
  const png1024 = await renderPng(1024)
  writeFileSync(join(here, "icon.png"), png1024)

  // ICO：Windows 常用尺寸集合。
  const icoSizes = [16, 32, 48, 64, 128, 256]
  const icoEntries = []
  for (const size of icoSizes) icoEntries.push({ size, png: await renderPng(size) })
  writeFileSync(join(here, "icon.ico"), buildIco(icoEntries))

  // ICNS：PNG 嵌入型 OSType。覆盖 16→1024（含 @2x）。
  const png16 = await renderPng(16)
  const png32 = await renderPng(32)
  const png64 = await renderPng(64)
  const png128 = await renderPng(128)
  const png256 = await renderPng(256)
  const png512 = await renderPng(512)
  const icns = buildIcns({
    icp4: png16, // 16
    icp5: png32, // 32
    icp6: png64, // 64
    ic07: png128, // 128
    ic08: png256, // 256
    ic09: png512, // 512
    ic10: png1024, // 1024 (512@2x)
    ic11: png32, // 16@2x
    ic12: png64, // 32@2x
    ic13: png256, // 128@2x
    ic14: png512, // 256@2x
  })
  writeFileSync(join(here, "icon.icns"), icns)

  console.log("生成完成：icon.png (1024), icon.ico (%s), icon.icns", icoSizes.join("/"))
}

main().catch((err) => {
  console.error("图标生成失败：", err)
  process.exit(1)
})
