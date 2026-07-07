#!/usr/bin/env bash
# 更新跟随脚本（US-012）：把 codex/ submodule 切到指定（或最新）上游 release tag，
# 更新基线锁定文件（brand/BASE_SHA / brand/BASE_TAG），再重放 brand/patches/ 补丁，
# 实现对 openai/codex 的可持续跟随。可本地运行，也可被 CI 复用。
#
# 用法：
#   scripts/update.sh                 # 取上游最新稳定 release tag，有新版本才更新
#   scripts/update.sh rust-v0.143.0   # 指定目标 tag（便于回滚 / 复现，即使与当前一致也重放补丁）
#   scripts/update.sh -h | --help
#
# 环境变量：
#   CX_UPSTREAM_URL   上游仓库地址（默认公开 https，本地/CI 通用，避开 .gitmodules 的 SSH 别名）
#
# 退出码：
#   0  补丁干净重放，codex/ 已切到目标 tag 并叠加补丁，可供后续编译发布
#   0  取最新且已是最新版本（无需更新）
#   非 0  查询失败 / 目标 tag 不存在 / 补丁重放冲突（reject）——此时已回滚到更新前状态，不继续发布
#
# 不变式：官方源码零手改，改动全在 brand/patches/*.patch。更新失败会回滚 BASE 文件与
#         codex/ 到更新前状态，绝不把带冲突标记的文件留在工作区。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

UPSTREAM_URL="${CX_UPSTREAM_URL:-https://github.com/openai/codex.git}"
APPLY_SCRIPT="$SCRIPT_DIR/apply-patches.sh"

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# 查询上游最新稳定 release tag（形如 rust-vX.Y.Z）。
# 过滤 alpha 预发布（rust-vX.Y.Z-alpha.N）与历史畸形 tag（rust-v.0.0.*），按版本号排序取最大。
latest_release_tag() {
  local tags
  tags="$(git ls-remote --tags --refs "$UPSTREAM_URL" 'rust-v*' 2>/dev/null \
            | awk '{print $2}' | sed 's#refs/tags/##' \
            | grep -E '^rust-v[0-9]' | grep -v alpha | grep -vE '^rust-v\.' \
            | sort -V || true)"
  [ -n "$tags" ] && printf '%s\n' "$tags" | tail -1
  return 0
}

# 校验目标 tag 在上游存在，输出其指向的 commit SHA。
# 注意：release tag 是 annotated tag —— ls-remote 会输出两行：
#   <tag对象SHA>       refs/tags/<tag>
#   <commit SHA>       refs/tags/<tag>^{}   （peeled，指向真正的 commit）
# brand/BASE_SHA 锁定的是 commit SHA，故优先取 ^{} 那行；无 peeled 行（lightweight tag）时取本体。
resolve_tag_sha() {
  local tag="$1" peeled plain
  # 不加 --refs：--refs 会把 ^{} peeled 行滤掉，正好丢掉我们要的 commit SHA
  peeled="$(git ls-remote --tags "$UPSTREAM_URL" "refs/tags/${tag}^{}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [ -n "$peeled" ]; then
    printf '%s\n' "$peeled"
    return 0
  fi
  plain="$(git ls-remote --tags "$UPSTREAM_URL" "refs/tags/${tag}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  [ -n "$plain" ] && printf '%s\n' "$plain"
  return 0
}

