#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'MSG'
load-test.sh no longer performs a live SST module swap.

Linux v7.1.13's intel_sst_acpi probe creates child platform devices for
sst-mfld-platform and the selected machine driver, while its remove callback
does not unregister those child platform devices. A live unload/reload can
therefore leave stale platform devices behind even if module refcounts can be
forced to zero.

Use the cold test instead:
  ./stage-cold-test.sh
  systemctl reboot

For the partial state left by the old load-test.sh (nocodec removed but SST
still loaded), run:
  ./rollback.sh
MSG
exit 2
