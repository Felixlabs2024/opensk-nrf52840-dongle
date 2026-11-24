# 踩坑与修正总表 / Pitfalls & Fixes

本文汇总两类坑：**搭建编译环境**时踩的，以及**刷机运行**时踩的。每条都给出「现象 → 根因 → 解法」。

> 表里的报错文本是原文引用，方便你直接搜索。

---

## 一、环境与构建类

| # | 现象（报错原文） | 根因 | 解法 |
|---|---|---|---|
| 1 | `git: 术语 'git' 不会被识别为 cmdlet…` | 没装 Git；或装了但 PATH 未刷新 | 装 Git for Windows，然后**关掉所有终端窗口重开** |
| 2 | `❌ Missing rustup command.` | 没装 rustup | 装 rustup，安装时选 **3) Don't install the prerequisites**（跳过 VS 构建工具） |
| 3 | `error: failed to display the current 'rustc' version: no release found for 'nightly-2026-10-02'` | 该日期的 nightly 已被 Rust 官方撤回（404） | 把 `rust-toolchain.toml` 改成 `nightly-2026-10-05`。**注意要改三处**：OpenSK 根、wasefire 根、以及 `crates/cli-tools/src/action.rs:991` 里硬编码的 `TOOLCHAIN` 常量 |
| 4 | 装了带日期的 nightly，但 `rustup` 报 404 | 清华 TUNA 镜像**不镜像带日期的 nightly 清单**（官方有，镜像没有） | **rustup 走官方源**，cargo 可以继续用 rsproxy 镜像。清掉 `~/.bashrc` 里的 `RUSTUP_DIST_SERVER` |
| 5 | `Error: Unsupported system. Install bin 'pkg-config' and rerun the command.` | Windows 没有 pkg-config，`--exists openssl` 探测失败 | 放一个假 `pkg-config` 垫片到 `~/bin/`（只需让 `--exists` 返回成功） |
| 6 | `tools/gen_key_materials.sh: line 98: uuidgen: command not found` | Windows Git Bash 没有 `uuidgen` | 放一个垫片：`python -c "import uuid,sys; print(uuid.uuid4())"` 命名为 `uuidgen` |
| 7 | `Error checking request extension section fido_reqext / hex string too short` | 上次失败残留的空 `crypto_data/aaguid.txt` | `rm -f crypto_data/aaguid.txt` 后重跑 `setup.sh` |
| 8 | `error: linking with 'link.exe' failed: exit code: 1 … link: extra operand` | Git Bash 的 GNU coreutils 里有个 `link.exe`，冒充了 MSVC 链接器 | 切到 **windows-gnu** 工具链（本项目默认就是 `x86_64-pc-windows-gnu`） |
| 9 | `dlltool.exe` 找不到；或 `CreateProcess` 失败（缺 `as.exe`） | Rust 的 gnu 工具链需要 binutils | 装 MSYS2 并 `pacman -S mingw-w64-x86_64-binutils`；把 `C:\msys64\mingw64\bin` 加入 PATH |
| 10 | `cargo install cargo-audit` 编译失败 | 缺 MSVC 链接器，而 cargo-audit 依赖它 | 本项目已打补丁：**没有 MSVC 就跳过 cargo-audit**（它是可选组件，不影响刷机） |
| 11 | `error: patch location '…\crates\patches\panic-abort' does not contain packages matching 'panic-abort'` | `[patch.crates-io]` 的**相对路径写错**（bootloader 嵌套 4 层，比 runner-nordic 多一级） | runner-nordic 用 `../../patches/panic-abort`，bootloader 用 `../../../../patches/panic-abort` |
| 12 | 后台执行 `rustup` 直接崩 | rustup 无 TTY 时会 panic | **必须前台运行** |
| 13 | 多行 `bash -c "..."` 里 `$PATH`/`$HOME` 被吃掉 | Windows 下 cmd 的引号转义会破坏长命令 | **一律写成 `.sh` 脚本文件再执行** |

---

## 二、烧录与运行类

