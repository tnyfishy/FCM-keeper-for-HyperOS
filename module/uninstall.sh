#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/proc.sh"
if [ -d "$RUN_DIR" ]; then
    lock_stop supervisor supervisor.sh
    lock_stop worker worker.sh
fi
case $DATA_DIR in
    ''|/|/data|/data/adb|/data/adb/) ;;
    *) rm -rf "$DATA_DIR" ;;
esac
exit 0
