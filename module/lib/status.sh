#!/system/bin/sh

start_supervisor() {
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$MODDIR/bin/supervisor.sh" </dev/null >/dev/null 2>&1 &
    else
        nohup sh "$MODDIR/bin/supervisor.sh" </dev/null >/dev/null 2>&1 &
    fi
}

ensure_running() {
    module_inactive && return 1
    fcmk_init_dirs
    if ! lock_owner_alive supervisor supervisor.sh; then
        start_supervisor
        _ei=0
        while [ "$_ei" -lt 15 ]; do
            lock_owner_alive supervisor supervisor.sh && break
            sleep_short
            _ei=$((_ei + 1))
        done
    fi
    return 0
}

print_status() {
    fcmk_init_dirs
    echo "FCM Keeper For HyperOS"
    if [ -e "$MODDIR/remove" ]; then
        echo "Module: ĐANG ĐƯỢC ĐÁNH DẤU GỠ (sẽ bị gỡ khi khởi động lại)"
    elif [ -e "$MODDIR/disable" ]; then
        echo "Module: ĐANG TẮT"
    fi
    if lock_owner_alive supervisor supervisor.sh; then
        _sp=$LK_PID
    else
        _sp=""
    fi
    if lock_owner_alive worker worker.sh; then
        _wp=$LK_PID
    else
        _wp=""
    fi
    if [ -n "$_wp" ]; then
        echo "Trạng thái: ĐANG CHẠY (worker PID $_wp, supervisor PID ${_sp:-không có})"
    else
        echo "Trạng thái: ĐÃ DỪNG (worker không chạy)"
    fi
    if millet_read; then
        if millet_has_gms_now; then
            echo "GMS trong MILLET: CÓ"
        else
            echo "GMS trong MILLET: KHÔNG (dạng khóa: $MILLET_KIND)"
        fi
    else
        echo "GMS trong MILLET: KHÔNG ĐỌC ĐƯỢC ($MILLET_ERR)"
    fi
    echo "Kiểm tra gần nhất: $(fmt_ts "$(state_get last_check)")"
    echo "Sửa thành công gần nhất: $(fmt_ts "$(state_get last_fix)")"
    echo "Gửi yêu cầu heartbeat gần nhất: $(fmt_ts "$(state_get last_hb)")"
    _le=$(state_get last_error)
    if [ -n "$_le" ]; then
        _lt=${_le%%|*}
        _lr=${_le#*|}
        echo "Lỗi gần nhất: $(fmt_ts "$_lt") [${_lr%%|*}] ${_lr#*|}"
    else
        echo "Lỗi gần nhất: không có"
    fi
    echo "Lưu ý: heartbeat chỉ là yêu cầu broadcast, không chứng minh FCM đã kết nối."
}