| # | 现象 | 根因 | 解法 |
|---|---|---|---|
| 1 | `download` 报 `Unknown file magic` | probe-rs 默认按 ELF 解析 hex | 显式 `--binary-format hex`；**但更好的做法是直接烧 ELF**（见 #2） |
| 2 | 烧 `platform.hex` 后设备不工作，而且 `--verify` 居然"通过" | 该 hex 用 4 条 `02`（Extended Segment Address）记录把**同一段 0x0000–0xFFFF 重叠映射 4 次**；probe-rs 只写对第一段，verify 校验的是它自己解析出的（自洽但错误的）镜像 | **不要用 `platform.hex`**。用 `target/thumbv7em-none-eabi/release/bootloader`（`.runner` 段已注入 applet 的 ELF） |
| 3 | 设备一直停在 `Open DFU Bootloader`（`VID_1915&PID_521F`，枚举成 COM 口），按键/复位/拔插都无效 | **`0xE0000` 处的 Nordic 原厂 DFU bootloader 拒绝放行**（详见 [架构文档](02-architecture.md)） | 让它的向量表失效：烧录时用 `--allow-erase-all`（全片擦除会把它一起清掉） |
| 4 | 用 `platform.hex` 烧完后，读 `0x8000` 前 16 字节是 `00 00 00 00 ff ff...`，误以为"applet 是空的" | `0x8000` 前 `0x100` 字节是 **Header 占位区**，applet 从 `0x8100`/`0x8200` 开始 | 检查 `0x8100` 是否为 `00 80 00 20`（栈指针 `0x20008000`）、`0x8200` 是否有有效指令 |
| 5 | `objcopy` 报不认 ARM 架构 | MSYS2 的 mingw binutils 不支持 ARM | 用 Rust 工具链自带的 `llvm-objcopy.exe`（`~/.rustup/toolchains/<tc>/lib/rustlib/x86_64-pc-windows-gnu/bin/`） |
| 6 | 打开 DFU 那个 COM 口，**一个字节都读不到** | 它是 CTAP/DFU **协议口**，不打印启动日志 | 别指望这条路诊断。要看日志得改用 RTT/defmt |
| 7 | USB DFU 刷写报 `firmware requires unavailable SoftDevice version` | 出厂 bootloader 要求特定 SoftDevice 版本 | 这是死路的一部分，见 #8 |
| 8 | 补了 `sd_req` 候选、`fw_version=0xFFFFFFFF`、甚至用 Nordic 调试私钥签名后，仍报 `InvalidObject`（trace 里 `Execute`(op 4) 返回 `result 5`） | **厂商换了签名信任锚**：bootloader 校验用的不是 Nordic 的调试公钥 | **放弃 USB DFU，只用 SWD**。卖家原话："这个目前只能用 JLink 烧录程序，不支持串口写入" |
| 9 | `probe-rs list` 能看到 J-Link，但 `info` 失败 | J-Link 装的是 SEGGER 驱动，probe-rs 需要 **WinUSB** | 用 Zadig 把 J-Link 的驱动换成 WinUSB（`Options → List All Devices` → 选 J-Link → WinUSB → Replace Driver） |
| 10 | 改 bootloader settings 的 `image_crc` 想让 bootloader 放行，改了没效果 | 这条校验不是拦路的原因；而且 bootloader 读的是 `0xFF000` 不是 `0xFE000` | 别浪费时间，直接走 #3 的方案 |
| 11 | 改 UICR `NRFFW[0] = 0x1000` 想绕过 bootloader，没效果 | 反汇编 MBR 发现它**硬编码 `0x000E0000`**（literal pool 在 `0xFF8`），根本不读 UICR | 同上。但**不要**因此把 `NRFFW[0]` 清掉，它对启动可能仍有作用（见 [安全文档](03-security.md)） |
| 12 | 清空存储区后读回发现 `0xDA000` 还有 4 个非 FF 字节，以为没擦干净 | 写完 probe-rs 会恢复芯片运行，固件发现 store 为空**立刻自动格式化**并写回 init 记录（`00 00 00 CE`） | 这是正常现象 |
| 13 | 本地 WebAuthn 诊断页一直转圈打不开 | 单线程 `TCPServer` + 浏览器 keep-alive 把服务堵死 | 用 `ThreadingHTTPServer`，并同时监听 `127.0.0.1` 与 `[::1]` |
| 14 | WebAuthn `rp.id` 用 `127.0.0.1` 报错 | **rp.id 不能是 IP 地址** | 用 `http://localhost:端口`，`rp.id = "localhost"` |
| 15 | 注册成功，但认证报"此安全密钥看起来不太眼熟"（CTAP2 `NO_CREDENTIALS`） | 多数情况是站点侧残留的旧凭据 / 旧状态 | 换一个全新用户名重新注册即通；若仍失败，用 [诊断页](04-verification.md) 定位是哪一条链路断了 |
| 16 | 想让认证不需要按键 | 需要改固件 | `src/touch.rs` 的 `is_present()` 直接 `return true`（补丁 0001 已包含）。**注意这会让任何插上钥匙的电脑都能直接认证** |
| 17 | 开了 APPROTECT 后 `probe-rs` 全线报错 | 这是**保护生效的正常表现** | 见 [安全文档](03-security.md)；重刷走 `scripts/recover.sh` |
| 18 | 报 `lacked the permission to do so: erase_all` | probe-rs 提示你需要授权全片擦除才能访问已保护的芯片 | **不要盲目加 `--allow-erase-all`**，那会清空一切 |

---

## 三、一句话总结

**这个项目的坑分三层**：
1. **环境层**（第 1 张表）——Windows 上编译 Rust 嵌入式项目的通病，按表逐个垫片即可；
2. **工具层**（#1、#2、#5）——probe-rs 与 Intel HEX 的兼容性问题，绕开用 ELF；
3. **芯片层**（#3）——**真正的拦路虎**，Nordic 原厂 bootloader 挡住了 MBR 到应用的跳转，必须让它失效。
