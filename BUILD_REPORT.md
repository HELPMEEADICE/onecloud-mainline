# OneCloud (Amlogic S805 / Meson8b) Linux 7.3.1 移植与固件构建报告

日期：2026-10-31  
工程目录：`/home/hedc/OneCloud/onecloud-mainline`  
最终产物目录：`/home/hedc/OneCloud/onecloud-mainline/output`

## 1. 结论摘要

本次工程完成了以下实际工作：

- 从 **kernel.org 官方 stable 7.3.1** 源码构建了 ARM32 `zImage`、`uImage`、`meson8b-onecloud.dtb` 和 1078 个内核模块。
- 将 Armbian 社区 6.12 的 OneCloud 设备树移植到 7.3.1，修正了 7.x 下已变化的 PWM v2、memory 节点和 USB 模式（USB0 改为 OTG + role-switch，见 4.3 节）。
- 使用 **Armbian 26.08.0 OneCloud Bookworm Minimal** 的 Debian ARMHF 根文件系统和原版引导链，集成新内核、模块和最小 initramfs。
- 生成了可导入 Amlogic USB Burning Tool 的 `.burn.img`，并生成普通磁盘 `.img`、`.xz` 和 SHA256 校验文件。
- 完成 113 项静态校验，全部通过；`AmlImg` 解包、重新打包与最终镜像 **逐字节一致**。
- 在 QEMU `virt` 通用平台补充验证：内核解压、initramfs、ext4 根文件系统、systemd、SSH、串口 getty 均正常，进入 `onecloud login:`。
- 在真实玩客云上验证了 7.3.1 启动、eMMC 根文件系统、千兆以太网和 Mali-450 GPU：`lima` 开机自动加载，生成 `/dev/dri/card0`/`renderD128`，Mesa EGL/GLES2 渲染测试通过（`GL_RENDERER: Mali450`）。
- 在真实玩客云上验证了 USB-A 口 host 枚举（USB 键盘）和 SD 卡槽的块设备读写；SD 卡槽测试卡的详细结论见第 8 节。
- 修复了 eMMC 顺序读性能：`meson-mx-sdhc` 的块队列 `max_segments` 从 1 提升到 64，并用 128 KiB DMA bounce buffer 处理多段请求。真实玩客云上 128K/1M 顺序读从约 15 MiB/s 提升到约 75 MiB/s（约 5 倍），底层请求数从 32768 降到 1024；4K 小块保持不变，读回数据 SHA256 一致。详见 8.1 节。

**实机验证范围：** 已确认启动链、eMMC、以太网、USB host、SD 卡块设备读写、GPU 3D 和 eMMC 顺序读性能修复。HDMI 显示输出、WiFi、IR、CPU 调压/调频等仍未逐项验证。QEMU `virt` 使用通用 DTB，不能替代 Meson8b 外设验证。

## 2. 实际采用的版本与来源

| 项目 | 实际值 |
|---|---|
| 内核 | Linux **7.3.1**（stable） |
| 官方发布页 | https://www.kernel.org/ |
| 源码包 | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz` |
| 源码 SHA256 | `fa595aad93734f829c963c2a90ef7c3673224fd7fdae7b49406e397cde2de231` |
| 校验 | 与 kernel.org `sha256sums.asc` 中的值一致 |
| 发布信息 | `releases.json`：stable 7.3.1，2026-10-30 |
| `kernelrelease` | **7.3.1-onecloud** |
| 内核配置基线 | `arch/arm/configs/multi_v7_defconfig` + `config/onecloud.fragment` |
| 交叉编译器 | Arm GNU Toolchain **15.2.Rel1**，`arm-none-linux-gnueabihf-gcc 15.2.1` |
| 交叉 binutils | GNU ld **2.45.1** |
| 宿主 | Arch Linux，x86_64，36 核，125 GiB RAM |
| 宿主 GCC | 16.2.1（仅用于 host tools） |
| 内核构建方式 | out-of-tree：`build/linux-7.3.1-gcc15` |
| 设备树 | `arch/arm/boot/dts/amlogic/meson8b-onecloud.dts` |
| 设备树 compatible | `"xunlei,onecloud", "amlogic,meson8b"` |

内核 tarball 解压后未使用 git 仓库，因此没有 Git commit；以上 SHA256 是源码身份的主校验值。内核源码原始 tar 包保留在 `tools/linux-7.3.1.tar.xz`。

## 3. 固件基线

采用同一发布批次的 Armbian OneCloud 标准镜像和线刷镜像作为兼容基线：

| 文件 | SHA256 |
|---|---|
| `Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.img.xz` | `cf9ef8e58037eccc51c29b846c5cd9be2fdadea6241323ed3565f4c3096dac20` |
| `Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.burn.img.xz` | `a02c00898a16b1543d6ef052d21128b16ca127ad2a3d12f54e5337d80bdcec17` |

下载来源（upleung/armbian-onecloud release `v2026.08.03-2135`）：

- `https://github.com/upleung/armbian-onecloud/releases/download/v2026.08.03-2135/Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.img.xz`
- `https://github.com/upleung/armbian-onecloud/releases/download/v2026.08.03-2135/Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.burn.img.xz`
- 注：该 Release 自带的 `sha256sums.txt` 只列出了 XFCE 资产，未包含 minimal 资产；上表中的 minimal 哈希是对实际下载文件计算并固定到 `package.sh` 的。
- Release：`upleung/armbian-onecloud` `v2026.08.03-2135`（2026-08-03）。
- 选择理由：这是截至 2026-10-31 两个参考仓库中发布日期和 Armbian 版本号最新的 Release；hzyitc 仓库最新为 `ci-20250823`（Armbian 25.11.0），均早于该版本。新基线的 Bootloader、DDR、UBOOT_COMP、resource 与旧基线逐字节相同，分区偏移和 boot.scr 也保持兼容。

基线内容：

