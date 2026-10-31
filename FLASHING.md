# OneCloud Linux 7.3.1 刷写、串口调试与救砖说明

本文只描述操作步骤。实际刷写、短接、断电等不可逆操作由设备所有者执行。本工程没有对任何物理块设备执行过写入。

## 0. 先校验文件

Windows PowerShell：

```powershell
certutil -hashfile .\OneCloud-Linux-7.3.1-armhf.burn.img SHA256
```

应得到：

```text
87312501debb771dceaf4ce91f49905576445b3598424fc00882c4f1c096b67f
```

Linux：

```bash
sha256sum -c OneCloud-Linux-7.3.1-armhf.burn.img.sha256
```

如果校验不一致，不要刷写。

## 1. 用 Amlogic USB Burning Tool 刷 `.burn.img`

### 1.1 工具与驱动

- 使用支持 **Amlogic S805** 的 USB Burning Tool。S805 常用 **v2.2.4** 一类的 2.x 版本；过新的 3.x/4.x 工具可能只支持 G12 及更新 SoC。若工具提示“不支持该芯片/镜像”，换 2.2.4。
- 安装工具时一并安装 Amlogic USB 驱动（常见名称 `WorldCup Device`）。Windows 10/11 如果驱动签名拦截，按工具厂商说明处理；不要从不明来源下载驱动。
- 使用机箱后置 USB 2.0 端口，避免 USB Hub、延长线、USB 3.x 蓝色口。

### 1.2 导入镜像

1. 打开 USB Burning Tool。
2. `File` → `Import image`，选择：
   `OneCloud-Linux-7.3.1-armhf.burn.img`
3. 工具应显示 12 个条目（DDR、UBOOT_COMP、ini、platform、bootloader、resource、boot、rootfs 及 VERIFY）。
4. 保持工具的默认擦除选项。该线刷包的 `aml_sdc_burn.ini` 中 `erase_bootloader = 1`，会重新写入包内保留的 U-Boot；这是预期行为。
5. 主包保留的是 Armbian 基线中经过使用验证的 U-Boot。另有实验性的 `OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img`，仅用于在串口和救砖条件下测试最新工具链重编的 U-Boot；不要把它当作首次刷写或量产镜像。
   其 SHA256：`54aeab76519b27dd44d949bd4494ff53559338906907ce4a86e828dea790ab63`。
5. **不要勾选 “Erase flash”**，除非你明确要清空整块 eMMC 做救砖。普通升级不需要。

### 1.3 进入烧录模式

不同批次玩客云的外壳/按键不同，通用流程：

1. 断开玩客云电源。
2. 按住复位键（或捅住复位孔）；没有复位键的批次，需要按社区方法短接 eMMC 的 CLK 到 GND 进入 Mask ROM（不同板型丝印不同，务必先确认，不要短接电源）。
3. 保持按住，把 USB 线插入玩客云的 **USB OTG 口**，另一端接电脑。
4. 工具出现 `Connect success` / 识别到 `Amlogic USB2.0 Device` 后松开复位。
5. 若没有识别：
   - 换另一个 USB 口再试（只有一个口是 OTG）；
   - 换电脑后置 USB 2.0 口；
   - 重新安装/更新 Amlogic USB 驱动；
   - 检查 USB 线是否只能充电、不能传数据。

### 1.4 烧录

1. 点击 `Start`。
2. 等待进度到 100%，显示 `Burn successfully`。
3. 不要在中途拔线或断电。
4. 烧录完成后断开 USB，重新上电。
5. 首次启动会自动扩展/初始化一些 Armbian 服务，串口会看到 systemd 日志。

## 2. 串口调试

### 2.1 接线

- 使用 **3.3V USB-TTL** 串口模块（CH340/CP2102/FT232 等），不要用 5V 电平。
- 只接三根线：`GND`、`TX`、`RX`。
- 电脑的 `TX` 接板子的 `RX`，电脑的 `RX` 接板子的 `TX`，`GND` 对 `GND`。
- **不要接 VCC/5V**，板子自行供电。
- UART 参数：`115200 8N1`，无流控。

OneCloud 的 UART 测试点位置因板型/外壳而异，通常在板边或 LED 附近，丝印可能是 `TX/RX/GND` 或 `UART`。先用万用表确认 GND，再确认 TX 在启动时有 3.3V 电平波动；不要凭颜色猜线序。

### 2.2 正常启动日志特征

上电后应看到类似：

```text
Starting kernel ...
Booting Linux on physical CPU 0x0
Linux version 7.3.1-onecloud ...
...
mmc1: SDHCI controller on ...
EXT4-fs (mmcblk1p2): mounted filesystem ...
systemd[1]: ...
```

