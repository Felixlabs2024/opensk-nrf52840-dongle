<div align="center">

# OpenSK Passkey on nRF52840 Dongle

**把一块 nRF52840 Dongle 变成 USB FIDO2 / Passkey 硬件密钥**
**Turn an nRF52840 Dongle into a USB FIDO2 / passkey security key**

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Hardware](https://img.shields.io/badge/hardware-nRF52840%20Dongle-2ea44f.svg))(#这是什么)
[![Standard](https://img.shields.io/badge/CTAP2-FIDO2-ff6f00.svg)](https://fidoalliance.org/specs/fido-v2.0-id-20180227/fido-client-to-authenticator-protocol-v2.0-id-20180227.html)
[![Firmware](https://img.shields.io/badge/prebuilt-389%20KB-informational.svg)](firmware/opensk-nrf52840dongle.elf)
[![Status](https://img.shields.io/badge/status-verified%20on%20real%20hardware-brightgreen.svg))(#功能验证)
[![Built with](https://img.shields.io/badge/built%20with-Rust-dea584.svg?logo=rust&logoColor=white)](https://www.rust-lang.org/)

**中文** ｜ [**English**](#english) ｜ [**在线交互版 / Live page**](https://felixlabs2024.github.io/opensk-nrf52840-dongle/)

</div>

> [!IMPORTANT]
> 这个仓库存在的理由：网上关于"用 OpenSK 自制 FIDO2 密钥"的教程，几乎都在**最后一公里**卡住——固件刷进去了，设备却永远停在 `Open DFU Bootloader`，然后没人告诉你为什么。
> 我们踩完了整条路，把**真正的拦路虎**（`0xE0000` 的原厂 bootloader）、**烧录的坑**（`platform.hex` 不可用）、**Windows 上的编译环境**全部写进了文档，并附上可直接烧的固件。
> 目标很朴素：**照着做，一把就成。**

---

## 目录 / Contents

| 章节 | 说明 |
|---|---|
| [这是什么](#这是什么) | 一张表看清硬件、固件、能力、限制 |
| [三条必须先知道的结论](#三条必须先知道的结论) | 省下你几个小时的关键事实 |
| [快速开始（3 步）](#快速开始已编译3-步) | 不编译，直接烧预编译固件 |
| [从源码构建](#从源码构建) | 编译环境 + 4 个补丁做了什么 |
| [安全：开启 APPROTECT](#安全强烈建议开启-approtect) | 不开读保护 = 没有保护 |
| [功能验证](#功能验证) | 诊断页 + 预期基线 |
| [目录结构](#目录结构) · [已知限制](#已知限制) · [常见问题](#常见问题) | — |

---

# 中文文档

## 这是什么

| 项目 | 说明 |
|---|---|
| **硬件** | nRF52840 Dongle（1 MB flash / 256 KB RAM），USB-A 直插 |
| **固件** | OpenSK（develop）+ wasefire runner，native applet |
| **标准** | CTAP2 / FIDO2，**150 条可发现凭据**，支持 PIN、credProtect |
| **传输** | 仅 USB HID（**无 NFC / 无 BLE**） |
| **烧录** | J-Link SWD（**USB DFU 不可用**，原因见下） |
| **状态** | ✅ 真实硬件实测：注册 / 认证 / 拔插后仍可用 |

**成本**：一块 dongle 约 ¥60，一个 J-Link 或兼容调试器。不需要 YubiKey 那种专用安全芯片。

**一键体验**：不想编译，直接烧 [`firmware/opensk-nrf52840dongle.elf`](firmware/opensk-nrf52840dongle.elf)（389 KB，applet 已注入）。

## 三条必须先知道的结论

> [!WARNING]
> 这三条是整个项目最贵的经验，按顺序读能省掉几小时。

**1. USB DFU 走不通 —— 只有 SWD 一条路**

这类 dongle 的出厂 bootloader 有厂商签名墙。我们试过补 `sd_req` 候选列表、把 `fw_version` 改成 `0xFFFFFFFF`、用 Nordic 的调试私钥签名，**全部返回 `InvalidObject`**（trace 里 `Execute`(op 4) → `result 5`）。别再在这条路上花时间。

**2. `platform.hex` 不能烧 —— 必须用 ELF**

`xtask bundle` 产出的 `platform.hex` 用 4 条 `02`（Extended Segment Address）记录把同一段 `0x0000–0xFFFF` 重叠映射 4 次。probe-rs 只写对第一段，而且 **`--verify` 校验的是它自己解析出的错误镜像，会误报"成功"**。要用 `target/thumbv7em-none-eabi/release/bootloader` 那个 ELF。

**3. 真正的拦路虎是 `0xE0000` 的原厂 bootloader**

芯片上电后 MBR 跳的是 flash 顶部的 Nordic DFU bootloader（不是你的固件），它校验不通过就停在 DFU，设备永远显示 `Open DFU Bootloader`（`VID_1915&PID_521F`，枚举成 COM 口）。

我们试过的两条"聪明办法"都**无效**，别重走：
- 改 bootloader settings 的 `image_crc`（`0xFF000` 页）→ 无效，那层校验不是拦路的原因；
- 改 UICR `NRFFW[0] = 0x1000` 让 MBR 跳过去 → 反汇编 MBR 发现它**硬编码 `0x000E0000`**，根本不读 UICR。

**真正的解法**：烧录时加 `--allow-erase-all`（全片擦除），把它一起清掉。

> 完整分析：[docs/02-architecture.md](docs/02-architecture.md) · 30+ 条坑与解法：[docs/01-pitfalls-and-fixes.md](docs/01-pitfalls-and-fixes.md)

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

> [!CAUTION]
> 用 J-Link 的 VDD 供电时，**dongle 的 USB 必须拔掉**；反过来要 USB 供电就不要接 VDD。**两个同时接会冲突。**

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
| `0001-opensk-toolchain-touch` | 工具链改 `10-05`；`setup.sh` 无 MSVC 时跳过 cargo-audit；**`touch.rs` 的 `is_present()` 恒返回 `true`** | `10-02` 已被官方撤回；免按键自动确认 |
| `0002-wasefire-toolchain` | 工具链改 `10-05`，裁掉用不到的 target | 省 100 MB+ 下载 |
| `0003-wasefire-windows-port` | 5 个文件加 `#[cfg(unix)]` / Windows 分支（UnixStream、chmod、exec、setsid、wrapper.sh 用 bash 跑） | 官方只支持 Unix |
| `0004-wasefire-panic-abort` | 两个 `Cargo.toml` 加 `[patch.crates-io]` | `panic-abort 0.3.2` 用了已移除的 `core::intrinsics::abort()` |

补丁用 `git apply` 可直接应用（已用上游原始 tree 做过 `git apply --check`）。`vendor/panic-abort/` 是修复版 crate，`apply-patches.sh` 会自动放到 `third_party/wasefire/patches/`。

## 安全：强烈建议开启 APPROTECT

> [!WARNING]
> 不开读保护时，**任何人拿到这块板子，接 4 根线跑一条命令就能导出全部私钥**。
> 原因：私钥用 master key 加密存在 flash，而 **master key 本身也明文存在同一块 flash**；PIN 只控制"使用授权"，不参与私钥加密。

```bash
./scripts/protect.sh      # 保留式写 UICR：只改 APPROTECT 4 字节，凭据和 PIN 都保留
```

开启后：SWD 无法读写 flash，攻击者只能 ERASEALL（数据全毁，拿不到）。
代价：**不能再用 SWD 调试**，以后升级固件必须全擦重刷（`./scripts/recover.sh`）。

| 攻击者 | 未保护 | 已保护 |
|---|---|---|
| 同事 / 维修店 / 捡到的人（有 J-Link、会 probe-rs） | 🔴 5 分钟 | 🟢 做不到 |
| 自制 glitch 设备 | 🔴 | 🟡 看硅版本 |
| 专业实验室（ChipWhisperer / EMFI） | 🔴 | 🟡 40–95%，$500–2500 |

详见 [docs/03-security.md](docs/03-security.md)（含硅版本差异、残余风险、加固清单）。

## 功能验证

"能注册但不能认证"这类问题，用站点很难判断断在哪一层。本仓库带一套**本地诊断页**，把 WebAuthn 拆成 5 步单独测：

```bash
cd tools/wa_diag && python server.py
# 浏览器打开 http://localhost:8765
```

关键看 **`idLength`**：`32` = 走了可发现凭据（写 flash），`≈241` = 走了加密 key handle。一眼就知道固件走了哪条存储路径。

正常基线（本项目实测）：

| 步骤 | 结果 |
|---|---|
| 1 注册 resident | 成功 ~10s，`idLength = 32` |
| 2 带 allowList 认证 | 成功 ~11s，`sameId = true` |
| 3 空 allowList 认证 | 成功 ~12s，`userHandle` 正常 |
| 4 注册非 resident | 成功 ~7s，`idLength = 241` |
| 5 非 resident 认证 | 成功 ~8s，`sameId = true` |

详见 [docs/04-verification.md](docs/04-verification.md)。

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

## 已知限制

| 限制 | 说明 |
|---|---|
| **仅 USB HID** | 无 NFC / 无 BLE；手机需 USB-A 转 Type-C 的 OTG 转接头 |
| **Nordic USB DFU 永久失效** | 烧录时 `--allow-erase-all` 会擦掉原厂 bootloader，之后只能 SWD |
| **无安全元件** | 不是 YubiKey 那种带认证安全芯片的方案；开了 APPROTECT 后仍需考虑故障注入 |
| **免按键 = 无物理确认** | 任何插上这把钥匙的电脑都能直接认证；不想这样就去掉 `touch.rs` 补丁重编 |
| **PIN 8 次上限是设备级** | 所有平台共用一个计数器，到顶只能整体重置 |
| **无 LED** | 无法从板子本身看状态，只能靠主机枚举 |

## 常见问题

**Q：能当日常主力 passkey 用吗？**
能。但如果你要带出门、插到别人的电脑上，建议**同时**开 APPROTECT 并去掉免按键补丁——否则别人捡到就能用（虽然读不出私钥）。

**Q：为什么不做成 USB 以外的形态？**
这块是 USB-A Dongle，OpenSK 这个固件只实现了 USB HID。没有 NFC，也没有蓝牙。

**Q：能不能不接 J-Link？**
不能。USB DFU 被签名墙堵死，SWD 是唯一通道。买一块兼容 CMSIS-DAP 也能用，probe-rs 支持。

**Q：`--allow-erase-all` 会不会把我的凭据冲掉？**
会。它是全片擦除。日常升级固件时，先备份好要重新注册的站点。

**Q：以后上游更新了怎么办？**
`0003`（Windows 移植）最可能冲突，因为它依赖上游当时的 Unix 专属 API。其余三个基本不会。

## 致谢与许可

- 固件基于 [google/OpenSK](https://github.com/google/OpenSK) 与 [google/wasefire](https://github.com/google/wasefire)，两者均为 Apache-2.0
- 本仓库的补丁、脚本与文档同样以 **Apache-2.0** 发布；`firmware/` 下的二进制是上述项目的衍生作品，详见 [NOTICE.md](NOTICE.md)
- 请遵守当地法律，**仅对自己拥有的设备操作**

---

# English

## What this is

| | |
|---|---|
| **Hardware** | nRF52840 Dongle (1 MB flash / 256 KB RAM), USB-A |
| **Firmware** | OpenSK (develop) + wasefire runner, native applet |
| **Standard** | CTAP2 / FIDO2, **150 discoverable credentials**, PIN + credProtect |
| **Transport** | USB HID only (**no NFC / no BLE**) |
| **Flashing** | J-Link SWD (**USB DFU does not work**, see below) |
| **Status** | ✅ Verified on real hardware: register / authenticate / survives replug |

**Cost**: a dongle is ~$8, plus a J-Link or compatible probe. No secure element required.

**Just want it working?** Flash [`firmware/opensk-nrf52840dongle.elf`](firmware/opensk-nrf52840dongle.elf) (389 KB, applet already embedded).

## Three things you must know first

> [!WARNING]
> These three are the expensive lessons. Read them before touching anything.

**1. USB DFU is a dead end — SWD only**

These dongles ship with a vendor-signed bootloader. We tried `sd_req` candidate lists, `fw_version = 0xFFFFFFFF`, and signing with Nordic's debug key — **all return `InvalidObject`** (`Execute`(op 4) → `result 5` in the trace). Don't spend time here.

**2. Do not flash `platform.hex` — use the ELF**

The `platform.hex` produced by `xtask bundle` uses four `02` (Extended Segment Address) records that map the same `0x0000–0xFFFF` range four times. probe-rs only lands the first segment, and **`--verify` checks its own misparsed image, so it reports success anyway**. Use `target/thumbv7em-none-eabi/release/bootloader`.

**3. The real blocker is the stock bootloader at `0xE0000`**

After reset, the MBR jumps to the Nordic DFU bootloader at the top of flash — not your firmware. When its check fails, it stays in DFU and the device shows `Open DFU Bootloader` (`VID_1915&PID_521F`, enumerating as a COM port).

Two "clever" workarounds we tried, **both useless** — don't repeat them:
- Patching `image_crc` in the bootloader settings page (`0xFF000`) → no effect; that check is not what blocks you.
- Setting UICR `NRFFW[0] = 0x1000` to redirect the MBR → disassembling the MBR shows it **hardcodes `0x000E0000`** and never reads UICR.

**The actual fix**: pass `--allow-erase-all` (full chip erase) when flashing, which wipes it.

> Full analysis: [docs/02-architecture.md](docs/02-architecture.md) · all pitfalls: [docs/01-pitfalls-and-fixes.md](docs/01-pitfalls-and-fixes.md)

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

> [!CAUTION]
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
| `0001-opensk-toolchain-touch` | Toolchain → `10-05`; skip `cargo-audit` without MSVC; **`touch.rs::is_present()` returns `true`** | `10-02` was withdrawn upstream; no-touch convenience |
| `0002-wasefire-toolchain` | Toolchain → `10-05`, trimmed targets | Saves 100 MB+ of downloads |
| `0003-wasefire-windows-port` | 5 files: `#[cfg(unix)]` / Windows branches (UnixStream, chmod, exec, setsid, wrapper.sh via bash) | Upstream is Unix-only |
| `0004-wasefire-panic-abort` | Two `Cargo.toml` files gain `[patch.crates-io]` | `panic-abort 0.3.2` uses the removed `core::intrinsics::abort()` |

## Security: enable APPROTECT

> [!WARNING]
> Without read-out protection, **anyone holding this dongle can dump every private key with one command**. Private keys are encrypted with a master key — and that master key sits in plaintext in the same flash. PIN only gates *use*, it does not encrypt keys.

```bash
./scripts/protect.sh      # preserve-style UICR write: only APPROTECT changes, credentials/PIN survive
```

Afterwards SWD cannot read flash; an attacker can only ERASEALL (destroying everything).
Cost: no more SWD debugging, and future firmware updates require a full erase (`./scripts/recover.sh`).

See [docs/03-security.md](docs/03-security.md) for the threat model, silicon revisions and remaining risks.

## Verification

`tools/wa_diag/` breaks WebAuthn into five independent steps. Watch **`idLength`**: `32` means a discoverable credential (written to flash), `≈241` means an encrypted key handle. That single number tells you which storage path the firmware took.

```bash
cd tools/wa_diag && python server.py
# open http://localhost:8765
```

## Limitations

- USB HID only — no NFC/BLE; phones need a USB-A to USB-C OTG adapter.
- The stock Nordic DFU bootloader is wiped by `--allow-erase-all`; SWD only from then on.
- No secure element — not a YubiKey-class device.
- The no-touch patch means any host can use the key without confirmation.
- PIN retry counter (8) is device-global and shared across all platforms.

## Credits & License

Built on [google/OpenSK](https://github.com/google/OpenSK) and [google/wasefire](https://github.com/google/wasefire), both Apache-2.0.
Patches, scripts and docs here are Apache-2.0 as well; binaries under `firmware/` are derivative works of the above — see [NOTICE.md](NOTICE.md).
Use only on hardware you own.

<div align="center">

**[⬆ 回到顶部 / Back to top](#opensk-passkey-on-nrf52840-dongle)**

</div>
