#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
DIST="${ROOT}/dist/${KVER}"
STAGE="/var/lib/yogabook-audio-oot/${KVER}"
ETCDIR="/etc/yogabook-audio-oot"
UNIT="/etc/systemd/system/yogabook-audio-oot.service"

required_modules=(
    x86-android-tablets.ko
    snd-soc-acpi-intel-match.ko
    snd-soc-sst-cht-rt5677.ko
)

product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
case "$product" in
    *YB1-X91*) ;;
    *)
        echo "error: refusing to stage Yoga Book audio modules on product: ${product:-unknown}" >&2
        exit 1
        ;;
esac

command -v rpm-ostree >/dev/null || {
    echo "error: this cold-test staging script currently targets rpm-ostree hosts" >&2
    exit 1
}

for ko in "${required_modules[@]}"; do
    [[ -f "$DIST/$ko" ]] || {
        echo "error: missing $DIST/$ko; build inside Toolbx first" >&2
        exit 1
    }
done

check_module() {
    local file="$1" expected_name="$2"
    local name vermagic
    name="$(modinfo -F name "$file")"
    vermagic="$(modinfo -F vermagic "$file")"
    [[ "$name" == "$expected_name" ]] || {
        echo "error: $file has module name '$name', expected '$expected_name'" >&2
        exit 1
    }
    [[ "$vermagic" == "$KVER "* ]] || {
        echo "error: $file vermagic '$vermagic' does not match running kernel '$KVER'" >&2
        exit 1
    }
}

check_module "$DIST/x86-android-tablets.ko" x86_android_tablets
check_module "$DIST/snd-soc-acpi-intel-match.ko" snd_soc_acpi_intel_match
check_module "$DIST/snd-soc-sst-cht-rt5677.ko" snd_soc_sst_cht_rt5677

if grep -qw '\[integrity\]' /sys/kernel/security/lockdown 2>/dev/null || \
   grep -qw '\[confidentiality\]' /sys/kernel/security/lockdown 2>/dev/null; then
    echo "warning: kernel lockdown is active; unsigned OOT modules may be rejected" >&2
fi

sudo -v
sudo install -d -m 0755 "$STAGE" "$ETCDIR"
for ko in "${required_modules[@]}"; do
    sudo install -m 0644 "$DIST/$ko" "$STAGE/$ko"
done

sudo tee "$ETCDIR/load.sh" >/dev/null <<'EOF_LOADER'
#!/usr/bin/env bash
set -euo pipefail

KVER="$(uname -r)"
STAGE="/var/lib/yogabook-audio-oot/${KVER}"

log() { printf 'yogabook-audio-oot: %s\n' "$*"; }
module_loaded() { [[ -d "/sys/module/$1" ]]; }

for ko in \
    x86-android-tablets.ko \
    snd-soc-acpi-intel-match.ko \
    snd-soc-sst-cht-rt5677.ko; do
    [[ -f "$STAGE/$ko" ]] || {
        log "missing staged module: $STAGE/$ko"
        exit 1
    }
done

# These must not have been auto-loaded from the Fedora module tree. If one is
# already present, do not attempt any live replacement; fail before changing
# the audio stack so the boot remains diagnosable.
for mod in \
    x86_android_tablets \
    snd_soc_acpi_intel_match \
    snd_intel_sst_acpi \
    snd_sof_acpi_intel_byt; do
    if module_loaded "$mod"; then
        log "refusing to continue: stock module already loaded: $mod"
        exit 1
    fi
done

load_deps_for_ko() {
    local ko="$1" deps dep
    deps="$(modinfo -F depends "$ko" 2>/dev/null || true)"
    IFS=',' read -r -a dep_array <<< "$deps"
    for dep in "${dep_array[@]}"; do
        [[ -n "$dep" ]] || continue
        modprobe "$dep"
    done
}

log "loading patched Yoga Book board resources"
load_deps_for_ko "$STAGE/x86-android-tablets.ko"
insmod "$STAGE/x86-android-tablets.ko"

log "loading patched Cherry Trail ACPI match table"
load_deps_for_ko "$STAGE/snd-soc-acpi-intel-match.ko"
insmod "$STAGE/snd-soc-acpi-intel-match.ko"

log "loading RT5677 machine driver"
load_deps_for_ko "$STAGE/snd-soc-sst-cht-rt5677.ko"
insmod "$STAGE/snd-soc-sst-cht-rt5677.ko"

log "loading legacy Intel SST frontend"
modprobe snd_intel_sst_acpi

log "loaded successfully"
EOF_LOADER
sudo chmod 0755 "$ETCDIR/load.sh"

sudo tee "$UNIT" >/dev/null <<'EOF_UNIT'
[Unit]
Description=Yoga Book X91F out-of-tree audio cold loader
DefaultDependencies=no
After=local-fs.target systemd-modules-load.service
Before=basic.target

[Service]
Type=oneshot
ExecStart=/etc/yogabook-audio-oot/load.sh
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF_UNIT

sudo systemctl daemon-reload
sudo systemctl enable yogabook-audio-oot.service

# Prevent the stock modules from binding before our early boot loader runs.
# rd.driver.blacklist covers dracut/initramfs autoload; modprobe.blacklist
# covers normal userspace alias based autoload. Direct insmod of our staged
# replacement modules is unaffected by modprobe blacklist entries.
KARG_RD='rd.driver.blacklist=x86_android_tablets,snd_soc_acpi_intel_match,snd_intel_sst_acpi,snd_sof_acpi_intel_byt'
KARG_MP='modprobe.blacklist=x86_android_tablets,snd_soc_acpi_intel_match,snd_intel_sst_acpi,snd_sof_acpi_intel_byt'
KARG_SST='snd_intel_dspcfg.dsp_driver=2'

sudo rpm-ostree kargs \
    --append-if-missing="$KARG_RD" \
    --append-if-missing="$KARG_MP" \
    --append-if-missing="$KARG_SST"

cat <<EOF_MSG

Cold test staged for kernel: $KVER
Modules copied to:          $STAGE
Loader:                     $ETCDIR/load.sh
Systemd unit:               $UNIT

No running kernel module was unloaded.

Next step:
  systemctl reboot

After reboot:
  cd "$ROOT"
  ./verify.sh
  systemctl status yogabook-audio-oot.service --no-pager
  journalctl -b -u yogabook-audio-oot.service --no-pager

To remove the test for the NEXT boot:
  ./unstage-cold-test.sh
EOF_MSG