登录提示：

```text
onecloud login:
```

如果只看到 U-Boot、没有 `Starting kernel`，问题在 U-Boot/镜像加载；如果内核启动但停在 initramfs rescue shell，问题在 rootfs UUID/分区；如果 systemd 进入 emergency mode，优先检查 `/boot` FAT 挂载和 rootfs。

### 2.3 登录与检查

Armbian 首次启动策略可能要求修改默认密码。常见默认是 `root/1234`；若提示修改，请立即设置强密码。

登录后：

```bash
uname -a
# 应包含 7.3.1-onecloud

ip addr
# 应看到 eth0 获取 DHCP 地址

systemctl status ssh
# 应为 active (running)

dmesg | grep -Ei 'mmc|sdhci|meson|eth|stmmac|usb|dwc2'
```

SSH：

```bash
ssh root@<设备IP>
```

如果 `eth0` 没有地址：

```bash
networkctl status
journalctl -u systemd-networkd -b
ip link
```

## 3. 普通 `.img` 的 SD/USB 启动测试

`OneCloud-Linux-7.3.1-armhf.img` 是普通磁盘镜像（MBR，16 MiB 偏移 + FAT boot + ext4 rootfs），**不是** USB Burning Tool 用的格式；不要把它导入烧录工具。

写入 SD 卡或 U 盘（Linux，确认设备名后）：

```bash
sudo dd if=OneCloud-Linux-7.3.1-armhf.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows 可用 balenaEtcher / Rufus 的“从镜像写入”模式。写入的是整盘镜像，不要只写某个分区。

玩客云 U-Boot 的 `boot.scr` 明确支持从 USB 或 eMMC 启动：

```text
Boot from USB:
  setenv bootdev "usb 0"
  usb start
  fatload ${bootdev} 0x20800000 boot.scr && autoscr 0x20800000

Boot from eMMC:
  setenv bootdev "mmc 1"
  fatload ${bootdev} 0x20800000 boot.scr && autoscr 0x20800000
```

上电时在 U-Boot 倒计时阶段打断，按上面的命令设置 `bootdev`。SD 卡通常对应 `mmc 0`，eMMC 对应 `mmc 1`；如果实际枚举不同，用 `mmc list` / `mmc dev` 确认。

## 4. 救砖

### 4.1 Linux 启动失败但 U-Boot 正常

优先用 USB Burning Tool 重新刷入**基线原版**：

```text
Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.burn.img
SHA256: a02c00898a16b1543d6ef052d21128b16ca127ad2a3d12f54e5337d80bdcec17
```

它能恢复已知可工作的 U-Boot + 6.12 内核 + 根文件系统。确认设备能正常启动后，再尝试本工程的 7.3.1 线刷包。

### 4.2 U-Boot 也被破坏

- 仍优先尝试 USB Burning Tool + 基线 `.burn.img`；Amlogic Mask ROM 不依赖 eMMC 中的 U-Boot。
- 如果工具始终不识别，需要按板型短接 eMMC 的 CLK/数据脚进入 Mask ROM。不同批次丝印不同，先查对应板型的拆机图；**不要短接电源、不要短接电池/电容**。
- 不要用 `dd` 向正在运行的设备的 `/dev/mmcblk*` 写引导区；一次错误的 `dd` 可能同时破坏 U-Boot 和分区表。

### 4.3 串口救急

如果还能进 U-Boot，但 Linux 起不来：

```text
setenv bootdev "mmc 1"
fatload ${bootdev} 0x20800000 boot.scr && autoscr 0x20800000
```

或者从 USB 启动一个已知可用的镜像，先把 eMMC 数据备份出来，再考虑重刷。

## 5. 已知限制

- 本工程没有在真实玩客云上验证，首次实机启动请务必接串口。
- HDMI/DRM 未启用，显示输出不可用；以串口和 SSH 为准。
- IR、WiFi 未配置。
- 如果实机只有 CPU0 在线，或 eFuse/MAC 读取异常，参考 `BUILD_REPORT.md` 第 10 节，评估 TrustZone 补丁。
- 主线的 U-Boot 重建产物已单独放在 `output/uboot/`；主镜像仍使用 Armbian 26.08.0 基线的已知可工作 U-Boot。实验性 U-Boot 包需要串口和救砖手段。
- 线刷包基于 Armbian 26.08.0 的 U-Boot 和分区布局；不要把它与其它板型的 Amlogic 烧录包混用。
- eMMC 为 8 GB 级别；本包解压后布局约 1.6 GiB，远小于容量，但不要根据 `.xz` 压缩文件大小判断闪存需求。
