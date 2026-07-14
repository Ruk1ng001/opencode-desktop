#!/usr/bin/env bash
# 补丁重放脚本：把 brand/patches/ 下的 .patch 按 NN- 前缀顺序，累积应用到
# opencode/ submodule（基线应为 brand/BASE_SHA）。是 update.sh 承诺的「apply
# 脚本」（见 update.sh 末尾提示），用于「submodule 锁上游 + 薄叠加层」中的重放环节。
#
# 自包含：不依赖 common.sh / manifest 解析；按 brand/patches/ 目录内 .patch 的
#         NN 序枚举（文件系统即真相，避免解析带大量注释的 manifest 出错）。
#
# 两种模式：
#   scripts/apply-patches.sh            # 【apply】在 opencode/ 内真实落地补丁（发布 / 编译前重放）
#   scripts/apply-patches.sh --check    # 【check】在临时 worktree 里从 BASE_SHA 累积重放做验证，
#                                       #          逐个报告 OK/FAIL，完事删 worktree，绝不碰 opencode/ 工作区
#   scripts/apply-patches.sh -h | --help
#
# 为什么 check 用临时 worktree：补丁是「按序累积」的（11 依赖 02/03 改过的
#   electron.vite.config.ts、12 依赖 03 改过的 server.ts）。单个 `git apply --check`
#   对干净基线跑会假 FAIL；必须真实按序落地才能验证。worktree 让验证不污染
#   opencode/ 当前状态。
#
# 退出码：
#   0  全部补丁应用成功（apply 落地 / check 验证通过）
#   非 0  某补丁应用失败（apply 模式停在首个失败；check 模式跑完全部再汇总失败）
#
# apply / check 的 git apply 语义不同（刻意为之）：
#   - apply（发布 / CI 重放）：strict `git apply`，补丁须精确适用，fuzzy 成功=隐患→硬失败；
#   - check（维护者验证）：`git apply --3way`，上下文轻微漂移时三方合并兜底，作诊断信号。
#   故本地 --check 通过≈CI 大概率能过，但以 apply(strict) 为最终判据。
#
# 不变式：不提交、不改 brand/patches/。apply 模式会弄脏 opencode/ 工作区（这是重放的
#         目的，gitlink 保持指向 BASE_SHA，编译取工作区文件）；check 模式零副作用。
set -euo pipefail

# —— 路径解析（不依赖调用时 cwd）——
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/opencode"
BRAND_DIR="$PROJECT_ROOT/brand"
PATCHES_DIR="$BRAND_DIR/patches"
BASE_SHA_FILE="$BRAND_DIR/BASE_SHA"

