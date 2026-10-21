#!/system/bin/sh

case $0 in */*) _d=${0%/*} ;; *) _d=. ;; esac
MODDIR=$(cd "$_d/.." && pwd)
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/proc.sh"

RESTART_BASE="${FCMK_RESTART_BASE:-5}"
case $RESTART_BASE in ''|*[!0-9]*|0) RESTART_BASE=5 ;; esac
RESTART_CAP=300
HEALTHY_SECS=120
POLL=2

fcmk_init_dirs
cfg_load

lock_acquire supervisor supervisor.sh
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
    lock_stop worker worker.sh
    lock_release supervisor
    log_msg "supervisor stopped pid=$$"
}
trap 'exit 0' TERM INT HUP
trap cleanup EXIT

log_msg "supervisor started pid=$$"

BACKOFF=$RESTART_BASE
WPID=""
SPAWN_TS=0

while :; do
    module_inactive && { log_msg "module disabled/removed: stopping supervisor"; break; }

    if lock_owner_alive worker worker.sh; then
        if [ "$(($(now_ts) - SPAWN_TS))" -ge "$HEALTHY_SECS" ]; then
            BACKOFF=$RESTART_BASE
        fi
        sleep_chk "$POLL" || continue
        continue
    fi

    if [ -n "$WPID" ]; then
        wait "$WPID" 2>/dev/null
        _rc=$?
        WPID=""
        _ran=$(($(now_ts) - SPAWN_TS))
        if [ "$_ran" -ge "$HEALTHY_SECS" ]; then
            BACKOFF=$RESTART_BASE
        fi
        log_msg "worker exited rc=$_rc after ${_ran}s; restart in ${BACKOFF}s"
        _w=$BACKOFF
        BACKOFF=$((BACKOFF * 2))
        [ "$BACKOFF" -le "$RESTART_CAP" ] || BACKOFF=$RESTART_CAP
        sleep_chk "$_w" || continue
        module_inactive && continue
    fi

    sh "$MODDIR/bin/worker.sh" </dev/null >/dev/null 2>&1 &
    WPID=$!
    SPAWN_TS=$(now_ts)
    _i=0
    while [ "$_i" -lt 20 ]; do
        lock_owner_alive worker worker.sh && break
        proc_stat "$WPID" || break
        case $PS_STATE in Z|X) break ;; esac
        sleep 0.5 2>/dev/null || sleep 1
        _i=$((_i + 1))
    done
done
exit 0
