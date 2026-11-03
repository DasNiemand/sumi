# SUMI: Quy ước chung (GĐ0, khóa)

## 1. Đường dẫn
| Thứ | Đường dẫn |
|---|---|
| Hub, lib, app | `~/.local/share/sumi/{hub,lib,apps/<id>}`; mỗi app có bản lib riêng ở `apps/<id>/lib/` (vendored) |
| Config | `~/.config/sumi/config.json` |
| Palette thô | `~/.config/sumi/colors.json` (7 key, xuất từ template Noctalia) |
| Đã cài | `~/.config/sumi/installed.json` |
| Cache registry | `~/.config/sumi/registry-cache.json` |
| Backup | `~/.config/sumi/backups/<timestamp>/`, đã xóa thì `backups/removed/<id>-<timestamp>/` |
| Khóa | `~/.config/sumi/sumi.lock` |
| Log | `/tmp/sumi.log` (hub), `/tmp/sumi-<id>.log` (app) |

## 2. Lệnh
`sumi` (mở hub), `sumi <app> [function]`, `sumi reset`, `sumi config apply|backups|restore`, `sumi update`, `sumi uninstall`.
`sumi config apply <json|->` kiểm cấu trúc, giữ `sumi.lock`, sao lưu `backups/<stamp>/config.json`, ghi file tạm rồi `mv` (nguyên tử), giữ tối đa `hub.maxBackups` bản (mặc định 20). Hub ghi config chỉ qua lệnh này.
Alias chuyển tiếp `clockwidget` và `confirm` giữ trong thời gian chuyển đổi.

## 3. Config
- Gộp: mặc định manifest < `global` < `apps.<id>`. Key thiếu lấy mặc định, key thừa bỏ qua.
- Đọc lỗi (JSON hỏng, sai schema) thì dùng toàn bộ mặc định và ghi một dòng vào log. App không bao giờ không mở được vì config.
- Ghi: validate, ghi file tạm, `rename` (atomic). Trước khi ghi phải backup.
- `config_version` theo app. Thấp hơn manifest thì chạy hàm migrate của app, thiếu hàm thì dùng mặc định.
- Tra cứu giá trị:
  - **Option riêng của app** (khai báo trong `manifest.options`): `apps.<id>.options[<key>]`, thiếu thì mặc định của manifest. Key là chuỗi phẳng, ví dụ `"timer.presets"`.
  - **Look chung** (`theme, tint, inkDarken, scanlines, scanlineOpacity, glitch, scaleBoost, fonts`): `apps.<id>` rồi `global` rồi mặc định của lib.
  - `crtBootMs`, `crtOutroMs` là option riêng của từng app vì mặc định khác nhau (kakunin 800/460, jigen 900/460).
- lib kẹp mọi giá trị số vào khoảng của schema trước khi dùng; giá trị sai kiểu bị bỏ qua và dùng mặc định.
- **Font theo vai trò:** `title, label, data, numeral, kanji`. Mặc định giữ nguyên giao diện hiện tại: `title`=sans, `label`=sans, `data`=mono, `numeral`=mono, `kanji`=sans.

## 4. Theme
- `colors.json` chứa palette thô. Màu cuối tính lúc chạy trong `lib/SumiTheme.qml` theo preset (`theme` trong config): `paper, ink, mono-white, mono-black, accent, follow`. Mặc định `paper`.
- Cặp giấy/mực của từng preset (L = palette sáng hơn trong surface/on_surface, D = tối hơn, A = primary; `soft/rule/wash` luôn là mix ink→paper 0.42/0.58/0.90):

| Preset | paper | ink |
|---|---|---|
| `paper` (công thức gốc, giữ nguyên) | `tint(darker(L,1.16), A·tint)` | `darker(D, inkDarken)` |
| `ink` | `tint(darker(D,1.25), A·tint)` | `lighter(L, 1+(inkDarken-1)·0.2)` |
| `mono-white` | xám cùng độ sáng với `darker(L,1.16)` | xám cùng độ sáng với `darker(D,inkDarken)` |
| `mono-black` | xám cùng độ sáng với `darker(D,1.25)` | xám cùng độ sáng với ink của `ink` |
| `accent` | `mix(darker(L,1.16), A, 0.22+tint·0.5)` | `darker(mix(D,A,0.28), inkDarken)` |
| `follow` | palette tối thì như `ink`, sáng thì như `paper` | |

