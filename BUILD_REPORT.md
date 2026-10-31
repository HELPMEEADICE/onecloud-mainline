# OneCloud (Amlogic S805 / Meson8b) Linux 7.3.1 移植与固件构建报告

日期：2026-10-31  
工程目录：`/home/hedc/OneCloud/onecloud-mainline`  
最终产物目录：`/home/hedc/OneCloud/onecloud-mainline/output`

## 1. 结论摘要

本次工程完成了以下实际工作：

- 从 **kernel.org 官方 stable 7.3.1** 源码构建了 ARM32 `zImage`、`uImage`、`meson8b-onecloud.dtb` 和 1078 个内核模块。
- 将 Armbian 社区 6.12 的 OneCloud 设备树移植到 7.3.1，修正了 7.x 下已变化的 PWM v2、memory 节点和 USB 模式描述。
- 使用 **Armbian 26.08.0 OneCloud Bookworm Minimal** 的 Debian ARMHF 根文件系统和原版引导链，集成新内核、模块和最小 initramfs。
- 生成了可导入 Amlogic USB Burning Tool 的 `.burn.img`，并生成普通磁盘 `.img`、`.xz` 和 SHA256 校验文件。
- 完成 102 项静态校验，全部通过；`AmlImg` 解包、重新打包与最终镜像 **逐字节一致**。
- 在 QEMU `virt` 通用平台补充验证：内核解压、initramfs、ext4 根文件系统、systemd、SSH、串口 getty 均正常，进入 `onecloud login:`。

**必须明确的限制：当前结果为“静态校验通过，尚未实机验证”。** QEMU `virt` 使用的是 QEMU 生成的通用 DTB，不是 OneCloud 的 Meson8b 设备树，因此不能据此宣称 S805 的 eMMC、以太网 PHY、USB PHY、CPU 调压/调频、U-Boot 引导链已经在真实玩客云上验证成功。

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
- 更新后主要版本：
  - `apt 2.6.1`
  - `openssh-server 1:9.2p1-2+deb12u10`
  - `systemd 252.39-1~deb12u2`
  - `armbian-firmware 26.8.3`
  - `armbian-config 26.8.0-trunk.426.1030.032129`
  - `u-boot-tools 2023.01+dfsg-2+deb12u3`（bookworm 当前版本）
- 使用 `scripts/restore-metadata.py` 从基线镜像恢复 setuid/setgid、shadow 组等元数据；最终 ext4 通过 `e2fsck -fn`。
- 最终 rootfs 仍有约 258 MiB 可用空间。

### 3.2 U-Boot 重建

最新 OneCloud U-Boot 源码仍是 hzyitc/u-boot-onecloud 的 `0038d741ed1c77a77570c3a6bf88fe6189c11733`（2022-10-28），没有更新的功能提交。本工程用 **Arm GNU Toolchain 15.2.Rel1** 重新构建了该源码，并为旧 U-Boot 2011.03 代码加入必要的 GCC 15/glibc 兼容补丁：

- `patches-uboot/0001-u-boot-gcc15-build-compat.patch`
- 兼容点：GNU89/fcommon、soft-float ABI、替代 32 位 i386 `bin2code`、现代 libgcc 的 `raise()` stub、host include 顺序、`show_boot_progress` weak 定义。
- 构建产物在 `output/uboot/`：`u-boot.bin`、`u-boot-comp.bin`、`ddr_init.bin`、补丁和构建日志。

**主镜像仍保留基线的已知可工作 Bootloader**，因为新编译的 U-Boot 没有经过真实硬件验证，直接替换不符合“保留可靠引导链”的原则。另提供独立实验镜像：

- `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img`
- SHA256 `54aeab76519b27dd44d949bd4494ff53559338906907ce4a86e828dea790ab63`
- 该镜像仅将 `1.UBOOT_COMP.USB` 和 `4.bootloader.PARTITION` 替换为 15.2 构建产物，并更新 `5.bootloader.VERIFY`；boot/rootfs 与主镜像相同。没有串口和救砖手段时不要刷它。

## 4. 设备树移植

初始设备树来自 Armbian `armbian-build` 仓库 6.12 归档补丁：

