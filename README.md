# OneCloud Linux 7.3.1 (Amlogic S805 / Meson8b)

把 Linux 7.3.1 上游 stable 内核移植到迅雷玩客云（Xunlei OneCloud，Amlogic S805 /
Meson8b）的构建工程，包含设备树与 U-Boot 补丁、内核配置、根文件系统定制脚本、
打包/校验脚本，以及完整的构建与刷机文档。

> 当前状态：静态校验通过，尚未在真实 OneCloud 硬件上完成实机验证。
> 详见 [BUILD_REPORT.md](BUILD_REPORT.md)。

## 文档

| 文件 | 内容 |
|---|---|
| [BUILD_REPORT.md](BUILD_REPORT.md) | 完整移植与构建报告：版本来源、设备树修改、根文件系统、校验结果、限制 |
| [FLASHING.md](FLASHING.md) | 刷机指南：线刷包与普通磁盘镜像的写入方法、串口与首次启动 |

## 目录结构

```
.
├── build.sh              # 内核 / DTB / 模块 / initramfs / uImage 构建
├── package.sh            # 生成 .img、.burn.img、.xz 与 SHA256
├── verify.sh             # 102 项静态校验（不写块设备）
├── config/
│   ├── onecloud.fragment         # 叠加在 multi_v7_defconfig 上的内核配置
│   ├── onecloud-7.3.1.config     # 最终完整内核配置
│   └── rootfs/                   # 根文件系统网络与模块配置
├── patches/              # 内核补丁（OneCloud 设备树、vendor prefix）
├── patches-uboot/        # U-Boot GCC 15 构建兼容补丁
├── scripts/              # 工具链、initramfs、rootfs、U-Boot 辅助脚本
└── logs/                 # 各阶段构建与校验日志（文本）
```

## 构建

依赖：Arch Linux / 常见 Linux 发行版，`gcc`、`make`、`flex`、`bison`、`perl`、
`openssl`、`patch`、`cpio`、`debugfs`、`xz`、`curl`。交叉编译器与内核源码由脚本
按固定 SHA256 自动下载到 `tools/`。

```bash
./build.sh                 # 构建内核、模块、DTB、initramfs、uImage
PACKAGE=1 ./build.sh       # 构建后直接打包
./verify.sh                # 静态校验输出产物
```

需要联网下载：

- Linux 7.3.1：<https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz>
- Arm GNU Toolchain 15.2.Rel1（arm-none-linux-gnueabihf）
- Armbian 26.08.0 OneCloud Bookworm Minimal 基线镜像（`package.sh`）

## 补丁

- `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`：新增
  `meson8b-onecloud.dts`，适配 7.x 的 PWM v2、memory 节点与 USB 模式。
- `patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`：新增 `xunlei`
  vendor prefix。
- `patches-uboot/0001-u-boot-gcc15-build-compat.patch`：让 pinned U-Boot
  在 GCC 15 下可构建。

## 说明

本仓库只同步源码、配置、补丁、脚本、文档与文本日志，**不包含**任何编译产物或
二进制文件（内核 `zImage`/`uImage`/模块、`.img`/`.burn.img`、`.ext4`/`.vfat`、
交叉工具链、上游源码压缩包等）。这些内容由构建脚本在本地生成，输出目录为
`output/`。

## 上游与基线

- 内核：kernel.org Linux 7.3.1 stable
- 根文件系统基线：[upleung/armbian-onecloud](https://github.com/upleung/armbian-onecloud)
  release `v2026.08.03-2135`（Armbian 26.08.0，Debian Bookworm ARMHF）
- U-Boot：[hzyitc/u-boot-onecloud](https://github.com/hzyitc/u-boot-onecloud)
  commit `0038d741ed1c77a77570c3a6bf88fe6189c11733`
- AmlImg：[hzyitc/AmlImg](https://github.com/hzyitc/AmlImg)
  commit `5ede4ed30b27c10187af5258f7e2f61f9ad71e1e`