- `danger` là màu cố định `#E63946` (`SumiTheme.danger`), không derive.
- Tương phản ink/paper theo WCAG: `(L1 + 0.05) / (L2 + 0.05)` với L là độ sáng tương đối (có linearize sRGB). **Dưới 4.5 chặn Apply, dưới 7 cảnh báo.**
- Runtime: app lỗi tương phản (< 4.5, ví dụ sửa tay config) thì `SumiTheme` tự rơi về `paper` (`fellBack`), không bao giờ vẽ chữ không đọc được.
- Hub ghi theme ở 3 phạm vi: `global`, `hub` (chỉ `hub.theme`; tint/inkDarken lấy của global), và từng app (`apps.<id>`). Thiếu key = kế thừa phạm vi cha.

## 5. Quy tắc phím
- Escape luôn là `cancel`, locked, không gán lại.
- Nhận phím sau ~180 ms kể từ khi mở, bỏ qua auto-repeat.
- Phím mặc định không được trùng nhau trong cùng app (trừ `confirm` và `cancel` có thể dùng chung phím với action khác không xung đột).
- Hub cảnh báo khi người dùng gán phím trùng.

## 6. An toàn khi cài
Validate trước khi rename vào `apps/`:
1. `manifest.json` qua `manifest.schema.json` + luật trong `tools/validate.py`.
2. Mọi chuỗi đường dẫn không chứa `..`, không bắt đầu bằng `/`, không có `\`.
3. Có đủ file: `manifest.json`, `View.qml`, `shell.qml`, `objects/<id>.qml` cho mọi object khai báo.
4. `requires_lib` khớp phiên bản lib hiện tại, không khớp thì `[INCOMPATIBLE]`.
5. `git rev-parse HEAD` của bản clone phải bằng `sha` trong registry.
6. Màn hình xác nhận hiển thị: nguồn, version, SHA, `shell_commands`, `requires` còn thiếu. Người dùng đồng ý mới cài.
- Không có script post-install. Không cài từ nguồn ngoài registry.
- Clone vào thư mục tạm, lỗi thì xóa sạch thư mục tạm.
- Cùng lúc chỉ một install/update/apply: giữ `sumi.lock`.

## 7. Phát hành
- Tag annotated `vX.Y.Z`, không bao giờ xóa hay đẩy lại tag đã phát hành.
- `sha` trong registry là SHA **commit**: `git rev-parse 'vX.Y.Z^{commit}'`.
- Kiểm tra bản mới: `git ls-remote <repo> 'refs/tags/vX.Y.Z^{}'`, cache 6 giờ, timeout 5 s, offline thì chỉ báo, không lỗi.
- Registry: `https://raw.githubusercontent.com/DasNiemand/sumi-index/main/index.json`. Link raw có thể cache vài phút.

## 8. App đang chạy
- Manifest có `kind`: `oneshot` (chạy xong thoát, như kakunin) hoặc `daemon` (sống nền và giữ trạng thái, như jigen khi đang hẹn giờ).
- Hub **từ chối cập nhật, xóa hoặc reset** app đang chạy. Với jigen đang đếm giờ, hub cảnh báo rằng tắt app sẽ hủy hẹn giờ tắt máy.
- `reload` của app `daemon` chỉ áp dụng giao diện và option cho lần mở overlay kế tiếp. Nó **không bao giờ** đụng timer đang chạy.
- `ipc_aliases` giữ tên IPC cũ (jigen giữ `clock-widget`) để bind Hyprland và nút Noctalia cũ chạy tiếp trong thời gian chuyển đổi.

## 9. Hub
- Hub **không phải app**: không có manifest, nằm ở `~/.local/share/sumi/hub/` và cũng giữ bản lib vendored riêng (`hub/lib/`).
- Mở bằng `sumi hub` (chọn màn hình đang focus qua `hyprctl`, truyền cho hub bằng biến `SUMI_MONITOR`; đã mở thì không mở thêm).
- Hub lấy dữ liệu từ `sumi list --json`: mảng các `{id, name, kanji, description, version, kind, running, dir, functions:[{id, label, ipc_name}]}`.
  `running` = có tiến trình `-p <dir>/shell.qml`. Manifest hỏng thì app đó bị bỏ qua, không làm hỏng cả danh sách.
- Hub chạy app bằng `Quickshell.execDetached([sumi, id, function])` rồi tự đóng để app nhận focus bàn phím.

## 10. Phiên bản
- **lib được vendor vào từng app** (`apps/<id>/lib/`, kèm file `VERSION`), vì Quickshell chỉ nhận import nằm trong thư mục chứa `shell.qml`. Repo app ghi `lib/` vào `.gitignore`. Hub cài hoặc cập nhật lib thì copy lại vào mọi app và kiểm tra `requires_lib`.
- lib dùng semver. Đổi breaking trong Object API hoặc App API thì tăng major.
- App khai báo `requires_lib`. Hub từ chối chạy app không khớp và báo `[INCOMPATIBLE]`.
