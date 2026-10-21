#!/system/bin/sh

MODID="fcm_keeper_hyperos"
GMS_PKG="com.google.android.gms"
MILLET_KEY="MILLET_NO_RESTRICT_APP"
LC_ALL=C
export LC_ALL
PATH="$PATH:/system/bin:/system_ext/bin:/vendor/bin"
export PATH

DATA_DIR="${FCMK_DATA_DIR:-/data/adb/$MODID}"
CONF_FILE="$DATA_DIR/config.conf"
STATE_DIR="$DATA_DIR/state"
RUN_DIR="$DATA_DIR/run"
LOG_DIR="$DATA_DIR/log"
LOG_FILE="$LOG_DIR/fcm_keeper.log"

NL='
'
CR=$(printf '\r')

FCMK_TMO=""
if command -v timeout >/dev/null 2>&1; then
    FCMK_TMO="timeout 15"
fi

CFG_INTERVAL=5
CFG_LOG_MAX_KB=128

fcmk_init_dirs() {
    umask 077
    mkdir -p "$STATE_DIR" "$RUN_DIR" "$LOG_DIR" 2>/dev/null
    chmod 700 "$DATA_DIR" "$STATE_DIR" "$RUN_DIR" "$LOG_DIR" 2>/dev/null
    return 0
}

now_ts() {
    date +%s
}

str_trim() {
    TRIMMED=$1
    while :; do
        case $TRIMMED in
            ' '*) TRIMMED=${TRIMMED# } ;;
            *) break ;;
        esac
    done
    while :; do
        case $TRIMMED in
            *' ') TRIMMED=${TRIMMED% } ;;
            *) break ;;
        esac
    done
}

cfg_load() {
    CFG_INTERVAL=5
    CFG_LOG_MAX_KB=128
    [ -f "$CONF_FILE" ] || return 0
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line=${_line%"$CR"}
        case $_line in
            ''|'#'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        _k=${_line%%=*}
        _v=${_line#*=}
        str_trim "$_k"
        _k=$TRIMMED
        str_trim "$_v"
        _v=$TRIMMED
        case $_v in
            ''|*[!0-9]*) continue ;;
        esac
        [ "${#_v}" -le 5 ] || continue
        while :; do
            case $_v in
                0?*) _v=${_v#0} ;;
                *) break ;;
            esac
        done
        case $_k in
            check_interval_sec)
                if [ "$_v" -ge 1 ] && [ "$_v" -le 300 ]; then CFG_INTERVAL=$_v; fi
                ;;
            log_max_kb)
                if [ "$_v" -ge 16 ] && [ "$_v" -le 1024 ]; then CFG_LOG_MAX_KB=$_v; fi
                ;;
        esac
    done < "$CONF_FILE"
    return 0
}

log_msg() {
    if [ -f "$LOG_FILE" ]; then
        _sz=$(wc -c < "$LOG_FILE" 2>/dev/null)
        _sz=$((${_sz:-0} + 0))
        if [ "$_sz" -ge $((CFG_LOG_MAX_KB * 1024)) ]; then
            mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
        fi
    fi
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
    return 0
}

state_set() {
    printf '%s\n' "$2" > "$STATE_DIR/$1.tmp.$$" 2>/dev/null &&
        mv -f "$STATE_DIR/$1.tmp.$$" "$STATE_DIR/$1" 2>/dev/null
}

state_get() {
    cat "$STATE_DIR/$1" 2>/dev/null
}

err_set() {
    _m=$2
    _m=${_m%%"$NL"*}
    state_set last_error "$(now_ts)|$1|$(printf '%.200s' "$_m")"
}

module_inactive() {
    [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ] || [ ! -d "$MODDIR" ]
}

sleep_chk() {
    _rem=$1
    while [ "$_rem" -gt 0 ]; do
        _c=$_rem
        [ "$_c" -le 5 ] || _c=5
        sleep "$_c" &
        _SLP=$!
        wait "$_SLP" 2>/dev/null
        _SLP=
        _rem=$((_rem - _c))
        module_inactive && return 1
    done
    return 0
}

sleep_short() {
    sleep 0.2 2>/dev/null || sleep 1
}

fmt_ts() {
    case $1 in
        ''|*[!0-9]*) printf '%s' "chưa có"; return 0 ;;
    esac
    date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'epoch %s' "$1"
}
