#!/usr/bin/env bash
# 通过 J-Link SWD 烧录固件（唯一可行的烧录方式）
# Flash over J-Link SWD — the only working method on these dongles.
#
# 用法 / Usage:
#   ./scripts/flash.sh [elf 路径]
#   PROBE=1366:0101 ./scripts/flash.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ELF="${1:-$ROOT/out/opensk-nrf52840dongle.elf}"
[ -f "$ELF" ] || ELF="$ROOT/firmware/opensk-nrf52840dongle.elf"

PROBE_RS="${PROBE_RS:-probe-rs}"   # 不在 PATH 里就传 PROBE_RS=/path/to/probe-rs
CHIP="nRF52840_xxAA"
PROBE="${PROBE:-1366:0101}"        # 多台 J-Link 时用 1366:0101:<序列号>（probe-rs list 可查）

command -v "$PROBE_RS" >/dev/null 2>&1 || [ -x "$PROBE_RS" ] || {
  echo "错误: 找不到 probe-rs（当前为 '$PROBE_RS'）。装好后加进 PATH，或 PROBE_RS=/path/to/probe-rs 指定" >&2
  exit 1
}

if [ ! -f "$ELF" ]; then
  echo "错误: 找不到固件。先跑 ./scripts/build.sh，或确认 firmware/ 下有 ELF" >&2
  exit 1
fi

cat <<EOF
将要烧录：
  固件 $ELF
  芯片 $CHIP
  探针 $PROBE

提醒：
  * dongle 的 USB 必须拔掉（由 J-Link 的 VDD 供电，避免双供电冲突）
  * --allow-erase-all 是【全片擦除】：固件、凭据、PIN、UICR 全部重置
  * 如果设备已开 APPROTECT，这条命令会失败 —— 改用 ./scripts/recover.sh
EOF
echo

set +e
"$PROBE_RS" info --probe "$PROBE" >/tmp/pr_info.txt 2>&1
INFO=$?
set -e
if [ $INFO -ne 0 ]; then
  echo "!! 无法 attach 到芯片。两种可能：" >&2
  echo "   1) 接线/供电问题（检查 GND/CLK/DIO/VDD，或先跑 probe-rs list）" >&2
  echo "   2) 设备已开启 APPROTECT（读保护）→ 请用 ./scripts/recover.sh" >&2
  sed 's/^/     /' /tmp/pr_info.txt >&2
  exit 1
fi

set +e
"$PROBE_RS" download --chip "$CHIP" --probe "$PROBE" \
  --allow-erase-all --binary-format elf --verify --reset "$ELF"
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo >&2
  echo "!! 烧录失败。常见原因：" >&2
  echo "   - 设备已开 APPROTECT → 用 ./scripts/recover.sh" >&2
  echo "   - 用了 hex 文件 → 请用 ELF（本脚本已默认 ELF）" >&2
  echo "   - 接线松/供电不足 → 重插杜邦线后重试" >&2
  exit $RC
fi

cat <<'EOF'

==> 烧录完成
现在请：
  1) 拔掉 J-Link 的 4 根杜邦线（不拔可能影响 USB 枚举）
  2) 把 dongle 的 USB 插到电脑
  3) ./scripts/verify.sh        验证是否枚举成 FIDO HID
EOF
