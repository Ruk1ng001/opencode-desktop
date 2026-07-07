#!/usr/bin/env bash
# 从 codex/ 当前工作区改动导出补丁到 brand/patches/。
#
# 工作方式:
#   - 读取 brand/patches.manifest,把改动的文件按「补丁组」归类;
#   - 对每个组用 `git diff` 生成一个 <序号>-<组名>.patch;
#   - 未在 manifest 中列出的已改动文件会被警告(避免漏进补丁)。
#
# 用法:
#   1. ./scripts/reset-src.sh          # 先回到干净基线
#   2. ./scripts/apply-patches.sh      # (可选)先套上已有补丁
#   3. 手动编辑 codex/ 里的源码
#   4. ./scripts/make-patches.sh       # 导出补丁
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MANIFEST="$BRAND_DIR/patches.manifest"
[ -f "$MANIFEST" ] || die "找不到清单文件: $MANIFEST"

cd "$SRC_DIR"

# 收集当前所有已改动/新增的文件(相对 codex/ 的路径)
mapfile -t CHANGED < <(git -C "$SRC_DIR" diff --name-only; git -C "$SRC_DIR" ls-files --others --exclude-standard)
if [ "${#CHANGED[@]}" -eq 0 ]; then
  echo "codex/ 没有任何改动,无补丁可导出。"
  exit 0
fi

# 解析 manifest: 每行 "组序号 组名 路径前缀"，# 开头为注释
# 例如:  1 rename        codex-rs/cli/src/main.rs
#        2 i18n-brand    codex-rs/tui/src/onboarding/
declare -a GROUP_NUM GROUP_NAME GROUP_PREFIX
while IFS= read -r line; do
  line="${line%%#*}"                       # 去掉行内注释
  line="$(echo "$line" | xargs || true)"   # 去首尾空白
  [ -z "$line" ] && continue
  num="$(echo "$line" | awk '{print $1}')"
  name="$(echo "$line" | awk '{print $2}')"
  prefix="$(echo "$line" | awk '{print $3}')"
  GROUP_NUM+=("$num"); GROUP_NAME+=("$name"); GROUP_PREFIX+=("$prefix")
done < "$MANIFEST"

[ "${#GROUP_NUM[@]}" -gt 0 ] || die "清单为空,无法分组"

# 为每个改动文件找到所属组(最长前缀匹配),未匹配的收集到 orphans
declare -A GROUP_FILES
orphans=()
for f in "${CHANGED[@]}"; do
  best_idx=-1; best_len=-1
  for i in "${!GROUP_PREFIX[@]}"; do
    p="${GROUP_PREFIX[$i]}"
    case "$f" in
      "$p"*) if [ "${#p}" -gt "$best_len" ]; then best_len="${#p}"; best_idx="$i"; fi ;;
    esac
  done
  if [ "$best_idx" -ge 0 ]; then
    GROUP_FILES["$best_idx"]+="$f"$'\n'
  else
    orphans+=("$f")
  fi
done

if [ "${#orphans[@]}" -gt 0 ]; then
  echo "⚠ 以下已改动文件未在 patches.manifest 中归类,不会进补丁:" >&2
  printf '   %s\n' "${orphans[@]}" >&2
  echo "   如需纳入,请在 brand/patches.manifest 增加对应前缀。" >&2
fi

mkdir -p "$PATCHES_DIR"

# 按组导出补丁
exported=0
for i in "${!GROUP_NUM[@]}"; do
  files_blob="${GROUP_FILES[$i]:-}"
  [ -z "$files_blob" ] && continue
  mapfile -t files < <(printf '%s' "$files_blob" | sed '/^$/d')
  out="$PATCHES_DIR/$(printf '%02d' "${GROUP_NUM[$i]}")-${GROUP_NAME[$i]}.patch"
  # 对新增文件需要 git add -N 才能进 diff
  for f in "${files[@]}"; do
    git -C "$SRC_DIR" add -N -- "$f" 2>/dev/null || true
  done
  git -C "$SRC_DIR" diff -- "${files[@]}" > "$out"
  if [ -s "$out" ]; then
    echo "✓ 导出 $(basename "$out")  (${#files[@]} 个文件)"
    exported=$((exported+1))
  else
    rm -f "$out"
  fi
done

echo "完成,共导出 $exported 个补丁到 $PATCHES_DIR"
echo "提示:导出后可运行 ./scripts/reset-src.sh 把 codex/ 还原为干净基线。"