- `patch/kernel/archive/meson-6.12/onecloud-0001-add-dts.patch`
- 上游作者：hzy `<hzyitc@outlook.com>`
- 参考仓库：`https://github.com/hzyitc/armbian-onecloud`、`https://github.com/hzyitc/armbian-build`

移植到 7.3.1 时做了以下必要修改（均已保存为补丁 `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`）：

1. **memory 节点**
   - 旧写法 `memory { ... }` 改为有单位地址的 `memory@40000000 { ... }`，符合 7.x DTC 的 unit-address 检查。

2. **PWM v2**
   - 7.3.1 的 `pwm-meson` 对 `amlogic,meson8-pwm-v2` 使用 4 个 clock 输入，且 binding 明确禁止 `clock-names`。
   - 删除 OneCloud DTS 中对 `&pwm_cd` 的旧式 `clocks = <&xtal>, <&xtal>; clock-names = "clkin0", "clkin1";` 覆盖，保留 `meson8b.dtsi` 中的 4 路 clock 描述。
   - 保留 `pwm_cd` 的 `pwm_c1_pins`/`pwm_d_pins` 和 `status = "okay"`，供 CPU 核心电压 `pwm-regulator` 使用。

3. **USB**
   - 旧 Armbian DTS 使用 `dr_mode = "otg"` + `usb-role-switch` + `role-switch-default-mode = "host"`。
   - 7.3.1 主线没有 Armbian 6.12 中的 USB role-switch/DWC2 connector 补丁；为避免依赖未移植的 API，改成明确的 `dr_mode = "host"`，两个 DWC2 控制器均作为 host 使用，满足 USB 存储、键盘、USB 启动等需求。

4. **厂商前缀**
   - 在 `Documentation/devicetree/bindings/vendor-prefixes.yaml` 增加 `"^xunlei,.*"`，避免 `make dtbs_check` 的厂商前缀警告。保存为 `patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`。

未移植的内容及原因：

- **HDMI/DRM**：Armbian 6.12 的 HDMI 补丁系列（`0045`–`0067`）包含 WiP/VCLK HACK，且 7.x 显示子系统 API 变动较大；本任务目标是无桌面 Debian Minimal，HDMI 不是启动必需项。因此本内核未启用 HDMI/DRM/Mali，DTS 中也没有 HDMI 输出节点。串口是主要控制台。
- **USB OTG role-switch**：依赖 Armbian 的 DWC2 connector 补丁，7.3.1 未合并；改为 host 模式，牺牲 OTG peripheral 功能。
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
- 其余 multi_v7 模块共 1078 个 `.ko`，完整归档在 `output/modules/modules-7.3.1-onecloud.tar.xz`，并全部复制进根文件系统 `/lib/modules/7.3.1-onecloud`。

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
- 内核：`uImage` 头 load/entry 均为 `0x20800000`。
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

验证脚本：`verify.sh`，日志：`logs/verify-final-all.log`。

**102 项通过，0 项失败**，包括：

- 官方 7.3.1 源码 SHA256 与 kernel.org 校验值一致。
- `zImage` 为 ARM zImage；`uImage` 为 ARM Linux Kernel Image，load address `0x20800000`；`uInitrd` 为 ARM ramdisk。
- `CONFIG_LOCALVERSION="-onecloud"`；关键启动配置均为 `y` 或所需 `m`。
- DTB 可被 `dtc` 反编译，model/compatible/memory/eMMC/SDIO/Ethernet/USB/PWM/chosen 等节点存在且状态正确。
- 模块 vermagic 为 `7.3.1-onecloud SMP mod_unload ARMv7 p2v8`；根文件系统中存在对应模块路径。
- 根文件系统通过 `e2fsck -fn`；Debian bookworm；`/lib/systemd/systemd` 为 ARM EABI5；`/etc/fstab` UUID 正确。
- boot FAT 可读、UUID 保持 `F937-F6E8`；`uImage`、`uInitrd`、`dtb/meson8b-onecloud.dtb` 均存在。
- `boot.scr` 为 U-Boot script，包含加载 uImage/uInitrd/DTB 和 `bootm` 三地址。
- 普通镜像 MBR 分区起点/大小正确；两个分区内容与 boot/rootfs 原始镜像逐字节一致；UUID 正确。
- `.burn.img` 用 AmlImg 解包成功；manifest 顺序与基线完全一致；DDR/UBOOT/ini/platform/bootloader/resource 未变；sparse 扩展后与 boot/rootfs 原始镜像逐字节一致；VERIFY SHA1 正确；重新打包逐字节一致。
- 镜像大小：`.burn.img` 1,137,641,292 字节（约 1.06 GiB），普通 `.img` 1,686,110,208 字节（约 1.57 GiB），均远小于 8 GB eMMC 容量。**闪存容量判断基于解压后的分区和镜像布局，不基于 `.xz` 压缩文件大小。**
- 补丁可对 pristine 7.3.1 文件重新应用。

