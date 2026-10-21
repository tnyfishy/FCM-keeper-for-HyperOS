#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/proc.sh"
. "$MODDIR/lib/millet.sh"
. "$MODDIR/lib/status.sh"
cfg_load
ensure_running
print_status
exit 0
