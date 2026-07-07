#!/usr/bin/env bash
# 把 codex/ 强制还原到锁定的官方基线 SHA，丢弃所有本地改动。
# 用途：导出补丁后清场，或应用补丁前确保干净基线。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BASE_SHA="$(read_base_sha)"
log "还原 codex/ 到基线 $BASE_SHA"

# 丢弃工作区改动 + 未跟踪文件，回到基线 commit
git -C "$SRC_DIR" reset --hard "$BASE_SHA"
git -C "$SRC_DIR" clean -fd

log "codex/ 已回到干净基线"
