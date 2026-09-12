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
lsmod | grep -Ei 'drv260x|x86_android_tablets|cht_rt5677|byt_cht_nocodec|rt5677|ts3a|sst|sof|snd_soc_acpi_intel_match' || true

printf '\n=== haptics I2C devices ===\n'
found_i2c=0
for dev in /sys/bus/i2c/devices/*DRV2604*; do
    [[ -e "$dev" ]] || continue
    found_i2c=1
    driver='(unbound)'
    if [[ -L "$dev/driver" ]]; then
        driver="$(basename "$(readlink -f "$dev/driver")")"
    fi
    printf '%s  driver=%s\n' "$dev" "$driver"
done
(( found_i2c )) || echo 'No DRV2604 ACPI/I2C devices found.'

printf '\n=== haptics force-feedback input devices ===\n'
found_ff=0
for namefile in /sys/class/input/event*/device/name; do
    [[ -r "$namefile" ]] || continue
    if [[ "$(cat "$namefile")" == 'drv260x:haptics' ]]; then
        found_ff=1
        event="$(basename "$(dirname "$(dirname "$namefile")")")"
        printf '/dev/input/%s  name=drv260x:haptics\n' "$event"
    fi
done
if (( ! found_ff )); then
    echo 'No drv260x:haptics event devices found.'
else
    cat <<'TXT'
To physically test each actuator, install Fedora's linuxconsoletools and run
fftest against each event path printed above:
  sudo dnf install -y linuxconsoletools
  sudo fftest /dev/input/eventX
Choose a rumble effect, stop it, then repeat for the other event device.
TXT
fi

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

printf '\n=== recent kernel audio/haptics log ===\n'
sudo dmesg | grep -Ei 'DRV2604|drv260x|haptic|cht-rt5677|chtrt5677|bytcht|rt5677|ts3a227|sst|asoc|audio port' | tail -220 || true
