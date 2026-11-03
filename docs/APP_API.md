# SUMI: App API (GĐ0, khóa)

Một app là một repo `sumi-<id>`:

```
manifest.json   # theo docs/manifest.schema.json
View.qml        # phần giao diện thuần
shell.qml       # vỏ mỏng: layer-shell + đọc config + IPC + chạy Process
objects/<id>.qml
preview.png     # dùng cho app chưa cài (khung thu nhỏ trong store)
README.md
```

## View.qml
- Là một `Item` thuần, **không có tác dụng phụ**: không `Process`, không ghi file, không gọi lệnh.
- Property vào: `palette` (màu đã tính từ Theme), `config` (config đã gộp của app), `previewMode` (bool).
- Hành động ra qua signal, ví dụ `accepted()`, `rejected()`, `actionRequested(string fn)`.
- Khi `previewMode` là true, View hiển thị bình thường nhưng không phát signal hành động. Nhờ vậy preview trong hub không thể tắt máy thật.

## shell.qml
- Tạo layer-shell window, nạp `View.qml`, nối signal với hành động thật (Process, exit code).
- Tự đọc config qua `lib/Config.qml`, lỗi thì dùng mặc định.
- Đăng ký IPC target theo `ipc_target`, tối thiểu có hàm `reload()`.
- Chọn monitor bằng `CONFIRM_MONITOR` như hợp đồng cũ của kakunin.
- Chạy độc lập: không đòi hub đang chạy, không đụng mạng, khởi động nhanh. kakunin được gọi từ script nên đây là bắt buộc.

## Hợp đồng riêng của kakunin
Exit code `0` = yes, `1` = no. Giữ nguyên khi chuyển sang kiến trúc mới.

## Hợp đồng reload
Hub gửi IPC `reload()` sau khi Apply. App đọc lại config và áp dụng. App không chạy thì lần mở sau tự đọc config mới. Việc tự theo dõi thay đổi file chỉ là tùy chọn, cần kiểm tra thực tế ở GĐ1 vì rename file có thể làm mất theo dõi.