### QEMU 补充验证

使用 QEMU 9.2.3 `virt,highmem=off`、Cortex-A15、1 GiB RAM，加载最终 `zImage` + `uInitrd`，并把 rootfs/boot 镜像作为 virtio 块设备：

- 观察到了内核解压和启动，串口显示 `Linux version 7.3.1-onecloud ... GCC 15.2.Rel1`。
- initramfs 找到 `UUID=8a03...`，将 `/dev/vda` 挂载为 ext4 根。
- apt 全量升级后的 rootfs 正常启动；systemd、`ssh.service`、`getty@tty1` 和 `serial-getty@ttyAMA0` 均启动，出现 `onecloud login: root (automatic login)`。
- `/boot`（FAT UUID `F937-F6E8`）挂载成功，没有 emergency mode。

注意：该测试使用 QEMU 生成的通用 DTB，未经过 Meson8b 的 eMMC、DWMAC、USB PHY、PWM regulator、CPU DVFS 等驱动路径，不能替代实机验证。日志：`logs/qemu-final-gcc15.log`。

## 9. 产物清单

目录：`/home/hedc/OneCloud/onecloud-mainline/output`

| 文件 | 大小（字节） | SHA256 |
|---|---:|---|
| `OneCloud-Linux-7.3.1-armhf.burn.img` | 1,137,641,292 | `87312501debb771dceaf4ce91f49905576445b3598424fc00882c4f1c096b67f` |
| `OneCloud-Linux-7.3.1-armhf.burn.img.xz` | 356,130,260 | `aabfc0b603ee2fec4b3f3639760d7596821dbc73a39cc2e5e82399957d67e8f2` |
| `OneCloud-Linux-7.3.1-armhf.img` | 1,686,110,208 | `6624297f126625a45b3eae6420d0a103ad37786f685852086e3b2082b83f02a1` |
| `OneCloud-Linux-7.3.1-armhf.img.xz` | 354,976,728 | `208aa82bf77ca1b23c9813374a962ca66cee854ace36729dd27d58dc6c0e6044` |
| `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img` | 1,137,622,772 | `54aeab76519b27dd44d949bd4494ff53559338906907ce4a86e828dea790ab63` |
| `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img.xz` | 356,077,288 | `63eeaba697a241af5612fddc1184dbe1581198b2859d87326ae466b67b1c0b8c` |

同时包含：

- `SHA256SUMS` 及四个单文件 `.sha256`。
- `kernel/zImage`、`kernel/uImage`、`kernel/uInitrd`、`kernel/meson8b-onecloud.dtb`、`kernel/config-7.3.1-onecloud`、`kernel/System.map-7.3.1-onecloud`。
- `modules/modules-7.3.1-onecloud.tar.xz`（完整 1078 模块）。
- `patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch`、`patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch`。
- `patches-uboot/0001-u-boot-gcc15-build-compat.patch` 及 `uboot/` 下的 U-Boot 15.2 构建产物。
- 实验性 U-Boot 线刷包及 `.xz`、`.sha256`。
- `build.sh`、`package.sh`、`verify.sh` 及 `scripts/` 辅助脚本。
- `BUILD_REPORT.md`、`FLASHING.md`。

完整构建日志位于 `logs/`，包括 `kernel-gcc15-build2.log`、`package-gcc15-final.log`、`verify-gcc15-final.log`、`qemu-final-gcc15.log`；U-Boot 日志在 `output/uboot/build.log`。

