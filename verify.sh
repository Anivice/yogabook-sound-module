#!/usr/bin/env bash
set -u

printf '=== kernel ===\n'
uname -a

printf '\n=== cards ===\n'
cat /proc/asound/cards 2>&1

printf '\n=== playback PCMs ===\n'
aplay -l 2>&1

printf '\n=== capture PCMs ===\n'
arecord -l 2>&1

printf '\n=== relevant modules ===\n'
lsmod | grep -Ei 'cht_rt5677|byt_cht_nocodec|rt5677|ts3a|sst|sof|snd_soc_acpi_intel_match' || true

printf '\n=== audio I2C clients ===\n'
find /sys/bus/i2c/devices -maxdepth 1 \
    \( -iname '*5677*' -o -iname '*003b*' -o -iname '*ts3a*' \) -print 2>/dev/null || true

printf '\n=== UCM tool ===\n'
if command -v alsaucm >/dev/null; then
    alsaucm listcards 2>&1 || true
else
    echo 'alsaucm not installed (Fedora package: alsa-ucm-utils)'
fi

printf '\n=== PipeWire ===\n'
wpctl status 2>&1 || true

printf '\n=== recent kernel audio log ===\n'
sudo dmesg | grep -Ei 'cht-rt5677|chtrt5677|bytcht|rt5677|ts3a227|sst|asoc|audio port' | tail -160 || true
