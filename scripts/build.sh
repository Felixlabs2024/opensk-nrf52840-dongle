#!/usr/bin/env bash
# 构建固件（不碰设备）—— 等价于官方 flash.sh 去掉最后一步刷写
# Build firmware only (no device access).
#
# 用法 / Usage:
#   ./scripts/build.sh /path/to/OpenSK
#
# 产物 / Output:
#   <OpenSK>/third_party/wasefire/target/thumbv7em-none-eabi/release/bootloader
#   -> 复制到 out/opensk-nrf52840dongle.elf（这就是要烧的文件）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPEN="${1:-}"

if [ -z "$OPEN" ]; then
  echo "用法: $0 <OpenSK 仓库路径>" >&2
  exit 1
fi

# 需要 MSYS2 的 binutils(as/dlltool) 与 cargo
export PATH="/c/msys64/mingw64/bin:/c/msys64/usr/bin:${HOME}/.cargo/bin:${PATH}"

WF="$OPEN/third_party/wasefire"
cd "$WF"

FEATURES="ctap1,config-command"
CRYPTO="software-crypto-aes256-cbc,software-crypto-hmac-sha256,software-crypto-p256-ecdh,software-crypto-p256-ecdsa"

echo "==> 构建 applet + runner + bootloader（bundle：只产包不刷机）"
echo "    这一步通常 5~20 分钟，首次更久"
echo

# 关键：子命令必须是 bundle 而不是 flash。
#   flash  = 构建 + 用 nrfdfu 走 USB DFU 刷写（在带签名墙的 dongle 上必然失败）
#   bundle = 只构建，产出 platform.wfb / platform.hex / 以及注入了 applet 的 bootloader ELF
cargo xtask --release --native applet rust ../.. --opt-level=z --features="$FEATURES" \
  runner nordic --board=dongle --opt-level=z --features=usb-ctap \
  --features="$CRYPTO" \
  bundle

ELF="target/thumbv7em-none-eabi/release/bootloader"
if [ ! -f "$ELF" ]; then
  echo "错误: 没有找到 $ELF" >&2
  exit 1
fi

mkdir -p "$ROOT/out"
cp "$ELF" "$ROOT/out/opensk-nrf52840dongle.elf"

SIZE=$(wc -c < "$ROOT/out/opensk-nrf52840dongle.elf")
echo
echo "==> 构建完成"
echo "    ELF  : $ROOT/out/opensk-nrf52840dongle.elf"
echo "    大小 : $SIZE 字节（正常约 380000~400000）"

# 体检：确认 .runner（applet）不是空的
OBJDUMP="$(command -v llvm-objdump || true)"
if [ -z "$OBJDUMP" ]; then
  for c in "${HOME}/.rustup/toolchains"/*/lib/rustlib/*/bin/llvm-objdump.exe; do
    [ -f "$c" ] && OBJDUMP="$c" && break
  done
fi
if [ -n "$OBJDUMP" ]; then
  echo
  echo "    段布局（.runner 应为 0x2a810 左右；若为 0 说明 applet 没注入）:"
  "$OBJDUMP" -h "$ROOT/out/opensk-nrf52840dongle.elf" 2>/dev/null | awk '/runner|header|vector_table|\.text/ {print "      "$0}'
fi

cat <<'EOF'

下一步：
  ./scripts/flash.sh            # 通过 J-Link SWD 烧录
EOF