# 补丁重放冲突时的诊断：在干净基线上逐组重放，定位第一个失败的补丁，
# 打印补丁名与其涉及/冲突的文件，供维护者定位。诊断后由调用方回滚，不留冲突产物。
diagnose_conflict() {
  local base_sha="$1" name p out
  git -C "$SRC_DIR" reset --hard "$base_sha" >/dev/null 2>&1 || true
  git -C "$SRC_DIR" clean -fd >/dev/null 2>&1 || true

  local groups=()
  mapfile -t groups < <(manifest_group_names)
  for name in "${groups[@]}"; do
    p="$PATCHES_DIR/$name.patch"
    if git -C "$SRC_DIR" apply --3way --whitespace=nowarn "$p" >/dev/null 2>&1; then
      continue   # 该补丁能干净重放，继续查下一组
    fi
    # —— 命中冲突的补丁 ——
    err "补丁重放冲突：$name.patch 无法干净应用到目标 tag。"
    err "  冲突补丁：$name.patch"
    err "  补丁涉及的文件："
    git -C "$SRC_DIR" apply --numstat "$p" 2>/dev/null | awk '{print "    - "$3}' >&2 || true
    # 再跑一次并转发 git 的原始报错（含 error: patch failed: <file> / U <file>），便于精确定位
    err "  git apply 冲突详情："
    git -C "$SRC_DIR" apply --3way --whitespace=nowarn "$p" 2>&1 | sed 's/^/    /' >&2 || true
    local conflicted
    conflicted="$(git -C "$SRC_DIR" diff --name-only --diff-filter=U 2>/dev/null || true)"
    if [ -n "$conflicted" ]; then
      err "  留有冲突标记的文件："
      printf '%s\n' "$conflicted" | sed 's/^/    - /' >&2
    fi
    return 0   # 只报告第一个冲突组即可
  done
  return 0
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  local requested_tag="${1:-}"

  # 记录更新前状态，失败时原子回滚（BASE 文件 + codex/ HEAD）
  local orig_sha orig_tag orig_head
  orig_sha="$(read_base_sha)"
  orig_tag="$(read_base_tag)"
  orig_head="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || echo "$orig_sha")"

  rollback() {
    warn "回滚：恢复 brand/BASE_SHA、brand/BASE_TAG 与 codex/ 到更新前状态。"
    printf '%s\n' "$orig_sha" > "$BASE_SHA_FILE"
    printf '%s\n' "$orig_tag" > "$BASE_TAG_FILE"
    git -C "$SRC_DIR" reset --hard "$orig_head" >/dev/null 2>&1 || true
    git -C "$SRC_DIR" clean -fd >/dev/null 2>&1 || true
  }

  # 切换 tag 会覆盖工作区，先确保 codex/ 没有未导出的改动
  ensure_clean_src

  # —— 1. 确定目标 tag ——
  local target_tag explicit=0
  if [ -n "$requested_tag" ]; then
    target_tag="$requested_tag"
    explicit=1
    log "指定目标 tag：$target_tag（当前基线 $orig_tag）"
  else
    log "查询上游最新稳定 release tag：$UPSTREAM_URL"
    target_tag="$(latest_release_tag)"
    [ -n "$target_tag" ] || die "查询上游最新 release tag 失败（网络不可达或无匹配 tag）。"
    log "上游最新稳定 release：$target_tag（当前基线 $orig_tag）"
  fi

  # —— 与当前基线比对 ——
  if [ "$target_tag" = "$orig_tag" ]; then
    if [ "$explicit" -eq 0 ]; then
      log "已是最新版本 $orig_tag，无需更新。"
      exit 0
    fi
    log "目标 tag 与当前基线一致，将重放补丁以复现当前基线。"
  fi

  # —— 2. 校验目标 tag 存在并取其 SHA ——
  local target_sha
  target_sha="$(resolve_tag_sha "$target_tag")"
  [ -n "$target_sha" ] || die "目标 tag 不存在于上游：$target_tag"

  # —— 3. 把 submodule 切到目标 tag ——
  log "拉取并切换 codex/ 到 $target_tag（$target_sha）"
  git -C "$SRC_DIR" fetch --force "$UPSTREAM_URL" \
    "refs/tags/${target_tag}:refs/tags/${target_tag}" >/dev/null 2>&1 \
    || die "从上游拉取 tag $target_tag 失败：$UPSTREAM_URL"
  git -C "$SRC_DIR" checkout -f "refs/tags/${target_tag}" >/dev/null 2>&1 \
    || die "checkout tag $target_tag 失败。"
  git -C "$SRC_DIR" clean -fd >/dev/null 2>&1 || true

  local new_sha
  new_sha="$(git -C "$SRC_DIR" rev-parse HEAD)"
  if [ "$new_sha" != "$target_sha" ]; then
    err "切换后 codex/ HEAD ($new_sha) 与 tag $target_tag 指向的 SHA ($target_sha) 不符。"
    rollback
    exit 1
  fi

  # —— 4. 更新基线锁定文件（保持文件末尾换行格式）——
  printf '%s\n' "$new_sha" > "$BASE_SHA_FILE"
  printf '%s\n' "$target_tag" > "$BASE_TAG_FILE"
  log "已更新基线：brand/BASE_TAG=$target_tag  brand/BASE_SHA=$new_sha"

  # —— 5. 重放补丁（apply-patches.sh 内部会 reset 到新基线再叠加补丁）——
  log "重放品牌补丁 ..."
  if bash "$APPLY_SCRIPT"; then
    log "补丁干净重放成功。codex/ 已切到 $target_tag 并叠加全部补丁，可供后续编译发布。"
    exit 0
  fi

  # —— 补丁冲突（reject）：诊断 → 回滚 → 非 0 退出，不继续发布 ——
  err "补丁重放失败：目标 tag $target_tag 与现有补丁存在冲突。"
  diagnose_conflict "$new_sha"
  err "处理：手动在 codex/ 上把冲突补丁改到能干净应用，再运行 make-patches.sh 重新导出补丁；"
  err "      或先用 scripts/update.sh <较旧 tag> 回滚。发布流程不应在此状态下继续。"
  rollback
  exit 1
}

main "$@"
