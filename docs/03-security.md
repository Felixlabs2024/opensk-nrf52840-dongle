# 安全：威胁模型与 APPROTECT / Security & APPROTECT

> 结论先给：**不开读保护的 nRF52840 安全密钥，等于没有保护。** 任何人拿到板子、接 4 根线、跑一条命令，就能把全部私钥导出来。

---

## 一、先看清威胁模型

| 攻击场景 | 不开保护 | 开了 APPROTECT |
|---|---|---|
| 网络钓鱼 / 冒充网站 | 🟢 很强（FIDO 的 origin 绑定，这是硬保证） | 🟢 一样 |
| 远程攻击（陌生人、网上程序） | 🟢 很强（密钥不在网络上） | 🟢 一样 |
| 电脑被恶意软件入侵 | 🟡 中（可用但需要 PIN；免按键补丁会削弱） | 🟡 一样 |
| **物理接触（拿到硬件）** | 🔴 **极弱，5 分钟可破** | 🟡 需要专业设备（见第五节） |

本文主要解决最后一行。

---

## 二、为什么必须开

nRF52840 是普通 MCU，没有安全元件。你的凭据是这样存的：

- 私钥用 **master key**（128 字节）加密后存在 flash（store 区 `0xDA000`）；
- **master key 本身也明文存在同一块 flash**；
- PIN 不参与私钥加密，只控制"使用时的授权"。

所以 **只要 flash 能被读出，就能拿到 master key，进而离线解出所有私钥，完全冒充你 —— 连 PIN 都不需要**。

没有 APPROTECT 时，读出 flash 只需要：

```bash
probe-rs read --chip nRF52840_xxAA --probe <sn> b8 0xDA000 24576 -f binary -o store.bin
```

（调试阶段常用这一步确认凭据是否真的写进了 flash。）

---

## 三、APPROTECT 做了什么

- 配置位：`UICR.APPROTECT` @ `0x10001208`，写 `0x00000000` 启用；
- 上电时硬件状态机读到该值，把调试访问端口（DAP）与内部总线断开；
- 之后所有 SWD 读写 flash 的请求被硬件拒绝。

| 能力 | 未保护 | 已保护 |
|---|---|---|
| SWD 读 flash / store | ✅ | ❌ |
| 改固件植入后门 | ✅ | ❌ |
| 重置 PIN 错误计数器后爆破 PIN | ✅ | ❌（8 次后锁死） |
| ERASEALL 全片擦除 | ✅ | ✅ **仍然可用——但擦完什么都没了** |

**关键**：ERASEALL 只能"毁掉"，不能"读出"。这是 APPROTECT 的全部价值。

---

## 四、怎么开（保留式写入，别搞错）

### 为什么不能"擦掉整页只写 APPROTECT"

nRF52 的 flash 只能**整页擦、按字写**。UICR 是独立一页（`0x10001000`，1KB），改任何一个字节都要先擦整页。而这一页里还存着：

| 字段 | 地址 | 说明 |
|---|---|---|
| `NRFFW[0]` | `0x10001014` | 启动地址（实测值 `0x00001000`）。**丢了可能起不来** |
| `PSELRESET[0]/[1]` | `0x10001200` / `0x10001204` | 复位引脚配置（实测值 `0x12`） |
| `APPROTECT` | `0x10001208` | 要改成 `0x00000000` |

### 正确做法

`scripts/protect.sh` 已经实现，手动等价于：

```bash
# 1) 备份整页
probe-rs read --chip nRF52840_xxAA --probe <sn> b8 0x10001000 1024 -f binary -o uicr.bin
# 2) 只改 0x208..0x20B 为 00，其余原样（用 python 改）
# 3) 整页写回
probe-rs download --chip nRF52840_xxAA --probe <sn> \
  --binary-format bin --base-address 0x10001000 --verify uicr-protected.bin
# 4) 断电重启（拔 SWD 线、插 USB）
```

