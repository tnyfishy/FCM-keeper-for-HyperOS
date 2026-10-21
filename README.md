# FCM Keeper For HyperOS

Module KernelSU (ID: `fcm_keeper_hyperos`) cho Xiaomi/Redmi/POCO chạy HyperOS. Module làm đúng hai việc, chỉ với `com.google.android.gms`:

1. Giữ `com.google.android.gms` trong `Settings.System.MILLET_NO_RESTRICT_APP` (danh sách "Không hạn chế" của pin HyperOS), không đụng đến các mục khác.
2. Gửi yêu cầu heartbeat tới GMS (`GTALK_HEARTBEAT` rồi `MCS_HEARTBEAT`, kèm `-p com.google.android.gms`) khi khởi động xong, khi danh sách bị đổi từ bên ngoài, và sau khi module bổ sung lại GMS thành công.

Không cần APK, giao diện, WebUI, Shizuku, LSPosed hay Zygisk. Không đổi SELinux, không có `sepolicy.rule`, không tải gì từ Internet, không thu thập hay gửi dữ liệu ra ngoài.

## Giới hạn (đọc kỹ)

- Module **giúp duy trì mục GMS trong MILLET và gửi yêu cầu heartbeat**. Không bảo đảm kết nối FCM luôn tồn tại và không vượt qua mọi chính sách tiết kiệm pin của HyperOS.
- Kết quả `am broadcast` chỉ cho biết lệnh gửi đã chạy, **không chứng minh FCM đã kết nối**. Log ghi "đã gửi yêu cầu heartbeat" chứ không ghi "FCM đã kết nối".
- Các ứng dụng khác (Telegram, v.v.) bạn tự đặt "Không hạn chế" trong cài đặt pin của HyperOS; module giữ nguyên chúng.
- Giám sát bằng **vòng lặp shell (polling) mỗi 5 giây**, không phải `ContentObserver`. Module không giữ wakelock và không đặt báo thức; khi máy suspend, vòng lặp tạm dừng và tiếp tục khi CPU thức.
- Thao tác đọc–sửa–ghi qua `settings` **không phải giao dịch nguyên tử**. Module giảm rủi ro bằng cách đọc lại ngay trước khi ghi và đọc lại sau khi ghi để xác minh, nhưng nếu hệ thống ghi đúng khoảnh khắc giữa hai bước thì vẫn có thể bị ghi đè; vòng kiểm tra kế tiếp sẽ phát hiện và sửa lại.
- Tiến trình root vẫn có thể bị hệ thống/người dùng kill; module có supervisor khởi động lại worker nhưng không khẳng định không thể bị dừng.
- Định dạng danh sách (dấu phẩy, `settings get` trả `null` khi khóa chưa có) lấy từ tài liệu cộng đồng ([dingwen07/hyperos-fcm-fix](https://github.com/dingwen07/hyperos-fcm-fix), [kingwatam/hyperos-gms-fcm-fix](https://github.com/kingwatam/hyperos-gms-fcm-fix)), chưa xác minh từ mã nguồn Xiaomi hay trên thiết bị của bạn. Nếu giá trị đọc ra có ký tự lạ ngoài `A-Za-z0-9_.-`, dấu phẩy và dấu cách, module **không ghi** mà chỉ báo lỗi.

## Cách module sửa danh sách

- Đọc `settings --user 0 get system MILLET_NO_RESTRICT_APP`; phân biệt: khóa chưa có (`null`), danh sách rỗng, danh sách có giá trị, và lỗi đọc.
- So khớp chính xác từng package (`com.google.android.gms.persistent` không được tính là GMS).
- Đã có GMS: không ghi. Chưa có: đọc lại giá trị mới nhất, chỉ nối thêm `,com.google.android.gms` vào chuỗi hiện có (giữ nguyên mọi mục khác, kể cả trùng lặp), ghi bằng `settings put`, rồi đọc lại. Chỉ ghi nhận "sửa thành công" khi đọc lại thấy GMS.
- Đọc lỗi/định dạng lạ/ghi lỗi/đọc lại không xác nhận: không báo thành công, giữ nguyên dữ liệu, thử lại với khoảng chờ tăng dần (5 → 10 → 20 → 40 → 60 giây), trở về chu kỳ mặc định khi bình thường.
- Heartbeat chờ ~400 ms sau bước xử lý MILLET; các sự kiện gần nhau được gộp (tối thiểu 30 giây giữa hai lần gửi). Lỗi heartbeat được tách riêng khỏi lỗi sửa MILLET và không bị gửi lại liên tục.

## Cài đặt

1. Mở KernelSU Manager → Module → Cài đặt từ bộ nhớ → chọn `FCM-Keeper-For-HyperOS-v1.0.0.zip`.
2. Khởi động lại máy. Module tự chạy sau khi `sys.boot_completed=1` và SettingsProvider truy cập được; không phụ thuộc mở khóa màn hình.

## Kiểm tra hoạt động

- Trong KernelSU Manager, bấm nút **Action** của module để xem: đang chạy/đã dừng, GMS có trong MILLET hay không, thời điểm kiểm tra / sửa / gửi heartbeat gần nhất, lỗi gần nhất. Action chỉ đọc, không gửi heartbeat và không ghi settings (nếu module bật mà worker chưa chạy thì nó khởi chạy supervisor, không tạo bản sao).
- Dòng lệnh (root): `sh /data/adb/modules/fcm_keeper_hyperos/bin/fcmkeeper status|start|stop|restart`
- Kiểm tra thủ công: `settings --user 0 get system MILLET_NO_RESTRICT_APP`

## Log và cấu hình

- Log: `/data/adb/fcm_keeper_hyperos/log/fcm_keeper.log` (xoay vòng sang `.log.1`, mặc định tối đa 128 KB mỗi tệp). Chỉ ghi khởi động, thay đổi MILLET, sửa thành công/thất bại, heartbeat, dừng; không ghi mỗi vòng lặp và không ghi cả danh sách ứng dụng.
- Cấu hình: `/data/adb/fcm_keeper_hyperos/config.conf` (đọc bằng phân tích `key=value`, không `source`/`eval`):
  - `check_interval_sec` (1–300, mặc định 5)
  - `log_max_kb` (16–1024, mặc định 128)
  Giá trị sai bị bỏ qua và dùng mặc định. Thay đổi có hiệu lực sau `fcmkeeper restart` hoặc khởi động lại.
- Trạng thái: `/data/adb/fcm_keeper_hyperos/state/`. Quyền thư mục 700, tệp cấu hình 600.

## Tắt và gỡ

- **Tắt**: bật công tắc tắt module trong KernelSU Manager (tạo tệp `disable`). Supervisor và worker phát hiện trong vài giây và tự dừng. Có thể dừng tay bằng `fcmkeeper stop`.
- **Gỡ**: gỡ module trong KernelSU Manager rồi khởi động lại. Khi gỡ, module dừng đúng tiến trình của nó (xác minh PID + thời điểm khởi tạo + boot ID + command line, không dùng `pkill`/`killall`) và xóa `/data/adb/fcm_keeper_hyperos/`. Module **không** xóa `com.google.android.gms` khỏi MILLET (mục này có thể do HyperOS/người dùng thêm) và không dừng Google Play Services.

## Cấu trúc

```
module/                 # nội dung được đóng gói vào ZIP
  module.prop customize.sh service.sh action.sh uninstall.sh config.default
  bin/worker.sh bin/supervisor.sh bin/fcmkeeper
  lib/common.sh lib/proc.sh lib/millet.sh lib/status.sh
tests/run_tests.sh      # kiểm tra mock + cú pháp (không đóng gói)
tests/mock/             # giả lập settings/am/getprop/sleep
build.sh                # đóng gói ZIP tái tạo được + SHA-256
dist/                   # ZIP và .sha256 đã build
```

## Build và kiểm tra

```sh
sh tests/run_tests.sh   # kiểm tra cú pháp + mock + tiến trình thật trên máy dev
sh build.sh             # tạo dist/FCM-Keeper-For-HyperOS-v1.0.0.zip và .sha256
```

Biến môi trường `FCMK_*` (`FCMK_MAX_LOOPS`, `FCMK_HB_MIN_GAP`, `FCMK_RESTART_BASE`, `FCMK_DATA_DIR`, `FCMK_BOOT_ID_FILE`) chỉ phục vụ kiểm thử; không đặt khi dùng thật.

## Trạng thái kiểm thử

- Đã làm: kiểm tra cú pháp (`sh -n`, `bash -n`), kiểm tra mock các tình huống MILLET/heartbeat/khóa/backoff/disable/remove và tiến trình thật trong môi trường Linux của máy dev.
- **Chưa làm**: chạy trên thiết bị HyperOS thật, chạy trong KernelSU thật (cài ZIP, `service.sh`, nút Action, gỡ module), và xác minh định dạng thực của `MILLET_NO_RESTRICT_APP` cũng như hành vi `settings get` khi khóa chưa có trên máy thật. Cần bạn kiểm tra các mục này (xem báo cáo bàn giao).