- 根文件系统：Debian GNU/Linux bookworm，ARMHF，systemd、SSH、apt、systemd-networkd、Netplan。
- 根文件系统 UUID：`8a03b678-0b46-4f41-bb09-3a2d154439bc`。
- boot FAT UUID：`F937-F6E8`，卷标 `armbi_boot`。
- 分区布局（普通镜像）：16 MiB 保留区 + 256 MiB FAT boot + 1336 MiB ext4 rootfs。
- 线刷包：`DDR`、`UBOOT_COMP`、`aml_sdc_burn.ini`、`platform.conf`、`bootloader`、`resource`、`boot` sparse、`rootfs` sparse 及对应 VERIFY 项。

Bootloader 保留 hzyitc/u-boot-onecloud 的已工作版本，未替换：

- 仓库：`https://github.com/hzyitc/u-boot-onecloud`
- commit：`0038d741ed1c77a77570c3a6bf88fe6189c11733`
- 版本字符串：`v2011.03-2410-g0038d741ed1`
- 线刷包中的 `4.bootloader.PARTITION` 与 `6.resource.PARTITION` 原样保留，SHA1 与基线一致。

### 3.1 根文件系统 apt 全量更新

在 ARMHF rootfs 中通过 `proot` + `qemu-arm-static` 执行了真实 apt 更新（不是仅改 sources）：

- `apt-get update`，然后 `apt-get -y -o Dpkg::Options::=--force-confold full-upgrade`。
- 为避免覆盖自建 7.3.1 内核和引导链，按住：
  `linux-image-current-meson`、`linux-dtb-current-meson`、`armbian-bsp-cli-onecloud-current`。
- 额外安装 Mali-450 用户态运行库（无桌面，仅 EGL/GLES/GBM）：
  `libgl1-mesa-dri`、`libegl-mesa0`、`libegl1`、`libgles2`、`libgbm1`、`mesa-utils`。
- 更新后主要版本：
  - `apt 2.6.1`
  - `openssh-server 1:9.2p1-2+deb12u10`
  - `systemd 252.39-1~deb12u2`
  - `armbian-firmware 26.8.3`
  - `armbian-config 26.8.0-trunk.426.1030.032129`
  - `u-boot-tools 2023.01+dfsg-2+deb12u3`（bookworm 当前版本）
- 使用 `scripts/restore-metadata.py` 从基线镜像恢复 setuid/setgid、shadow 组等元数据；最终 ext4 通过 `e2fsck -fn`。
- apt 全量升级并安装 Mesa 后，rootfs 仍有约 190 MiB 可用空间；写入 7.3.1 模块后约 154 MiB。

### 3.2 U-Boot 重建

最新 OneCloud U-Boot 源码仍是 hzyitc/u-boot-onecloud 的 `0038d741ed1c77a77570c3a6bf88fe6189c11733`（2022-10-28），没有更新的功能提交。本工程用 **Arm GNU Toolchain 15.2.Rel1** 重新构建了该源码，并为旧 U-Boot 2011.03 代码加入必要的 GCC 15/glibc 兼容补丁：

- `patches-uboot/0001-u-boot-gcc15-build-compat.patch`
- 兼容点：GNU89/fcommon、soft-float ABI、替代 32 位 i386 `bin2code`、现代 libgcc 的 `raise()` stub、host include 顺序、`show_boot_progress` weak 定义。
- 构建产物在 `output/uboot/`：`u-boot.bin`、`u-boot-comp.bin`、`ddr_init.bin`、补丁和构建日志。

**主镜像仍保留基线的已知可工作 Bootloader**，因为新编译的 U-Boot 没有经过真实硬件验证，直接替换不符合“保留可靠引导链”的原则。

早期实验镜像曾把 `1.UBOOT_COMP.USB` 和 `4.bootloader.PARTITION` 全部替换为
GCC 15 构建产物，实机结果是完全无法启动。原因是旧 U-Boot 2011.03 的 SPL /
DDR 初始化代码对编译器和时序非常敏感，上游 CI 本身使用的是 GCC Linaro 4.8，
而不是 GCC 15。现在实验镜像改为**混合引导链**：

- `1.UBOOT_COMP.USB`、`0.DDR.USB` 保持基线（保证 USB 烧录工具和救砖路径可用）；
- `4.bootloader.PARTITION` 的前 32 KiB（SPL + DDR 初始化 + 头）保持基线；
- 只把后面的压缩 U-Boot proper payload 替换为 GCC 15 构建的
  `output/uboot/u-boot-comp.bin`；
- `5.bootloader.VERIFY` 按新的 `4.bootloader.PARTITION` 更新。

对应文件：`OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img`。即使这个实验镜像
仍失败，主镜像和 USB 救砖路径也不受影响。没有串口和救砖手段时不要刷它。

## 4. 设备树移植

初始设备树来自 Armbian `armbian-build` 仓库 6.12 归档补丁：

- `patch/kernel/archive/meson-6.12/onecloud-0001-add-dts.patch`
- 上游作者：hzy `<hzyitc@outlook.com>`
- 参考仓库：`https://github.com/hzyitc/armbian-onecloud`、`https://github.com/hzyitc/armbian-build`

移植到 7.3.1 时做了以下必要修改（均已保存为补丁 `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`）：

1. **memory 节点**
   - 保留旧写法 `memory { ... }`，**不能**改成 `memory@40000000 { ... }`。
   - 原因：OneCloud 使用的 U-Boot 2011.03 在 `bootm_linux_fdt()` 中调用
     `fixup_memory_node()` / `fdt_fixup_memory_banks()`，这两个函数只按路径
     `/memory` 查找节点；若不存在就**额外创建**一个 `/memory`。
   - 若 DTS 写成 `memory@40000000`，U-Boot 会新增 `/memory`（0x0–0x40000000），
     同时保留 `memory@40000000`（0x40000000–0x80000000），内核因此看到两个重叠的
     1 GiB 内存节点（共 2 GiB），在 1 GiB 的 S805 上会导致早期启动挂死或内存错乱。
   - 保留 `/memory` 后，U-Boot 会把它修正为 0x0–0x40000000，与已验证的 Armbian
     6.12 基线行为一致。dtc 会产生一条无害的 `unit_address_vs_reg` 警告。

