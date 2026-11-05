# SUMI: Object API (GĐ0, khóa)

Object là phần đồ họa tương tác (globe, cube...) đặt tại `objects/<id>.qml` của app, hoán đổi được theo function.

## Property bắt buộc
| Property | Kiểu | Ý nghĩa |
|---|---|---|
| `palette` | object | Màu đã tính từ Theme |
| `running` | bool | false thì dừng toàn bộ animation |
| `size` | real | Kích thước ô vẽ |
| `speed` | real | Hệ số tốc độ, 1.0 là mặc định |
| `interactive` | bool | Cho phép kéo, quán tính |
| `grid` | int | Mật độ lưới (44–56) nếu object dùng lưới. **0 = dùng lưới mặc định của object** (mỗi object có mặc định riêng) |

## Quy ước
- Object tự lo xoay, kéo và quán tính. App không điều khiển bên trong.
- Object không có tác dụng phụ, không đọc/ghi file, không gọi Process.
- Khi `running` là false và `interactive` là false thì object phải ngừng dùng CPU/GPU.
- Object chỉ dùng màu từ `palette`, không đặt hex cố định (trừ `danger` nếu cần).
- `id` của object theo `^[a-z][a-z0-9-]{1,31}$`, khớp tên file `objects/<id>.qml`.
- Option riêng của object (speed, grid, interactive) lưu ở `apps.<id>.objects.<function>` trong config.

## Cách app nạp object (jigen là bản mẫu)
- File `objects/<id>.qml` (id khớp `^[a-z][a-z0-9-]{1,31}$`, đúng với `functions[].objects` trong manifest) là **wrapper** theo bảng trên; bên trong có thể bọc type dựng sẵn (jigen: `globe` bọc `GlobeObject`, `torus` và `hourglass` bọc `PointObject`).
- `ObjectSlot.qml` (ở thư mục gốc app) nạp `objects/<id>.qml` bằng `Loader`, gán 6 thuộc tính chuẩn bằng `Binding`, và rơi về `defaultObject` của function nếu object lỗi khi nạp. Layout chỉ đặt vị trí/kích thước và `fn: "<function>"`.
- `View.objectFor(fn)` kiểm tra từng giá trị đọc thô từ `apps.<id>.objects.<fn>`: `id` phải nằm trong danh sách của function (không thì dùng `defaultObject`), `speed` kẹp 0..5, `grid` chỉ nhận 44..56 (ngoài khoảng = 0 = mặc định), `interactive` phải là bool. Danh sách `objectAllowed`/`objectDefaults` trong View phải khớp manifest (có test).
- Màn cảnh báo cuối của jigen (mode `warning`) dùng layout shutdown nên dùng object của function **shutdown**.
- Hub, tab 5 OBJECTS (hoặc `J` ở trang APPS): mỗi function có hàng `OBJECT` (chọn id, chỉ khi có từ 2 object), `SPEED` (0..5, bước 0.1) và `DRAG` (interactive). `grid` hub không sửa nhưng được giữ nguyên nếu có trong config; muốn đổi thì sửa tay `apps.<id>.objects.<function>.grid`.
