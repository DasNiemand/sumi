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
| `grid` | int | Mật độ lưới (44–56) nếu object dùng lưới |

## Quy ước
- Object tự lo xoay, kéo và quán tính. App không điều khiển bên trong.
- Object không có tác dụng phụ, không đọc/ghi file, không gọi Process.
- Khi `running` là false và `interactive` là false thì object phải ngừng dùng CPU/GPU.
- Object chỉ dùng màu từ `palette`, không đặt hex cố định (trừ `danger` nếu cần).
- `id` của object theo `^[a-z][a-z0-9-]{1,31}$`, khớp tên file `objects/<id>.qml`.
- Option riêng của object (speed, grid, interactive) lưu ở `apps.<id>.objects.<function>` trong config.