2. **PWM v2**
   - 7.3.1 的 `pwm-meson` 对 `amlogic,meson8-pwm-v2` 使用 4 个 clock 输入，且 binding 明确禁止 `clock-names`。
   - 删除 OneCloud DTS 中对 `&pwm_cd` 的旧式 `clocks = <&xtal>, <&xtal>; clock-names = "clkin0", "clkin1";` 覆盖，保留 `meson8b.dtsi` 中的 4 路 clock 描述。
   - 保留 `pwm_cd` 的 `pwm_c1_pins`/`pwm_d_pins` 和 `status = "okay"`，供 CPU 核心电压 `pwm-regulator` 使用。

3. **USB**
   - OneCloud 的 USB-A 口接在 **USB0（`c9040000.usb`，OTG 控制器）** 上；
     USB1（`c90c0000.usb`）是另一个 host-only 控制器。
   - 旧 Armbian DTS 使用 `dr_mode = "otg"` + `usb-role-switch` +
     `role-switch-default-mode = "host"`。移植时曾误以为 7.3.1 缺少
     DWC2 role-switch 支持，改成 `dr_mode = "host"`，结果 USB-A 口完全失效：
     PHY 在 host 模式下执行 ACA/ID 检测，本板 ID 引脚悬空，返回
     `USB ID detect failed`，`phy poweron` 失败（`-EINVAL`），dwc2 probe
     中止（`dwc2 c9040000.usb: probe with driver dwc2 failed with error -22`）。
   - 7.3.1 主线 `drivers/usb/dwc2/drd.c` **已经实现** `usb-role-switch` 和
     `role-switch-default-mode`，不需要 Armbian 的 connector 补丁。恢复为
     `dr_mode = "otg"` + `usb-role-switch` + `role-switch-default-mode = "host"`：
     OTG 模式让 PHY 跳过 ACA 检查，dwc2 注册 role switch 并默认以 host 角色
     工作。USB1 保持 `dr_mode = "host"`。
   - 实机验证：USB-A 口插入 `CASUE USB KB` 键盘后正常枚举，生成
     `/dev/input/event1`～`event3`，`lsusb` 可见 `2a7a:939f`。

4. **厂商前缀**
   - 在 `Documentation/devicetree/bindings/vendor-prefixes.yaml` 增加 `"^xunlei,.*"`，避免 `make dtbs_check` 的厂商前缀警告。保存为 `patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`。

**HDMI/DRM 显示（已移植并在实机验证）**

Armbian 6.12 的 HDMI 补丁系列（`0045`–`0067`）已移植为
`patches/0003-drm-meson-add-Meson8b-VPU-HDMI-support.patch`，包括 Meson8b VPU、
TranSwitch HDMI TX、HDMI PHY、VCLK 和 DTS 节点。实机验证 1920x1080
framebuffer console 正常显示，HDMI HPD/EDID 正常。

移植到 7.3.1 时修复的关键问题：

- `meson.dtsi` 的 `hhi` syscon 节点补回 `#address-cells`/`#size-cells`/`ranges`。
  7.3.1 删除了这三个属性，导致 `hdmi-phy@3a0` 的子设备没有可翻译的 MMIO
  资源，PHY probe 返回 `-EINVAL`。
- TranSwitch bridge 改用 `devm_drm_bridge_alloc()`，并补上
  `atomic_create_state` 回调。7.3.1 的 `drm_bridge_add()` 要求 bridge 由该
  helper 分配；旧式内嵌零初始化 `struct drm_bridge` 会在 `drm_bridge_add()`
  和 `drm_bridge_attach()` 中段错误。
- `meson_venc_init()` 的 VDAC/HHI 写入增加 `priv->hhi` 保护。S805 的 VPU
  节点没有 HHI 内存资源，`priv->hhi == NULL`，原先会 NULL 解引用。
- VCLK 频率统一按 Hz 传递（7.3.1 的 `clk_set_rate_exclusive()` 使用 Hz），
  HDMI PHY 频率上限也改为 Hz。
- bridge 的 `atomic_enable`/`atomic_disable`、`attach`/`detect`、
  `get_dai_id` 和 color format 标志按 7.3.1 API 调整。
- 不使用 Armbian 的 CVBS DAC PHY：7.3.1 没有该驱动，HDMI 不依赖它。

HDMI 驱动以模块形式构建，由 `/etc/modules-load.d/onecloud.conf` 在开机时
加载，`hdmi-load.service` 作为 deferred-probe 兜底；加载顺序为
`display-connector` → `phy-meson8-hdmi-tx` → `meson-transwitch-hdmi` →
`meson-drm`。

未移植的内容及原因：

- **USB OTG peripheral 模式**：USB0 已使用 `usb-role-switch` 并默认 host；
  本板 ID 引脚悬空、没有 OTG 连接器或角色切换源，因此 peripheral/gadget
  角色未验证，host 角色已实机验证。
- **IR 遥控器**：DTS 保留了 `&ir_receiver`，但本次配置中 `CONFIG_IR_MESON` 未被 Kconfig 接受（最终 `.config` 中没有该符号），因此没有 `meson-ir` 模块；不影响启动。
- **WiFi SDIO**：OneCloud 的 SDIO WiFi 需要额外芯片/固件支持，本次未配置；SD 卡槽本身可用。

## 5. 内核配置要点

完整配置：`output/kernel/config-7.3.1-onecloud`，片段：`config/onecloud.fragment`。

启动关键驱动均内建（`=y`）：

- `ARCH_MESON`、`MACH_MESON8`、`SMP`
- `PINCTRL_MESON8B`、`COMMON_CLK_MESON8B`、`RESET_MESON`
- `MMC_MESON_MX_SDHC`（eMMC）、`MMC_MESON_MX_SDIO`（SD 卡）、`MMC_BLOCK`、`PWRSEQ_EMMC`
- `EXT4_FS`、`VFAT_FS`、`NLS_ASCII`、`NLS_CODEPAGE_437`、`NLS_UTF8`
- `SERIAL_MESON`、`SERIAL_MESON_CONSOLE`
- `DWMAC_MESON`、`STMMAC_ETH`、`REALTEK_PHY`
- `PHY_MESON8B_USB2`、`USB_DWC2`（dual-role 编译，DTS 强制 host）
- `REGULATOR_PWM`、`PWM_MESON`
- `CPUFREQ_DT`、`MESON_MX_SOCINFO`、`NVMEM_MESON_MX_EFUSE`
- `MESON_WATCHDOG`
- `DEVTMPFS_MOUNT`、`BLK_DEV_INITRD`

