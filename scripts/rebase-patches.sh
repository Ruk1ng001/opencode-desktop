#!/usr/bin/env bash
# 补丁栈 rebase 脚本：把 brand/patches/*.patch 整体 rebase 到 opencode 上游新 tag。
#
# 背景：opencode submodule 锁在 brand/BASE_SHA；定制以 NN 序补丁叠加。上游发新版时，
# 补丁改到的「上游已有文件」可能漂移（上下文行偏移 / 逻辑冲突），strict apply 失败。
# 本脚本把「这次手工 rebase 到 v1.18.4」的流程固化成一条命令，只把真正需要人判断的
# 环节（解冲突 hunk）留给维护者，其余全自动。
#
# 两阶段用法（因解冲突必须人工，故拆两步）：
#   scripts/rebase-patches.sh plan v1.18.4     # ① 在 v1.18.4 worktree 逐补丁重放，
#                                              #    冲突处停下、落 .rej、报告。可反复重跑。
#   （维护者手工解 worktree 里的冲突文件 + 删对应 .rej）
#   scripts/rebase-patches.sh finish           # ② 重导出所有漂移补丁（保留注释头）、
#                                              #    刷新 BASE_TAG/BASE_SHA、跑 --check 验证。
#
#   scripts/rebase-patches.sh status           # 查看当前 rebase 进度（worktree / 待解冲突）
#   scripts/rebase-patches.sh abort            # 放弃：删 worktree 与状态，不改任何受控文件
#   scripts/rebase-patches.sh -h | --help
#
# 设计不变式：
#   - 官方源码零手改承诺不变；本脚本只在临时 worktree 里操作，最终产物是 brand/patches/*、
#     brand/BASE_TAG、brand/BASE_SHA、父仓 opencode gitlink。
#   - 不自动提交、不自动推送——由维护者审阅 diff 后决定。
#   - 幂等/可恢复：plan 可反复重跑；中途放弃用 abort 清理，绝不留半污染状态。
#   - 复用现成脚本：apply-patches.sh（--preflight/--check）、export-patch.sh（导出+strict 验证）、
#     validate-patch.py（结构校验）。不重复实现这些逻辑。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/opencode"
BRAND_DIR="$PROJECT_ROOT/brand"
PATCHES_DIR="$BRAND_DIR/patches"
MANIFEST_FILE="$BRAND_DIR/patches.manifest"
BASE_TAG_FILE="$BRAND_DIR/BASE_TAG"
BASE_SHA_FILE="$BRAND_DIR/BASE_SHA"
APPLY_SCRIPT="$SCRIPT_DIR/apply-patches.sh"
EXPORT_SCRIPT="$SCRIPT_DIR/export-patch.sh"
VALIDATE_PY="$SCRIPT_DIR/validate-patch.py"

# rebase 中间态：worktree 与进度记录都放这，abort 一删了之。
WORKTREE=".tmp-rebase"                        # 相对 SRC_DIR
WORKTREE_ABS="$SRC_DIR/$WORKTREE"
STATE_DIR="$PROJECT_ROOT/.rebase-state"       # 父仓内、gitignore 外亦无妨（abort 会删）
STATE_TARGET="$STATE_DIR/target-tag"          # 目标 tag
STATE_TARGET_SHA="$STATE_DIR/target-sha"      # 目标 tag 的 commit SHA
STATE_DRIFT="$STATE_DIR/drifted"              # 需重导出的补丁名（每行一个，无 .patch 后缀）
STATE_CKPT="$STATE_DIR/checkpoints"           # 「补丁名<TAB>pre-N 检查点 SHA」
STATE_CONFLICT="$STATE_DIR/conflict"          # 当前卡住待人工解的补丁名（空=无）

