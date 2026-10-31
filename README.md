# OneCloud Linux 7.3.1 (Amlogic S805 / Meson8b)

把 Linux 7.3.1 上游 stable 内核移植到迅雷玩客云（Xunlei OneCloud，Amlogic S805 /
Meson8b）的构建工程，包含设备树与 U-Boot 补丁、内核配置、根文件系统定制脚本、
打包/校验脚本，以及完整的构建与刷机文档。

> 当前状态：已在真实玩客云上验证 7.3.1 启动、eMMC 根文件系统、千兆以太网、
> USB host（键盘）、Mali-450 GPU（lima 驱动 + Mesa）以及 HDMI 显示输出
> （1920x1080 framebuffer console，颜色正常）。
> eMMC 顺序读取已从约 15 MiB/s 提升到约 75 MiB/s（4K 小块不变），
> 由补丁 0004 的 DMA bounce buffer 实现，详见
> [BUILD_REPORT.md](BUILD_REPORT.md) 第 8.1 节。
> 已修复的启动/驱动阻断点：DTS 的 `/memory` 节点名（U-Boot 2011.03
> 内存 fixup 兼容性）、`uImage` 头部加载地址（与 Armbian 基线一致）、
> 根文件系统缺少 `modules.dep`/`modules.alias` 导致模块（含 GPU 驱动）无法加载、
> USB0 的 host 模式触发 PHY ACA/ID 检查导致 dwc2 probe 失败，以及 HDMI
> 移植中的 HHI `ranges`、DRM bridge 分配 API 和 HHI 可选访问问题。
> 详见 [BUILD_REPORT.md](BUILD_REPORT.md)。

## 文档

| 文件 | 内容 |
|---|---|
| [BUILD_REPORT.md](BUILD_REPORT.md) | 完整移植与构建报告：版本来源、设备树修改、根文件系统、校验结果、限制 |
| [FLASHING.md](FLASHING.md) | 刷机指南：线刷包与普通磁盘镜像的写入方法、串口与首次启动 |
| [docs/KERNEL_PACKAGES.md](docs/KERNEL_PACKAGES.md) | Debian/Armbian APT 和 Arch Linux ARM pacman 内核升级包 |

## 目录结构

