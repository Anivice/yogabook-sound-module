#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
DIST="${ROOT}/dist/${KVER}"

for ko in \
    x86-android-tablets.ko \
    snd-soc-acpi-intel-match.ko \
    snd-soc-sst-cht-rt5677.ko; do
    [[ -f "$DIST/$ko" ]] || {
        echo "error: missing $DIST/$ko; build inside Toolbx first" >&2
        exit 1
    }
done

product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
case "$product" in
    *YB1-X91*) ;;
    *)
        echo "error: refusing to hot-swap Yoga Book modules on product: ${product:-unknown}" >&2
        exit 1
        ;;
esac

if grep -qw lockdown /sys/kernel/security/lockdown 2>/dev/null; then
    echo "warning: kernel lockdown is enabled; unsigned OOT modules may be rejected" >&2
fi

remove_if_loaded() {
    local name="$1"
    if lsmod | awk '{print $1}' | grep -qx "$name"; then
        echo "==> Removing $name"
        sudo modprobe -r "$name"
    fi
}

printf '%s\n' "==> Stopping user audio services"
systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true

# Remove the currently selected no-codec machine and both Intel DSP frontends
# which hold references to snd_soc_acpi_intel_match.
remove_if_loaded snd_soc_sst_byt_cht_nocodec
remove_if_loaded snd_intel_sst_acpi
remove_if_loaded snd_sof_acpi_intel_byt
remove_if_loaded snd_soc_acpi_intel_match

# This temporarily unregisters/recreates the X91 board-described I2C clients,
# including the battery fuel gauge. It is expected to disappear briefly.
remove_if_loaded x86_android_tablets

echo "==> Loading stock TS3A227E codec driver"
sudo modprobe snd_soc_ts3a227e

echo "==> Loading patched X91 board-resource module"
sudo insmod "$DIST/x86-android-tablets.ko"

echo "==> Loading patched Cherry Trail match table"
sudo insmod "$DIST/snd-soc-acpi-intel-match.ko"

echo "==> Loading RT5677 machine driver"
sudo insmod "$DIST/snd-soc-sst-cht-rt5677.ko"

echo "==> Starting legacy SST frontend"
sudo modprobe snd_intel_sst_acpi

sleep 1

printf '\n=== module origins ===\n'
for name in x86_android_tablets snd_soc_acpi_intel_match snd_soc_sst_cht_rt5677; do
    if [[ -d "/sys/module/$name" ]]; then
        printf '%-30s loaded\n' "$name"
    else
        printf '%-30s NOT LOADED\n' "$name"
    fi
done

printf '\n=== I2C audio devices ===\n'
find /sys/bus/i2c/devices -maxdepth 1 \
    \( -iname '*5677*' -o -iname '*003b*' -o -iname '*ts3a*' \) -print 2>/dev/null || true

printf '\n=== ALSA cards ===\n'
cat /proc/asound/cards || true

printf '\n=== PCM playback ===\n'
aplay -l || true

printf '\n=== PCM capture ===\n'
arecord -l || true

printf '\n=== recent audio kernel log ===\n'
sudo dmesg | grep -Ei 'cht-rt5677|chtrt5677|rt5677|ts3a227|sst|asoc|audio port' | tail -120 || true

printf '\n==> Restarting user audio services\n'
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

cat <<'EOF'

Expected kernel-level success:
  * bytcht-nocodec is gone
  * /proc/asound/cards contains chtrt5677 / cht-rt5677
  * aplay -l and arecord -l show real PCM devices

If any module load fails, run:
  ./rollback.sh
EOF
