# 架构：启动链路与 Flash 布局 / Boot Chain & Flash Layout

理解这一页，才能理解"为什么要这么做"。这也是整个项目最难、最花时间的一块。

---

## 一、启动链路（本项目的核心）

```
上电 / 复位
 │
 ├─ MBR (0x0)  ← 芯片固化，不可修改
 │     │  反汇编可见：literal pool 在 0xFF8 处硬编码 0x000E0000
 │     │  （不动点：它【不】读 UICR.NRFFW[0] 来决定跳转）
 │     ▼
 ├─ 0xE0000: Nordic 原厂 DFU Bootloader
 │     │  校验 0x1000 处应用（settings 里的 image_crc / image_size / bank_code）
 │     ├─ 校验通过 → 跳 0x1000
 │     └─ 校验失败 → 停在 DFU 模式
 │                    USB 枚举为 "Open DFU Bootloader" (VID_1915:PID_521F) + COM 口
 │                    ↑↑↑ 就是这里，卡了整整一个阶段 ↑↑↑
 │     ▼
 ├─ 0x1000: wasefire bootloader（只做一件事：比较 A/B 两侧 Header 版本，然后跳 0x8100）
 │     ▼
 └─ 0x8100: runner + OpenSK applet（native 链接在一起）
       ▼
    USB 枚举为 FIDO HID (VID_18D1:PID_0239)
```

**关键结论**：只要 `0xE0000` 那个 bootloader 还活着并拒绝放行，后面刷得再对也永远不会执行。

---

## 二、Flash 分区（nRF52840 Dongle，来自 `board-dongle.x` + `memory.x`）

| 区域 | 地址范围 | 用途 |
|---|---|---|
| MBR | `0x00000–0x01000` | 芯片固化 |
| wasefire bootloader | `0x01000–0x08000` | 复位向量 `0x1101` |
| platform A · Header | `0x08000–0x08100` | `version@0x00`、`attempts@0x04`(×3)、`name@0x10` |
| platform A · 代码 | `0x08100–0x98000` | **runner + OpenSK applet 都在这里** |
| platform B · Header | `0x50000–0x50100` | A/B 双分区升级用（本项目为空） |
| platform B · 代码 | `0x50100–0x98000` | 空 |
| applet 区（动态 applet） | `0x98000–0xDA000` | native applet 不用此区 |
| **持久化存储 store** | `0xDA000–0xE0000` | **24KB（6×4KB）**，凭据 / PIN / 主密钥都在这 |
| **Nordic 原厂 bootloader** | `0xE0000–0x100000` | 本项目已擦除其向量表 |
| Nordic bootloader settings | `0xFE000` / `0xFF000` | 两页内容相同；bootloader 实际读 `0xFF000` |
| UICR | `0x10001000+` | `NRFFW[0]@0x10001014`、`PSELRESET@0x10001200`、`APPROTECT@0x10001208` |

几个容易记错的点：

- **`0x8000` 前 0x100 字节不是代码**，是 Header 占位区（`00 00 00 00 ff ff...`）。applet 从 `0x8100` 开始 —— 只看前 16 字节会误判"applet 没烧进去"。
- **凭据存在 `0xDA000`**，不在 applet 里。所以清凭据和刷固件是两件事（开了 APPROTECT 才被迫合并）。
- **OpenSK 的凭据键空间是 `1700..2000`**，最多 150 条；PIN、计数器、主密钥在键 `1..20`。

---

## 三、为什么"改 settings / 改 UICR"都不管用

在找到真正解法前，试过两条看起来很有道理的路，都失败了。**记录下来是为了让你不要重走**：

### 尝试 A：修正 bootloader settings 的 CRC

推断：bootloader 校验 `0x1000` 处应用的 CRC，刷了新固件导致不匹配，所以拒绝跳转。

做法：读 `0xFE000` / `0xFF000`，逆出结构 —— `image_size@0x18`、`image_crc@0x1C`、`bank_code@0x20`，且 settings 自身 CRC 覆盖 `[4, 0x5C)`、算法是标准 CRC-32（用自校验验证过算法正确）。然后把 CRC 改成当前固件的值并写回。

