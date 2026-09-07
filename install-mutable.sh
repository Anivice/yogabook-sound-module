#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
DIST="$ROOT/dist/$KVER"
DEST="/usr/lib/modules/$KVER/updates/yogabook-x91f"

[[ -f "$DIST/SHA256SUMS" ]] || {
    echo "error: build artifacts not found; run build.sh first" >&2
    exit 1
}

if ! sudo test -w "/usr/lib/modules/$KVER"; then
    cat >&2 <<'EOF'
error: /usr/lib/modules is not writable.
This is expected on Fedora Atomic/OSTree. Do not remount /usr writable just for
this script. Use load-test.sh for the live test; package/layer the modules for
persistent Atomic deployment after the live test succeeds.
EOF
    exit 1
fi

sudo install -d -m 0755 "$DEST"
for ko in x86-android-tablets.ko snd-soc-acpi-intel-match.ko snd-soc-sst-cht-rt5677.ko; do
    sudo install -m 0644 "$DIST/$ko" "$DEST/$ko"
done
sudo depmod -a "$KVER"

sudo tee /etc/modprobe.d/yogabook-x91f-audio.conf >/dev/null <<'EOF'
# Yoga Book YB1-X91F: use the tested legacy SST path for the RT5677 backport.
options snd_intel_dspcfg dsp_driver=2
EOF

printf '\nInstalled. Verify module resolution before reboot:\n'
for name in x86_android_tablets snd_soc_acpi_intel_match snd_soc_sst_cht_rt5677; do
    modinfo -n "$name" || true
done