实测：改动前后**只有 `0x208–0x20B` 四个字节不同**。

### 验证

| 检查 | 保护前 | 保护后 |
|---|---|---|
| `probe-rs info` | `Detected chip: nRF52840_xxAA` | ❌ `could not automatically be determined` |
| `probe-rs read` | 正常返回数据 | ❌ `lacked the permission to do so: erase_all` |
| USB 枚举 | HID FIDO | ✅ **仍是 HID FIDO（数据没丢）** |

---

## 五、保护强度能到什么程度（诚实版）

| 攻击者 | 未保护 | 已保护 |
|---|---|---|
| 同事 / 维修店 / 捡到的人（有 J-Link、会用 probe-rs） | 🔴 5 分钟 | 🟢 **做不到** |
| 有电子基础 + 自制 glitch 设备 | 🔴 | 🟡 看硅版本 |
| 专业实验室（ChipWhisperer / EMFI） | 🔴 | 🟡 40–95% 成功率，$500–2,500 |

取决于芯片的**硅版本**：

| | Legacy APPROTECT（约 2020 前，build code A/C） | SECUREAPPROTECT（B0/D0 及以后） |
|---|---|---|
| 机制 | UICR 寄存器 + 软件判定 | 硬件模块 + 128 位 OTP 密钥 |
| 已知绕过 | 电压毛刺（**CVE-2020-27211**） | 需电磁故障注入（EMFI） |
| 成功率 | 85–95% | 40–60% |
| 市价 | $500–900 / 5–8 天 | $1,200–2,500 / 8–15 天 |

判断方法：看芯片表面丝印，形如 `N52840 QIAA-Bx0`；`B0` 及以后是 SECUREAPPROTECT。

### 即使开了保护，仍然存在的路径

1. **故障注入**（上表）；
2. **固件漏洞** —— APPROTECT 只挡外部调试器，不挡"芯片自己跑被利用的代码"。CTAP2/USB 协议栈若有内存破坏漏洞，插着 USB 用畸形包就能利用，**不需要调试口**；
3. **侧信道**（功耗/电磁分析）；
4. **免按键补丁** —— 攻击者拿不走密钥，但可以**使用**它：任何插上钥匙的电脑都能直接认证（未强制 UV 的站点连 PIN 都不用）。要堵住这条必须去掉 `touch.rs` 补丁。

---

## 六、开了保护之后怎么重刷

见 `scripts/recover.sh`，本质是三步：

1. **ERASEALL** 解除保护（全片擦除：固件 + 凭据 + PIN + UICR）；
2. 烧固件（此时芯片已解锁）；
3. **写回 UICR**（`firmware/uicr/uicr-approtect.bin`）—— 因为 ERASEALL 把 `NRFFW[0]` 清成 `0xFFFFFFFF` 了，不恢复可能起不来。

> **顺序不能变**：UICR 必须最后写。写完 `APPROTECT=0` 后调试口**当场就锁**，之后无法再做任何 SWD 操作。

想恢复成"无保护"方便调试：第 3 步换成 `firmware/uicr/uicr-no-protection.bin`。

**不会变砖**：ERASEALL（CTRL-AP）永远可用，最坏情况就是全擦重来。

---

## 七、加固清单（按性价比）

| 优先级 | 措施 | 效果 | 代价 |
|---|---|---|---|
| ★★★ | **开 APPROTECT** | 从"5 分钟"变成"专业设备 + 数百到数千美元" | 无法 SWD 调试；升级需全擦 |
| ★★★ | **去掉免按键补丁**（`touch.rs` 改回读触摸） | 堵住"拿到钥匙就能用" | 每次认证要按一下 |
| ★★ | 所有站点强制 UV（`userVerification=required`） | 即使免按键也需 PIN | 每次输 PIN |
| ★★ | PIN 设 6 位以上 | 配合保护，8 次上限才真正有效 | 记忆负担 |
| ★ | 物理保管（不插公共电脑） | — | — |
