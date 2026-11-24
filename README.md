# OpenSK Passkey on nRF52840 Dongle

把一块 **nRF52840 Dongle** 变成一把 **USB FIDO2 / Passkey 硬件密钥**，基于 Google [OpenSK](https://github.com/google/OpenSK) + [wasefire](https://github.com/google/wasefire)，用 **J-Link SWD** 烧录。

Turn an **nRF52840 Dongle** into a **USB FIDO2 / Passkey security key** using Google OpenSK + wasefire, flashed over **J-Link SWD**.

> 想看得舒服一点（可点击切换中英文、按章节筛选）：
> **用浏览器打开 [`index.html`](index.html)** · For a nicer reading experience with a language toggle, open **`index.html`** in a browser.

**[中文](#中文文档) · [English](#english)**

---

# 中文文档

## 这是什么

| 项目 | 说明 |
|---|---|
| 硬件 | nRF52840 Dongle（1MB flash / 256KB RAM），USB-A |
| 固件 | OpenSK（develop）+ wasefire runner，native applet |
| 传输 | 仅 USB HID（**无 NFC / 无 BLE**） |
| 能力 | CTAP2 / FIDO2，**150 条可发现凭据**，支持 PIN |
| 烧录 | J-Link SWD（**USB DFU 不可用**，见下） |
| 状态 | ✅ 实测可用：webauthn.io 注册/认证通过，拔插后凭据仍在 |

**一键体验**：不想编译的话，直接烧 `firmware/opensk-nrf52840dongle.elf`（约 389KB，已含 applet）。

## 三条必须先知道的结论

1. **USB DFU 走不通。** 这类 dongle 的出厂 bootloader 有厂商签名墙（我们试过补 `sd_req` 候选、改 `fw_version`、用 Nordic 调试私钥签名，全部返回 `InvalidObject`）。**只有 SWD 一条路。**
2. **`platform.hex` 不能烧。** 它用重叠段编码地址，probe-rs 只能写对第一段，而且 `--verify` 会误报通过。**要用 `release/bootloader` 那个 ELF。**
3. **真正的拦路虎是 `0xE0000` 的 Nordic 原厂 bootloader** —— 它会拦住 MBR 到应用的跳转，导致设备永远停在 "Open DFU Bootloader"。烧录时加 `--allow-erase-all`（全片擦除）即可一并解决。

> 详细原理：[docs/02-architecture.md](docs/02-architecture.md) · 全部坑：[docs/01-pitfalls-and-fixes.md](docs/01-pitfalls-and-fixes.md)

## 快速开始（已编译，3 步）

### 0. 准备

- J-Link 调试器 + 4 根杜邦线
- [probe-rs](https://probe.rs/) 0.32+，在 `PATH` 里；不在 `PATH` 就用 `PROBE_RS=/path/to/probe-rs` 指定
- **把 J-Link 的驱动换成 WinUSB**（probe-rs 必需）：用 [Zadig](https://zadig.akeo.ie/) → `Options → List All Devices` → 选 J-Link（确认 `1366:0101`）→ 目标驱动选 `WinUSB` → `Replace Driver`

### 1. 接线（dongle 的 USB 先拔掉）

| dongle 背面 DEBUG 4 孔（左→右） | J-Link 20 针 |
|---|---|
| GND | pin 4 |
| CLK | pin 9 |
| DIO | pin 7 |
| VDD | pin 1（VTref 3.3V） |

> 用 J-Link 的 VDD 供电时，`dongle 的 USB 必须拔掉`；反之要 USB 供电就不要接 VDD。**不要两个同时接。**

### 2. 烧录

```bash
./scripts/flash.sh          # 默认烧 firmware/opensk-nrf52840dongle.elf
```

等价命令：

```bash
probe-rs download --chip nRF52840_xxAA --probe 1366:0101 \
  --allow-erase-all --binary-format elf --verify --reset \
  firmware/opensk-nrf52840dongle.elf
```

> `--probe 1366:0101` 只按 VID:PID 选探针（手头只有一台时够用）。接了多台 J-Link 时写成 `1366:0101:<序列号>`，序列号用 `probe-rs list` 查。

### 3. 验收

拔掉 4 根 SWD 线 → 插上 dongle 的 USB → 运行：

```bash
./scripts/verify.sh
```

应看到 **`HID-compliant fido`**（`VID_18D1&PID_0239`）且**没有 COM 口**。然后去 https://webauthn.io 注册 + 认证（**免按键**，只需输入 PIN）。

## 从源码构建

### 环境

| 组件 | 版本 / 位置 | 备注 |
|---|---|---|
| Windows | 11 | Linux/macOS 理论可行，本仓库补丁针对 Windows |
| Rust | `nightly-2026-10-05`（`x86_64-pc-windows-gnu`） | 补丁已固定版本；官方源装（镜像不含带日期 nightly） |
| MSYS2 | `C:\msys64`，装 `mingw-w64-x86_64-binutils` | 提供 `as.exe` / `dlltool.exe` / `gcc.exe` |
| Python 3 | — | 仅脚本用，用于改 UICR 字节 |
| probe-rs | 0.32.0 | 烧录 |

### 步骤

```bash
# 1) 取源码（含子模块）
git clone https://github.com/google/OpenSK
cd OpenSK
git checkout f53621c          # 本项目验证过的提交附近
git submodule update --init --recursive
# wasefire 需为 1e46740ed6fe9b9900606454928bd3ae8c11cc7e

# 2) 打补丁（4 个，含 Windows 移植 + 免按键 + panic-abort 修复）
cd /path/to/this/repo
./scripts/apply-patches.sh /path/to/OpenSK

# 3) 构建（等价于官方 flash.sh，但只构建不刷机）
./scripts/build.sh /path/to/OpenSK
# 产物会复制到 out/opensk-nrf52840dongle.elf
```

> `build.sh` 内部用的是 `cargo xtask ... bundle`，**不是 `flash`**。`flash` 最后会调用 `nrfdfu` 走 USB DFU，在这类 dongle 上必然失败。

### 补丁都改了什么

| 补丁 | 内容 | 为什么 |
|---|---|---|
| `0001-opensk-toolchain-touch` | 工具链改 10-05；`setup.sh` 无 MSVC 时跳过 cargo-audit；**`touch.rs` 的 `is_present()` 恒返回 `true`** | 10-02 已被官方撤回；免按键自动确认 |
| `0002-wasefire-toolchain` | 工具链改 10-05，裁掉用不到的 target | 省 100MB+ 下载 |
| `0003-wasefire-windows-port` | 5 个文件加 `#[cfg(unix)]` / Windows 分支（UnixStream、chmod、exec、setsid、wrapper.sh 用 bash 跑） | 官方只支持 Unix |
| `0004-wasefire-panic-abort` | 两个 `Cargo.toml` 加 `[patch.crates-io]` | `panic-abort 0.3.2` 用了已移除的 `core::intrinsics::abort()` |

补丁用 `git apply` 可直接应用（已用原始 tree 验证过）。`vendor/panic-abort/` 是修复版 crate，`apply-patches.sh` 会自动放到 `third_party/wasefire/patches/`。

## 目录结构

```
.
├─ README.md                 ← 本文（中英双文）
├─ index.html                ← 交互版：点击切换中英 / 按章节筛选
├─ LICENSE                   ← Apache-2.0
├─ NOTICE.md                 ← 衍生关系与第三方许可说明
├─ CHECKSUMS.txt             ← 固件与 UICR 镜像的 SHA256
├─ firmware/
│   ├─ opensk-nrf52840dongle.elf      ← 可直接烧录的完整固件
│   └─ uicr/
│       ├─ uicr-no-protection.bin     ← 无读保护（调试友好）
│       └─ uicr-approtect.bin         ← 已开读保护（安全，重刷后写回这份）
├─ patches/                  ← 4 个源码补丁（含 README 说明如何应用）
├─ vendor/panic-abort/       ← panic-abort 修复 crate
├─ scripts/
│   ├─ apply-patches.sh      ← 打补丁
│   ├─ build.sh              ← 构建固件
│   ├─ flash.sh              ← SWD 烧录
│   ├─ verify.sh             ← 验收（设备枚举）
│   ├─ protect.sh            ← 开启 APPROTECT 读保护（保留式写 UICR）
│   └─ recover.sh            ← 已保护设备的全擦重刷流程
├─ tools/wa_diag/            ← 本地 WebAuthn 诊断页（定位"能注册不能认证"）
└─ docs/
    ├─ 01-pitfalls-and-fixes.md   ← 30+ 条坑与解法
    ├─ 02-architecture.md         ← 启动链路 / flash 布局 / 根因分析
    ├─ 03-security.md             ← 威胁模型与 APPROTECT
    └─ 04-verification.md         ← 诊断页用法与正常基线
```

## 安全：强烈建议开启 APPROTECT

不开读保护时，**任何人拿到这块板子，接 4 根线跑一条命令就能导出全部私钥**（master key 明文存在 flash 里，PIN 不加密私钥）。

```bash
./scripts/protect.sh      # 保留式写 UICR：只改 APPROTECT 4 字节，凭据和 PIN 都保留
```

开启后：SWD 无法读写 flash，攻击者只能 ERASEALL（数据全毁）。
代价：**不能再用 SWD 调试**，以后升级固件必须全擦重刷（`./scripts/recover.sh`）。
详见 [docs/03-security.md](docs/03-security.md)。

## 已知限制

| 限制 | 说明 |
|---|---|
| **仅 USB HID** | 无 NFC / 无 BLE；手机需 USB-A 转 Type-C 的 OTG 转接头 |
| **Nordic USB DFU 永久失效** | 烧录时 `--allow-erase-all` 会擦掉原厂 bootloader，之后只能 SWD |
| **无安全元件** | 不是 YubiKey 那种带认证安全芯片的方案；开了 APPROTECT 后仍需考虑故障注入 |
| **免按键 = 无物理确认** | 任何插上这把钥匙的电脑都能直接认证；不想这样就去掉 `touch.rs` 补丁重编 |
| **PIN 8 次上限是设备级** | 所有平台共用一个计数器，到顶只能整体重置 |
| **无 LED** | 无法从板子本身看状态，只能靠主机枚举 |

## 致谢与许可

- 固件基于 [google/OpenSK](https://github.com/google/OpenSK)（Apache-2.0）与 [google/wasefire](https://github.com/google/wasefire)（Apache-2.0）
- 本仓库的补丁、脚本与文档同样以 **Apache-2.0** 发布；`firmware/` 下的二进制是上述项目的衍生作品
- 请遵守当地法律，仅对自己拥有的设备操作

---

# English

## What this is

| | |
|---|---|
| Hardware | nRF52840 Dongle (1MB flash / 256KB RAM), USB-A |
| Firmware | OpenSK (develop) + wasefire runner, native applet |
| Transport | USB HID only (**no NFC / no BLE**) |
| Capabilities | CTAP2 / FIDO2, **150 discoverable credentials**, PIN supported |
| Flashing | J-Link SWD (**USB DFU does not work**, see below) |
| Status | ✅ Verified: webauthn.io register + authenticate works, credentials survive replug |

**Just want it working?** Flash `firmware/opensk-nrf52840dongle.elf` (~389KB, applet already embedded).

## Three things you must know first

1. **USB DFU is a dead end.** These dongles ship with a vendor-signed bootloader. We tried `sd_req` candidate lists, `fw_version=0xFFFFFFFF`, and signing with Nordic's debug key — all return `InvalidObject`. **SWD is the only path.**
2. **Do not flash `platform.hex`.** Its overlapping segment records are misparsed by probe-rs (only the first segment lands), and `--verify` reports success anyway. **Use the `release/bootloader` ELF instead.**
3. **The real blocker sits at `0xE0000`** — the stock Nordic DFU bootloader blocks the MBR → application hand-off, so the device stays in "Open DFU Bootloader" forever. `--allow-erase-all` (full chip erase) clears it as a side effect.

> Details: [docs/02-architecture.md](docs/02-architecture.md) · all pitfalls: [docs/01-pitfalls-and-fixes.md](docs/01-pitfalls-and-fixes.md)

## Quick start (prebuilt, 3 steps)

### 0. Prerequisites

- J-Link probe + 4 jumper wires
- [probe-rs](https://probe.rs/) 0.32+ on your `PATH` (or set `PROBE_RS=/path/to/probe-rs`)
- **Switch the J-Link driver to WinUSB** (required by probe-rs): use [Zadig](https://zadig.akeo.ie/) → `Options → List All Devices` → pick J-Link (`1366:0101`) → select `WinUSB` → `Replace Driver`

### 1. Wire it up (unplug the dongle's USB first)

| Dongle DEBUG header (left→right) | J-Link 20-pin |
|---|---|
| GND | pin 4 |
| CLK | pin 9 |
| DIO | pin 7 |
| VDD | pin 1 (VTref 3.3V) |

> If you power from J-Link's VDD, the dongle's USB **must be unplugged**. Never connect both.

### 2. Flash

```bash
./scripts/flash.sh
```

Equivalent:

```bash
probe-rs download --chip nRF52840_xxAA --probe 1366:0101 \
  --allow-erase-all --binary-format elf --verify --reset \
  firmware/opensk-nrf52840dongle.elf
```

> `--probe 1366:0101` selects by VID:PID only (fine for a single probe). With multiple J-Links attached, use `1366:0101:<serial>` — find the serial with `probe-rs list`.

### 3. Verify

Unplug the 4 SWD wires, plug the dongle into USB, then:

```bash
./scripts/verify.sh
```

You should see **`HID-compliant fido`** (`VID_18D1&PID_0239`) and **no COM port**. Then register + authenticate at https://webauthn.io (**no button press needed**, PIN only).

## Build from source

```bash
# 1) sources
git clone https://github.com/google/OpenSK && cd OpenSK
git checkout f53621c
git submodule update --init --recursive     # wasefire must be 1e46740e

# 2) apply patches
/path/to/this/repo/scripts/apply-patches.sh /path/to/OpenSK

# 3) build (same pipeline as upstream flash.sh, but build-only)
/path/to/this/repo/scripts/build.sh /path/to/OpenSK
# -> out/opensk-nrf52840dongle.elf
```

> `build.sh` uses `cargo xtask ... bundle`, **not `flash`**. `flash` ends by invoking `nrfdfu` over USB DFU, which cannot work on these dongles.

Requires Rust `nightly-2026-10-05` (x86_64-pc-windows-gnu), MSYS2 binutils, Python 3. See the Chinese section for the full table.

## What the patches change

| Patch | Content | Why |
|---|---|---|
| `0001-opensk-toolchain-touch` | Toolchain → 10-05; skip `cargo-audit` without MSVC; **`touch.rs::is_present()` returns `true`** | 10-02 was withdrawn upstream; no-touch convenience |
| `0002-wasefire-toolchain` | Toolchain → 10-05, trimmed targets | Saves 100MB+ of downloads |
| `0003-wasefire-windows-port` | 5 files: `#[cfg(unix)]` / Windows branches (UnixStream, chmod, exec, setsid, wrapper.sh via bash) | Upstream is Unix-only |
| `0004-wasefire-panic-abort` | Two `Cargo.toml` files gain `[patch.crates-io]` | `panic-abort 0.3.2` uses the removed `core::intrinsics::abort()` |

## Security: enable APPROTECT

Without read-out protection, **anyone holding this dongle can dump every private key in minutes** — the master key is stored in plaintext flash and PIN does not encrypt private keys.

```bash
./scripts/protect.sh      # preserve-style UICR write: only APPROTECT changes, credentials/PIN survive
```

Afterwards SWD cannot read flash; an attacker can only ERASEALL (destroying everything).
Cost: no more SWD debugging, and future firmware updates require a full erase (`./scripts/recover.sh`).
See [docs/03-security.md](docs/03-security.md).

## Limitations

- USB HID only — no NFC/BLE; phones need a USB-A to USB-C OTG adapter.
- The stock Nordic DFU bootloader is wiped by `--allow-erase-all`; SWD only from then on.
- No secure element — not a YubiKey-class device.
- The no-touch patch means any host can use the key without confirmation.
- PIN retry counter (8) is device-global and shared across all platforms.

## Credits & License

Built on [google/OpenSK](https://github.com/google/OpenSK) and [google/wasefire](https://github.com/google/wasefire), both Apache-2.0.
Patches, scripts and docs here are Apache-2.0 as well; binaries under `firmware/` are derivative works of the above.
Use only on hardware you own.