模块（`=m`，已全部安装）：

- `USB_STORAGE=m`
- `MESON_SARADC=m`
- `DRM_LIMA=m`（Mali-450 3D GPU；依赖 `DRM_GEM_DMA_HELPER`、`DRM_SCHED`、`GPU_SCHED`，由 `modules.dep` 自动解析）
- 其余 multi_v7 模块共 1078 个 `.ko`，完整归档在 `output/modules/modules-7.3.1-onecloud.tar.xz`，并全部复制进根文件系统 `/lib/modules/7.3.1-onecloud`。

**模块依赖库缺失（GPU 无法驱动的直接原因）：**

早期打包产物中的 `/lib/modules/7.3.1-onecloud` 只有 `.ko`、`modules.builtin` 和 `modules.order`，缺少 `modules.dep`/`modules.alias`。实机上 `modprobe lima` 直接报 `Module lima not found`，udev 也无法根据 modalias 自动加载任何模块，所以 GPU 没有 `/dev/dri`。`make modules_install` 虽然打印了 `DEPMOD` 行，但该次构建没有实际留下数据库文件。现在：

- `build.sh` 在 `modules_install` 之后显式执行
  `depmod -ae -F System.map -b rootfs/modules-full 7.3.1-onecloud`，
  并检查 `modules.dep`、`modules.alias` 非空，否则构建失败。
- `package.sh` 在复制模块前再次检查，缺失时自动补跑 `depmod`。
- `lima` 写入 `/etc/modules-load.d/onecloud.conf`，保证开机即加载。
- `scripts/update-rootfs.sh` 安装 Mesa 的 EGL/GLES/GBM 运行库，使 `/dev/dri`
  能真正用于渲染。

**构建过程中发现并修复的关键问题：**

第一次 QEMU 启动时，systemd 报：

```
FAT-fs (vdb): IO charset ascii not found
boot.mount: Failed with result 'exit-code'
```

原因是只设置了 `CONFIG_FAT_DEFAULT_IOCHARSET="ascii"`，但没有内建 `CONFIG_NLS_ASCII` 和 `CONFIG_NLS_CODEPAGE_437`。这会导致实机 `/boot` 挂载失败并进入 emergency mode。已补上：

```
CONFIG_NLS=y
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ASCII=y
CONFIG_NLS_UTF8=y
CONFIG_FAT_DEFAULT_IOCHARSET="utf8"
```

并重新编译、重新打包、重新验证。最终 QEMU 启动不再出现 `boot.mount` 失败。

同时删除了内建 `CONFIG_CMDLINE="console=ttyAML0..."` 和 `CONFIG_CMDLINE_EXTEND`，与 Armbian 基线保持一致：控制台参数由 U-Boot `boot.scr` / `armbianEnv.txt` 提供，避免重复 console 参数和通用 QEMU 启动时等待不存在的 `ttyAML0`。

## 6. 启动链

启动链完全沿用基线：

- U-Boot：hzyitc u-boot-onecloud（Amlogic 2011.03 分支），保留原 `bootloader.PARTITION`。
- `boot.scr`：基线 U-Boot script，未修改；加载地址：
  - `uImage` → `0x20800000`
  - `uInitrd` → `0x22000000`
  - DTB → `0x21800000`
  - `bootm 0x20800000 0x22000000 0x21800000`
- `armbianEnv.txt`：`rootdev=UUID=8a03b678-0b46-4f41-bb09-3a2d154439bc`，`rootfstype=ext4`。
- 内核：`uImage` 头 load/entry 均为 `0x208000`（与 Armbian 基线一致）。
  `boot.scr` 先把文件加载到 `0x20800000`，再由 U-Boot `bootm` 按头部地址搬到
  `0x208000` 后启动。早期版本把头部写成 `0x20800000`，跳过了基线验证过的搬运路径。
- initramfs：静态 busybox 1.38.0 armhf，按 `/proc/cmdline` 的 `root=` 或内置 UUID 查找根设备，挂载 ext4 后 `switch_root` 到 `/sbin/init`。
- 根文件系统：Debian bookworm armhf，systemd；`/etc/fstab` 中 `/boot` 使用 FAT UUID `F937-F6E8`，与保留的 boot 分区一致。

## 7. 打包与 Amlogic 镜像格式

- `AmlImg`：`https://github.com/hzyitc/AmlImg`，commit `5ede4ed30b27c10187af5258f7e2f61f9ad71e1e`。
- 使用基线 `commands.txt` 的 12 项顺序，不修改 DDR、UBOOT_COMP、ini、platform、bootloader、resource。
- `boot` 与 `rootfs` 重新生成 Android/Amlogic sparse：
  - boot：256 MiB，block size 4096，sparse 扩展后 `268435456` 字节。
  - rootfs：1336 MiB，sparse 扩展后 `1400897536` 字节。
- 更新 `9.boot.VERIFY`、`11.rootfs.VERIFY` 为对应 sparse 文件的 SHA1，格式与基线一致（`sha1sum <hex>`，无换行）。
- `AmlImg pack` 生成 `.burn.img`；再次解包、重新打包后与最终文件 `cmp` 逐字节一致。

普通磁盘镜像不是通过改扩展名得到的：它是复制基线普通 `.img`，保留前 16 MiB 引导区，再在偏移 16 MiB 写入新 boot FAT、偏移 272 MiB 写入新 ext4 rootfs。分区表和 UUID 保持基线一致。

## 8. 验证结果

验证脚本：`verify.sh`，日志：`logs/verify-gpu.log`。

**113 项通过，0 项失败**，包括：

