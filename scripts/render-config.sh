#!/usr/bin/env bash
# 打包期配置渲染：把 brand/config.template.toml 里的占位符替换成真实渠道值，
# 产出可直接写入 ~/.codex/config.toml 的成品配置（方案 A：纯配置注入，不改源码）。
#
# ── 真实值的唯一来源与替换点（集中定义，验收 5）────────────────────────
# 三个占位符 → 三个环境变量，一一对应，集中声明在下方 PLACEHOLDER_VARS：
#     __BASE_URL__  ←  CX_BASE_URL   渠道 API 地址（须提供 /v1/responses 端点）
#     __TOKEN__     ←  CX_TOKEN      渠道 bearer token
#     __MODEL__     ←  CX_MODEL      默认模型名
# 增删占位符只改这一张表即可，无需动替换逻辑。
#
# ── 值从哪来（优先级从高到低）───────────────────────────────────────
#   1. 进程环境变量：CI 里由 GitHub Actions Secret 注入，绝不进 git；
#   2. brand/channel.env：本地打包用的真实值文件，已被 .gitignore 忽略，绝不进 git。
#      （格式见随仓库提供的 brand/channel.env.example）
# 想换渠道：线上改 CI Secret、本地改 brand/channel.env，源码与模板都不用动。
#
# 用法：
#   scripts/render-config.sh [输出路径]
#     省略输出路径 → 打印到 stdout；
#     指定输出路径 → 写入该文件并 chmod 600（含 token，按敏感文件处理）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TEMPLATE="$BRAND_DIR/config.template.toml"
CHANNEL_ENV="$BRAND_DIR/channel.env"
OUT_PATH="${1:-}"

# 占位符 → 环境变量名（真实值来源的单一映射表）
declare -A PLACEHOLDER_VARS=(
  ["__BASE_URL__"]="CX_BASE_URL"
  ["__TOKEN__"]="CX_TOKEN"
  ["__MODEL__"]="CX_MODEL"
)

[ -f "$TEMPLATE" ] || die "找不到配置模板: $TEMPLATE"

# 1) 先记录来自真实进程环境（CI Secret）的非空值——它们优先级最高。
declare -A from_env=()
for ph in "${!PLACEHOLDER_VARS[@]}"; do
  var="${PLACEHOLDER_VARS[$ph]}"
  if [ -n "${!var:-}" ]; then
    from_env["$var"]="${!var}"
  fi
done

# 2) 从本地 brand/channel.env 补充（若存在）。source 会设置这些变量。
if [ -f "$CHANNEL_ENV" ]; then
  log "从 $CHANNEL_ENV 读取渠道值（环境变量优先，会覆盖此文件）"
  set -a
  # shellcheck disable=SC1090
  source "$CHANNEL_ENV"
  set +a
fi

# 3) 环境变量优先：把第 1 步记录的真实环境值覆盖回去。
for var in "${!from_env[@]}"; do
  printf -v "$var" '%s' "${from_env[$var]}"
done

# 4) 校验每个占位符都拿到了非空值，否则列出缺失的环境变量并退出。
missing=()
for ph in "${!PLACEHOLDER_VARS[@]}"; do
  var="${PLACEHOLDER_VARS[$ph]}"
  [ -n "${!var:-}" ] || missing+=("$var")
done
if [ "${#missing[@]}" -gt 0 ]; then
  err "渠道值缺失：以下环境变量为空，无法渲染配置："
  for m in "${missing[@]}"; do err "    - $m"; done
  err "处理：在 CI 里配置对应的 Secret，或复制 brand/channel.env.example 为 brand/channel.env 并填入真实值。"
  exit 1
fi

# 5) 逐个替换占位符（纯 bash 字符串替换，token/url 里的 / & 等字符对它无害，
#    不像 sed 需要转义分隔符）。
content="$(<"$TEMPLATE")"
for ph in "${!PLACEHOLDER_VARS[@]}"; do
  var="${PLACEHOLDER_VARS[$ph]}"
  val="${!var}"
  content="${content//"$ph"/$val}"
done

# 6) 校验无残留占位符（形如 __XXX__），防止漏替换把占位符写进用户配置。
if printf '%s' "$content" | grep -qE '__[A-Z_]+__'; then
  err "渲染后仍残留未替换的占位符："
  printf '%s' "$content" | grep -oE '__[A-Z_]+__' | sort -u | while IFS= read -r p; do
    err "    - $p"
  done
  err "处理：为每个占位符在 PLACEHOLDER_VARS 里补上对应环境变量。"
  exit 1
fi

# 7) 输出。写文件时按敏感文件（含 token）处理，权限收紧到 600。
if [ -n "$OUT_PATH" ]; then
  printf '%s\n' "$content" > "$OUT_PATH"
  chmod 600 "$OUT_PATH"
  log "已渲染配置到 $OUT_PATH（权限 600）"
else
  printf '%s\n' "$content"
fi
