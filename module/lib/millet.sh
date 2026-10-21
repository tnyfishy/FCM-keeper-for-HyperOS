#!/system/bin/sh

millet_validate() {
    case $1 in
        *"$NL"*|*"$CR"*) return 1 ;;
    esac
    case $1 in
        *[!-A-Za-z0-9_.,' ']*) return 1 ;;
    esac
    _vl=$1
    _vend=""
    while :; do
        case $_vl in
            *,*) _vt=${_vl%%,*}; _vl=${_vl#*,} ;;
            *) _vt=$_vl; _vl=""; _vend=1 ;;
        esac
        str_trim "$_vt"
        case $TRIMMED in
            *' '*) return 1 ;;
        esac
        [ -z "$_vend" ] || break
    done
    return 0
}

millet_has_pkg() {
    _hl=$1
    _hend=""
    while :; do
        case $_hl in
            *,*) _ht=${_hl%%,*}; _hl=${_hl#*,} ;;
            *) _ht=$_hl; _hl=""; _hend=1 ;;
        esac
        str_trim "$_ht"
        [ "$TRIMMED" != "$2" ] || return 0
        [ -z "$_hend" ] || break
    done
    return 1
}

millet_append() {
    str_trim "$1"
    if [ -z "$TRIMMED" ]; then
        NEW_VAL=$2
        return 0
    fi
    case $TRIMMED in
        *,) NEW_VAL="$1$2" ;;
        *) NEW_VAL="$1,$2" ;;
    esac
}

millet_read() {
    MILLET_KIND="error"
    MILLET_VAL=""
    MILLET_ERR=""
    _mo=$($FCMK_TMO settings --user 0 get system "$MILLET_KEY" 2>&1)
    _mrc=$?
    if [ "$_mrc" -ne 0 ]; then
        MILLET_ERR="settings get rc=$_mrc"
        return 1
    fi
    if [ "$_mo" = "null" ]; then
        MILLET_KIND="absent"
        return 0
    fi
    if [ -z "$_mo" ]; then
        MILLET_KIND="empty"
        return 0
    fi
    if ! millet_validate "$_mo"; then
        MILLET_ERR="unsafe/unknown value format"
        return 1
    fi
    MILLET_KIND="list"
    MILLET_VAL=$_mo
    return 0
}

millet_snapshot() {
    printf '%s:%s' "$MILLET_KIND" "$MILLET_VAL"
}

millet_has_gms_now() {
    [ "$MILLET_KIND" = "list" ] && millet_has_pkg "$MILLET_VAL" "$GMS_PKG"
}

millet_put() {
    _po=$($FCMK_TMO settings --user 0 put system "$MILLET_KEY" "$1" 2>&1)
    _prc=$?
    if [ "$_prc" -ne 0 ]; then
        MILLET_ERR="settings put rc=$_prc"
        return 1
    fi
    return 0
}

millet_ensure() {
    ENS_RESULT=""
    ENS_SNAP=""
    ENS_ERR=""
    if ! millet_read; then
        ENS_RESULT="read_error"
        ENS_ERR=$MILLET_ERR
        return 1
    fi
    if millet_has_gms_now; then
        ENS_RESULT="present"
        ENS_SNAP=$(millet_snapshot)
        return 0
    fi
    case $MILLET_KIND in
        absent|empty) NEW_VAL=$GMS_PKG ;;
        *) millet_append "$MILLET_VAL" "$GMS_PKG" ;;
    esac
    if ! millet_put "$NEW_VAL"; then
        ENS_RESULT="write_error"
        ENS_ERR=$MILLET_ERR
        return 1
    fi
    if ! millet_read; then
        ENS_RESULT="verify_error"
        ENS_ERR="readback failed: $MILLET_ERR"
        return 1
    fi
    if ! millet_has_gms_now; then
        ENS_RESULT="verify_error"
        ENS_ERR="readback does not contain $GMS_PKG"
        return 1
    fi
    ENS_RESULT="fixed"
    ENS_SNAP=$(millet_snapshot)
    return 0
}

hb_send() {
    HB_GTALK="fail"
    HB_MCS="fail"
    HB_ERR=""
    for _ha in GTALK_HEARTBEAT MCS_HEARTBEAT; do
        _ho=$($FCMK_TMO am broadcast --user 0 -a "com.google.android.intent.action.$_ha" -p "$GMS_PKG" 2>&1)
        _hrc=$?
        _hres="ok"
        if [ "$_hrc" -ne 0 ]; then
            _hres="fail"
            HB_ERR="$_ha rc=$_hrc"
        else
            case $_ho in
                *Exception*|*"Error:"*|*"Error type"*)
                    _hres="fail"
                    HB_ERR="$_ha reported error"
                    ;;
            esac
        fi
        if [ "$_ha" = "GTALK_HEARTBEAT" ]; then HB_GTALK=$_hres; else HB_MCS=$_hres; fi
    done
    [ "$HB_GTALK" = "ok" ] || [ "$HB_MCS" = "ok" ]
}
