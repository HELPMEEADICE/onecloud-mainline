# Automatic OneCloud Linux prereleases

The [kernel-prerelease.yml](workflows/kernel-prerelease.yml) workflow polls
[kernel.org releases.json](https://www.kernel.org/releases.json) every six hours.
It selects the highest official final, non-EOL stable/mainline version at or above
Linux 7.3.1, including both patch updates and new minor series. Release tag:
`linux-VERSION-onecloud`. Existing tags are skipped. Use **Actions → Linux kernel
auto prerelease → Run workflow** to build a currently active specific version.

On Ubuntu 24.04, the workflow provisions tools, downloads the kernel source,
checks SHA256 and a recognized release maintainer's PGP signature, applies
**all** existing kernel patches, compiles kernel/modules/DTBs, prepares the
Armbian Bookworm rootfs with Mesa, then builds both regular disk images and
Amlogic USB Burning Tool images. A failed patch, missing tool, absent Mesa,
invalid signature, checksum mismatch, or image verification failure blocks release.

It publishes raw and compressed images, uImage/uInitrd/DTB, module archive and
SHA256SUMS as **Pre-release**, preserving the working baseline SPL and U-Boot.
No generated image is considered device-validated merely because CI passes.

**Review steps**: merge the PR after lint succeeds, verify Actions and release
permissions, manually dispatch the workflow, inspect the job logs and
SHA256SUMS, and test the prerelease on a spare OneCloud with UART recovery.
Standard hosted runners may need extra disk space: if exhausted, use a
self-hosted Ubuntu runner with 50+ GiB free and change `runs-on` on publish.

Failures leave diagnostic logs as an Actions artifact (retention 14 days).
For a kernel tree API change, update patches; CI intentionally does not
automatically rewrite incompatible driver or DTS code.
