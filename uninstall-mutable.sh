#!/usr/bin/env bash
set -euo pipefail
KVER="${KVER:-$(uname -r)}"
sudo rm -rf "/usr/lib/modules/$KVER/updates/yogabook-x91f"
sudo rm -f /etc/modprobe.d/yogabook-x91f-audio.conf
sudo depmod -a "$KVER"
echo "Removed persistent Yoga Book OOT modules for $KVER. Reboot to return to stock." 
