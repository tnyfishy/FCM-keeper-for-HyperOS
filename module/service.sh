#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/proc.sh"
. "$MODDIR/lib/millet.sh"
. "$MODDIR/lib/status.sh"
module_inactive && exit 0
fcmk_init_dirs
start_supervisor
exit 0