结果：**无效**，设备行为不变。

结论：拦路的不是这个校验（或者它还有更上层的条件）。

### 尝试 B：改 UICR `NRFFW[0]` 让 MBR 直接跳 `0x1000`

推断：MBR 从 `UICR->NRFFW[0]` 读 bootloader 地址，把它改成 `0x1000` 就能跳过 Nordic bootloader。

做法：写入 `0x00001000` 到 `0x10001014`，复位。

结果：**表面无效**（当时看 `Header A` 的 attempts 字段没变化）。后来反汇编 MBR 才确认：**它硬编码 `0x000E0000`，根本不读 UICR**。

> ⚠️ 但这里有个**未解的历史疑点**：最终成功的那次，`NRFFW[0]=0x1000` 和"擦除 `0xE0000`"**两件事同时存在**，而当时的判据是错的，所以无法 100% 排除 `NRFFW[0]` 也起了作用。
> **因此：永远不要清掉 `NRFFW[0]`**。`scripts/protect.sh` 和 `scripts/recover.sh` 都是"保留式"写入 UICR 的，正是为了这个原因。

---

## 四、真正的解法：让 Nordic bootloader 失效

**做法**：把 `0xE0000` 处的向量表擦成空白（写 4KB 全 `0xFF`）。

**为什么有效**：MBR 的目标地址是死的（`0xE0000`），但它对目标内容的校验会失败；失败后 MBR 仍会把控制权交给 `0x1000`（wasefire bootloader），于是后面的链路正常跑起来。

**实际操作**：不需要单独做这一步。因为烧录命令里的 **`--allow-erase-all` 本身就是全片擦除**，会把 `0xE0000` 一起清成空白：

```bash
probe-rs download --chip nRF52840_xxAA --probe 1366:0101 \
  --allow-erase-all --binary-format elf --verify --reset \
  firmware/opensk-nrf52840dongle.elf
```

**代价**：Nordic 的 USB DFU 升级通道**永久失效**（事后想恢复只能全片重刷）。对个人/开发用途完全可以接受。

---

## 五、怎么判断 wasefire 到底有没有跑起来

按可靠性从低到高：

| 判据 | 可靠性 | 说明 |
|---|---|---|
| `Header A @0x8000` 的 `attempts` 变成 0 | ❌ 不可靠 | 只有 A 侧被选中时才写，容易误判 |
| `Header B @0x50000` 的 `attempts[0]` 从 `FF` 变成 `00` | 🟡 一般 | wasefire 的 `mark()` 执行过 |
| **USB 枚举出现 `VID_18D1&PID_0239` 的 `HID-compliant fido`** | ✅ **唯一可靠** | 用 `scripts/verify.sh` 即可 |

---

## 六、产物之间的关系（避免拿错文件）

| 文件 | 是什么 | 能不能烧 |
|---|---|---|
| `target/wasefire/platform.hex` | bootloader + applet 的 iHEX 打包 | ❌ **不要用**（分段编码 probe-rs 解析不了） |
| `target/wasefire/platform_a.bin` | 只有 applet 包（174096 字节） | ❌ 单独烧没有意义 |
| `target/wasefire/platform.wfb` | wasefire bundle 容器 | ❌ 不是给 SWD 用的 |
| **`target/thumbv7em-none-eabi/release/bootloader`** | **bootloader ELF，`.runner` 段已注入 applet** | ✅ **就用这个** |

`bootloader` 这个 ELF 是 `cargo xtask` 在构建流程里生成的：先 `cargo build` bootloader，再 `llvm-objcopy --update-section=.runner=<applet bundle>` 把 applet 注入进去。所以它虽然是"bootloader"这个名字，实际上已经是完整固件。

段布局参考（正常值）：

```
.runner         0x0002a810   VMA 0x8000    ← Header(0x100) + applet
.header         0x00000100   VMA 0x50000   ← B 侧 header 占位
.vector_table   0x00000100   VMA 0x1000    ← wasefire bootloader 向量表
.text           0x00000264   VMA 0x1100
```
