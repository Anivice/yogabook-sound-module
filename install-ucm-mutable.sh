#!/usr/bin/env bash
set -euo pipefail

WORK="${WORK:-$PWD/work-ucm}"
REPO="$WORK/Yoga-Book-ALSA-UCM-Config"

if ! sudo test -w /usr/share/alsa/ucm2; then
    cat >&2 <<'EOF'
error: /usr/share/alsa/ucm2 is not writable (typical on Fedora Atomic).
Do not remount /usr. First prove the kernel/PCM path with load-test.sh; then
install the UCM tree through an OSTree/RPM layer rather than mutating /usr.
EOF
    exit 1
fi

rm -rf "$REPO"
git clone --depth 1 https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config.git "$REPO"
sudo cp -a "$REPO/ucm2/." /usr/share/alsa/ucm2/
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true

echo "Yoga Book UCM2 files installed. Run: alsaucm listcards"
