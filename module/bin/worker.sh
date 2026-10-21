#!/system/bin/sh

case $0 in */*) _d=${0%/*} ;; *) _d=. ;; esac
MODDIR=$(cd "$_d/.." && pwd)
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/proc.sh"
. "$MODDIR/lib/millet.sh"

HB_DELAY="0.4"
HB_MIN_GAP="${FCMK_HB_MIN_GAP:-30}"
case $HB_MIN_GAP in ''|*[!0-9]*) HB_MIN_GAP=30 ;; esac

fcmk_init_dirs
cfg_load

lock_acquire worker worker.sh
case $? in
    0) ;;
    1) exit 0 ;;
    *) exit 1 ;;
esac

_SLP=""
_DONE=""
cleanup() {
    [ -z "$_DONE" ] || return 0
    _DONE=1
    [ -z "$_SLP" ] || kill "$_SLP" 2>/dev/null
    state_set worker_stopped "$(now_ts)"
    lock_release worker
    log_msg "worker stopped pid=$$"
}
trap 'exit 0' TERM INT HUP
trap cleanup EXIT

log_msg "worker started pid=$$ interval=${CFG_INTERVAL}s"
state_set worker_started "$(now_ts)"

next_backoff() {
    _nb=$(($1 * 2))
    [ "$_nb" -le "$2" ] || _nb=$2
    echo "$_nb"
}

BACKOFF_CAP=60
[ "$CFG_INTERVAL" -le "$BACKOFF_CAP" ] || BACKOFF_CAP=$CFG_INTERVAL

FAIL=0
ERR_LOGGED=""
note_error() {
    FAIL=$((FAIL + 1))
    err_set "$1" "$2"
    if [ "$ERR_LOGGED" != "$1" ] || [ $((FAIL % 30)) -eq 0 ]; then
        log_msg "error[$1]: $2 (consecutive=$FAIL)"
        ERR_LOGGED=$1
    fi
}
note_ok() {
    if [ "$FAIL" -gt 0 ]; then
        log_msg "recovered after $FAIL consecutive failure(s)"
    fi
    FAIL=0
    ERR_LOGGED=""
}

wait_ready() {
    _wd=2
    _wlogged=""
    while :; do
        module_inactive && return 1
        if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && millet_read; then
            return 0
        fi
        if [ -z "$_wlogged" ]; then
            log_msg "waiting for boot_completed / SettingsProvider"
            _wlogged=1
        fi
        sleep_chk "$_wd" || return 1
        _wd=$(next_backoff "$_wd" 30)
    done
}

if ! wait_ready; then
    exit 0
fi
log_msg "system ready"

LAST_SEEN=""
HAVE_LAST=""
PENDING_HB=1
LAST_HB=0
LAST_CHECK_W=0
DELAY=$CFG_INTERVAL
LOOPS=0

while :; do
    module_inactive && { log_msg "module disabled/removed: stopping"; break; }

    _now=$(now_ts)
    if [ $((_now - LAST_CHECK_W)) -ge 30 ]; then
        state_set last_check "$_now"
        LAST_CHECK_W=$_now
    fi

    GMS_OK=""
    if millet_read; then
        _snap=$(millet_snapshot)
        if [ -z "$HAVE_LAST" ]; then
            HAVE_LAST=1
            LAST_SEEN=$_snap
        elif [ "$_snap" != "$LAST_SEEN" ]; then
            log_msg "MILLET list changed externally (kind=$MILLET_KIND)"
            LAST_SEEN=$_snap
            PENDING_HB=1
        fi
        if millet_has_gms_now; then
            GMS_OK=1
            state_set gms_present 1
            note_ok
            DELAY=$CFG_INTERVAL
        else
            state_set gms_present 0
            [ "$FAIL" -gt 0 ] || log_msg "GMS missing from MILLET list (kind=$MILLET_KIND): fixing"
            millet_ensure
            case $ENS_RESULT in
                fixed)
                    LAST_SEEN=$ENS_SNAP
                    GMS_OK=1
                    state_set gms_present 1
                    state_set last_fix "$(now_ts)"
                    log_msg "MILLET fixed and verified by readback"
                    PENDING_HB=1
                    note_ok
                    DELAY=$CFG_INTERVAL
                    ;;
                present)
                    LAST_SEEN=$ENS_SNAP
                    GMS_OK=1
                    state_set gms_present 1
                    PENDING_HB=1
                    note_ok
                    DELAY=$CFG_INTERVAL
                    ;;
                *)
                    note_error "millet_$ENS_RESULT" "$ENS_ERR"
                    DELAY=$(next_backoff "$DELAY" "$BACKOFF_CAP")
                    ;;
            esac
        fi
    else
        note_error "millet_read_error" "$MILLET_ERR"
        DELAY=$(next_backoff "$DELAY" "$BACKOFF_CAP")
    fi

    if [ -n "$PENDING_HB" ] && [ -n "$GMS_OK" ]; then
        _now=$(now_ts)
        if [ $((_now - LAST_HB)) -ge "$HB_MIN_GAP" ]; then
            sleep "$HB_DELAY" 2>/dev/null || sleep 1
            PENDING_HB=""
            LAST_HB=$(now_ts)
            if hb_send; then
                state_set last_hb "$LAST_HB"
                log_msg "heartbeat requests sent (GTALK=$HB_GTALK MCS=$HB_MCS); request only, FCM connection not verified"
            else
                log_msg "heartbeat error: GTALK=$HB_GTALK MCS=$HB_MCS"
            fi
            if [ "$HB_GTALK" != "ok" ] || [ "$HB_MCS" != "ok" ]; then
                err_set "heartbeat" "GTALK=$HB_GTALK MCS=$HB_MCS $HB_ERR"
            fi
        fi
    fi

    LOOPS=$((LOOPS + 1))
    if [ -n "$FCMK_MAX_LOOPS" ] && [ "$LOOPS" -ge "$FCMK_MAX_LOOPS" ]; then
        break
    fi
    sleep_chk "$DELAY" || { log_msg "module disabled/removed: stopping"; break; }
done
exit 0
