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
- **Font theo vai trò:** `title, label, data, numeral, kanji`. Mặc định giữ nguyên giao diện hiện tại: `title`=sans, `label`=sans, `data`=mono, `numeral`=mono, `kanji`=font hệ thống.
  Lưu dạng `global.fonts` / `apps.<id>.fonts` = `{ "<role>": "<family>" }`. Thiếu role = kế thừa (app, rồi global, rồi mặc định). Family là chuỗi 1..80 ký tự, không có `"`, `\` hay ký tự điều khiển. Hub không có font riêng, dùng font của `global`.
  Hub lấy danh sách font từ `fc-list` (`%{family[0]}`, `%{spacing}` 100/110 = mono, `:lang=ja` = có glyph Nhật). Kanji chọn font không có glyph Nhật thì cảnh báo (không chặn).
- **Keybind:** `apps.<id>.keybinds` = `{ "<action>": "<tên phím>" }`, tên là tên phím Qt bỏ `Key_` (`Y`, `Return`, `Space`, `Left`, `Comma`...; danh sách trong `SumiConfigEdit.keyNames`, khớp `SumiKeyMap`). Chỉ lưu phần khác mặc định; action `locked` không ghi được. Esc (cancel) và Tab/Backtab không gán được.

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
- Hub cảnh báo (không chặn Apply) khi: phím trùng action khác trong cùng app; gán phím app xử lý cố định cho action khác (`Return/Enter/Space`=confirm, mũi tên và `W/S`=nav); gán `1-3` trong app có nhiều function (dùng để nhảy function).

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
- Hub lấy dữ liệu từ `sumi list --json`: mảng các `{id, name, kanji, description, version, kind, running, dir, functions:[{id, label, ipc_name}], keybinds:[{action, default, label, locked}], fonts:[...]}`. `fonts` là `manifest.fonts` nguyên văn (mảng tên vai trò); rỗng hoặc không nhận ra thì hub coi app dùng cả 5 vai trò.
  `running` = có tiến trình `-p <dir>/shell.qml`. Manifest hỏng thì app đó bị bỏ qua, không làm hỏng cả danh sách.
- Hub chạy app bằng `Quickshell.execDetached([sumi, id, function])` rồi tự đóng để app nhận focus bàn phím.

## 10. Phiên bản
- **lib được vendor vào từng app** (`apps/<id>/lib/`, kèm file `VERSION`), vì Quickshell chỉ nhận import nằm trong thư mục chứa `shell.qml`. Repo app ghi `lib/` vào `.gitignore`. Hub cài hoặc cập nhật lib thì copy lại vào mọi app và kiểm tra `requires_lib`.
- lib dùng semver. Đổi breaking trong Object API hoặc App API thì tăng major.
- App khai báo `requires_lib`. Hub từ chối chạy app không khớp và báo `[INCOMPATIBLE]`.

## 11. Cài đặt trong hub (GĐ2b)
- Ba tab: THEME, FONT, KEYS (Tab / Shift+Tab / phím 1-3). Phạm vi: THEME = global, hub, các app; FONT = global và các app; KEYS = chỉ app có `keybinds`. Phạm vi chọn gần nhất được giữ khi đổi tab.
- Mỗi tab có bản nháp riêng theo phạm vi; đổi phạm vi thì bỏ bản nháp chưa áp dụng. Dấu `*` trên tab = có thay đổi chưa áp dụng.
- Mọi thay đổi đều ghi qua `sumi config apply` (xem mục 2), không bao giờ ghi trực tiếp. Config hiện có mà đọc không ra JSON thì hub từ chối ghi.
- App oneshot (kakunin) đọc config mỗi lần chạy. App daemon (jigen) chỉ nhận giao diện, font, phím mới ở lần mở overlay kế tiếp sau khi reload.

## 9. Store CLI (`sumi store`, file `bin/sumi-store`)
Hub gọi với `--json`; mỗi lệnh in đúng một đối tượng/mảng JSON. Lỗi: `{"ok":false,"code":"...","message":"..."}`.

| Lệnh | Việc |
|---|---|
| `registry [--refresh]` | Tải `index.json` (cache `registry-cache.json`, hạn `hub.checkUpdateHours`, mặc định 6 giờ, timeout 5 s; offline thì dùng cache cũ và `stale:true`). Mỗi app có `state`: `available`, `installed`, `update` (sha registry khác sha đã cài), `dev` (có thư mục app nhưng không do store quản lý). |
| `inspect <id>` | `ls-remote` kiểm tag, clone tạm, xác minh SHA, validate, kiểm `requires_lib` và gói hệ thống. Không cài gì. Dữ liệu cho màn hình xác nhận: nguồn, version, SHA, `shell_commands`, `requires` (ok/missing/unknown), `lib.compatible`, `conflict`, `warnings`. |
| `install <id> --sha <sha> [--replace]` | `--sha` phải bằng SHA registry (người dùng đã xác nhận ở `inspect`), lệch thì từ chối `registry_changed`. Clone lại, xác minh lại, validate, vendor lib, rename vào `apps/`. `--replace` để thay bản dev (bản dev được sao lưu). |
| `update <id> --sha <sha>` | Như install; bản cũ vào `backups/removed/<id>-<stamp>/`. |
| `remove <id> [--force]` | Chuyển app vào `backups/removed/`. Giữ nguyên `apps.<id>` trong `config.json`. Bản dev cần `--force`. |
| `removed [<id>]`, `restore <id> [stamp]` | Liệt kê và khôi phục sao lưu (dùng làm rollback sau update). Giữ tối đa 5 bản cho mỗi id. |

- **installed.json**: `{"version":1,"apps":{"<id>":{"repo","ref","sha","version","installed_at","source":"store"}}}`. App không có bản ghi là app dev (`install-dev.sh` xóa bản ghi khi ghi đè app).
- **Mã thoát**: 0 ok, 1 lỗi chung, 2 sai cú pháp, 3 app đang chạy, 4 `[INCOMPATIBLE]`, 5 không qua kiểm tra, 6 offline, 7 xung đột (đã cài/bản dev/chưa cài).
- **Luật bổ sung so với mục 6** (do code kiểm tra, không chỉ validator): `run` chỉ được là `qs -p {dir}/shell.qml` hoặc `quickshell -p {dir}/shell.qml` (vì `sumi <app>` exec thẳng chuỗi này); không symlink; không file đặc biệt; tối đa 5 MiB và 300 file; repo có file `*.sh`/`*.py`/có bit thực thi thì hiện cảnh báo ở màn xác nhận; thư mục `lib/` của repo (nếu có) bị thay bằng lib của SUMI.
- Clone chạy với `GIT_ALLOW_PROTOCOL=https`, không đọc git config người dùng/hệ thống, tắt hooks, không submodule, không tag; `.git` bị xóa sau khi xác minh SHA.
- Thao tác ghi giữ `sumi.lock`. Từ chối khi app đang chạy (pgrep `-p <dir>/shell.qml`).

### Hub: tab STORE (GĐ3b)
- Trang APPS bấm `G` mở STORE. Hub **không tự ghi gì**: chỉ gọi `sumi store ... --json` rồi hiển thị; logic thuần nằm ở `lib/SumiStoreLogic.qml`, máy trạng thái ở `hub/shell.qml` (`store*`).
- Phím: `W/S` chọn app, `Enter` cài/cập nhật (luôn qua `inspect` rồi màn hình xác nhận), `X` gỡ, `B` bản sao lưu (Enter để khôi phục), `R` tải lại registry (`--refresh`), `Esc` quay lại.
- Màn hình xác nhận hiển thị: nguồn, version, SHA đầy đủ, lib, gói `requires` (thiếu thì đỏ), mọi `shell_commands`, cảnh báo. Lệnh cài dùng đúng SHA của lần `inspect` (`--sha`), không lấy SHA từ nơi nào khác. `[INCOMPATIBLE]` thì không cho xác nhận.
- Hub chặn trước khi app đang chạy (jigen: cảnh báo tắt app sẽ huỷ hẹn giờ); CLI vẫn chặn thật bằng mã 3.
- Đang chạy lệnh store thì hub không đóng được (tránh ngắt giữa chừng).

## 10. Tab OPTIONS và `protectedClasses` (GĐ2b-3)
- **Kiểu option** (`manifest.options[].type`): `bool`, `int`, `float`, `enum`, `intlist` (1..16 số nguyên, mỗi số trong `[min,max]`), `string` (0..64 ký tự, không ký tự điều khiển), `stringlist` (0..32 chuỗi, mỗi chuỗi 1..64 ký tự gồm chữ, số và `_ . * ? -`; dùng cho glob class cửa sổ). `locked: true` thì hub không cho đổi.
- **Lưu**: `config.apps.<id>.options = { "<key>": giá trị }`, chỉ ghi phần **khác mặc định**; bằng mặc định thì xoá key. Key option lạ (app khác phiên bản) được giữ nguyên khi ghi. Giá trị sai kiểu/ngoài khoảng bị bỏ qua khi đọc và app dùng mặc định.
- **Hub, tab 4 OPTIONS** (hoặc `O` ở trang APPS): `W/S` chọn hàng, `A/D` chỉnh một nấc (bool/enum đổi giá trị; int bước ≈ khoảng/20 làm tròn lũy thừa 10; float bước ≈ khoảng/50, tối thiểu 0.01), `Enter` sửa (bool/enum đổi giá trị, còn lại mở ô nhập: `Enter` lưu nháp, `Esc` huỷ, giá trị sai thì ở lại ô nhập và báo lỗi), `R` về mặc định hàng, `X` về mặc định hết, `Space` apply (cùng luồng validate, backup, ghi atomic như các tab khác). Danh sách app lấy từ `sumi list --json` (trường `options`).
- **Cảnh báo chéo** (không chặn): `timer.defaultMinutes` không nằm trong `timer.presets` thì viền đỏ ở hàng defaultMinutes (khớp luật của `tools/validate.py`).
- **`protectedClasses`** (kakunin, `stringlist`, mặc định `["zen*","Minecraft*"]`): danh sách glob class cửa sổ mà `contrib/safe-close.sh` phải hỏi kakunin trước khi đóng. Script đọc `apps.kakunin.options.protectedClasses` bằng `jq` mỗi lần chạy:
  - chưa đặt / thiếu file / JSON hỏng / sai kiểu → dùng mặc định;
  - `[]` → không bảo vệ app nào;
  - mục sai định dạng bị bỏ qua (không bao giờ được diễn giải thành lệnh).
  - Chốt chặn một dialog: `pgrep -f -- '-p [^ ]*/apps/kakunin/shell\.qml'` (khớp cả `qs -p` lẫn `quickshell -p`).
