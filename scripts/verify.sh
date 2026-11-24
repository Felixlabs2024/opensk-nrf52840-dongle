#!/usr/bin/env bash
# 验收：检查设备是否已枚举成 FIDO HID（不依赖 SWD）
# Verify the dongle enumerates as a FIDO HID device (no SWD needed).
#
# 用法 / Usage:
#   ./scripts/verify.sh
set -uo pipefail

echo "==> 检查 VID_18D1 设备（OpenSK / Google FIDO）"
PS="$(command -v powershell.exe || command -v powershell || true)"
if [ -z "$PS" ]; then
  echo "!! 没找到 powershell，请手动在设备管理器里确认" >&2
  exit 1
fi

"$PS" -NoProfile -Command '
$d = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match "VID_18D1" }
if (-not $d) {
  Write-Output "  未发现 VID_18D1 设备 —— 设备没有正常启动"
  Write-Output "  排查: 1) 是否还插着 SWD 线?  2) 是否停在 Open DFU Bootloader(VID_1915)?"
  exit 1
}
$d | Select-Object Status, Class, FriendlyName | Format-Table -AutoSize
$fido = $d | Where-Object { $_.FriendlyName -match "fido" }
if (-not $fido) {
  Write-Output "  有 VID_18D1 设备但没有 HID-compliant fido —— 固件可能不完整"
  exit 2
}
Write-Output "  OK: 已枚举为 FIDO HID"
' 2>&1 | sed 's/^/  /'

echo
echo "==> 检查是否残留 COM 口（应该没有）"
"$PS" -NoProfile -Command '
$c = Get-CimInstance Win32_SerialPort | Where-Object { $_.PNPDeviceID -match "VID_1915|VID_18D1" }
if ($c) { $c | Select-Object DeviceID, Name | Format-Table -AutoSize } else { Write-Output "  无残留 COM 口" }
' 2>&1 | sed 's/^/  /'

cat <<'EOF'

==> 下一步：功能实测（只能人工做）
  1) 打开 https://webauthn.io
  2) 输入用户名 -> Register -> 按提示设置/输入 PIN
  3) 立刻点 Authenticate（同一用户名）-> 应显示 "You're logged in!"
  4) 拔插 USB 后再 Authenticate 一次 -> 仍应成功（验证持久化）

想更细地定位"能注册不能认证"，用本地诊断页：
  cd tools/wa_diag && python server.py
  浏览器打开 http://localhost:8765
EOF