- 官方 7.3.1 源码 SHA256 与 kernel.org 校验值一致。
- `zImage` 为 ARM zImage；`uImage` 为 ARM Linux Kernel Image，load address `0x208000`；`uInitrd` 为 ARM ramdisk。
- `CONFIG_LOCALVERSION="-onecloud"`；关键启动配置均为 `y` 或所需 `m`；`CONFIG_DRM_LIMA=m`。
- DTB 可被 `dtc` 反编译，model/compatible/memory/eMMC/SDIO/Ethernet/USB/PWM/chosen 等节点存在且状态正确。
- DTB 保留 legacy `/memory` 节点（不是 `memory@40000000`），确保 U-Boot 2011.03
  的 `fdt_fixup_memory_banks()` 能更新而不是新增第二个内存节点。
- DTB 含启用的 Mali-450 节点（`arm,mali-450`）；`lima.ko` 存在于模块树和根文件系统。
- 模块树和根文件系统均包含非空的 `modules.dep`/`modules.alias`；
  `/etc/modules-load.d/onecloud.conf` 包含 `lima`。
- 模块 vermagic 为 `7.3.1-onecloud SMP mod_unload ARMv7 p2v8`；根文件系统中存在对应模块路径。
- 根文件系统通过 `e2fsck -fn`；Debian bookworm；`/lib/systemd/systemd` 为 ARM EABI5；`/etc/fstab` UUID 正确；
  包含 Mesa 的 `lima_dri.so`。
- boot FAT 可读、UUID 保持 `F937-F6E8`；`uImage`、`uInitrd`、`dtb/meson8b-onecloud.dtb` 均存在。
- `boot.scr` 为 U-Boot script，包含加载 uImage/uInitrd/DTB 和 `bootm` 三地址。
- 普通镜像 MBR 分区起点/大小正确；两个分区内容与 boot/rootfs 原始镜像逐字节一致；UUID 正确。
- `.burn.img` 用 AmlImg 解包成功；manifest 顺序与基线完全一致；DDR/UBOOT/ini/platform/bootloader/resource 未变；sparse 扩展后与 boot/rootfs 原始镜像逐字节一致；VERIFY SHA1 正确；重新打包逐字节一致。
- 镜像大小：`.burn.img` 1,246,726,296 字节（约 1.16 GiB），普通 `.img` 1,686,110,208 字节（约 1.57 GiB），均远小于 8 GB eMMC 容量。**闪存容量判断基于解压后的分区和镜像布局，不基于 `.xz` 压缩文件大小。**
- 补丁可对 pristine 7.3.1 文件重新应用。

### QEMU 补充验证

使用 QEMU 9.2.3 `virt,highmem=off`、Cortex-A15、1 GiB RAM，加载最终 `zImage` + `uInitrd`，并把 rootfs/boot 镜像作为 virtio 块设备：

- 观察到了内核解压和启动，串口显示 `Linux version 7.3.1-onecloud ... GCC 15.2.Rel1`。
- initramfs 找到 `UUID=8a03...`，将 `/dev/vda` 挂载为 ext4 根。
- apt 全量升级后的 rootfs 正常启动；systemd、`ssh.service`、`getty@tty1` 和 `serial-getty@ttyAMA0` 均启动，出现 `onecloud login: root (automatic login)`。
- `/boot`（FAT UUID `F937-F6E8`）挂载成功，没有 emergency mode。

注意：该测试使用 QEMU 生成的通用 DTB，未经过 Meson8b 的 eMMC、DWMAC、USB PHY、PWM regulator、CPU DVFS 等驱动路径，不能替代实机验证。日志：`logs/qemu-final-gcc15.log`（首次构建）、`logs/qemu-gpu-rootfs.log`（加入 Mesa 并重新打包后）。

### 实机验证（2026-10-31）

在真实 OneCloud（`root@<onecloud-ip>`）上完成：

- 内核启动：`Linux onecloud 7.3.1-onecloud #1 SMP ... armv7l`，根文件系统
  `/dev/mmcblk1p2`（eMMC），`eth0` 以 1 Gbps 全双工工作，SSH 可用。
- GPU 驱动：修复 `modules.dep` 后，`lima d00c0000.gpu` 识别出 Mali-450
  （gp + pp0/pp1），注册 `/dev/dri/card0` 和 `/dev/dri/renderD128`；
  重启后由 `systemd-modules-load` 自动加载，无需手工 `modprobe`。
- 用户态：Mesa 22.3.6 的 `lima_dri.so` 可用。EGL surfaceless + GLES2
  清屏并读回像素的测试结果为
  `GL_VENDOR: lima`、`GL_RENDERER: Mali450`、
  `GL_VERSION: OpenGL ES 2.0 Mesa 22.3.6`，读回 `[64, 128, 191, 255]`，
  `glGetError=0`。
- GPU devfreq：当前 255 MHz，可用频率
  255/364.285/425/510/637.5 MHz。
- USB host（2026-11-01）：USB0 恢复 `dr_mode = "otg"` + `usb-role-switch` +
  `role-switch-default-mode = "host"` 后，USB-A 口插入 `CASUE USB KB` 键盘
  正常枚举（`lsusb` 显示 `2a7a:939f`），生成 `/dev/input/event1`～`event3`
  （键盘、Consumer Control、System Control）。修复前 USB0 probe 报
  `USB ID detect failed` / `-22`，端口没有 root hub。
- SD 卡槽（2026-11-01）：`mmc0`（`amlogic,meson8b-sdio` + `mmc-slot`）能
  识别 SD 卡并完成 4-bit 块设备读写。测试用卡的 CID/CSD 在两次初始化间
  不一致：一次报 SanDisk 32GB（CSD v2.0、2021 年产），读错误后回退为
  32MB `SD032`（CSD v1.0、2006 年产）；32MB 回退模式下全卡 30.6MiB
  连续读取两次 MD5 一致（`80d0116c...`，约 7.6MB/s），证明卡槽和驱动的
  数据通路正常；32GB 模式下块读取会超时或极慢。该卡全卡内容为 0x88、
  没有分区表，回退身份的产品序列号为 `0xffffffff`，判断为扩容/异常卡。
  换用正常 SD 卡即可作为存储使用；此类异常卡在开机分区扫描时可能长时间
  占用 udev，甚至让 `/boot` 设备超时进入 emergency mode，建议不要长期
  插在机器里开机。