# —— 日志（对齐 update.sh）——
log()  { printf '\033[36m[cx]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[cx]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[cx]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

read_base_sha() { tr -d '[:space:]' < "$BASE_SHA_FILE" 2>/dev/null || true; }

# check 模式的临时 worktree 清理钩子（脚本级，供 EXIT trap 调用）。
# CHECK_WT 可能未定义（check 尚未走到建 worktree），故用 ${CHECK_WT:-} 兜底避开 set -u。
CHECK_WT=""
cleanup_wt() {
  [ -n "${CHECK_WT:-}" ] || return 0
  git -C "$SRC_DIR" worktree remove --force "$CHECK_WT" >/dev/null 2>&1 || true
  rm -rf "$CHECK_WT" >/dev/null 2>&1 || true
}

# 按 NN 序列出所有补丁的绝对路径（无补丁则空）。
list_patches() {
  # LC_ALL=C 保证 02-,03-... 稳定字典序（等价 NN 序）。
  LC_ALL=C ls "$PATCHES_DIR"/*.patch 2>/dev/null | LC_ALL=C sort || true
}

# —— check 模式：临时 worktree 里从 BASE_SHA 累积重放，逐个报告 ——
run_check() {
  local base_sha; base_sha="$(read_base_sha)"
  [ -n "$base_sha" ] || die "读取基线 SHA 失败：$BASE_SHA_FILE"

  # submodule 里必须能找到 BASE_SHA 这个 commit（否则 worktree 建不出来）
  git -C "$SRC_DIR" cat-file -e "${base_sha}^{commit}" 2>/dev/null \
    || die "opencode/ 内找不到基线 commit $base_sha（先 git submodule update --init）。"

  # worktree 路径提到脚本级（trap 在函数 return 后于全局作用域触发，local 会出作用域）
  CHECK_WT="$(mktemp -d "${TMPDIR:-/tmp}/cx-apply-check.XXXXXX")"
  trap cleanup_wt EXIT

  log "check：在临时 worktree 从基线 $base_sha 累积重放（不碰 opencode/ 工作区）"
  git -C "$SRC_DIR" worktree add --detach "$CHECK_WT" "$base_sha" >/dev/null 2>&1 \
    || die "创建临时 worktree 失败（基线 $base_sha）。"

  local fails=0 total=0 p name
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    total=$((total + 1))
    name="$(basename "$p")"
    if git -C "$CHECK_WT" apply --3way "$p" >/dev/null 2>&1; then
      printf 'OK    %s\n' "$name"
    else
      fails=$((fails + 1))
      printf 'FAIL  %s\n' "$name"
      # 把 git 的具体报错缩进打出来，便于定位
      git -C "$CHECK_WT" apply --3way "$p" 2>&1 | sed 's/^/        /' || true
    fi
  done < <(list_patches)

  if [ "$total" -eq 0 ]; then
    warn "brand/patches/ 下没有 .patch，无补丁可验证。"
    return 0
  fi
  if [ "$fails" -eq 0 ]; then
    log "check 通过：$total 个补丁按序累积应用零冲突。"
    return 0
  fi
  err "check 失败：$total 个补丁中 $fails 个应用失败（见上）。"
  return 1
}

# —— apply 模式：在 opencode/ 内真实按序落地 ——
run_apply() {
  local base_sha head
  base_sha="$(read_base_sha)"
  head="$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)"

  # 工作区必须干净，否则可能是「已重放过」或有手改，重复 apply 会 already-applied 报错
  if [ -n "$(git -C "$SRC_DIR" status --porcelain 2>/dev/null)" ]; then
    err "opencode/ 工作区非干净——可能已重放过补丁或有手改。"
    err "如需重新重放，先 git -C opencode checkout -f . && git -C opencode clean -fd。"
    exit 1
  fi
  # 提示（非致命）：当前 HEAD 与基线 SHA 不一致时补丁上下文可能对不上
  if [ -n "$base_sha" ] && [ -n "$head" ] && [ "$head" != "$base_sha" ]; then
    warn "opencode/ HEAD ($head) 与基线 BASE_SHA ($base_sha) 不一致，补丁可能不适用。"
  fi

  local total=0 p name
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    total=$((total + 1))
    name="$(basename "$p")"
    # strict apply（不带 --3way）：补丁必须精确适用。与 release.yml / auto-upgrade.yml
    # 的 CI 重放语义一致——fuzzy 兜底成功往往是上游漂移的隐患，发布路径宁可硬失败。
    # （check 模式用 --3way 容错，是给维护者的诊断信号，语义不同故不共用。）
    if git -C "$SRC_DIR" apply "$p" >/dev/null 2>&1; then
      log "应用 $name"
    else
      err "应用 $name 失败："
      git -C "$SRC_DIR" apply "$p" 2>&1 | sed 's/^/        /' >&2 || true
      die "重放中断于 $name（前序补丁改动已落在 opencode/ 工作区，可 checkout -f 回退）。"
    fi
  done < <(list_patches)

  [ "$total" -gt 0 ] || { warn "brand/patches/ 下没有 .patch，无补丁可应用。"; return 0; }
  log "已按序落地 $total 个补丁到 opencode/（gitlink 仍指向基线，编译取工作区文件）。"
}

main() {
  local mode="apply"
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --check)   mode="check" ;;
    "")        mode="apply" ;;
    *)         die "未知参数：$1（用 -h 查看用法）。" ;;
  esac

  [ -d "$SRC_DIR/.git" ] || [ -f "$SRC_DIR/.git" ] \
    || die "找不到已初始化的 submodule：$SRC_DIR（先 git submodule update --init）。"
  [ -d "$PATCHES_DIR" ] || die "找不到补丁目录：$PATCHES_DIR"

  if [ "$mode" = "check" ]; then
    run_check
  else
    run_apply
  fi
}

main "$@"
