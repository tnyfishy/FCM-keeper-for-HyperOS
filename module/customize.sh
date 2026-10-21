#!/system/bin/sh
MODID_FCMK="fcm_keeper_hyperos"
DATA="/data/adb/$MODID_FCMK"

say() { if command -v ui_print >/dev/null 2>&1; then ui_print "$1"; else echo "$1"; fi; }

say "- FCM Keeper For HyperOS"
if [ "$KSU" != "true" ]; then
    say "! Khong phat hien KernelSU; module chi duoc thiet ke cho KernelSU."
fi
if ! command -v settings >/dev/null 2>&1; then
    say "! Khong tim thay lenh 'settings' trong PATH cua trinh cai dat (van co the co luc chay)."
fi

OLD="/data/adb/modules/$MODID_FCMK"
if [ -f "$OLD/bin/fcmkeeper" ]; then
    sh "$OLD/bin/fcmkeeper" stop >/dev/null 2>&1
fi

umask 077
mkdir -p "$DATA/state" "$DATA/run" "$DATA/log"
chmod 700 "$DATA" "$DATA/state" "$DATA/run" "$DATA/log"
if [ ! -f "$DATA/config.conf" ]; then
    cp "$MODPATH/config.default" "$DATA/config.conf"
    chmod 600 "$DATA/config.conf"
    say "- Da tao cau hinh mac dinh: $DATA/config.conf"
else
    say "- Giu nguyen cau hinh hien co"
fi

if command -v set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive "$MODPATH" 0 0 0755 0644
    for f in customize.sh service.sh action.sh uninstall.sh bin/worker.sh bin/supervisor.sh bin/fcmkeeper lib/common.sh lib/proc.sh lib/millet.sh lib/status.sh; do
        set_perm "$MODPATH/$f" 0 0 0755
    done
fi
say "- Hoan tat. Khoi dong lai may de module tu chay."