- 实机 `/lib/modules/7.3.1-onecloud/modules.dep` 和 `modules.alias` 的 SHA256
  与最终镜像内文件完全一致（`0c3bfa56...` / `04074733...`），说明镜像内的
  模块依赖库就是实机验证通过的那一份。
- 最终镜像内的 `lima_dri.so` 与实机渲染测试所用文件 SHA256 一致
 （`40197f41...`），Mesa 用户态也经过同一份二进制验证。
- 启动日志中的
  `lima: error -ENODEV: _opp_set_regulators: no regulator (mali) found`
  是预期提示：OneCloud 的 `VCC_CORE` 同时供给 CPU 和 GPU，DTS 故意不绑定
  `mali-supply`，避免 GPU DVFS 与 cpufreq 争抢同一个 PWM regulator。
  lima 仍正常初始化并按 OPP 调频。

### eMMC 顺序读性能修复（2026-11-01）

**问题与根因**

实机 fio 基线显示，128 MiB 顺序读无论 `bs` 为 4K、64K、128K 还是 1M，
底层块层请求数都恰好是 **32768 次，平均 4.0 KiB**；4K QD1 平均延迟约
258 µs，1M QD1 平均约 67 ms（约 256 × 258 µs），说明 1 MiB 请求被拆成了
256 个 4 KiB MMC 命令。

源码定位确认：

- `drivers/mmc/host/meson-mx-sdhc-mmc.c` 从未设置 `mmc->max_segs`，MMC
  core 在 `mmc_alloc_host()` 中默认设为 1，块层因此只能把每个请求限制在
  一个物理连续段（通常一页 4 KiB）。
- `meson_mx_sdhc_start_cmd()` 只把 `sg_dma_address(cmd->data->sg)`（第一个
  SG 段）写入 `MESON_SDHC_ADDR`；该控制器的内部 DMA 只有这一个地址寄存器，
  不能直接遍历 SG 表。
- 同一控制器的 Amlogic BSP 驱动使用 `max_segs = 1024` 和 512 KiB coherent
  bounce buffer，验证了"多段请求 → 连续缓冲区 → 单地址 DMA"的可行性。

**补丁 0004 的实现**

- 保留单 SG 段（`sg_len == 1`）的直接 DMA 路径，小 I/O 和 SDIO 不额外拷贝。
- 多 SG 段请求复制到 128 KiB bounce buffer：写方向在 DMA map 前
  `sg_copy_to_buffer()`，读方向在 `dma_unmap_single()` 后
  `sg_copy_from_buffer()`；cache 一致性由标准 DMA API 保证。
- `max_segs = 64`、`max_seg_size = max_req_size = 128 KiB`、
  `max_blk_count = max_req_size / 512 = 256`，保证来自块层和 SDIO 的请求
  都不超过 bounce buffer，并让 SDIO 大传输也按单段下发。
- bounce buffer 在 `probe()` 中用 `devm_kmalloc()` 分配一次；失败时回退到
  `max_segs = 1`，不会让 probe 失败。
- unmap 放在控制器 reset、FIFO flush 和 response read 之后；DMA map 失败
  只让当前请求失败，不再永久写入 `host->error`。
- 内存开销：每个 host 128 KiB bounce buffer；队列深度 64 × 64 个 SG 表项
  约 100 KiB，对 1 GiB RAM 可忽略。

**实测结果**

同一台玩客云，eMMC 为 Samsung 8GME4R，HS200 8-bit 141.67 MHz；除标注外
均为本次 3 次运行的均值：

| 测试 | 修改前 | 修改后 | 提升 | 底层请求数（前 → 后） |
|---|---:|---:|---:|---:|
| 4K QD1 | 14.47 MiB/s | 14.69 MiB/s | 1.02× | 32768 → 32768 |
| 64K QD1 | 15.06 MiB/s | 63.21 MiB/s | 4.2× | 32768 → 2048 |
| 128K QD1 | 15.08 MiB/s | 75.13 MiB/s | 5.0× | 32768 → 1024 |
| 1M QD1 | 15.07 MiB/s | 75.93 MiB/s | 5.0× | 32768 → 1024 |
| 1M 256M | 15.6 MiB/s* | 73.56 MiB/s | 4.7× | 32768 → 2048 |
| 4K QD16 | 15.4 MiB/s* | 15.69 MiB/s | 1.02× | 32768 → 32768 |

\* 修改前的 1M 256M 与 4K QD16 使用任务开始时提供的原始实测数据；其余为
本次基线复测。128K/1M 的平均请求大小从 4.0 KiB 变为 128.0 KiB。

| 测试 | 修改前 mean / P99 | 修改后 mean / P99 |
|---|---|---|
| 4K QD1 | 258–260 µs / 432 µs | 255 µs / 403 µs |
| 64K QD1 | 4.09–4.21 ms / 5.67–5.73 ms | 0.976 ms / 1.76 ms |
| 128K QD1 | 8.20–8.42 ms / 11.2–11.3 ms | 1.65 ms / 3.03 ms |
| 1M QD1 | 65.3–67.2 ms / 89.7 ms | 13.3 ms / 21.4 ms |

eMMC 冷启动后复测：64K 62.65 MiB/s、128K 74.72 MiB/s、1M 74.85 MiB/s，
与 USB 启动测试一致；1 GiB 长读 73.81 MiB/s。大请求的 `sys%` 从约
16–18% 降到约 10–11%。

**数据一致性与稳定性**

- 在 eMMC 根文件系统上创建 128 MiB 临时文件，`O_DIRECT` 写入后
  `drop_caches`，分别用 4K/64K/128K/1M O_DIRECT 读回：5 次 SHA256 全部为
  `f001a3d31164a0ecf5036ae904cc492fb1d0184baf4ce4b6a4b39561fdfd3bc9`，
  PASS；临时文件已删除。
- 256 MiB `fio --rw=write --verify=crc32c --do_verify=1` 通过（rc=0）。
- `/sys/kernel/debug/mmc1/err_stats` 所有计数器为 0；dmesg 无
  CRC/timeout/reset/DMA 错误；4K/64K/128K/1M 各 3 次运行速度波动小。
