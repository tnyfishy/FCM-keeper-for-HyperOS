#!/bin/sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/module"
PASS=0; FAIL=0
T=""
ok()   { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
check() {
    d=$1; shift
    if "$@"; then ok "$d"; else bad "$d"; fi
}
count() { grep -c -- "$1" "$2" 2>/dev/null || true; }

setup() {
    T=$(mktemp -d)
    cp -R "$SRC" "$T/mod"
    mkdir -p "$T/mock" "$T/data/state" "$T/data/run" "$T/data/log"
    MOCK="$T/mock"; DATA="$T/data"; MODD="$T/mod"
    : > "$MOCK/calls.log"; : > "$MOCK/sleeps.log"
    printf 'check_interval_sec=1\n' > "$DATA/config.conf"
    export MOCK_DIR="$MOCK" FCMK_DATA_DIR="$DATA" FCMK_HB_MIN_GAP=0
    export PATH="$ROOT/tests/mock:$ORIG_PATH"
    unset FCMK_MAX_LOOPS FCMK_RESTART_BASE FCMK_BOOT_ID_FILE
    printf 'bootA\n' > "$T/boot_id"; export FCMK_BOOT_ID_FILE="$T/boot_id"
}
teardown() {
    for p in $(_allmatch "$T"); do kill -KILL "$p" 2>/dev/null; done
    rm -rf "$T"
}
_allmatch() {
    _pat="[${1%"${1#?}"}]${1#?}"
    grep -la -- "$_pat" /proc/[0-9]*/cmdline 2>/dev/null | while read -r f; do
        p=${f#/proc/}; p=${p%/cmdline}
        [ "$p" = "$$" ] || echo "$p"
    done
}
procs_of() {
    _all=$(_allmatch "$1")
    for p in $_all; do
        pp=$(sed 's/.*) //' "/proc/$p/stat" 2>/dev/null | cut -d' ' -f2)
        case " $(echo $_all) " in *" $pp "*) continue ;; esac
        echo "$p"
    done
}
worker() {
    FCMK_MAX_LOOPS=$1 sh "$MODD/bin/worker.sh"
}
puts()   { grep -c '^settings put' "$MOCK/calls.log"; }
ams()    { grep -c '^am broadcast' "$MOCK/calls.log"; }
val()    { cat "$MOCK/value" 2>/dev/null; }
is()     { [ "$1" = "$2" ]; }
state()  { cat "$DATA/state/$1" 2>/dev/null; }

ORIG_PATH=$PATH
failq() { { echo keep; i=0; while [ $i -lt 60 ]; do echo fail; i=$((i+1)); done; } > "$MOCK/get_queue"; }

echo "== A. Cu phap =="
for f in "$SRC"/*.sh "$SRC"/bin/* "$SRC"/lib/*.sh "$ROOT"/build.sh "$ROOT"/tests/run_tests.sh "$ROOT"/tests/mock/*; do
    check "sh -n $(basename "$f")" sh -n "$f"
done
if command -v bash >/dev/null; then
    for f in "$SRC"/*.sh "$SRC"/bin/* "$SRC"/lib/*.sh; do check "bash -n $(basename "$f")" bash -n "$f"; done
fi
if command -v shellcheck >/dev/null; then
    check "shellcheck" shellcheck -s sh -e SC2034,SC2086,SC1090,SC1091,SC2154 "$SRC"/*.sh "$SRC"/bin/* "$SRC"/lib/*.sh
else
    echo "  skip - shellcheck khong co trong moi truong"
fi
check "khong dung pkill/killall/eval" sh -c "! grep -nE '(^|[^a-z_])(pkill|killall|eval)([^a-z_]|\$)' '$SRC'/*.sh '$SRC'/bin/* '$SRC'/lib/*.sh | grep -v '^[^:]*:[0-9]*:#'"
check "khong co CRLF" sh -c "! grep -rl \"$(printf '\r')\" '$SRC'"
check "khong co sepolicy.rule" test ! -e "$SRC/sepolicy.rule"

echo "== B. Don vi: phan tich danh sach MILLET =="
setup
. "$MODD/lib/common.sh"; . "$MODD/lib/millet.sh"
check "gms exact"                    millet_has_pkg "a.b,com.google.android.gms,c.d" com.google.android.gms
check "gms voi khoang trang"         millet_has_pkg "a.b, com.google.android.gms ,c.d" com.google.android.gms
check "persistent KHONG phai gms"    sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/millet.sh'; ! millet_has_pkg com.google.android.gms.persistent com.google.android.gms"
check "tien to khong khop"           sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/millet.sh'; ! millet_has_pkg 'x.com.google.android.gms,com.google.android.gms.y' com.google.android.gms"
millet_append "" com.google.android.gms;            check "append rong"      is "$NEW_VAL" com.google.android.gms
millet_append "a.b, c.d" com.google.android.gms;    check "append giu nguyen" is "$NEW_VAL" "a.b, c.d,com.google.android.gms"
millet_append "a.b," com.google.android.gms;        check "append dau phay cuoi" is "$NEW_VAL" "a.b,com.google.android.gms"
millet_append "a.b,a.b,,c" com.google.android.gms;  check "khong chuan hoa trung/rong" is "$NEW_VAL" "a.b,a.b,,c,com.google.android.gms"
check "validate ok"        millet_validate "a.b, c_d.e-f,"
check "validate loi java"  sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/millet.sh'; ! millet_validate 'Error type 3'"
check "validate ky tu la"  sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/millet.sh'; ! millet_validate 'a;b'"
check "validate nhieu dong" sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/millet.sh'; ! millet_validate 'a
b'"
teardown

echo "== C. Worker: cac kich ban MILLET (mock) =="
G=com.google.android.gms
setup; rm -f "$MOCK/value"; worker 3
check "khoa chua co: ghi dung gia tri"  is "$(val)" "$G"
check "khoa chua co: 1 lan ghi"         is "$(puts)" 1
check "last_fix duoc ghi"               test -n "$(state last_fix)"
check "heartbeat 2 broadcast"           is "$(ams)" 2
check "thu tu GTALK truoc MCS"          sh -c "grep '^am' '$MOCK/calls.log' | sed -n 1p | grep -q GTALK_HEARTBEAT && grep '^am' '$MOCK/calls.log' | sed -n 2p | grep -q MCS_HEARTBEAT"
check "broadcast co -p gms --user 0"    sh -c "grep '^am' '$MOCK/calls.log' | grep -q -e '--user 0 -a com.google.android.intent.action.GTALK_HEARTBEAT -p $G'"
check "tre 0.4 truoc heartbeat"         grep -qx '0.4' "$MOCK/sleeps.log"
check "khong gui heartbeat lap (own write)" is "$(ams)" 2
teardown

setup; : > "$MOCK/value"; worker 2
check "danh sach rong: ghi gms"   is "$(val)" "$G"
teardown

setup; echo "$G" > "$MOCK/value"; worker 6
check "da co gms: khong ghi"          is "$(puts)" 0
check "da co gms: heartbeat khoi tao 1 lan" is "$(ams)" 2
check "khong co last_fix"             test -z "$(state last_fix)"
teardown

setup; echo "$G.persistent" > "$MOCK/value"; worker 2
check "chi co .persistent: van bo sung" is "$(val)" "$G.persistent,$G"
teardown

setup; echo "a.b, c.d,e.f" > "$MOCK/value"; worker 2
check "giu nguyen cac muc khac"   is "$(val)" "a.b, c.d,e.f,$G"
teardown

setup; echo "a.b" > "$MOCK/value"; failq; worker 4
check "doc loi: khong ghi"        is "$(puts)" 0
check "doc loi: khong heartbeat"  is "$(ams)" 0
teardown

setup; echo "a.b" > "$MOCK/value"; touch "$MOCK/always_get_fail"
sh "$MODD/bin/worker.sh" </dev/null >/dev/null 2>&1 &
/bin/sleep 1.5
check "SettingsProvider chua san sang: worker doi, khong ghi/heartbeat" sh -c "[ \$(grep -c '^settings put' '$MOCK/calls.log') = 0 ] && [ \$(grep -c '^am' '$MOCK/calls.log') = 0 ] && [ -n \"\$(grep -la worker.sh /proc/[0-9]*/cmdline 2>/dev/null)\" ]"
sh "$MODD/bin/fcmkeeper" stop >/dev/null 2>&1
check "dung worker dang cho bang CLI stop" is "$(procs_of "$MODD/bin/worker.sh" | wc -l | tr -d ' ')" 0
teardown

setup; echo "Error type 3" > "$MOCK/value"
sh "$MODD/bin/worker.sh" </dev/null >/dev/null 2>&1 &
/bin/sleep 1
check "dinh dang la: khong ghi (worker doi)"   is "$(puts)" 0
check "dinh dang la: khong heartbeat"          is "$(ams)" 0
check "dinh dang la: gia tri giu nguyen"       is "$(val)" "Error type 3"
sh "$MODD/bin/fcmkeeper" stop >/dev/null 2>&1
teardown

setup; echo "a.b" > "$MOCK/value"; { echo keep; echo keep; echo "set:Error type 3"; i=0; while [ $i -lt 40 ]; do echo "set:Error type 3"; i=$((i+1)); done; } > "$MOCK/get_queue"; worker 4
check "dinh dang doi thanh la giua chung: khong ghi" is "$(puts)" 0
check "dinh dang la giua chung: loi doc duoc ghi" sh -c "grep -q millet_read_error '$DATA/state/last_error'"
teardown

setup; echo "a.b" > "$MOCK/value"; touch "$MOCK/put_fail"; worker 3
check "ghi loi: khong bao thanh cong" is "$(state last_fix)" ""
check "ghi loi: loai loi millet_write_error" sh -c "state_v=\$(cat '$DATA/state/last_error'); case \$state_v in *millet_write_error*) exit 0;; *) exit 1;; esac"
check "ghi loi: khong heartbeat"  is "$(ams)" 0
check "ghi loi: gia tri giu nguyen" is "$(val)" "a.b"
teardown

setup; echo "a.b" > "$MOCK/value"; touch "$MOCK/put_noop"; worker 3
check "doc lai khong xac nhan: khong bao thanh cong" is "$(state last_fix)" ""
check "verify_error duoc ghi"     sh -c "grep -q millet_verify_error '$DATA/state/last_error'"
check "verify_error: khong heartbeat" is "$(ams)" 0
teardown

setup; echo "a.b" > "$MOCK/value"
printf 'keep\nset:a.b,x.y\n' > "$MOCK/get_queue"; worker 1
check "doi ngay truoc khi sua: dung du lieu moi nhat" is "$(val)" "a.b,x.y,$G"
teardown

setup; echo "a.b" > "$MOCK/value"
printf 'keep\nset:a.b,%s\n' "$G" > "$MOCK/get_queue"; worker 1
check "GMS xuat hien truoc khi ghi: khong ghi" is "$(puts)" 0
teardown

echo "== D. Heartbeat va thay doi ben ngoai =="
setup; echo "$G" > "$MOCK/value"
printf 'keep\nkeep\nset:x.y\n' > "$MOCK/get_queue"; worker 6
check "go GMS ben ngoai: sua 1 lan"    is "$(puts)" 1
check "go GMS ben ngoai: val dung"     is "$(val)" "x.y,$G"
check "khoi tao + 1 su kien = 2 cap heartbeat" is "$(ams)" 4
teardown

setup; echo "$G" > "$MOCK/value"; export FCMK_HB_MIN_GAP=3600
printf 'keep\nset:x.y,%s\nset:x.z,%s\n' "$G" "$G" > "$MOCK/get_queue"; worker 6
check "gop su kien gan nhau: chi 1 cap heartbeat" is "$(ams)" 2
teardown

setup; rm -f "$MOCK/value"; printf 'fail\n' > "$MOCK/am_queue"; worker 3
check "broadcast 1 loi: broadcast 2 van thu" is "$(ams)" 2
check "loi heartbeat tach khoi loi MILLET"  sh -c "grep -q '|heartbeat|' '$DATA/state/last_error'"
check "MILLET van sua thanh cong"           test -n "$(state last_fix)"
check "khong gui lien tuc khi loi"          is "$(ams)" 2
teardown

echo "== E. Backoff / chu ky =="
setup; . "$MODD/lib/common.sh"
printf 'check_interval_sec=abc\nlog_max_kb=99999999\n' > "$DATA/config.conf"; cfg_load
check "cau hinh sai -> mac dinh" sh -c "[ $CFG_INTERVAL = 5 ] && [ $CFG_LOG_MAX_KB = 128 ]"
printf 'check_interval_sec=0\n' > "$DATA/config.conf"; cfg_load; check "interval 0 bi tu choi" is "$CFG_INTERVAL" 5
printf 'check_interval_sec=301\n' > "$DATA/config.conf"; cfg_load; check "interval 301 bi tu choi" is "$CFG_INTERVAL" 5
printf 'check_interval_sec = 008\r\nlog_max_kb=32\n' > "$DATA/config.conf"; cfg_load
check "cau hinh hop le (CRLF, so 0 dau)" sh -c "[ $CFG_INTERVAL = 8 ] && [ $CFG_LOG_MAX_KB = 32 ]"
printf 'check_interval_sec=$(touch %s/pwn)\n' "$T" > "$DATA/config.conf"; cfg_load
check "khong thuc thi noi dung cau hinh" test ! -e "$T/pwn"
teardown

setup; echo "a.b" > "$MOCK/value"; failq; worker 6
ints=$(grep -E '^[0-9]+$' "$MOCK/sleeps.log" | head -n 2 | tr '\n' ' ')
check "backoff tang dan (2 4 ...)" is "$ints" "2 4 "
check "loi lap: log khong bi spam" sh -c "[ \$(grep -c 'error\[' '$DATA/log/fcm_keeper.log') -le 2 ]"
teardown

setup; echo "$G" > "$MOCK/value"; worker 20
check "khong doi: log chi vai dong, khong ghi moi vong" sh -c "[ \$(wc -l < '$DATA/log/fcm_keeper.log') -le 6 ]"
check "khong doi: khong ghi settings" is "$(puts)" 0
teardown

setup; echo "$G" > "$MOCK/value"; printf '0\n0\n1\n' > "$MOCK/boot_queue"; worker 1
check "cho boot_completed roi moi thao tac" is "$(ams)" 2
teardown

setup; printf 'log_max_kb=16\n' > "$DATA/config.conf"; . "$MODD/lib/common.sh"; cfg_load
i=0; while [ $i -lt 600 ]; do log_msg "line $i padding padding padding padding padding"; i=$((i+1)); done
check "log xoay vong" test -f "$DATA/log/fcm_keeper.log.1"
check "log gioi han dung luong" sh -c "[ \$(wc -c < '$DATA/log/fcm_keeper.log') -le 20000 ]"
teardown

echo "== F. Khoa va danh tinh tien trinh =="
setup; . "$MODD/lib/common.sh"; . "$MODD/lib/proc.sh"; RUN_DIR="$DATA/run"
/bin/sleep 300 & VP=$!
proc_stat $VP; ST=$PS_START
mkdir -p "$RUN_DIR/worker.lock"
mk() { printf '%s\n%s\n%s\n%s\n' "$1" "$2" "$3" "$4" > "$RUN_DIR/worker.lock/owner"; }
CMD=$(proc_cmdline $VP)
mk $VP $ST bootA "$CMD"
check "khoa hop le (pid+start+boot+cmd)" lock_owner_alive worker sleep
check "marker sai -> khong hop le"       sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/proc.sh'; RUN_DIR='$DATA/run'; FCMK_BOOT_ID_FILE='$T/boot_id'; ! lock_owner_alive worker worker.sh"
mk $VP $((ST+1)) bootA "$CMD"
check "PID tai su dung (starttime khac)" sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/proc.sh'; RUN_DIR='$DATA/run'; FCMK_BOOT_ID_FILE='$T/boot_id'; ! lock_owner_alive worker sleep"
mk $VP $ST bootOLD "$CMD"
check "boot_id khac (sau khoi dong lai)" sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/proc.sh'; RUN_DIR='$DATA/run'; FCMK_BOOT_ID_FILE='$T/boot_id'; ! lock_owner_alive worker sleep"
mk $VP $ST bootA "sh /other/worker.sh"
check "cmdline khac" sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/proc.sh'; RUN_DIR='$DATA/run'; FCMK_BOOT_ID_FILE='$T/boot_id'; ! lock_owner_alive worker sleep"
kill $VP; wait $VP 2>/dev/null
mk $VP $ST bootA "$CMD"
check "PID da chet" sh -c ". '$MODD/lib/common.sh'; . '$MODD/lib/proc.sh'; RUN_DIR='$DATA/run'; FCMK_BOOT_ID_FILE='$T/boot_id'; ! lock_owner_alive worker sleep"
/bin/sleep 300 & VP=$!
proc_stat $VP; mk $VP $((PS_START+7)) bootA "$(proc_cmdline $VP)"
FCMK_MAX_LOOPS=1 sh "$MODD/bin/worker.sh"; rc=$?
check "khoa cu (PID tai su dung) khong chan worker moi" test "$rc" = 0
check "worker moi da chay (da ghi)" test -n "$(state worker_started)"
check "tien trinh khong lien quan khong bi kill" kill -0 $VP
kill $VP 2>/dev/null; wait $VP 2>/dev/null
check "khoa duoc don sau khi thoat" test ! -e "$DATA/run/worker.lock"
teardown

echo "== G. Dong thoi, giam sat, disable/remove (tien trinh that) =="
setup; export MOCK_SLEEP=0.05; echo "$G" > "$MOCK/value"
/bin/sleep 600 & BYSTANDER=$!
for i in 1 2 3 4; do sh "$MODD/bin/supervisor.sh" </dev/null >/dev/null 2>&1 & done
i=0; while [ $i -lt 40 ]; do [ -n "$(procs_of "$MODD/bin/worker.sh")" ] && break; /bin/sleep 0.25; i=$((i+1)); done
/bin/sleep 1
check "4 supervisor dong thoi -> dung 1" is "$(procs_of "$MODD/bin/supervisor.sh" | wc -l | tr -d ' ')" 1
check "dung 1 worker"                    is "$(procs_of "$MODD/bin/worker.sh" | wc -l | tr -d ' ')" 1
sh "$MODD/bin/fcmkeeper" start >/dev/null 2>&1; /bin/sleep 1
check "start lai khong tao ban sao" is "$(procs_of "$MODD/bin/worker.sh" | wc -l | tr -d ' ')" 1
check "status chay"               sh -c "sh '$MODD/bin/fcmkeeper' status | grep -q 'ĐANG CHẠY'"
check "action khong gui them heartbeat" sh -c "b=\$(grep -c '^am' '$MOCK/calls.log'); sh '$MODD/action.sh' >/dev/null; a=\$(grep -c '^am' '$MOCK/calls.log'); [ \$a = \$b ]"
check "action khong ghi settings" is "$(puts)" 0
check "action chi in trang thai (GMS co)" sh -c "sh '$MODD/action.sh' | grep -q 'GMS trong MILLET: CÓ'"
touch "$MODD/disable"
i=0; while [ $i -lt 60 ]; do [ -z "$(procs_of "$MODD/bin/")" ] && break; /bin/sleep 0.25; i=$((i+1)); done
check "disable: supervisor + worker dung"  is "$(procs_of "$MODD/bin/" | wc -l | tr -d ' ')" 0
check "disable: tien trinh khac van song"  kill -0 $BYSTANDER
check "disable: khoa duoc don" sh -c "[ ! -e '$DATA/run/worker.lock' ] && [ ! -e '$DATA/run/supervisor.lock' ]"
check "start bi tu choi khi disable" sh -c "! sh '$MODD/bin/fcmkeeper' start >/dev/null 2>&1"
rm -f "$MODD/disable"
sh "$MODD/bin/fcmkeeper" start >/dev/null 2>&1; /bin/sleep 1
check "start lai sau khi bat" is "$(procs_of "$MODD/bin/worker.sh" | wc -l | tr -d ' ')" 1
touch "$MODD/remove"
i=0; while [ $i -lt 60 ]; do [ -z "$(procs_of "$MODD/bin/")" ] && break; /bin/sleep 0.25; i=$((i+1)); done
check "remove: tien trinh dung" is "$(procs_of "$MODD/bin/" | wc -l | tr -d ' ')" 0
rm -f "$MODD/remove"
sh "$MODD/bin/fcmkeeper" start >/dev/null 2>&1; /bin/sleep 1
sh "$MODD/bin/fcmkeeper" stop >/dev/null 2>&1
check "CLI stop dung het" is "$(procs_of "$MODD/bin/" | wc -l | tr -d ' ')" 0
check "val MILLET khong bi sua khi stop/remove" is "$(val)" "$G"
sh "$MODD/bin/fcmkeeper" start >/dev/null 2>&1; /bin/sleep 1
sh "$MODD/uninstall.sh"
check "uninstall: dung tien trinh" is "$(procs_of "$MODD/bin/" | wc -l | tr -d ' ')" 0
check "uninstall: xoa du lieu cua module" test ! -e "$DATA"
check "uninstall: khong xoa GMS khoi MILLET" is "$(val)" "$G"
kill $BYSTANDER 2>/dev/null
unset MOCK_SLEEP
teardown

setup; export MOCK_SLEEP=0.02
printf '#!/bin/sh\nexit 1\n' > "$MODD/bin/worker.sh"
FCMK_RESTART_BASE=1 sh "$MODD/bin/supervisor.sh" </dev/null >/dev/null 2>&1 &
/bin/sleep 3
sh "$MODD/bin/fcmkeeper" stop >/dev/null 2>&1
ints=$(grep -E '^[0-9]+$' "$MOCK/sleeps.log" | head -n 4 | tr '\n' ' ')
check "worker thoat bat thuong: backoff 1 2 4 ..." sh -c "case '$ints' in '1 2 4 '*) exit 0;; *) echo got '$ints'; exit 1;; esac"
check "worker crash: khong spawn vo han (log gioi han)" sh -c "[ \$(grep -c 'worker exited' '$DATA/log/fcm_keeper.log') -le 12 ]"
unset MOCK_SLEEP
teardown

echo "== H. Goi ZIP =="
if [ -x "$ROOT/build.sh" ] || [ -f "$ROOT/build.sh" ]; then
    OUT=$(mktemp -d)
    sh "$ROOT/build.sh" "$OUT" >/dev/null 2>&1
    Z=$(ls "$OUT"/*.zip 2>/dev/null | head -n 1)
    check "tao duoc ZIP" test -n "$Z"
    if [ -n "$Z" ]; then
        LIST=$(unzip -Z1 "$Z")
        check "module.prop o goc ZIP" sh -c "echo '$LIST' | grep -qx module.prop"
        for f in customize.sh service.sh action.sh uninstall.sh; do check "ZIP co $f" sh -c "echo '$LIST' | grep -qx $f"; done
        check "ZIP khong co tests/mock/dist" sh -c "! echo '$LIST' | grep -qE '^(tests|dist|\\.git)'"
        check "ZIP khong co sepolicy.rule" sh -c "! echo '$LIST' | grep -q sepolicy"
        check "ZIP co quyen thuc thi cho script" sh -c "unzip -Zv '$Z' >/dev/null; zipinfo '$Z' service.sh | grep -q '^-rwxr-xr-x'"
        sh "$ROOT/build.sh" "$OUT/b" >/dev/null 2>&1
        check "ZIP tai tao duoc (cung SHA-256)" sh -c "[ \"\$(sha256sum '$Z' | cut -d' ' -f1)\" = \"\$(sha256sum '$OUT'/b/*.zip | cut -d' ' -f1)\" ]"
    fi
    rm -rf "$OUT"
fi

echo
echo "Ket qua: $PASS dat, $FAIL that bai"
[ "$FAIL" -eq 0 ]