PREFIX="rebase"
log()  { printf '\033[36m[%s]\033[0m %s\n' "$PREFIX" "$*"; }
warn() { printf '\033[33m[%s]\033[0m %s\n' "$PREFIX" "$*" >&2; }
err()  { printf '\033[31m[%s]\033[0m %s\n' "$PREFIX" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

read_base_tag() { tr -d '[:space:]' < "$BASE_TAG_FILE" 2>/dev/null || true; }
read_base_sha() { tr -d '[:space:]' < "$BASE_SHA_FILE" 2>/dev/null || true; }

# 上游 URL（同 update.sh 策略：优先 env，再 .gitmodules，最后公开 HTTPS）。
resolve_upstream_url() {
  if [ -n "${CX_UPSTREAM_URL:-}" ]; then printf '%s\n' "$CX_UPSTREAM_URL"; return 0; fi
  local u
  u="$(git -C "$PROJECT_ROOT" config -f .gitmodules submodule.opencode.url 2>/dev/null || true)"
  [ -n "$u" ] && { printf '%s\n' "$u"; return 0; }
  printf '%s\n' "https://github.com/anomalyco/opencode.git"
}

# 补丁文件按 NN 序列出（全路径）。
list_patches() {
  find "$PATCHES_DIR" -maxdepth 1 -type f -name '*.patch' -print 2>/dev/null | LC_ALL=C sort
}

# 从补丁名（无后缀）拿全路径。
patch_path() { printf '%s/%s.patch\n' "$PATCHES_DIR" "$1"; }

# 补丁的注释头行数（第一个 diff --git 之前，全为 # 或空行）。无头返回 0。
patch_header_lines() {
  local p="$1"
  awk 'BEGIN{n=0} /^diff --git /{print n; exit} {n++} END{if(NR==0||n==NR)print n}' "$p"
}

# 抽出补丁注释头（不含 diff 正文）。无头则输出空。
extract_patch_header() {
  local p="$1" n
  n="$(patch_header_lines "$p")"
  [ "$n" -gt 0 ] && sed -n "1,${n}p" "$p"
}

# 从 manifest 提取某 section 的文件列表（相对 opencode/）。
manifest_files_for() {
  local name="$1"
  awk -v s="[$name]" '
    $0==s {f=1; next}
    /^\[/ {f=0}
    f && NF && $0 !~ /^#/ {print}
  ' "$MANIFEST_FILE"
}

require_clean_submodule() {
  # 忽略脚本自己的 worktree 目录（.tmp-rebase/）——它是 rebase 中间产物，不是用户未导出的改动。
  # 排除它才能让 plan 在上次残留 worktree 存在时仍可清理并继续（否则死锁：清不掉又过不了检查）。
  if [ -n "$(git -C "$SRC_DIR" status --porcelain -- . ":(exclude)$WORKTREE" 2>/dev/null)" ]; then
    err "opencode/ 有未提交改动，拒绝 rebase（先导出到 brand/patches/ 或 checkout -f 回退）。"
    git -C "$SRC_DIR" status --short -- . ":(exclude)$WORKTREE" >&2
    exit 1
  fi
}

worktree_exists() {
  git -C "$SRC_DIR" worktree list --porcelain 2>/dev/null \
    | grep -qxF "worktree $WORKTREE_ABS"
}

remove_worktree() {
  worktree_exists && git -C "$SRC_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$WORKTREE_ABS" >/dev/null 2>&1 || true
}

# ── plan：在目标 tag 的 worktree 逐补丁重放，冲突处停下 ────────────────────────
cmd_plan() {
  local target_tag="${1:-}"
  [ -n "$target_tag" ] || die "plan 需要目标 tag，例：scripts/rebase-patches.sh plan v1.18.4"

  [ -x "$APPLY_SCRIPT" ] || die "缺少 $APPLY_SCRIPT"
  [ -x "$EXPORT_SCRIPT" ] || die "缺少 $EXPORT_SCRIPT"
  [ -f "$MANIFEST_FILE" ] || die "缺少 manifest：$MANIFEST_FILE"

  # 先清掉上次残留的自有 worktree（否则它会被下面的洁净检查当成未提交改动而卡死）。
  remove_worktree
  require_clean_submodule

  # 先做零副作用预检：补丁语法坏就别开工。
  log "预检补丁语法与 manifest 一致性…"
  "$APPLY_SCRIPT" --preflight || die "preflight 失败，先修补丁再 rebase。"

  local url; url="$(resolve_upstream_url)"

  # 确保本地有目标 tag（本地无则从上游拉）。
  if ! git -C "$SRC_DIR" rev-parse -q --verify "refs/tags/${target_tag}" >/dev/null 2>&1; then
    log "本地无 tag ${target_tag}，从上游拉取：$url"
    git -C "$SRC_DIR" fetch --force "$url" \
      "refs/tags/${target_tag}:refs/tags/${target_tag}" >/dev/null 2>&1 \
      || die "拉取 tag ${target_tag} 失败：$url"
  fi
  local target_sha
  target_sha="$(git -C "$SRC_DIR" rev-parse "refs/tags/${target_tag}^{commit}" 2>/dev/null || true)"
  [ -n "$target_sha" ] || die "解析 tag ${target_tag} 的 commit SHA 失败。"

  # 干净起步：清旧 worktree 与状态。
  remove_worktree
  rm -rf "$STATE_DIR"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$target_tag" > "$STATE_TARGET"
  printf '%s\n' "$target_sha" > "$STATE_TARGET_SHA"
  : > "$STATE_DRIFT"
  : > "$STATE_CKPT"

  log "在 ${target_tag}（${target_sha}）建临时 worktree：$WORKTREE"
  git -C "$SRC_DIR" worktree add --detach "$WORKTREE" "$target_sha" >/dev/null 2>&1 \
    || die "创建 worktree 失败。"

  local wt="$WORKTREE_ABS"
  # worktree 内提交需要身份；用临时局部身份，绝不碰全局配置。
  git -C "$wt" config user.email "rebase@local" >/dev/null 2>&1 || true
  git -C "$wt" config user.name "rebase-bot" >/dev/null 2>&1 || true

  # 从第 1 个补丁开始重放。冲突则停在该补丁、留 .rej，等 continue。
  replay_from 1
}

# 从第 idx 个补丁（1-based，按 NN 序）开始逐补丁重放到 worktree。
# 每个补丁：strict → 3way → --reject 三级降级；strict/3way 成功即提交检查点并继续；
# --reject 落 .rej 后记录断点（STATE_CONFLICT）并 return，等维护者解冲突后 continue。
# 全部落地无残留 .rej 时打印 finish 引导。
replay_from() {
  local start_idx="$1" wt="$WORKTREE_ABS"
  local -a patches=()
  local p
  while IFS= read -r p; do [ -n "$p" ] && patches+=("$p"); done < <(list_patches)

  local total="${#patches[@]}" i name patch
  for (( i = start_idx; i <= total; i++ )); do
    patch="${patches[$((i-1))]}"
    name="$(basename "$patch" .patch)"

    # 记录 pre-N 检查点（当前 worktree HEAD）——供 finish 阶段按区间导出。
    local ckpt
    ckpt="$(git -C "$wt" rev-parse HEAD)"
    printf '%s\t%s\n' "$name" "$ckpt" >> "$STATE_CKPT"

    # ① strict：干净适用则直接落地，不算漂移。
    if git -C "$wt" apply "$patch" >/dev/null 2>&1; then
      git -C "$wt" add -A >/dev/null 2>&1
      git -C "$wt" commit -q -m "cp: $name (strict)" --allow-empty
      printf 'STRICT  %s\n' "$name"
      continue
    fi

    # ② 3way：能自动合并 → 落地并标记为「漂移，需重导出」。
    if git -C "$wt" apply --3way "$patch" >/dev/null 2>&1; then
      git -C "$wt" add -A >/dev/null 2>&1
      git -C "$wt" commit -q -m "cp: $name (3way)" --allow-empty
      printf '%s\n' "$name" >> "$STATE_DRIFT"
      printf '3WAY    %s  ← 上下文漂移，将重导出\n' "$name"
      continue
    fi

    # ③ 冲突：--reject 落干净 hunk + .rej，停下让人工解。
    # 注意：--reject 与 --3way 互斥（同用会报 "cannot be used together" 直接失败）。
    # 此处走纯 --reject——② 的 3way 已整体失败，此处只求把能干净套上的 hunk 落地、
    # 冲突 hunk 写成 .rej 供人工补。冲突文件保持上游原状 + .rej，不留半合并的 <<<< 标记。
    git -C "$wt" apply --reject "$patch" >/dev/null 2>&1 || true
    printf '%s\n' "$name" >> "$STATE_DRIFT"
    # 记录断点：continue 时从这个补丁的下一个继续（本补丁由 continue 提交）。
    printf '%s\t%s\n' "$name" "$i" > "$STATE_CONFLICT"
    printf 'CONFLICT %s  ← 需人工解冲突\n' "$name" >&2

    local rejects
    rejects="$(cd "$wt" && find . -name '*.rej' 2>/dev/null | sed 's#^\./##' | LC_ALL=C sort)"
    warn ""
    warn "补丁 ${name} 有冲突 hunk 无法自动合并（已重放 ${i}/${total}，其后补丁尚未重放）。"
    warn "请人工处理："
    warn "  1. 进入 worktree：cd $wt"
    warn "  2. 按下列 .rej 手工把改动补进对应源文件："
    printf '%s\n' "$rejects" | sed 's/^/         - /' >&2
    warn "  3. 改完后删除对应 .rej 文件。"
    warn "  4. 回项目根运行：scripts/rebase-patches.sh continue"
    warn "     （提交本补丁 + 从下一个补丁继续重放；再遇冲突会再次停下）"
    warn ""
    warn "放弃本次 rebase：scripts/rebase-patches.sh abort"
    return 0
  done

  # 全部补丁无残留冲突落地。
  rm -f "$STATE_CONFLICT"
  local nrej
  nrej="$(cd "$wt" && find . -name '*.rej' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [ "$nrej" != "0" ]; then
    warn "worktree 仍有 $nrej 个 .rej 未清理，解完再 continue。"
    return 0
  fi

  local target_tag; target_tag="$(cat "$STATE_TARGET" 2>/dev/null || echo '?')"
  log "全部补丁已在 ${target_tag} 落地，无残留冲突。"
  local ndrift
  ndrift="$(sed '/^$/d' "$STATE_DRIFT" | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')"
  if [ "$ndrift" = "0" ]; then
    log "没有补丁漂移——理论上无需重导出，但仍建议 finish 以刷新 BASE 并跑 --check。"
  else
    log "有 $ndrift 个补丁漂移，将在 finish 阶段重导出："
    sed '/^$/d' "$STATE_DRIFT" | LC_ALL=C sort -u | sed 's/^/         - /'
  fi
  log "下一步：scripts/rebase-patches.sh finish"
}

# ── continue：提交已解冲突的补丁，从断点继续重放 ─────────────────────────────
cmd_continue() {
  [ -d "$STATE_DIR" ] || die "没有进行中的 rebase（先跑 plan）。"
  worktree_exists || die "找不到 rebase worktree（可能已被清理，abort 后重跑 plan）。"
  [ -f "$STATE_CONFLICT" ] || die "当前没有待解冲突的断点（若已全部落地，直接 finish）。"

  local wt="$WORKTREE_ABS" cname cidx
  cname="$(cut -f1 "$STATE_CONFLICT")"
  cidx="$(cut -f2 "$STATE_CONFLICT")"
  [ -n "$cname" ] && [ -n "$cidx" ] || die "断点状态损坏，abort 后重跑 plan。"

  # 冲突必须全解完（无 .rej）才能继续。
  local nrej
  nrej="$(cd "$wt" && find . -name '*.rej' 2>/dev/null | wc -l | tr -d '[:space:]')"
  [ "$nrej" = "0" ] || {
    err "worktree 仍有 $nrej 个 .rej 未解，解完再 continue："
    (cd "$wt" && find . -name '*.rej' 2>/dev/null | sed 's#^\./#         - #') >&2
    exit 1
  }

  # 提交手工解好的当前补丁（cname）为它的检查点。
  git -C "$wt" add -A >/dev/null 2>&1
  git -C "$wt" commit -q -m "cp: $cname (manual)" --allow-empty
  log "已提交手工解冲突的补丁：$cname"
  rm -f "$STATE_CONFLICT"

  # 从下一个补丁继续重放。
  replay_from "$((cidx + 1))"
}

# ── finish：重导出漂移补丁 + 刷新 BASE + --check ─────────────────────────────
cmd_finish() {
  [ -d "$STATE_DIR" ] || die "没有进行中的 rebase（先跑 plan）。"
  worktree_exists || die "找不到 rebase worktree（可能已被清理，重跑 plan）。"

  local target_tag target_sha wt="$WORKTREE_ABS"
  target_tag="$(cat "$STATE_TARGET" 2>/dev/null || true)"
  target_sha="$(cat "$STATE_TARGET_SHA" 2>/dev/null || true)"
  [ -n "$target_tag" ] && [ -n "$target_sha" ] || die "状态文件损坏，abort 后重跑 plan。"

  # 冲突必须全解完（无 .rej）。
  local nrej
  nrej="$(cd "$wt" && find . -name '*.rej' 2>/dev/null | wc -l | tr -d '[:space:]')"
  [ "$nrej" = "0" ] || die "worktree 仍有 $nrej 个 .rej 未解，解完再 finish。"

  # 把最终工作区（含手工解冲突结果）提交为终态检查点——供漂移补丁按区间导出。
  git -C "$wt" add -A >/dev/null 2>&1
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    git -C "$wt" commit -q -m "final: all patches (with manual conflict resolution)" --allow-empty
  fi

  # 逐个漂移补丁重导出：以 pre-N 检查点为基线，diff 出该补丁覆盖的文件，拼回注释头。
  local drift_list
  drift_list="$(sed '/^$/d' "$STATE_DRIFT" | LC_ALL=C sort -u || true)"

  if [ -z "$drift_list" ]; then
    log "无漂移补丁需重导出。"
  else
    local name ckpt final tmp header files_line
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      final="$(patch_path "$name")"
      [ -f "$final" ] || die "补丁不存在：$final"

      ckpt="$(awk -F'\t' -v n="$name" '$1==n{print $2; exit}' "$STATE_CKPT")"
      [ -n "$ckpt" ] || die "找不到 ${name} 的 pre-N 检查点 SHA。"

      # post-N 检查点：pre-N 在通往 HEAD 线性历史上的直接子提交（= 应用补丁 N 后那次 commit）。
      # 重导出必须 diff「pre-N → post-N」，绝不能 diff「pre-N → HEAD(终态)」——后者会把 N 之后
      # 补丁对共享文件（如 07 与 17 共享 layout-new.tsx / cx-account-launcher.tsx）的改动一并
      # 算进 N，导致 strict 重放时 N 抢先写成终态、后续补丁 "does not apply"。历史严格线性
      # （每补丁一个 cp 提交），--ancestry-path 取 ckpt..HEAD 路径上最旧一个即 post-N。
      local post
      # sed -n 1p（非 head -1）：读完整个流不提前关闭管道，避免 rev-list 收 SIGPIPE 在
      # pipefail+set -e 下误触发 die。取 --ancestry-path 路径上最旧一个提交即 post-N。
      post="$(git -C "$wt" rev-list --reverse --ancestry-path "${ckpt}..HEAD" 2>/dev/null | sed -n 1p)"
      [ -n "$post" ] || die "找不到 ${name} 的 post-N 检查点（pre-N=${ckpt} 无子提交）。"

      # manifest 里该补丁覆盖的文件（相对 opencode/）。
      local -a files=()
      while IFS= read -r files_line; do
        [ -n "$files_line" ] && files+=("$files_line")
      done < <(manifest_files_for "$name")
      [ "${#files[@]}" -gt 0 ] || die "manifest 中 [$name] 没有文件列表。"

      # 新增文件需 intent-to-add 才进 git diff（不改 index 内容）。
      local f
      for f in "${files[@]}"; do
        if ! git -C "$wt" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
          git -C "$wt" add -N -- "$f" >/dev/null 2>&1 || true
        fi
      done

      # 抽出旧补丁的注释头（重导出后拼回）。
      header="$(extract_patch_header "$final" || true)"

      tmp="$(mktemp "${TMPDIR:-/tmp}/rebase-export.XXXXXX")"
      {
        [ -n "$header" ] && printf '%s\n' "$header"
        git -C "$wt" diff --binary "$ckpt" "$post" -- "${files[@]}"
      } > "$tmp"

      # 结构校验：拼头后仍须是合法 unified diff（注释头是 git apply 容忍的前导文本）。
      if ! python3 "$VALIDATE_PY" "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        die "重导出的 ${name} 不是结构合法的 unified diff。"
      fi
      # git apply 解析校验（在目标 tag worktree 的 pre-N 检查点上）。
      if ! git -C "$wt" apply --numstat "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        die "重导出的 ${name} 无法被 git apply 解析。"
      fi

      mv -f "$tmp" "$final"
      log "已重导出：$name"
    done < <(printf '%s\n' "$drift_list")
  fi

  # 刷新基线锁定文件（末尾保留换行，同 update.sh 约定）。
  printf '%s\n' "$target_tag" > "$BASE_TAG_FILE"
  printf '%s\n' "$target_sha" > "$BASE_SHA_FILE"
  log "已刷新基线：BASE_TAG=$target_tag  BASE_SHA=$target_sha"

  # 把父仓 submodule 切到目标 tag 并暂存 gitlink（供本地一致、CI 干净跟随）。
  require_clean_submodule
  git -C "$SRC_DIR" checkout -f "refs/tags/${target_tag}" >/dev/null 2>&1 \
    || die "把主 submodule 切到 ${target_tag} 失败。"
  git -C "$SRC_DIR" clean -fd >/dev/null 2>&1 || true
  git -C "$PROJECT_ROOT" add opencode >/dev/null 2>&1 || true

  # 清理 worktree 与状态（BASE 已刷新，检查点不再需要）。
  remove_worktree
  rm -rf "$STATE_DIR"

  # 最终 CI 等价验证：从新 BASE_SHA strict 重放全部补丁。
  log "跑 CI 等价 strict 重放验证（--check）…"
  if "$APPLY_SCRIPT" --check; then
    log "rebase 完成：补丁栈已 rebase 到 ${target_tag}，strict 重放零冲突。"
    log "请审阅改动后提交：git add brand/ opencode && git commit"
  else
    err "--check 失败！补丁栈在新基线上仍有问题，请人工排查（BASE 已刷新，可 git checkout 回退）。"
    return 1
  fi
}

cmd_status() {
  if [ ! -d "$STATE_DIR" ]; then
    log "当前没有进行中的 rebase。"
    return 0
  fi
  local target_tag; target_tag="$(cat "$STATE_TARGET" 2>/dev/null || echo '?')"
  log "进行中的 rebase 目标：$target_tag"
  if worktree_exists; then
    log "worktree：$WORKTREE_ABS"
    local nrej
    nrej="$(cd "$WORKTREE_ABS" && find . -name '*.rej' 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [ "$nrej" != "0" ]; then
      warn "待解冲突 .rej（$nrej 个）："
      (cd "$WORKTREE_ABS" && find . -name '*.rej' 2>/dev/null | sed 's#^\./#         - #') >&2
    else
      log "无残留 .rej，可运行 finish。"
    fi
  else
    warn "worktree 已不存在，建议 abort 后重跑 plan。"
  fi
  if [ -s "$STATE_DRIFT" ]; then
    log "漂移补丁（将重导出）："
    sed '/^$/d' "$STATE_DRIFT" | LC_ALL=C sort -u | sed 's/^/         - /'
  fi
}

cmd_abort() {
  remove_worktree
  rm -rf "$STATE_DIR"
  log "已放弃 rebase：worktree 与状态已清理，brand/ 与 gitlink 未改动。"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    -h|--help|"") usage; [ -z "$cmd" ] && exit 1; exit 0 ;;
  esac
  shift || true

  [ -d "$SRC_DIR/.git" ] || [ -f "$SRC_DIR/.git" ] \
    || die "找不到已初始化的 submodule：$SRC_DIR（先 git submodule update --init）。"

  case "$cmd" in
    plan)     cmd_plan "$@" ;;
    continue) cmd_continue ;;
    finish)   cmd_finish ;;
    status) cmd_status ;;
    abort)  cmd_abort ;;
    *) die "未知子命令：$cmd（用 -h 查看用法）。" ;;
  esac
}

main "$@"
