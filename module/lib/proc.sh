#!/system/bin/sh

boot_id() {
    cat "${FCMK_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null
}

proc_stat() {
    PS_STATE=""
    PS_START=""
    _ps=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    [ -n "$_ps" ] || return 1
    _ps=${_ps##*) }
    set -- $_ps
    PS_STATE=$1
    [ "$#" -ge 20 ] || return 1
    shift 19
    PS_START=$1
    return 0
}

proc_cmdline() {
    _c=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)
    while :; do
        case $_c in
            *' ') _c=${_c% } ;;
            *) break ;;
        esac
    done
    printf '%s' "$_c"
}

guard_enter() {
    _gi=0
    while ! mkdir "$RUN_DIR/guard.d" 2>/dev/null; do
        _gm=$(stat -c %Y "$RUN_DIR/guard.d" 2>/dev/null)
        case $_gm in
            ''|*[!0-9]*) ;;
            *)
                if [ $(($(now_ts) - _gm)) -gt 15 ]; then
                    rmdir "$RUN_DIR/guard.d" 2>/dev/null
                    continue
                fi
                ;;
        esac
        _gi=$((_gi + 1))
        [ "$_gi" -le 50 ] || return 1
        sleep_short
    done
    return 0
}

guard_leave() {
    rmdir "$RUN_DIR/guard.d" 2>/dev/null
}

lock_read_owner() {
    _f="$RUN_DIR/$1.lock/owner"
    [ -f "$_f" ] || return 1
    {
        IFS= read -r LK_PID
        IFS= read -r LK_START
        IFS= read -r LK_BOOT
        IFS= read -r LK_CMD
    } < "$_f"
    case $LK_PID in
        ''|*[!0-9]*) return 1 ;;
    esac
    case $LK_START in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

lock_owner_alive() {
    lock_read_owner "$1" || return 1
    [ "$LK_BOOT" = "$(boot_id)" ] || return 1
    proc_stat "$LK_PID" || return 1
    case $PS_STATE in
        Z|X) return 1 ;;
    esac
    [ "$PS_START" = "$LK_START" ] || return 1
    _oc=$(proc_cmdline "$LK_PID")
    [ "$_oc" = "$LK_CMD" ] || return 1
    case $_oc in
        *"$2"*) ;;
        *) return 1 ;;
    esac
    return 0
}

lock_acquire() {
    _ld="$RUN_DIR/$1.lock"
    guard_enter || return 2
    if [ -e "$_ld" ]; then
        if lock_owner_alive "$1" "$2"; then
            guard_leave
            return 1
        fi
        rm -rf "$_ld"
    fi
    if ! mkdir "$_ld" 2>/dev/null; then
        guard_leave
        return 2
    fi
    proc_stat "$$"
    {
        printf '%s\n' "$$"
        printf '%s\n' "$PS_START"
        printf '%s\n' "$(boot_id)"
        printf '%s\n' "$(proc_cmdline "$$")"
    } > "$_ld/owner" 2>/dev/null
    guard_leave
    lock_read_owner "$1" && [ "$LK_PID" = "$$" ] || return 2
    return 0
}

lock_release() {
    if lock_read_owner "$1" && [ "$LK_PID" = "$$" ]; then
        rm -rf "$RUN_DIR/$1.lock"
    fi
    return 0
}

lock_stop() {
    if ! lock_owner_alive "$1" "$2"; then
        if [ -e "$RUN_DIR/$1.lock" ] && guard_enter; then
            lock_owner_alive "$1" "$2" || rm -rf "$RUN_DIR/$1.lock"
            guard_leave
        fi
        return 0
    fi
    _sp=$LK_PID
    kill -TERM "$_sp" 2>/dev/null
    _si=0
    while [ "$_si" -lt 30 ]; do
        sleep_short
        lock_owner_alive "$1" "$2" || break
        _si=$((_si + 1))
    done
    if lock_owner_alive "$1" "$2" && [ "$LK_PID" = "$_sp" ]; then
        kill -KILL "$_sp" 2>/dev/null
        sleep_short
    fi
    if ! lock_owner_alive "$1" "$2"; then
        if guard_enter; then
            lock_owner_alive "$1" "$2" || rm -rf "$RUN_DIR/$1.lock"
            guard_leave
        fi
    fi
    return 0
}
