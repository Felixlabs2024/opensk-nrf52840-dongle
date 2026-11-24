# patches

四个补丁，按编号顺序应用。`scripts/apply-patches.sh` 会自动完成，这里说明手动做法和依赖关系。

## 应用顺序与位置

| 补丁 | 作用目录 | 说明 |
|---|---|---|
| `0001-opensk-toolchain-touch.patch` | **OpenSK 仓库根** | 工具链版本 + `setup.sh` + **免按键补丁** |
| `0002-wasefire-toolchain.patch` | `third_party/wasefire` | 工具链版本 + 裁剪 target |
| `0003-wasefire-windows-port.patch` | `third_party/wasefire` | Windows 移植（5 个文件） |
| `0004-wasefire-panic-abort.patch` | `third_party/wasefire` | 两个 `Cargo.toml` 的 `[patch.crates-io]` |

手动应用：

```bash
cd /path/to/OpenSK
git apply /path/to/repo/patches/0001-opensk-toolchain-touch.patch

cd third_party/wasefire
git apply /path/to/repo/patches/0002-wasefire-toolchain.patch
git apply /path/to/repo/patches/0003-wasefire-windows-port.patch
git apply /path/to/repo/patches/0004-wasefire-panic-abort.patch

# 0004 引用了 ../vendor/panic-abort，必须先放到位
mkdir -p patches
cp -r /path/to/repo/vendor/panic-abort patches/panic-abort
```

## 依赖关系

`0004` 里的 `[patch.crates-io]` 是相对路径：

- `crates/runner-nordic/Cargo.toml` → `../../patches/panic-abort`
- `crates/runner-nordic/crates/bootloader/Cargo.toml` → `../../../../patches/panic-abort`（**多一级**）

路径写错会报：

```
error: patch location '...\crates\patches\panic-abort' does not contain packages matching 'panic-abort'
```

所以 `panic-abort` 必须放在 `third_party/wasefire/patches/panic-abort`。

## 关于换行符

本仓库的补丁已统一为 **LF**。如果你的工作副本被 Git 转成了 CRLF（`core.autocrlf=true`），`git apply` 可能报 context 不匹配。三种处理：

```bash
git -c core.autocrlf=false apply <patch>          # 推荐
git apply --ignore-whitespace <patch>             # 备选
git config --global core.autocrlf false           # 一劳永逸
```

本仓库的四个补丁已用「从 `git show HEAD:` 取出的原始文件」做过 `git apply --check`，均能干净应用。

## 验证补丁是否生效

```bash
grep -n 'nightly' OpenSK/rust-toolchain.toml OpenSK/third_party/wasefire/rust-toolchain.toml
# 都应为 nightly-2026-10-05

grep -n -A2 'fn is_present' OpenSK/src/touch.rs
# 应返回 true

ls OpenSK/third_party/wasefire/patches/panic-abort/src/lib.rs
# 应存在
```

## 为什么不在仓库里直接放整份源码

OpenSK 加上 wasefire 子模块有几个 GB，且本项目只改了 **60 行左右**。用补丁 + 上游 clone 更轻、更透明，也便于跟随上游更新。

## 已知的上游版本

| 项目 | 版本 |
|---|---|
| OpenSK | develop 分支，`f53621c`（"Allow custom PIN hash verification (#836)"）附近 |
| wasefire | `1e46740ed6fe9b9900606454928bd3ae8c11cc7e` |

换其它版本时，`0003`（Windows 移植）最可能冲突，因为它是按上游当时的 Unix 专属 API 写的。
