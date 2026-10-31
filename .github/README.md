# Automatic OneCloud Linux prereleases

The [kernel-prerelease.yml](workflows/kernel-prerelease.yml) workflow polls
[kernel.org releases.json](https://www.kernel.org/releases.json) every six hours.
It selects the highest official final, non-EOL stable/mainline version at or above
Linux 7.3.1, including both patch updates and new minor series. Release tag:
`linux-VERSION-onecloud`. Existing tags are skipped on scheduled runs. After merging the workflow into
the default branch, use **Actions → Linux kernel auto prerelease → Run workflow**
to build any final version from Linux 7.3.1 onward, including older releases.
The archive is accepted only after its official SHA256 and PGP checks succeed.

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

## Download builds from GitHub Actions

A **manual Run workflow** now always builds the selected version, even when
its Release tag already exists. Following successful `verify.sh` and
`sha256sum -c SHA256SUMS` checks, the workflow uploads downloadable
**Artifacts** to the completed Actions run. They also appear on successful
PR integration runs. No Release publication is needed to retrieve artifacts.

The **firmware** artifact (14-day retention) contains the compressed
`OneCloud-Linux-<version>-armhf.img.xz` regular disk image,
`OneCloud-Linux-<version>-armhf.burn.img.xz` Amlogic USB burning image,
`SHA256SUMS`, and checksums for both compressed files. Download and
unzip the GitHub artifact ZIP, then extract the `.xz` file to obtain the
original `.img` for flashing. Verify compressed files first with the
individual `.sha256` files; extract both images before running the complete
`sha256sum -c SHA256SUMS` check.

The **kernel** artifact (14-day retention) includes `zImage`, `uImage`,
`uInitrd`, the OneCloud DTB, kernel config, System.map, a modules archive,
and patch files.

When starting a manual build, optionally tick **include_uncompressed** to
also upload two separate raw disk/USB burning IMG artifacts (7-day retention,
~2.8 GB extra). This is off by default to avoid large redundant uploads.
Artifact names contain the kernel version, Actions run ID and attempt number.

The nightly/scheduled build still skips already released versions;
`workflow_dispatch` never skips a requested rebuild merely because the
Release exists. A fresh version can still receive a Pre-release after
its verified artifacts have been uploaded; an existing Release is left intact.
Artifacts are temporary and not a substitute for long-term GitHub Releases.
