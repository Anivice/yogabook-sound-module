#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KVER="${KVER:-$(uname -r)}"
KERNEL_TAG="${KERNEL_TAG:-v7.1.13}"
KDIR="${KDIR:-/usr/src/kernels/${KVER}}"
WORK="${WORK:-${ROOT}/work}"
TREE="${WORK}/linux-${KERNEL_TAG#v}"
DIST="${ROOT}/dist/${KVER}"
ASOC_MBOX="${WORK}/asoc-v7.mbx"
ASOC_MSGID="20260902123007.769820-1-mauriziocasciano7@gmail.com"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "error: missing required command: $1" >&2
        exit 1
    }
}

for cmd in git b4 python3 make gcc modinfo sha256sum; do
    need "$cmd"
done

if [[ ! -f "${KDIR}/Makefile" ]]; then
    cat >&2 <<EOF
error: kernel build tree not found at:
  ${KDIR}

Run this script inside the Toolbx where your matching kernel-devel tree exists,
or set KDIR explicitly.
EOF
    exit 1
fi

case "$KVER" in
    7.1.13-200.fc44.x86_64) ;;
    *)
        echo "warning: this backport was designed for 7.1.13-200.fc44.x86_64; got ${KVER}" >&2
        echo "         set ALLOW_OTHER_KERNEL=1 to continue intentionally." >&2
        [[ "${ALLOW_OTHER_KERNEL:-0}" == 1 ]] || exit 1
        ;;
esac

mkdir -p "$WORK" "$DIST"

if [[ ! -d "${TREE}/.git" ]]; then
    echo "==> Sparse-cloning Linux ${KERNEL_TAG} baseline"
    git clone --depth 1 --filter=blob:none --sparse --branch "$KERNEL_TAG" \
        https://github.com/gregkh/linux.git "$TREE"
    git -C "$TREE" sparse-checkout set \
        sound/soc/intel/common \
        sound/soc/intel/boards \
        sound/soc/intel/atom \
        sound/soc/codecs \
        drivers/platform/x86
else
    echo "==> Reusing ${TREE}"
fi

# Always regenerate from the pristine v7.1.13 tag so repeated builds are deterministic.
git -C "$TREE" reset --hard "$KERNEL_TAG"
git -C "$TREE" clean -fdx

echo "==> Retrieving ASoC v7 patch 1/2 with b4"
(
    cd "$TREE"
    b4 am -P 1 -o - "$ASOC_MSGID" > "$ASOC_MBOX"
)

echo "==> Extracting upstream cht_rt5677.c and applying 7.1.13 board backport"
python3 "$ROOT/prepare.py" extract-driver \
    --mailbox "$ASOC_MBOX" \
    --output "$TREE/sound/soc/intel/boards/cht_rt5677.c"
python3 "$ROOT/prepare.py" patch-tree --tree "$TREE"

# Restrict external Kbuild to the three modules we actually need.
# The stable common/x86 Makefiles already define the composite object lists;
# adding obj-m directly while forcing their CONFIG selectors to n prevents
# unrelated configured modules from being built.
cat > "$TREE/sound/soc/intel/boards/Makefile" <<'EOF'
snd-soc-sst-cht-rt5677-y := cht_rt5677.o
obj-m += snd-soc-sst-cht-rt5677.o
EOF
printf '\nobj-m += snd-soc-acpi-intel-match.o\n' >> "$TREE/sound/soc/intel/common/Makefile"
printf '\nobj-m += x86-android-tablets.o\n' >> "$TREE/drivers/platform/x86/x86-android-tablets/Makefile"

build_dir() {
    local dir="$1"
    shift
    echo "==> Building ${dir#$TREE/}"
    make -C "$KDIR" M="$dir" clean "$@"
    make -C "$KDIR" M="$dir" -j"${JOBS:-$(nproc)}" "$@" modules
}

build_dir "$TREE/sound/soc/intel/common" \
    CONFIG_SND_SOC_ACPI_INTEL_MATCH=n \
    CONFIG_SND_SOC_ACPI_INTEL_SDCA_QUIRKS=n
build_dir "$TREE/sound/soc/intel/boards"
build_dir "$TREE/drivers/platform/x86/x86-android-tablets" \
    CONFIG_X86_ANDROID_TABLETS=n

rm -rf "$DIST"
mkdir -p "$DIST"
cp -v "$TREE/sound/soc/intel/common/snd-soc-acpi-intel-match.ko" "$DIST/"
cp -v "$TREE/sound/soc/intel/boards/snd-soc-sst-cht-rt5677.ko" "$DIST/"
cp -v "$TREE/drivers/platform/x86/x86-android-tablets/x86-android-tablets.ko" "$DIST/"

printf '\n==> Module metadata\n'
for ko in "$DIST"/*.ko; do
    printf '%-38s name=%-30s vermagic=%s\n' \
        "$(basename "$ko")" \
        "$(modinfo -F name "$ko")" \
        "$(modinfo -F vermagic "$ko")"
    vm="$(modinfo -F vermagic "$ko")"
    [[ "$vm" == "$KVER "* ]] || {
        echo "error: vermagic mismatch for $ko: $vm" >&2
        exit 1
    }
done

(
    cd "$DIST"
    sha256sum ./*.ko > SHA256SUMS
)

cat <<EOF

Build complete:
  ${DIST}

Next, leave Toolbx and run on the host:
  ./load-test.sh
EOF