## 10. 尚未解决/需要实机确认的问题

1. **没有真实玩客云硬件验证。** 这是当前最大的限制。无法确认：
   - 该 U-Boot 版本加载 7.3.1 zImage/uInitrd/DTB 的实际行为；
   - eMMC 初始化、HS200/1.8V 信号、pwrseq 复位时序；
   - RTL8211F RGMII 时序、PHY 复位和中断；
   - CPU 核心电压 PWM regulator 与 OPP 表配合；
   - USB PHY、host 模式枚举；
   - 串口电平/引脚与 `ttyAML0` 输出。

2. **TrustZone 补丁未应用。** Armbian 6.12 归档中包含 Meson6/8/8b/8m2 的 TrustZone 固件支持补丁（`tz_firmware`、SMP、eFuse、socinfo）。本工程未应用，因为检查 hzyitc U-Boot 的 `m8b_onecloud` 配置没有启用 `CONFIG_MESON_TRUSTZONE`，主线的 `amlogic,meson8b-smp` 路径应该可用。如果实机出现：
   - 只有 CPU0 在线；
   - `meson-mx-efuse` 读取失败、MAC 地址异常；
   - 温度校准缺失；
   则需要移植 Armbian 的 `0029`–`0034` 补丁，并把 CPU `enable-method` 改为 `amlogic,meson8-trustzone-firmware-smp`（需同时加入 firmware 节点）。这是下一步最值得优先验证的兼容性点。

3. **HDMI/DRM/Mali 未启用。** 本镜像定位为无桌面服务器；显示输出不可用。若需要 HDMI，需要移植 6.12 的 DRM 补丁系列并解决 7.x API 变化，工作量和风险都较大。

4. **IR 驱动未编译。** `CONFIG_IR_MESON` 在当前配置组合下未被 Kconfig 接受；DTS 节点保留但无驱动。若需要红外，需要单独调整 `RC_CORE`/media 依赖并重新构建。

5. **WiFi 未配置。** SDIO WiFi 需要具体芯片型号、固件和 NVRAM；本工程未包含。

6. **MAC 地址。** 没有从 eFuse 显式指定 MAC；如果 efuse 读取失败，内核可能使用随机 MAC。实机可用 `ip link` 查看。

7. **根文件系统仍保留旧 6.12 模块目录。** 这是从 Armbian 基线继承的 `/lib/modules/6.12.28-current-meson`。它不影响 7.3.1 启动；如需进一步精简，可在最终 rootfs 中删除。当前 rootfs 有约 258 MiB 可用空间。

8. **Armbian 首次启动策略。** 根文件系统保留 Armbian `armbian-firstrun`、SSH 主机密钥和默认用户策略。请按 Armbian 默认首次启动流程登录（常见为 `root/1234`，若系统提示修改请立即修改），或通过串口/SSH 设置强密码。不要把该镜像直接暴露在不可信网络。

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

`scripts/update-rootfs.sh` 可在 ARMHF rootfs 中重新执行 apt 更新，并调用 `scripts/restore-metadata.py` 恢复 setuid/setgid 和组归属；`scripts/verify-uboot.sh` 校验实验性 U-Boot 镜像。

`package.sh` 默认使用已通过 apt 更新的 `rootfs/onecloud-rootfs.ext4`（由 `scripts/update-rootfs.sh` 生成），把新的 7.3.1 模块写入其中；如果该文件不存在，则回退到 Armbian 基线 rootfs。原始下载文件不会被修改，所有中间副本位于 `build/` 和 `rootfs/`。

## 12. 结论

当前交付物是**真实生成、可解包、可校验、格式合法**的 Amlogic 线刷包和普通磁盘镜像，不是方案或伪文件。内核来自官方 stable 7.3.1，设备树针对 7.3.1 做了实际修复，根文件系统和引导链来自经过验证的 Armbian OneCloud 基线。静态验证和 QEMU 用户空间验证均通过。

但由于没有真实玩客云，最终结论必须标记为：

> **静态校验通过，QEMU 通用平台用户空间验证通过，尚未在 Amlogic S805 玩客云实机验证。**
