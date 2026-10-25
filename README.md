# FCM Keeper For HyperOS

- Module **giúp duy trì trạng thái kết nối tới FCM (dịch vụ thông báo đẩy của Google)**

## Cài đặt

1. Mở KernelSU Manager → Module → Cài đặt từ bộ nhớ → chọn `FCM-Keeper-For-HyperOS-v*.zip`.
2. Khởi động lại máy.

## Kiểm tra hoạt động

- Trong KernelSU Manager, bấm nút **Action** của module để xem: đang chạy/đã dừng, GMS có trong MILLET hay không, thời điểm kiểm tra / sửa / gửi heartbeat gần nhất, lỗi gần nhất.
- Dòng lệnh (root): `sh /data/adb/modules/fcm_keeper_hyperos/bin/fcmkeeper status|start|stop|restart`
- Kiểm tra thủ công: `settings --user 0 get system MILLET_NO_RESTRICT_APP`
