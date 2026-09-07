# Lenovo Yoga Book YB1-X91F audio — Linux 7.1.13 OOT backport

This bundle keeps the currently running Fedora kernel and backports only the
missing Yoga Book audio pieces as external modules.

Target tested environment for the build logic:

- Lenovo Yoga Book 1 `YB1-X91F` / X91 family
- Fedora 44
- `7.1.13-200.fc44.x86_64`
- legacy Intel SST path (`intel/fw_sst_22a8.bin`)

It produces exactly three modules:

- `snd-soc-sst-cht-rt5677.ko` — RT5677 Yoga Book machine driver
- `snd-soc-acpi-intel-match.ko` — stock 7.1.13 Intel ACPI match module,
  rebuilt with the `10EC5677 -> cht-rt5677` Cherry Trail entry
- `x86-android-tablets.ko` — stock 7.1.13 tablet module, rebuilt with only the
  Yoga Book audio resource fixes (TS3A227E + RT5677 GPIO2/GPIO4)

The package deliberately does **not** vendor the large upstream Linux driver
source. `build.sh` retrieves the reviewed v7 ASoC patch by Message-ID with
`b4`, extracts the new driver, and downloads the Linux `v7.1.13` baseline with
a sparse Git checkout. This makes the provenance explicit and reproducible.

## 1. Build inside Toolbx

The host and Toolbx share the running kernel, but your matching kernel build
tree is in Toolbx. Enter the same Toolbx where this exists:

```bash
/usr/src/kernels/7.1.13-200.fc44.x86_64/Makefile
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

Expected output directory:

```text
dist/7.1.13-200.fc44.x86_64/
├── SHA256SUMS
├── snd-soc-acpi-intel-match.ko
├── snd-soc-sst-cht-rt5677.ko
└── x86-android-tablets.ko
```

`build.sh` refuses another kernel release by default. This is intentional:
these modules must be built against the exact running Fedora kernel-devel
headers and Module.symvers.

## 2. Leave Toolbx and live-test on the host

```bash
exit
cd /path/to/yogabook-x91f-audio-oot
./load-test.sh
```

The script:

1. stops the user PipeWire/WirePlumber session;
2. removes the current `bytcht-nocodec` / SST/SOF match users;
3. temporarily unloads `x86_android_tablets`;
4. loads stock `snd_soc_ts3a227e`;
5. loads the patched X91 board resources;
6. loads the patched Intel Cherry Trail match table;
7. loads `snd_soc_sst_cht_rt5677`;
8. starts `snd_intel_sst_acpi` again;
9. prints ALSA cards, PCM devices, I2C devices and relevant dmesg output.

### Important battery note

`x86_android_tablets` also creates the X91F BQ27542 fuel-gauge I2C client.
During a live module swap the battery device can therefore disappear briefly
and be recreated when the patched module loads. The code keeps the existing
7.1.13 fuel-gauge description unchanged.

## 3. Kernel-level success criteria

Run:

```bash
./verify.sh
```

The important changes are:

```text
BEFORE
1 [bytchtnocodec]: bytcht-nocodec
aplay: no soundcards found
arecord: no soundcards found
```

and, after a successful SST backport, something equivalent to:

```text
1 [chtrt5677]: cht-rt5677
```

`aplay -l` and `arecord -l` should then list actual PCM devices.

Also check that a TS3A227E client exists on I2C1 address `0x3b`, usually shown
by sysfs as an `1-003b`-style device.

If `bytcht-nocodec` remains selected, do not move on to UCM/PipeWire yet — the
kernel machine selection is still wrong.

## 4. Roll back a live test

```bash
./rollback.sh
```

This removes the OOT modules and modprobes the Fedora stock modules again.
Because `load-test.sh` never overwrites files under `/usr/lib/modules`, a live
test is reversible without changing the installed kernel.

## 5. UCM after PCM devices exist

The Yoga Book also needs its UCM2 routing configuration for normal desktop
speaker/microphone use.

Fedora's `alsaucm` executable is in:

```bash
alsa-ucm-utils
```

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

Your boot command line shows an OSTree deployment. On an Atomic host `/usr`
is normally immutable. **Do not remount `/usr` writable just to install this
bundle.**

Use `load-test.sh` first because it loads `.ko` files directly from the shared
working directory and requires no persistent `/usr` modification.

`install-mutable.sh` and `install-ucm-mutable.sh` intentionally refuse a
read-only `/usr`. Once the live kernel/PCM test succeeds, persistent Atomic
packaging should be done as a kernel-version-specific RPM/OSTree layer rather
than by overwriting the deployment.

## 6. Optional persistent install on mutable Fedora

Only after the live test works:

```bash
./install-mutable.sh
```

It installs to:

```text
/usr/lib/modules/$(uname -r)/updates/yogabook-x91f/
```

and runs `depmod`. It never overwrites Fedora's stock copies under
`kernel/...`.

It also writes:

```text
/etc/modprobe.d/yogabook-x91f-audio.conf
```

with `snd_intel_dspcfg dsp_driver=2`, keeping the first-stage setup on the SST
path that already works on your machine and has the required firmware.

Undo:

```bash
./uninstall-mutable.sh
```

## 7. If a load fails

Capture these before changing anything else:

```bash
sudo dmesg | tail -200
lsmod | grep -Ei 'rt5677|ts3a|sst|sof|snd_soc'
cat /proc/asound/cards
find /sys/bus/i2c/devices -maxdepth 1 \
  \( -iname '*5677*' -o -iname '*003b*' -o -iname '*ts3a*' \) -print
```

Typical failure classes:

- `Unknown symbol ...` — source/backport or Fedora ABI mismatch; do not force
  the module.
- `invalid module format` — wrong kernel-devel/vermagic.
- `Key was rejected by service` — kernel lockdown/module-signing issue.
- X91 board module fails around `0x3b` — inspect TS3A IRQ/GPIO creation first.
- machine driver says it is waiting for the codec — confirm
  `i2c-10EC5677:00` exists and that `snd_soc_rt5677` reprobed successfully.
- card exists but desktop still shows no usable speaker/mic — kernel path is
  likely fixed; install/validate Yoga Book UCM next.

## Upstream inputs

The scripts intentionally pin these inputs:

- Linux baseline: `gregkh/linux`, tag `v7.1.13`
- ASoC v7 cover Message-ID:
  `20260902123007.769820-1-mauriziocasciano7@gmail.com`
- Yoga Book board resource behavior corresponds to the audio-only parts of
  platform/x86 v3 patches 2/3 and 3/3. Haptics changes are intentionally not
  included.

