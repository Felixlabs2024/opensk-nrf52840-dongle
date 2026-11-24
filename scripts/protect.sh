#!/usr/bin/env bash
# 开启 APPROTECT 读保护（保留式写入，不破坏 NRFFW[0] / PSELRESET / 已有凭据）
# Enable APPROTECT while preserving the rest of the UICR page.
#
# 用法 / Usage:
#   ./scripts/protect.sh
#
# 后果 / Consequences:
#   * SWD 从此无法读写 flash（probe-rs info 会报 "could not automatically be determined"）
#   * 以后升级固件必须先 ERASEALL（清空一切）→ ./scripts/recover.sh
#   * 已有 passkey / PIN 不受影响
#   * 不会变砖：ERASEALL 永远可用
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/out}"
mkdir -p "$WORK"

PROBE_RS="${PROBE_RS:-probe-rs}"   # 不在 PATH 里就传 PROBE_RS=/path/to/probe-rs
CHIP="nRF52840_xxAA"
PROBE="${PROBE:-1366:0101}"        # 多台 J-Link 时用 1366:0101:<序列号>（probe-rs list 可查）

command -v "$PROBE_RS" >/dev/null 2>&1 || [ -x "$PROBE_RS" ] || {
  echo "错误: 找不到 probe-rs（当前为 '$PROBE_RS'）。装好后加进 PATH，或 PROBE_RS=/path/to/probe-rs 指定" >&2
  exit 1
}
UICR_BASE=$((0x10001000))
UICR_LEN=1024

PY=""
for c in python python3 py; do command -v "$c" >/dev/null 2>&1 && PY="$c" && break; done
[ -n "$PY" ] || { echo "错误: 需要 python" >&2; exit 1; }

BACKUP="$WORK/uicr_backup_before_protect.bin"
NEWIMG="$WORK/uicr_with_approtect.bin"

echo "==> 1/3 读取 UICR 整页并备份 -> $BACKUP"
"$PROBE_RS" read --chip "$CHIP" --probe "$PROBE" b8 "$UICR_BASE" "$UICR_LEN" \
  -f binary -o "$BACKUP"

echo "==> 2/3 检查关键字段 + 生成新镜像（仅改 APPROTECT 4 字节）"
set +e
"$PY" - "$BACKUP" "$NEWIMG" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
orig = open(src, 'rb').read()
def w(b, o): return int.from_bytes(b[o:o + 4], 'little')

nrffw0, ps1, ps2, ap = w(orig, 0x014), w(orig, 0x200), w(orig, 0x204), w(orig, 0x208)
print("    NRFFW[0]  = 0x%08X   (启动地址，必须原样保留)" % nrffw0)
print("    PSELRESET = 0x%08X / 0x%08X" % (ps1, ps2))
print("    APPROTECT = 0x%08X   %s" % (ap, "已是保护状态" if ap == 0 else "未保护"))

if ap == 0:
    print("    -> 已经是保护状态，无需重复操作。")
    sys.exit(2)

new = bytearray(orig)
new[0x208:0x20C] = b'\x00\x00\x00\x00'
open(dst, 'wb').write(bytes(new))
diff = [hex(i) for i in range(len(orig)) if orig[i] != new[i]]
print("    改动字节 :", diff, "（应为 0x208~0x20b）")
sys.exit(0)
PYEOF
RC=$?
set -e
[ $RC -eq 2 ] && exit 0
[ $RC -ne 0 ] && { echo "错误: 生成镜像失败" >&2; exit 1; }

echo "==> 3/3 写入 UICR（写完后调试口立即锁死，之后不能再做 SWD 操作）"
"$PROBE_RS" download --chip "$CHIP" --probe "$PROBE" \
  --binary-format bin --base-address "$UICR_BASE" --verify "$NEWIMG"

cat <<EOF

==> 完成
请拔掉 SWD 线、插上 dongle 的 USB，然后：
  ./scripts/verify.sh
  \$PROBE_RS info --probe $PROBE    # 应报 could not automatically be determined（说明已锁）
EOF
