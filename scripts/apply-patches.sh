#!/usr/bin/env bash
# 把本项目所需的所有源码补丁打到一份干净的 OpenSK 克隆上
# Apply all source patches onto a clean OpenSK checkout.
#
# 用法 / Usage:
#   ./scripts/apply-patches.sh /path/to/OpenSK
#
# 前置 / Requires:
#   OpenSK  develop 分支, commit f53621c 附近
#   wasefire 子模块 commit 1e46740ed6fe9b9900606454928bd3ae8c11cc7e
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPEN="${1:-}"

if [ -z "$OPEN" ]; then
  echo "用法: $0 <OpenSK 仓库路径>" >&2
  echo "Usage: $0 <path-to-OpenSK-clone>" >&2
  exit 1
fi
if [ ! -d "$OPEN/.git" ]; then
  echo "错误: $OPEN 不是一个 git 仓库" >&2
  exit 1
fi

WF="$OPEN/third_party/wasefire"
if [ ! -d "$WF" ]; then
  echo "错误: 找不到 wasefire 子模块，请先 git submodule update --init --recursive" >&2
  exit 1
fi

echo "==> OpenSK:  $OPEN"
echo "==> wasefire: $WF"
echo

apply() { # $1=repo dir  $2=patch file
  local repo="$1" patch="$2" name
  name="$(basename "$patch")"
  printf '  %-42s ' "$name"
  if git -C "$repo" apply --check "$patch" 2>/dev/null; then
    git -C "$repo" apply --ignore-whitespace "$patch"
    echo "applied"
  elif git -C "$repo" apply --reverse --check "$patch" 2>/dev/null; then
    echo "already applied (skipped)"
  else
    echo "FAILED"
    echo "    请手动检查：git -C \"$repo\" apply --check \"$patch\"" >&2
    return 1
  fi
}

echo "[1/3] OpenSK 主仓补丁"
apply "$OPEN" "$ROOT/patches/0001-opensk-toolchain-touch.patch"

echo "[2/3] wasefire 子模块补丁"
apply "$WF" "$ROOT/patches/0002-wasefire-toolchain.patch"
apply "$WF" "$ROOT/patches/0003-wasefire-windows-port.patch"
apply "$WF" "$ROOT/patches/0004-wasefire-panic-abort.patch"

echo "[3/3] 放入 panic-abort 修复 crate（0004 补丁引用了它）"
mkdir -p "$WF/patches"
rm -rf "$WF/patches/panic-abort"
cp -r "$ROOT/vendor/panic-abort" "$WF/patches/panic-abort"
echo "  -> $WF/patches/panic-abort"

echo
echo "完成。核对以下三处："
echo "  grep -n 'nightly'      \"$OPEN/rust-toolchain.toml\" \"$WF/rust-toolchain.toml\""
echo "  grep -n 'is_present' -A2 \"$OPEN/src/touch.rs\"          # 应返回 true"
echo "  ls \"$WF/patches/panic-abort/src/lib.rs\""