- 测试后确认 lima `/dev/dri/card0`、meson-drm `/dev/dri/card1`、
  USB 存储和千兆网络均正常。

**构建集成修复**

- `patches/0001` 的 DTS hunk 长度从 407 修正为 424。原值会让 `patch` 在
  干净 7.3.1 源码上静默截断新 DTS，丢掉 USB/IR 节点；`patches/0003` 的
  DTS 末段 hunk 也相应调整为在完整 DTS 末尾追加 HDMI 节点。
- `build.sh` 在补丁集 SHA256 变化时自动恢复 pristine 源码树并重新应用完整
  补丁栈；补丁集不变时仍由 stamp 跳过，重复构建不会重复应用。
- 从干净树应用 0001–0004 后生成的 DTB 与修复前构建的 DTB 反编译内容完全
  一致；`verify.sh` 113 项通过。

**限制与后续**

- 4K QD1/QD16 基本不变（约 14.7/15.7 MiB/s）。4 KiB 请求本来就走直接 DMA，
  本次补丁针对大请求合并，不改变小块随机性能。
- 128K/1M 约 75 MiB/s，约为 141.67 MB/s 总线速率的 55%；64K 为 63 MiB/s，
  128K 已进入平台期，主要受 eMMC 自身顺序读能力限制。继续增大
  `max_req_size` 或调整 PDMA burst 的收益有限，且会增加 bounce 内存和
  延迟，本次未做。
- 写路径实测约 24.4 MiB/s（256 MiB fio write + CRC32C verify 通过），受
  eMMC 写入能力限制；本次未针对写优化。
- 驱动仍要求单个 SG 段在物理上连续（MMC core 的 SG 构造约定）；多段请求
  一律 bounce。bounce buffer 的拷贝开销在 75 MiB/s 下约占 10% `sys` CPU。
- 补丁仅修改 `meson-mx-sdhc` host 驱动，使用标准 DMA/scatterlist API，
  checkpatch 为 0 errors / 0 warnings / 0 checks，设计有 BSP 驱动先例，
  具备提交 linux-mmc 的条件。可讨论点：是否把 `max_blk_count` 限制拆成
  单独补丁、bounce buffer 用 `devm_kmalloc` 还是 `dma_alloc_coherent`
  （后者在 ARM32 上通常是非缓存，拷贝更慢）、以及 `max_segs` 取 32 还是 64。

## 9. 产物清单

目录：`/home/hedc/OneCloud/onecloud-mainline/output`

| 文件 | 大小（字节） | SHA256 |
|---|---:|---|
| `OneCloud-Linux-7.3.1-armhf.burn.img` | 1,246,959,768 | `05cfa5f8d52a9332621b99e7d77d2d73664cfba290ffe3f72d5c52cc3b7736bb` |
| `OneCloud-Linux-7.3.1-armhf.burn.img.xz` | 384,138,584 | `689cfdeb3852906094ca192d575bb998b07368ada6a6fba6f75ae13c773b76ac` |
| `OneCloud-Linux-7.3.1-armhf.img` | 1,686,110,208 | `f31ca8f66d5b7446a8f299d8216b38c9e482bc34d34eef9d49e4d1ec490ce640` |
| `OneCloud-Linux-7.3.1-armhf.img.xz` | 384,327,012 | `e38f6bfca27dc9433513ca0f3720013aae1818f808b2aab6b540d9b66f5a2292` |
| `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img` | 1,246,950,508 | `4cdb172ef404401f638dfd21ec9c0585cc60b0c15b774121a944ca537d9d3155` |
| `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img.xz` | 384,479,904 | `3da845522d88b28dc0dee0a13d62b36b866a529ad3b34c50335fe07f148027f1` |

同时包含：

- `SHA256SUMS` 及六个单文件 `.sha256`。
- `kernel/zImage`、`kernel/uImage`、`kernel/uInitrd`、`kernel/meson8b-onecloud.dtb`、`kernel/config-7.3.1-onecloud`、`kernel/System.map-7.3.1-onecloud`。
- `modules/modules-7.3.1-onecloud.tar.xz`（完整 1078 模块）。
- `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`、`patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`。
- `patches-uboot/0001-u-boot-gcc15-build-compat.patch` 及 `uboot/` 下的 U-Boot 15.2 构建产物。
- 实验性 U-Boot 线刷包及 `.xz`、`.sha256`。
- `build.sh`、`package.sh`、`verify.sh` 及 `scripts/` 辅助脚本。
- `BUILD_REPORT.md`、`FLASHING.md`。

完整构建日志位于 `logs/`，包括 `kernel-gcc15-build2.log`、`package-gcc15-final.log`、`verify-gcc15-final.log`、`qemu-final-gcc15.log`；U-Boot 日志在 `output/uboot/build.log`。

## 10. 尚未解决/需要实机确认的问题

1. **实机验证范围仍有限。** 已在真实玩客云（私网地址已隐去）验证 7.3.1
   启动、eMMC 根文件系统、千兆以太网、USB host 枚举、Mali-450 GPU 3D、
   HDMI 1920x1080 显示（含 HPD/EDID）以及 SD 卡槽的块设备读写/拔插识别。
   尚未逐项确认：
   - USB 设备热插拔与 USB 存储大文件读写；
   - RTL8211F RGMII 时序和高负载下的长期稳定性；
   - CPU 核心电压 PWM regulator 与 cpufreq/GPU devfreq 的长期稳定性；
   - HDMI 音频和 4K 输出（S805 HDMI PHY 上限约 1.65 GHz）。
   
   SD 卡槽本身工作正常，但本次实机使用的 32GB 卡是扩容/异常卡（双身份、
   32GB 模式读超时、内容全 0x88），相关分析和风险见第 8 节；这属于卡的问题，
   不是 `meson-mx-sdio` 驱动或 DTS 的问题。

   已修复的两个启动阻断点（legacy `/memory` 节点、`uImage` 加载地址
   `0x208000`）均已在实机启动中验证通过。

