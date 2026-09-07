# Source/provenance notes

`prepare.py` contains original glue/backport-generation code. It does not ship
the 647-line upstream `cht_rt5677.c`; the file is extracted at build time from
the public ASoC v7 mailbox fetched with `b4`.

The 7.1.13-specific transformations add only the functional data needed by the
Yoga Book X91F audio path: the 10EC5677 Cherry Trail machine match, TS3A227E
I2C/IRQ description, and the RT5677 GPIO2/GPIO4 software-node properties.

The stable source tree itself is fetched from the `v7.1.13` tag, and the output
modules are linked/modposted against the Fedora kernel-devel tree selected by
`KDIR`.
