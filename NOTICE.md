# NOTICE

## 上游项目

本仓库的固件、补丁与文档是下列项目的衍生作品：

| 项目 | 许可 | 用途 |
|---|---|---|
| [google/OpenSK](https://github.com/google/OpenSK) | Apache-2.0 | FIDO2 / CTAP2 实现（applet） |
| [google/wasefire](https://github.com/google/wasefire) | Apache-2.0 | 安全执行环境 + nRF52840 runner / bootloader |
| [nrf-rs/nrf-hal](https://github.com/nrf-rs/nrf-hal) 等 | MIT / Apache-2.0 | 底层 HAL |

`firmware/opensk-nrf52840dongle.elf` 是上述代码的**编译产物**，其中包含 OpenSK、wasefire 及其依赖的机器码。
按 Apache-2.0 的要求，再分发时应保留上游的 LICENSE 与 NOTICE。**发布本仓库前请自行附上上游的 `LICENSE` 文件**（本仓库未内置，避免与上游版本不一致）。

## 本仓库自身

- 补丁（`patches/`）、脚本（`scripts/`）、文档（`docs/`、`README.md`、`index.html`）、工具（`tools/wa_diag/`）
  —— 以 **Apache-2.0** 发布。
- `vendor/panic-abort/` —— 修复自 `panic-abort 0.3.2`（原项目 MIT/Apache-2.0 双许可），改动仅把已移除的
  `core::intrinsics::abort()` 换成 `udf` 陷阱指令 / 宿主 abort。
- `firmware/uicr/*.bin` —— 设备 UICR 页快照（1KB），只含启动地址、复位引脚、APPROTECT 三个字段，**不含任何密钥材料**。

## 不含敏感数据

本仓库**刻意不包含**：

- 设备的持久化存储镜像（store 区 `0xDA000`，24KB）—— 里面有凭据、PIN 哈希和 **master key**；
- 任何私钥、PIN、attestation 私钥或 `crypto_data/` 内容；
- 与个人账号相关的任何标识。

如果你自己也 dump 了 store 区，**不要提交到公开仓库**。

## 安全提醒

本项目的固件包含一个**免按键补丁**（`src/touch.rs` 的 `is_present()` 恒为 `true`），意味着：

- 任何能把设备插上的主机都可以在**不需要物理确认**的情况下完成认证；
- 未强制 UV（user verification）的站点，连 PIN 都不需要。

并且，**若未开启 APPROTECT 读保护**，任何拿到设备的人都能通过 SWD 导出全部私钥（master key 明文存于 flash）。

请自行评估是否适合你的使用场景。详见 [`docs/03-security.md`](docs/03-security.md)。

## 免责声明

本项目为个人实验性质，与 Google、Nordic Semiconductor、SEGGER 均无关联，也未获其背书。
按"现状"提供，不附带任何担保。刷机有风险（可能损坏设备、丢失数据），请仅在**你拥有的硬件**上操作，并遵守当地法律。
