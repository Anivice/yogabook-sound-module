#!/usr/bin/env bash
set -euo pipefail

KVER="${KVER:-$(uname -r)}"
STAGE="/var/lib/yogabook-audio-oot/${KVER}"
ETCDIR="/etc/yogabook-audio-oot"
UNIT="/etc/systemd/system/yogabook-audio-oot.service"
KARG_RD='rd.driver.blacklist=x86_android_tablets,snd_soc_acpi_intel_match,snd_intel_sst_acpi,snd_sof_acpi_intel_byt'
KARG_MP='modprobe.blacklist=x86_android_tablets,snd_soc_acpi_intel_match,snd_intel_sst_acpi,snd_sof_acpi_intel_byt'
KARG_SST='snd_intel_dspcfg.dsp_driver=2'

command -v rpm-ostree >/dev/null || {
    echo "error: rpm-ostree not found" >&2
    exit 1
}

# Do not try to unload a running SST stack. Only change the next boot.
sudo systemctl disable yogabook-audio-oot.service 2>/dev/null || true
sudo rm -f "$UNIT"
sudo rm -rf "$ETCDIR"
sudo rm -rf "$STAGE"
sudo systemctl daemon-reload

sudo rpm-ostree kargs \
    --delete-if-present="$KARG_RD" \
    --delete-if-present="$KARG_MP" \
    --delete-if-present="$KARG_SST" || true

cat <<'EOF_MSG'
Cold-test staging removed for the next deployment.
No running audio module was hot-unloaded.

Reboot to return to the stock Fedora audio module set:
  systemctl reboot
EOF_MSG