2. **TrustZone 补丁未应用。** Armbian 6.12 归档中包含 Meson6/8/8b/8m2 的 TrustZone 固件支持补丁（`tz_firmware`、SMP、eFuse、socinfo）。本工程未应用，因为检查 hzyitc U-Boot 的 `m8b_onecloud` 配置没有启用 `CONFIG_MESON_TRUSTZONE`，主线的 `amlogic,meson8b-smp` 路径应该可用。如果实机出现：
   - 只有 CPU0 在线；
   - `meson-mx-efuse` 读取失败、MAC 地址异常；
   - 温度校准缺失；
   则需要移植 Armbian 的 `0029`–`0034` 补丁，并把 CPU `enable-method` 改为 `amlogic,meson8-trustzone-firmware-smp`（需同时加入 firmware 节点）。这是下一步最值得优先验证的兼容性点。

3. **HDMI 显示已启用。** `meson-drm`、`meson_transwitch_hdmi`、HDMI PHY
   和 `display-connector` 以模块形式加载，实机输出 1920x1080 framebuffer
   console，颜色正常。模块由 `/etc/modules-load.d/onecloud.conf` 和
   `hdmi-load.service` 自动加载。S805 的 HDMI PHY 上限约 1.65 GHz，因此
   不支持 4K；HDMI 音频未验证。若需要无模块的早期显示，可把上述符号改为
   `=y` 内建，但当前模块方案已在实机验证。

4. **IR 驱动未编译。** `CONFIG_IR_MESON` 在当前配置组合下未被 Kconfig 接受；DTS 节点保留但无驱动。若需要红外，需要单独调整 `RC_CORE`/media 依赖并重新构建。

5. **WiFi 未配置。** SDIO WiFi 需要具体芯片型号、固件和 NVRAM；本工程未包含。

6. **MAC 地址。** 没有从 eFuse 显式指定 MAC；如果 efuse 读取失败，内核可能使用随机 MAC。实机可用 `ip link` 查看。

7. **根文件系统仍保留旧 6.12 模块目录。** 这是从 Armbian 基线继承的 `/lib/modules/6.12.28-current-meson`。它不影响 7.3.1 启动；如需进一步精简，可在最终 rootfs 中删除。写入 7.3.1 模块后，当前 rootfs 有约 154 MiB 可用空间。

8. **Armbian 首次启动策略。** 根文件系统保留 Armbian `armbian-firstrun`、SSH 主机密钥和默认用户策略。请按 Armbian 默认首次启动流程登录（常见为 `root/1234`，若系统提示修改请立即修改），或通过串口/SSH 设置强密码。不要把该镜像直接暴露在不可信网络。

9. **VPU 视频硬解未支持。** 本次启用的 Mali-450/lima 只提供 3D 加速。S805 的
   VPU 视频解码单元没有 mainline 驱动，H.264/H.265 等视频解码仍由 CPU 完成；
   需要硬解时应使用厂商 3.10/4.4 内核或等待 mainline VPU 支持。

## 11. 复现

```bash
cd /home/hedc/OneCloud/onecloud-mainline

# 仅构建内核、模块、DTB、initramfs、uImage
./build.sh

# 重新组装 rootfs/boot/普通镜像/线刷镜像，并压缩、生成校验
./package.sh

# 静态校验（不接触块设备）
./verify.sh
```

`build.sh` 会：

- 下载并校验 `linux-7.3.1.tar.xz` 和 Arm GNU Toolchain 15.2.Rel1；
- 解压源码、应用 `patches/*.patch`；
- 以 `multi_v7_defconfig` 为基础合并 `config/onecloud.fragment`；
- 编译 `zImage`、模块、DTB；
- 生成最小 initramfs、`uImage`、`uInitrd`；
- 默认调用 `scripts/build-uboot.sh`（`BUILD_UBOOT=1`），再调用 `package.sh`。

`scripts/update-rootfs.sh` 可在 ARMHF rootfs 中重新执行 apt 更新，安装 Mali-450 的 Mesa 用户态运行库，并调用 `scripts/restore-metadata.py` 恢复 setuid/setgid 和组归属；`scripts/verify-uboot.sh` 校验实验性 U-Boot 镜像。

`package.sh` 默认使用已通过 apt 更新的 `rootfs/onecloud-rootfs.ext4`（由 `scripts/update-rootfs.sh` 生成），把新的 7.3.1 模块写入其中；如果该文件不存在，则回退到 Armbian 基线 rootfs。原始下载文件不会被修改，所有中间副本位于 `build/` 和 `rootfs/`。

## 12. 结论

当前交付物是**真实生成、可解包、可校验、格式合法**的 Amlogic 线刷包和普通磁盘镜像，不是方案或伪文件。内核来自官方 stable 7.3.1，设备树针对 7.3.1 做了实际修复，根文件系统和引导链来自经过验证的 Armbian OneCloud 基线。静态验证、QEMU 用户空间验证和真实玩客云实机验证均通过。

本次修复的三个阻断点：

1. `memory@40000000` → `memory`：U-Boot 2011.03 的 `fixup_memory_node()` 只查找
   `/memory`，否则会新增第二个内存节点，内核在 1 GiB 板上看到 2 GiB。
2. `uImage` 头 load/entry `0x20800000` → `0x208000`：与 Armbian 6.12 已验证
   镜像一致，恢复 `bootm` 的标准搬运路径。
3. 根文件系统缺少 `modules.dep`/`modules.alias`：`modprobe` 和 udev 无法加载
   任何模块，Mali-450 的 `lima` 驱动因此不绑定、没有 `/dev/dri`。现在
   `build.sh` 显式运行并校验 `depmod`，`package.sh` 再次检查，`lima` 写入
   `/etc/modules-load.d/onecloud.conf`；实机重启后 GPU 自动可用。

实验性 GCC15 U-Boot 镜像改为“基线 SPL/DDR + GCC15 U-Boot payload”，避免
GCC15 重编时序敏感的 SPL 导致完全无法启动。

最终结论：

> **静态校验通过；QEMU 通用平台用户空间验证通过；真实 OneCloud（Amlogic S805）
> 实机验证了启动、eMMC、千兆以太网、Mali-450 GPU 3D 和 HDMI 1920x1080
> 显示输出。**
