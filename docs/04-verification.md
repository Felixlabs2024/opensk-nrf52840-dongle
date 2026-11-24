# 功能验证：本地 WebAuthn 诊断页 / Verification Tool

当设备"能注册但不能认证"或者"完全没反应"时，用 **webauthn.io** 很难判断问题出在哪一层。本目录下的 `tools/wa_diag/` 是一套**本地诊断页**，把 WebAuthn 的每一步拆开单独测。

---

## 一、为什么需要它

OpenSK 的凭据有两条完全不同的存储路径，失败方式也不同：

| 路径 | 触发条件 | 返回的 credential ID 长度 |
|---|---|---|
| **resident（可发现凭据）** | `residentKey: required`，凭据存 flash | **32 字节**（随机数） |
| **非 resident（加密 key handle）** | `residentKey: discouraged`，凭据自带加密 | **约 241 字节** |

而认证时的查找也有两条路径：
- 带 `allowCredentials`（站点知道凭据 ID）→ 先按 ID 查 store，再尝试解密 key handle；
- `allowCredentials: []`（usernameless）→ 遍历 store 里所有可发现凭据。

**只要看到 `idLength`，就能立刻知道固件走了哪条路。** 这就是诊断页最大的价值。

---

## 二、怎么跑

```bash
cd tools/wa_diag
python server.py
```

然后浏览器打开：

- **http://localhost:8765** —— 5 步基础测试
- **http://localhost:8765/credprotect.html** —— 6 步 credProtect / UV 组合测试

> ⚠️ 必须用 `localhost`，**不能用 `127.0.0.1`** —— WebAuthn 的 `rp.id` 不接受 IP 地址。
> 每步的结果会自动 POST 回 `diag.log`，同时显示在页面上。

---

## 三、5 步测试分别测什么

| 步骤 | 操作 | 验证的链路 |
|---|---|---|
| 1 | 注册 `residentKey=required` | 可发现凭据是否**写得进 flash**；看 `idLength` 是否 32 |
| 2 | 认证，`allowCredentials=[该凭据]` | **和 webauthn.io 完全一样**的流程 |
| 3 | 认证，`allowCredentials=[]` | 纯可发现凭据查找（usernameless） |
| 4 | 注册 `residentKey=discouraged` | 非 resident 路径；`idLength` 应约 241 |
| 5 | 认证第 4 步的凭据 | 主密钥能否正确**解密 key handle** |

判读逻辑：

| 结果 | 说明 |
|---|---|
| 2、3 都失败，4、5 成功 | resident 存储/查找坏了（flash 写入或 `iter_credentials` 有问题） |
| 2 失败、3 成功 | allowList 匹配环节有问题 |
| 4、5 失败 | 主密钥读取或 key handle 解密有问题 |
| 全成功 | 固件完全正常，问题在站点侧（旧凭据/旧状态），换个新用户名重注册即可 |

---

## 四、credProtect 页（6 步）

用来排除"凭据被标记为必须 UV，而某次认证没走 UV 导致被过滤"这种情况 —— 这是 CTAP2 里一个很容易误判的坑。

| 步骤 | 参数 |
|---|---|
| A | 注册，带 `extensions.credProtect = 2`，`rk/uv` 都用 `preferred` |
| B | 认证，`uv = preferred` |
| C | 认证，`uv = discouraged`（不输 PIN） |
| D | 认证，`uv = required` |
| E | 对照组：注册**不带** credProtect |
| F | 对照组认证，`uv = preferred` |

若 **B 失败、D 成功、F 成功** → 就是 credProtect + UV 策略导致的过滤。

---

## 五、本项目的实测基线（正常情况应该是这样）

```
步骤 1 注册 resident      成功  ~10s   idLength = 32   transports=[usb]
步骤 2 allowList 认证     成功  ~11s   sameId = true
步骤 3 空 allowList 认证  成功  ~12s   sameId = true, userHandle 正常返回
步骤 4 注册非 resident    成功   ~7s   idLength = 241
步骤 5 非 resident 认证   成功   ~8s   sameId = true

credProtect 组：A~F 全部成功（注：Windows 实际没有把 credProtect 扩展传给设备，ext 返回空）
```

如果你测出来的结果和这张表一致，说明**固件、存储、PIN、key handle 解密全部正常**，问题一定在站点侧或浏览器侧。

---

## 六、静态验收（不用浏览器）

```bash
./scripts/verify.sh
```

它会检查：

1. 是否有 `VID_18D1` 设备；
2. 是否是 `HID-compliant fido`；
3. 是否还有残留 COM 口（**应该没有**）。

期望输出：

```
Status  Class     FriendlyName
------  -----     ------------
OK      USB       USB Composite Device
OK      USBDevice Wasefire
OK      HIDClass  USB 输入设备
OK      HIDClass  HID-compliant fido
  OK: 已枚举为 FIDO HID
  无残留 COM 口
```

> 注意 `Wasefire` 那个 WinUSB 接口是固件的 `config-command` 特性开的配置通道，属于正常现象。

---

## 七、只能人工做的部分

两个标准站点实测（**必须做，这是最终判据**）：

1. 打开 https://webauthn.io → 输入用户名 → **Register** → 按提示设置/输入 PIN
2. 立刻 **Authenticate**（同一用户名）→ 应显示 "You're logged in!"
3. **拔插 USB** → 再 Authenticate 一次 → 仍应成功（验证 flash 持久化）

第 3 步是关键：很多"看起来能用"的实现，一断电凭据就没了。
