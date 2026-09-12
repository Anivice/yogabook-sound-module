# Source/provenance notes

`prepare.py` contains original glue/backport-generation code. It does not ship
the upstream `cht_rt5677.c`; the file is extracted at build time from the public
ASoC v7 mailbox fetched with `b4`.

The Yoga Book X91 board transformation follows the public platform/x86 v3 patch
series: two ACPI-enumerated DRV2604 controllers get LRA mode, empty waveform
library selection and their Cherryview enable GPIO mappings (community-verified
pins 79 and 47); TS3A227E gets its I2C/IRQ/mic-bias description; and RT5677 gets
its GPIO2/GPIO4 software-node properties. The existing BQ27542 fuel-gauge
resource is retained.

The selected Linux baseline already contains generic drv260x ACPI support for
`DRV2604` and exposes the controller through the input force-feedback API. The
normal build therefore does not replace `drv260x.ko`.

For suspend/resume robustness, `WITH_DRV260X_PM_FIX=1` makes `build.sh` fetch the
public 2026-08-31 drv260x PM v7 patch by Message-ID
`20260831150323.2922792-1-mauriziocasciano7@gmail.com`, apply it to the selected
upstream baseline, and build `drv260x.ko` as an optional fourth replacement
module. This path is opt-in because the patch was still under review when this
bundle was prepared.

`build.sh` derives the upstream Linux stable tag from `KVER` by stripping the
distro release suffix (for example, `7.2.4-200.fc44.x86_64` selects `v7.2.4`).
`KERNEL_TAG` remains available as an explicit override. The output modules are
linked/modposted against the exact kernel-devel tree selected by `KDIR`, whose
`kernelrelease` must match `KVER`.
