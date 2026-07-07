#!/usr/bin/env bash
# 把 brand/patches/*.patch 按文件名顺序应用到干净的官方基线上。
# 先重置到基线，保证每次应用都是可复现的。
# CI 和本机验证都用这个脚本。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BASE_SHA="$(read_base_sha)"

# 先确保 codex/ 停在干净基线（CI 里 codex 是新 checkout，本机可能有残留）
git -C "$SRC_DIR" reset --hard "$BASE_SHA" >/dev/null
git -C "$SRC_DIR" clean -fd >/dev/null

shopt -s nullglob
patches=("$PATCHES_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  log "没有补丁可应用（$PATCHES_DIR 为空）"
  exit 0
fi

log "共 ${#patches[@]} 个补丁，开始应用到 $BASE_SHA"
for p in "${patches[@]}"; do
  name="$(basename "$p")"
  # --3way 让 git 在上下文变动时用三方合并，比纯 apply 更能容错
  if git -C "$SRC_DIR" apply --3way --whitespace=nowarn "$p"; then
    log "  ✓ $name"
  else
    err "  ✗ $name 应用失败"
    err "    基线 SHA 可能与补丁生成时不一致，或官方改动与补丁冲突。"
    err "    处理：手动解决冲突后运行 make-patches.sh 重新导出。"
    exit 1
  fi
done

log "全部补丁应用完成"