```
.
├── build.sh              # 内核 / DTB / 模块 / initramfs / uImage 构建
├── package.sh            # 生成 .img、.burn.img、.xz 与 SHA256
├── verify.sh             # 113 项静态校验（不写块设备）
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
`openssl`、`patch`、`cpio`、`debugfs`、`depmod`（kmod）、`xz`、`curl`。交叉编译器与内核源码由脚本
按固定 SHA256 自动下载到 `tools/`。

```bash
./build.sh                 # 构建内核、模块、DTB、initramfs、uImage
PACKAGE=1 ./build.sh       # 构建后直接打包
./verify.sh                # 静态校验输出产物
```

补丁成功应用后会在 `src/linux-7.3.1-upstream/.onecloud-patches.sha256`
记录补丁集哈希，重复运行 `build.sh` 时会跳过已应用的补丁。修改
`patches/*.patch` 后请删除该文件并重新解压源码，否则旧的补丁栈可能与新
补丁冲突。

需要联网下载：

- Linux 7.3.1：<https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz>
- Arm GNU Toolchain 15.2.Rel1（arm-none-linux-gnueabihf）
- Armbian 26.08.0 OneCloud Bookworm Minimal 基线镜像（`package.sh`）

## 补丁

- `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`：新增
  `meson8b-onecloud.dts`，适配 7.x 的 PWM v2 与 USB 模式（USB0 使用 OTG +
  role-switch，见下文），并保留 U-Boot 2011.03 内存 fixup 能识别的 legacy
  `/memory` 节点。
- `patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`：新增 `xunlei`
  vendor prefix。
- `patches/0003-drm-meson-add-Meson8b-VPU-HDMI-support.patch`：Meson8/8b/8m2
  VPU、TranSwitch HDMI TX、VCLK 和 HDMI PHY 支持，并在 OneCloud DTS 中启用
  HDMI。
- `patches/0004-mmc-meson-mx-sdhc-optimize-dma-transfers.patch`：为 Meson MX
  SDHC 增加 128 KiB DMA bounce buffer，使块层可以把多个物理页合并为一个
  128 KiB MMC 命令；eMMC 顺序读从约 15 MiB/s 提升到约 75 MiB/s。
- `patches-uboot/0001-u-boot-gcc15-build-compat.patch`：让 pinned U-Boot
  在 GCC 15 下可构建。注意：GCC15 重编的 SPL/DDR 初始化在实机上不可靠，
  实验镜像只替换 U-Boot proper payload，SPL/DDR 仍使用 Armbian 基线。

## USB（DWC2 host）

- OneCloud 面向用户的 USB-A 口接在 **USB0（`c9040000.usb`，OTG 控制器）**
  上，不是 USB1。USB1（`c90c0000.usb`）为 host-only 控制器。
- 如果把 USB0 设成 `dr_mode = "host"`，`phy-meson8b-usb2` 会执行 ACA/ID
  检测；本板 ID 引脚悬空，检测返回 `USB ID detect failed`，PHY
  `power_on` 失败（`-EINVAL`），整个 dwc2 probe 中止，端口完全不可用。
- 正确做法与 Armbian 6.12 一致：USB0 使用 `dr_mode = "otg"` +
  `usb-role-switch` + `role-switch-default-mode = "host"`。OTG 模式下 PHY
  跳过 ACA 检查，dwc2 注册 role switch 并默认以 host 角色工作。7.3.1 主线
  的 DWC2 已内建这套 API，**不需要** Armbian 的 connector 补丁。
- 实机验证：USB-A 口插入 `CASUE USB KB` 键盘后正常枚举，生成
  `/dev/input/event1`～`event3`（键盘、Consumer Control、System Control）。
  USB 存储使用 `usb-storage` 模块，走相同的 host 路径。

## HDMI 显示（Meson8b VPU + TranSwitch HDMI TX）

- 设备树新增 `vpu@100000`（`amlogic,meson8b-vpu`）、`hdmi-tx@42000`
  （`amlogic,meson8b-hdmi-tx`）、`hdmi-phy@3a0`
  （`amlogic,meson8b-hdmi-tx-phy`）和 `hdmi-connector`，补丁为
  `patches/0003-drm-meson-add-Meson8b-VPU-HDMI-support.patch`。
- 内核启用 `CONFIG_DRM_MESON=m`、`CONFIG_DRM_MESON_TRANSWITCH_HDMI=m`、
  `CONFIG_PHY_MESON8_HDMI_TX=m`、`CONFIG_MESON_CANVAS=m` 和
  `CONFIG_DRM_DISPLAY_CONNECTOR=m`。启动后生成 `/dev/dri/card1` 和
  `card1-HDMI-A-1`，framebuffer console 输出 1920x1080。
- HDMI 模块由 `/etc/modules-load.d/onecloud.conf` 在开机时加载，
  `hdmi-load.service` 作为 deferred-probe 的兜底再次 `modprobe`；
  两处都是幂等的。模块加载顺序为 `display-connector` →
  `phy-meson8-hdmi-tx` → `meson-transwitch-hdmi` → `meson-drm`。
- 实机验证：HDMI 热插拔检测为 `connected`，EDID 可读，1920x1080
  framebuffer console 画面和颜色正常。S805 的 HDMI PHY 上限约 1.65 GHz，
  因此不支持 4K；HDMI 音频未验证。
- 移植时修复的 7.3.1 适配问题：
  - `hhi` syscon 节点补回 `#address-cells`/`#size-cells`/`ranges`，
    否则 `hdmi-phy@3a0` 没有可翻译的 MMIO 资源，PHY probe 返回 `-EINVAL`；
  - TranSwitch bridge 改用 `devm_drm_bridge_alloc()`，并补上
    `atomic_create_state`，否则 7.3.1 的 `drm_bridge_add()`/`attach` 会段错误；
  - `meson_venc_init()` 的 VDAC/HHI 写入加 `priv->hhi` 保护，S805 没有
    HHI 资源时不再 NULL 解引用；
  - VCLK 频率统一使用 Hz，HDMI PHY 频率上限也用 Hz 表示。

## GPU（Mali-450 / lima）

- 内核启用 `CONFIG_DRM_LIMA=m`，设备树使用 `meson8b.dtsi` 的
  `arm,mali-450` 节点；驱动绑定后生成 `/dev/dri/card0` 和
  `/dev/dri/renderD128`。
- 镜像通过 `/etc/modules-load.d/onecloud.conf` 中的 `lima` 在开机时自动加载。
  `build.sh` 会显式运行并校验 `depmod`，确保 `modules.dep`/`modules.alias`
  写入根文件系统；缺少这两个文件时 `modprobe` 和 udev 无法加载任何模块。
- 根文件系统包含 Bookworm 的 Mesa（`lima_dri.so`、libEGL、libGLES、libgbm）。
  EGL surfaceless + GLES2 实测：`GL_VENDOR: lima`、`GL_RENDERER: Mali450`。
- S805 的 HDMI 显示输出已启用（见上一节）；VPU 硬件视频解码没有
  mainline 驱动（视频解码仍走 CPU）。`VCC_CORE` 由 CPU 与 GPU 共用，
  DTS 不绑定 `mali-supply`，启动日志中的
  `_opp_set_regulators: no regulator (mali) found` 是预期提示，不影响 lima。
- 最小 Armbian 镜像默认不带 Mesa，只有 `/dev/dri` 不能完成 GL/EGL 渲染；
  `scripts/update-rootfs.sh` 已把 Mesa 运行库加入镜像。
- 非 root 用户需要加入 `video` 和 `render` 组才能访问 `/dev/dri`：
  `usermod -aG video,render <user>`。
- 实机自检：把 `scripts/gpu-check.py` 拷到设备后运行 `python3 gpu-check.py`。
  脚本用 EGL surfaceless 创建 GLES2 上下文，清屏并读回像素；成功时输出
  `GL_RENDERER: Mali450` 和 `RESULT: lima EGL/GLES2 rendering OK`，如果落到
  llvmpipe/softpipe 会直接报错。如果提示找不到 `libEGL.so.1`，说明镜像里没有
  安装 Mesa 运行库。

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
