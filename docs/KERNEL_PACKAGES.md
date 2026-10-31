# Kernel upgrade packages (.deb / .pkg.tar.zst)

The release workflow produces **two binary packages from the same ARMv7
kernel build** in addition to the complete `.img` / `.burn.img` flash images:

* `onecloud-linux_<kernel>-1_armhf.deb` — Debian/Armbian Bookworm (APT/dpkg).
* `onecloud-linux-<kernel>-1-armv7h.pkg.tar.zst` — Arch Linux ARM (pacman).

These are local installable package files, **not** an APT or pacman package
repository. A repository index (APT Packages/Release signing and pacman
database/signing) is not generated here.

## Installing

Before upgrading, back up important data and make sure you have a tested
recovery path. A broken kernel can stop network access.

On a supported Debian/Armbian OneCloud system:

~~~bash
sudo apt install ./onecloud-linux_<kernel>-1_armhf.deb
~~~

On an existing Arch Linux ARM **armv7h** OneCloud system:

~~~bash
sudo pacman -U ./onecloud-linux-<kernel>-1-armv7h.pkg.tar.zst
~~~

Replace `<kernel>` with a real release number, for example `7.3.2`.
The package manager installs the modules into `/usr/lib/modules/<kernel>-onecloud`
(which resolves to `/lib/modules/...` on merged-/usr systems), places the
kernel/DTB/ramdisk objects in `/usr/lib/onecloud-kernel/<kernel>-onecloud`,
runs `depmod`, and activates the boot payloads via the package's post-install
script. No U-Boot, partition table or rootfs partitions are rewritten.

For safety, activation requires:

* The running device tree contains `xunlei,onecloud`.
* `/boot` is a separately mounted writable **FAT** volume, containing the
  original OneCloud `boot.scr`, `armbianEnv.txt` and `dtb/` directory.
* The root filesystem follows the merged-/usr layout (`/lib -> /usr/lib`).
* The boot loader still loads `/boot/uImage`, `/boot/uInitrd` and
  `/boot/dtb/meson8b-onecloud.dtb`.

Activation checks SHA256 for all three boot payloads, calls `depmod`, stores
a backup under `/var/backups/onecloud-kernel/`, and stages replacements on
the FAT filesystem. It replaces the DTB first, the ramdisk second and
`uImage` last, verifying the finished files. A script-detected failure
attempts to restore previous files. **FAT cannot atomically replace all
three**, so power failure during installation still carries some risk.
Do not unplug the OneCloud while upgrading. The old U-Boot 2011.03 is
retained and uses the original known-compatible image load address.

A reboot is **never initiated automatically**. Verify the package install
finished successfully, then reboot when convenient. To inspect the previous
boot files, consult the printed backup directory.

## Limitations

An ordinary Arch Linux ARM installation for an unrelated board is not
supported. The pacman package requires an existing **OneCloud-compatible
system with the same boot script and FAT layout**. The distribution is not
converted by installing a kernel package; an ARMv7 kernel package cannot
turn Debian into Arch or vice versa.

The packaged initramfs follows the OneCloud project boot/rootfs contract,
including its existing root UUID fallback. If you change the partition
layout or the boot script, adapt and test these details **before** upgrading.
On a new minor Linux branch, CI may fail to apply downstream device tree,
HDMI or SDHC patches; such a build is not published.

The two packages are inspected and checked against the original kernel
objects and each other before GitHub releases them. This is a **static**
verification only; hardware installation, reboot and recovery have not been
tested automatically. Packages remain in GitHub **Pre-releases** until
independently qualified on real hardware.
