# SUMI: App API (GĐ0, khóa)

Một app là một repo `sumi-<id>`:

```
manifest.json   # theo docs/manifest.schema.json
View.qml        # phần giao diện thuần
shell.qml       # vỏ mỏng: layer-shell + đọc config + IPC + chạy Process
objects/<id>.qml
lib/             # bản lib vendored do hub/installer copy vào, KHÔNG commit (.gitignore)
preview.png     # dùng cho app chưa cài (khung thu nhỏ trong store)
README.md
```

## Import
Trong app dùng `import "lib"` (không dùng `../../lib`).

## View.qml
- Là một `Item` thuần, **không có tác dụng phụ**: không `Process`, không ghi file, không gọi lệnh.
- **Property vào**: View không tự đọc config; `shell.qml` đọc config (`SumiConfig`) rồi gán vào View. Giữ đúng **tên chuẩn** để preview trong hub gán được: `closing, active, previewMode, mode, bgColor, fgColor, mutedColor, accentColor, dangerColor, fontTitle, fontLabel, fontData, fontNumeral, fontKanji, preset, tint, inkDarken, bootMs, outroMs, scanOpacity, scanlinesEnabled, glitchEnabled, scaleU (hoặc scaleBoost), objectCfg` (xem CONVENTIONS mục 12). Màu thô (`bgColor`...) đi qua `SumiTheme` trong View để ra màu giấy/mực; không đặt hex cố định (trừ `danger`).
- Hành động ra qua signal, ví dụ `accepted()`, `rejected()`, `actionRequested(string fn)`.
- Khi `previewMode` là true, View hiển thị bình thường, không nhận phím, không giữ focus, và hub không nối signal nào; preview cũng chặn chuột. Nhờ vậy preview trong hub không thể tắt máy thật.
- Trong `ShapePath`, `PathLine` không thấy property tự khai báo trên `ShapePath`: phải đặt `id` và viết `<id>.<property>` (có test tĩnh `tools/tests/shape.test.js`).
- Khung app mới: `bash tools/new-app.sh <id>` (CONVENTIONS mục 16).

## shell.qml
- Tạo layer-shell window, nạp `View.qml`, nối signal với hành động thật (Process, exit code).
- Tự đọc config qua `lib/SumiConfig.qml`, lỗi thì dùng mặc định.
- Đăng ký IPC target theo `ipc_target`, tối thiểu có hàm `reload()`.
- Chọn monitor bằng `CONFIRM_MONITOR` như hợp đồng cũ của kakunin.
- Chạy độc lập: không đòi hub đang chạy, không đụng mạng, khởi động nhanh. kakunin được gọi từ script nên đây là bắt buộc.

## Hợp đồng riêng của kakunin
Exit code `0` = yes, `1` = no. Giữ nguyên khi chuyển sang kiến trúc mới.

## Namespace layer-shell
Giữ nguyên tên gốc (`clock-widget`, `clock-widget-confirm`, `confirm-close`) để các `layerrule` Hyprland đang có vẫn khớp.

## Phím
Mỗi action có **một phím chính** cấu hình được qua `keybinds`. Các phím phụ có sẵn (mũi tên, Space, Enter, Tab, W/S...) giữ nguyên, không cấu hình được. `cancel` luôn là Escape và bị khóa. lib cung cấp `KeyMap.match(event, "Y")` để so khớp tên phím với `event.key`.

## Kiểu app
- `oneshot`: `sumi <id>` chạy thẳng `quickshell -p {dir}/shell.qml`, truyền nguyên biến môi trường và exit code. Không cần hub.
- `daemon`: `sumi <id> <function>` tự khởi động app nếu chưa chạy rồi gọi IPC. Tên hàm IPC lấy từ `ipc_name` (nếu có) hoặc `id` của function.

## Hợp đồng reload
- Hub ghi config bằng `sumi config apply` (ghi atomic: tạo file tạm rồi đổi tên). `lib/SumiConfig.qml` theo dõi file (`watchChanges`) và tự đọc lại; app không chạy thì lần mở sau đọc config mới. Hub **không** gửi IPC sau khi Apply.
- Mọi app vẫn khai IPC `reload()` (đọc lại config ngay, dùng khi cần ép hoặc khi theo dõi file bị mất sau rename). Reload của app daemon chỉ áp dụng cho lần mở thẻ kế tiếp và **không bao giờ đụng trạng thái đang chạy** (jigen: timer đang đếm giữ nguyên).
