# Automated kernel pre-releases

The workflow at `.github/workflows/auto-release.yml` checks the current
**final** Linux release published by kernel.org twice daily, or on demand from
**Actions → Automatic Linux kernel pre-releases → Run workflow**.

Both 7.3.x patch updates and new final minor versions (for example, 7.4)
use exactly the same **Pre-release** policy. Release names and tags are
`onecloud-linux-v<VERSION>`. A pre-existing release tag is skipped.

For an explicit kernel version, enter e.g. `7.3.2` in `kernel_version`.
RCs, arbitrary shell input, and versions older than the tested 7.3.1 baseline
are rejected. Use `python3 -m unittest discover -s tests -v` to run the
release-discovery tests locally.

## What gets published

The CI runner builds the kernel, modules, DTB and initramfs using `build.sh`,
assembles normal and Amlogic USB Burning Tool images using `package.sh`,
then runs the **existing full static verification suite** via `verify.sh`.
Only an entirely successful build and verification can reach `gh release create
--prerelease`.

Release assets include both compressed flash images, a Debian armhf `.deb` kernel
upgrade package, an Arch Linux ARM armv7h `.pkg.tar.zst` kernel upgrade package,
a modules archive,
OneCloud DTB, final kernel configuration, SHA256SUMS, a build manifest, the
upstream tarball SHA256 record, and the complete verification log. The
uncompressed image files remain local to the ephemeral CI runner to avoid
oversized Release assets. The published SHA256SUMS covers both the published
and locally built deliverables; after download, run
`sha256sum -c SHA256SUMS` only if all listed paths are present, or verify
individual downloaded assets with `sha256sum`.

Package creation is checked with a synthetic smoke test, then the real binary
archives are unpacked and compared with the built objects and each other.
Installation and boot on real hardware remain untested; see
[Kernel upgrade packages](KERNEL_PACKAGES.md) for conditions and commands.

Source verification is performed by the repository's existing
`scripts/fetch-kernel.sh`. It verifies a checksum from kernel.org's sums
listing and checks the tarball's detached OpenPGP signature against pinned
Linux maintainer signing fingerprints. Missing or invalid signatures fail
the job. Toolchain and Armbian base images use their existing pinned SHA256
checks, and the U-Boot bootloader in burn images is retained from the pinned
Armbian baseline. Experimental GCC15 U-Boot flashing variants are disabled
in CI.

## Operational notes

* The workflow is scheduled only after its configuration is merged into the
  repository's **default branch**, and scheduled GitHub Actions executions
  can be delayed.
* The default GitHub token needs **contents: write**; repository/organization
  policies must permit Release creation.
* Native Ubuntu 24.04 runners need adequate free disk space for the compiler,
  Armbian baseline, unpacked partitions, normal image, burn image, packaging
  temporary files, and verification copies. The workflow removes unused SDKs,
  but a hosted runner may still run out of disk space. A sufficiently large
  self-hosted runner is the recommended fallback if that occurs.
* This is not a boot or physical flash test. **Every CI-built artifact is
  marked Pre-release, even when static checks pass.** New minor versions in
  particular may require rebasing the kernel patches before build succeeds.
  A failed patch application stops the workflow and publishes nothing.
