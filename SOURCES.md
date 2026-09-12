# Source/provenance notes

`prepare.py` contains original glue/backport-generation code. It does not ship
the upstream `cht_rt5677.c`; the file is extracted at build time from the public
ASoC v7 mailbox fetched with `b4`.

The transformations add only the functional data needed by the Yoga Book X91F
audio path: the 10EC5677 Cherry Trail machine match, TS3A227E I2C/IRQ
description, and the RT5677 GPIO2/GPIO4 software-node properties.

`build.sh` derives the upstream Linux stable tag from `KVER` by stripping the
distro release suffix (for example, `7.2.4-200.fc44.x86_64` selects `v7.2.4`).
`KERNEL_TAG` remains available as an explicit override. The output modules are
linked/modposted against the exact kernel-devel tree selected by `KDIR`, whose
`kernelrelease` must match `KVER`.
