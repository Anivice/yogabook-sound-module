#!/usr/bin/env bash
set -euo pipefail

# Safe recovery for the specific partial state produced by the OLD hot-swap
# script: bytcht-nocodec was removed, but snd_intel_sst_acpi itself refused to
# unload. In that state the original platform device is still present, so
# simply reloading the no-codec machine driver is the least invasive recovery.

if [[ -d /sys/module/snd_intel_sst_acpi ]] && \
   [[ ! -d /sys/module/snd_soc_sst_cht_rt5677 ]]; then
    echo "==> SST frontend is still loaded; restoring stock no-codec machine driver"
    sudo modprobe snd_soc_sst_byt_cht_nocodec || true

    echo "==> Restarting PipeWire/WirePlumber sockets and services"
    systemctl --user start pipewire.socket pipewire-pulse.socket 2>/dev/null || true
    systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true

    printf '\n=== ALSA cards after recovery ===\n'
    cat /proc/asound/cards || true
    exit 0
fi

if [[ -d /sys/module/snd_soc_sst_cht_rt5677 ]]; then
    cat >&2 <<'MSG'
The OOT RT5677 stack is active. This script will not hot-unload it.
Run ./unstage-cold-test.sh and reboot to return to Fedora stock modules.
MSG
    exit 2
fi

cat >&2 <<'MSG'
No recognized partial hot-swap state was found.
If you staged the cold test, use:
  ./unstage-cold-test.sh
  systemctl reboot
MSG
exit 2
