#!/usr/bin/env bash
set -euo pipefail

remove_if_loaded() {
    local name="$1"
    if lsmod | awk '{print $1}' | grep -qx "$name"; then
        echo "==> Removing $name"
        sudo modprobe -r "$name"
    fi
}

systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null || true

remove_if_loaded snd_intel_sst_acpi
remove_if_loaded snd_soc_sst_cht_rt5677
remove_if_loaded snd_soc_acpi_intel_match
remove_if_loaded x86_android_tablets

echo "==> Restoring stock Fedora modules"
sudo modprobe x86_android_tablets
sudo modprobe snd_soc_acpi_intel_match
sudo modprobe snd_intel_sst_acpi

systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

printf '\n=== restored ALSA cards ===\n'
cat /proc/asound/cards || true
