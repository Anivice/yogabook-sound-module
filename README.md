# Lenovo Yoga Book YB1-X91F audio — kernel-versioned OOT backport

This bundle keeps the selected Fedora kernel and backports only the missing Yoga
Book audio pieces as external modules. It is not pinned to one Linux point
release: `build.sh` reads the kernel version from the matching kernel-devel tree
and selects the corresponding upstream stable tag automatically.

Target environment for the build logic:

- Lenovo Yoga Book 1 `YB1-X91F` / X91 family
- Fedora with a matching `kernel-devel` tree for the target kernel
- legacy Intel SST path (`intel/fw_sst_22a8.bin`)

It produces exactly three modules:

- `snd-soc-sst-cht-rt5677.ko` — RT5677 Yoga Book machine driver
- `snd-soc-acpi-intel-match.ko` — Intel ACPI match module rebuilt with the
  `10EC5677 -> cht-rt5677` Cherry Trail entry
- `x86-android-tablets.ko` — tablet module rebuilt with only the Yoga Book audio
  resource fixes (TS3A227E + RT5677 GPIO2/GPIO4)

The package deliberately does **not** vendor the large upstream Linux machine
driver source. `build.sh` retrieves the reviewed v7 ASoC patch by Message-ID
with `b4`, extracts the new driver, and sparse-checks out the upstream Linux tag
derived from the selected kernel-devel tree. This keeps provenance explicit and
reproducible without hard-coding one kernel point release.

## 1. Build inside Toolbx

The host and Toolbx share the running kernel, but the matching kernel build tree
must exist in Toolbx. For the running kernel, the default path is:

```bash
/usr/src/kernels/$(uname -r)/Makefile
```

Install build dependencies if necessary:

```bash
sudo dnf install -y \
    git b4 gcc make python3 kmod \
    elfutils-libelf-devel
```

Then:

```bash
cd /path/to/yogabook-x91f-audio-oot
python3 -m unittest -v tests/test_prepare.py
./build.sh
```

By default, `KVER` is `uname -r`, `KDIR` is
`/usr/src/kernels/$KVER`, and the upstream Linux tag is derived by stripping
the distro suffix from `KVER`. For example:

```text
7.2.4-200.fc44.x86_64 -> v7.2.4
```

`KERNEL_TAG` can still be set explicitly when a custom or prerelease source
baseline is required.

Before compiling, `build.sh` also checks:

```bash
make -s -C "$KDIR" kernelrelease
```

and refuses to continue unless that release exactly matches `KVER`. This keeps
the external modules tied to the intended distro kernel ABI and Module.symvers.

Expected output directory:

```text
dist/<kernel-release>/
├── SHA256SUMS
├── snd-soc-acpi-intel-match.ko
├── snd-soc-sst-cht-rt5677.ko
└── x86-android-tablets.ko
```

## 2. Install on a mutable Fedora host

Leave Toolbx, install the built modules, and reboot:

```bash
exit
cd /path/to/yogabook-x91f-audio-oot
./install-mutable.sh
sudo reboot
```

`install-mutable.sh` installs the modules under:

```text
/usr/lib/modules/$(uname -r)/updates/yogabook-x91f/
```

runs `depmod`, and writes:

```text
/etc/modprobe.d/yogabook-x91f-audio.conf
```

with `snd_intel_dspcfg dsp_driver=2`, keeping the setup on the legacy SST path.
It does not overwrite Fedora's stock copies under `kernel/...`.

The patched `x86_android_tablets` module also creates the X91F BQ27542
fuel-gauge I2C client; the existing fuel-gauge description is left unchanged.

## 3. Verify after reboot

Run:

```bash
./verify.sh
```

A successful backport should select `cht-rt5677` instead of
`bytcht-nocodec`, and `aplay -l` / `arecord -l` should list actual PCM devices.
Also check that a TS3A227E client exists on I2C1 address `0x3b`, usually shown
by sysfs as an `1-003b`-style device.

If `bytcht-nocodec` remains selected, do not move on to UCM/PipeWire yet — the
kernel machine selection is still wrong.

## 4. Uninstall the persistent modules

```bash
./uninstall-mutable.sh
sudo reboot
```

This removes the OOT update directory and the Yoga Book modprobe configuration,
runs `depmod`, and returns module resolution to the Fedora stock modules after
reboot.

## 5. UCM after PCM devices exist

The Yoga Book also needs its UCM2 routing configuration for normal desktop
speaker/microphone use. Fedora's `alsaucm` executable is provided by
`alsa-ucm-utils`.

On a mutable Fedora installation:

```bash
sudo dnf install -y alsa-ucm-utils
./install-ucm-mutable.sh
alsaucm listcards
systemctl --user restart wireplumber pipewire pipewire-pulse
wpctl status
```

The UCM installer pulls `Yoga-Book/Yoga-Book-ALSA-UCM-Config`, whose current
configuration includes the `cht-rt5677` legacy-SST alias.

### Fedora Atomic / OSTree

On an Atomic host `/usr` is normally immutable. **Do not remount `/usr` writable
just to install this bundle.** `install-mutable.sh` and
`install-ucm-mutable.sh` intentionally refuse a read-only `/usr`. Persistent
installation there should be done through a kernel-version-matched RPM/OSTree
layer or another supported deployment mechanism.

## 6. If module loading fails

Capture these before changing anything else:

```bash
sudo dmesg | tail -200
lsmod | grep -Ei 'rt5677|ts3a|sst|sof|snd_soc'
cat /proc/asound/cards
find /sys/bus/i2c/devices -maxdepth 1 \
  \( -iname '*5677*' -o -iname '*003b*' -o -iname '*ts3a*' \) -print
```

Typical failure classes:

- `Unknown symbol ...` — source/backport or distro ABI mismatch; do not force
  the module.
- `invalid module format` — wrong kernel-devel/vermagic.
- `Key was rejected by service` — kernel lockdown/module-signing issue.
- X91 board module fails around `0x3b` — inspect TS3A IRQ/GPIO creation first.
- machine driver says it is waiting for the codec — confirm
  `i2c-10EC5677:00` exists and that `snd_soc_rt5677` reprobed successfully.
- card exists but desktop still shows no usable speaker/mic — kernel path is
  likely fixed; install/validate Yoga Book UCM next.

## Upstream inputs

The scripts intentionally pin only the reviewed patch input, not one Linux point
release:

- Linux baseline: `gregkh/linux`, tag derived from `KVER` after stripping the
  distro release suffix (override with `KERNEL_TAG` when necessary)
- ASoC v7 cover Message-ID:
  `20260902123007.769820-1-mauriziocasciano7@gmail.com`
- Yoga Book board resource behavior corresponds to the audio-only parts of
  platform/x86 v3 patches 2/3 and 3/3. Haptics changes are intentionally not
  included.
