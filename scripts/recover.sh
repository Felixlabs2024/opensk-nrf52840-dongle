#!/usr/bin/env bash
# 已开 APPROTECT 的设备如何重刷固件（三步，缺一不可）
# Recover / reflash a device that has APPROTECT enabled.
#
# 用法 / Usage:
#   ./scripts/recover.sh [elf 路径]
#
# ⚠️ 会清空一切：固件、所有 passkey、PIN、UICR
#    完成后需要重新注册凭据。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ELF="${1:-$ROOT/out/opensk-nrf52840dongle.elf}"
[ -f "$ELF" ] || ELF="$ROOT/firmware/opensk-nrf52840dongle.elf"
UICR="$ROOT/firmware/uicr/uicr-approtect.bin"

PROBE_RS="${PROBE_RS:-probe-rs}"   # 不在 PATH 里就传 PROBE_RS=/path/to/probe-rs
CHIP="nRF52840_xxAA"
PROBE="${PROBE:-1366:0101}"        # 多台 J-Link 时用 1366:0101:<序列号>（probe-rs list 可查）

command -v "$PROBE_RS" >/dev/null 2>&1 || [ -x "$PROBE_RS" ] || {
  echo "错误: 找不到 probe-rs（当前为 '$PROBE_RS'）。装好后加进 PATH，或 PROBE_RS=/path/to/probe-rs 指定" >&2
  exit 1
}

[ -f "$ELF" ]  || { echo "错误: 找不到固件 $ELF" >&2; exit 1; }
[ -f "$UICR" ] || { echo "错误: 找不到 UICR 镜像 $UICR" >&2; exit 1; }

cat <<EOF
这将【彻底清空】设备：
  固件   $ELF
  UICR   $UICR
  清空对象：固件 + 全部 passkey + PIN + UICR

确认 dongle 的 USB 已拔掉、4 根 SWD 线已接好。
按 Ctrl-C 可中止，10 秒后继续...
EOF
sleep 10

echo
echo "==> [1/3] ERASEALL 解除 APPROTECT（全片擦除）"
if ! "$PROBE_RS" erase --chip "$CHIP" --probe "$PROBE" 2>/dev/null; then
  echo "    erase 子命令不可用或未获授权，改用 download --allow-erase-all 触发全片擦除"
  printf '\x00\x00\x00\x00' > "$ROOT/out/_dummy.bin"
  "$PROBE_RS" download --chip "$CHIP" --probe "$PROBE" \
    --allow-erase-all --binary-format bin --base-address 0x1000 "$ROOT/out/_dummy.bin" || true
  rm -f "$ROOT/out/_dummy.bin"
fi

echo "    校验是否已解锁（能读出 0x1000 即为解锁）..."
if ! "$PROBE_RS" read --chip "$CHIP" --probe "$PROBE" b8 0x1000 4 >/dev/null 2>&1; then
  cat >&2 <<'EOF'
    !! 仍无法访问芯片，解锁失败。可选方案：
       1) 重插 J-Link / 检查 4 根杜邦线后重试本脚本
       2) 用 SEGGER 工具：J-Link Commander 里执行 unlock
          （需先把 J-Link 驱动从 WinUSB 换回 SEGGER 驱动）
       3) 用 nrfjprog --recover（同上，需 SEGGER 驱动）
EOF
  exit 1
fi
echo "    已解锁"

echo
echo "==> [2/3] 烧录固件"
"$PROBE_RS" download --chip "$CHIP" --probe "$PROBE" \
  --allow-erase-all --binary-format elf --verify "$ELF"

echo
echo "==> [3/3] 恢复 UICR（关键！ERASEALL 清掉了 NRFFW[0]，不恢复可能起不来）"
"$PROBE_RS" download --chip "$CHIP" --probe "$PROBE" \
  --binary-format bin --base-address 0x10001000 --verify "$UICR"

cat <<'EOF'

==> 完成（注意：UICR 写入后调试口立即锁死）
请拔掉 SWD 线、插上 dongle 的 USB，然后：
  ./scripts/verify.sh          # 应枚举成 HID-compliant fido
  去 https://webauthn.io 重新注册一个 passkey（旧的已随擦除消失）

如果想恢复成"无保护"状态以后方便调试：
  把第 3 步的 uicr-approtect.bin 换成 firmware/uicr/uicr-no-protection.bin
EOF
