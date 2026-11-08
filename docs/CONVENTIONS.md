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
- **Bố cục hub (từ 1.1)**: cửa sổ layer-shell phủ **toàn màn hình** (`card` = `anchors.fill: parent`, `u = min(w/1920, h/1080) * 1.15`), giấy + khung mảnh 1 px thụt 14, vát góc dưới phải; CRT bật/tắt thu cả màn hình. Trang APPS là dashboard 3 cột (A 22% / B 48% / C 30%): A = danh sách app, REGISTRY, LOG (6 dòng cuối `/tmp/sumi.log`); B = tên + kanji, DETAILS, FUNCTIONS (A/D, hiện object đang dùng), KEYBINDS hiệu lực, thanh RUN; C = PREVIEW (V), SYSTEM (MEM/BAT/TEMP/LOAD/UPTIME thật, làm mới 2 s chỉ khi ở trang APPS), SHORTCUTS bấm chuột được. Settings là **một màn hình gộp** theo phạm vi (xem mục 11); STORE giữ bố cục cũ trên vùng toàn màn hình. Số liệu SYSTEM/LOG chỉ lấy từ `sysProc` (không bịa); thêm panel mới thì lấy dữ liệu qua `Process` + `SplitParser`, không dựng số liệu giả.
- Hub lấy dữ liệu từ `sumi list --json`: mảng các `{id, name, kanji, description, version, kind, running, dir, functions:[{id, label, ipc_name}], keybinds:[{action, default, label, locked}], fonts:[...]}`. `fonts` là `manifest.fonts` nguyên văn (mảng tên vai trò); rỗng hoặc không nhận ra thì hub coi app dùng cả 5 vai trò.
  `running` = có tiến trình `-p <dir>/shell.qml`. Manifest hỏng thì app đó bị bỏ qua, không làm hỏng cả danh sách.
- Hub chạy app bằng `Quickshell.execDetached([sumi, id, function])` rồi tự đóng để app nhận focus bàn phím.

## 10. Phiên bản
- **lib được vendor vào từng app** (`apps/<id>/lib/`, kèm file `VERSION`), vì Quickshell chỉ nhận import nằm trong thư mục chứa `shell.qml`. Repo app ghi `lib/` vào `.gitignore`. Hub cài hoặc cập nhật lib thì copy lại vào mọi app và kiểm tra `requires_lib`.
- lib dùng semver. Đổi breaking trong Object API hoặc App API thì tăng major.
- App khai báo `requires_lib`. Hub từ chối chạy app không khớp và báo `[INCOMPATIBLE]`.

## 11. Cài đặt trong hub (GĐ2b)
- **Một màn hình cho mỗi phạm vi** (từ 1.1; không còn tab/trang riêng): cột trái chọn phạm vi (`GLOBAL`, `HUB`, rồi từng app; `Q/E` hoặc chuột), cột giữa là danh sách hàng chia section **THEME** (6 preset, TINT, INK DARKEN) / **FONT** (5 vai trò) / **KEYS** / **OPTIONS** (gồm OBJECTS của từng function, rồi option khai trong manifest), cột phải là PREVIEW luôn bật + DETAIL của hàng đang chọn.
- Section nào không áp dụng cho phạm vi thì ẩn: GLOBAL = THEME + FONT; HUB = THEME (chỉ preset; tint/ink theo GLOBAL) + OPTIONS của hub; app = đủ 4 (KEYS chỉ khi app có `keybinds`, OPTIONS chỉ khi có option hoặc objects).
- Phím: `W/S` đi hàng (hết section thì sang section kế, vòng tròn), `A/D` chỉnh hàng (preset, tint ±0.02, ink ±0.1, option/object một nấc), `Enter` sửa (mở bộ chọn font, gán phím, ô nhập option), `Tab/Shift+Tab` hoặc `1..4` nhảy section, `Space` **áp dụng tất cả section đang có nháp trong MỘT lần ghi config**, `R` về mặc định hàng, `X` về mặc định cả section, `Esc` về. Từ trang APPS: `Tab`/`T` (theme), `F`, `K`, `O`/`J` (options) mở cài đặt của app đang chọn và focus đúng section.
- Một bản nháp chung cho cả phạm vi; đổi phạm vi thì bỏ nháp chưa áp dụng. Nháp mọi section được phản ánh ngay trong preview. Theme tương phản < 4.5 hoặc bất kỳ section nào không hợp lệ thì **không ghi gì cả**.
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
- **Hub, section OPTIONS** (hoặc `O` ở trang APPS): `W/S` chọn hàng, `A/D` chỉnh một nấc (bool/enum đổi giá trị; int bước ≈ khoảng/20 làm tròn lũy thừa 10; float bước ≈ khoảng/50, tối thiểu 0.01), `Enter` sửa (bool/enum đổi giá trị, còn lại mở ô nhập: `Enter` lưu nháp, `Esc` huỷ, giá trị sai thì ở lại ô nhập và báo lỗi), `R` về mặc định hàng, `X` về mặc định hết, `Space` apply (cùng luồng validate, backup, ghi atomic như các tab khác). Danh sách app lấy từ `sumi list --json` (trường `options`).
- **Cảnh báo chéo** (không chặn): `timer.defaultMinutes` không nằm trong `timer.presets` thì viền đỏ ở hàng defaultMinutes (khớp luật của `tools/validate.py`).
- **`protectedClasses`** (kakunin, `stringlist`, mặc định `["zen*","Minecraft*"]`): danh sách glob class cửa sổ mà `contrib/safe-close.sh` phải hỏi kakunin trước khi đóng. Script đọc `apps.kakunin.options.protectedClasses` bằng `jq` mỗi lần chạy:
  - chưa đặt / thiếu file / JSON hỏng / sai kiểu → dùng mặc định;
  - `[]` → không bảo vệ app nào;
  - mục sai định dạng bị bỏ qua (không bao giờ được diễn giải thành lệnh).
  - Chốt chặn một dialog: `pgrep -f -- '-p [^ ]*/apps/kakunin/shell\.qml'` (khớp cả `qs -p` lẫn `quickshell -p`).

## 11. OBJECTS (GĐ2b-4; từ 1.1 nằm chung section OPTIONS)
- `J` ở trang APPS (= mở OPTIONS). OBJECTS hiện ở đầu section OPTIONS của app, trước option khai trong manifest; ghi vào `apps.<id>.objects`, còn option ghi vào `apps.<id>.options` (một lần Apply tách đúng chỗ, giữ nguyên `grid`). Danh sách app lấy những app có function khai `objects` (từ `sumi list --json`: `functions[].objects`, `functions[].defaultObject`). Hub dùng lại giao diện và phím của tab OPTIONS với danh sách option "ảo" sinh từ manifest (`SumiConfigEdit.objectOptsOf`): khoá `<function>.id|speed|interactive`.
- Lưu: `config.apps.<id>.objects.<function> = {id, speed, interactive}`, chỉ phần khác mặc định (mặc định của id là `defaultObject`, `speed` là 1, `interactive` là true); function về mặc định hết thì entry bị xoá; `grid` và function lạ giữ nguyên.
- Tài liệu object: `docs/OBJECT_API.md`.

## 12. Preview trong hub (GĐ2b-5)
- Preview **luôn bật** (không còn phím `V`): khung 16:9 ở đầu cột phải của dashboard và của màn hình cài đặt. Chỉ một preview một lúc; scope `HUB` và trang Store không có preview. Lưu ý: object dither của jigen luôn xoay nên preview tốn CPU một chút khi hub đang mở.
- Hub nạp `Loader { source: "file://<dir>/View.qml" }` vào sân khấu 1920x1080 rồi thu nhỏ bằng `scale`, nên View (tính kích thước theo `min(w/1920, h/1080)`) trông giống hệt khi chạy thật. `import "lib"` trong View.qml trỏ tới lib đã vendored trong thư mục app (đây là lý do mọi app vendored lib).
- Hub gán thuộc tính cho View **chỉ khi View có thuộc tính đó** (`typeof item[k] !== "undefined"`), theo thứ tự: `bootMs`, `outroMs`, màu (`bgColor`, `fgColor`, `mutedColor`, `accentColor`, `dangerColor`), font 5 vai trò, `preset`, `tint`, `inkDarken`, `scanOpacity`, `scanlinesEnabled`, `glitchEnabled`, `scaleBoost`, `previewMode`, `closing`, `mode`, `objectCfg`, dữ liệu mẫu (`appName`, `appTitle`, `appWs`, `userName`, `standby`, `managing`), cuối cùng `active: true`. View mới nên dùng đúng các tên này.
- **Bản nháp được phản ánh ngay** ở màn hình cài đặt: theme (nháp của phạm vi đang sửa; sửa GLOBAL thì app có ghi đè riêng giữ nguyên theme riêng), font (tương tự), object. Trang APPS hiển thị cấu hình đã lưu.
- `mode` lấy từ `functions[].ipc_name` (hoặc `id`) của function đang xem: trang APPS theo `A/D`, màn hình cài đặt theo hàng OPTIONS đang chọn (tiền tố `<function>.`).
- Hợp đồng cho View: `previewMode: true` nghĩa là không nhận phím, không giữ focus, không Process/ghi file/thoát tiến trình (đã là quy tắc của View thuần); preview không nhận chuột.

## 13. Auto-revert và cài đặt HUB (GĐ2b-6)
- **Cài đặt hub** nằm ở section OPTIONS của phạm vi **HUB**, lưu ở `config.hub.<key>`, chỉ phần khác mặc định, giữ nguyên `hub.theme` và `hub.registryUrl`:
  `autoRevert` (bool, mặc định tắt), `autoRevertSec` (10/15/30, mặc định 15), `maxBackups` (5..100, mặc định 20; `sumi config` dùng để tỉa backup), `checkUpdateHours` (1..168, mặc định 6; `sumi store` dùng làm hạn cache registry).
- **Auto-revert**: khi `autoRevert` bật, sau mỗi Apply thành công hub hiện thanh đếm ngược (`KEEP THIS SETTING?  REVERTING IN n s`). `Enter`/`Space` giữ; `Esc`/`Backspace`/`Delete`, hết giờ, hoặc **đóng hub** thì hoàn tác. Các phím khác bị chặn trong lúc đếm.
- **Cách hoàn tác**: áp lại bản config ngay trước lần Apply đó (`revertSnapshot`: luôn có `version: 1` và `global`) qua chính `sumi config apply` (có backup như mọi lần ghi, kết quả hiện `REVERTED`). Không dựa vào stamp backup nên chạy cả khi trước đó chưa có config.json.
- Không đếm ngược khi: Apply lỗi, hoặc phạm vi HUB đang có nháp OPTIONS (để bật/tắt auto-revert không tự hoàn tác chính nó).
- Lưu ý: hoàn tác chỉ trả lại file config; bản nháp trên màn hình giữ nguyên để bạn chỉnh tiếp.

## 14. Cài đặt, cập nhật, gỡ lõi (GĐ4a)
- **Cài**: `git clone https://github.com/DasNiemand/sumi && cd sumi && bash install.sh` (có thể thêm `--apps kakunin,jigen [--yes]`). Không có `curl | sh`. `install.sh` copy `lib/`, `hub/` (kèm lib vendored) vào `~/.local/share/sumi/`, đặt `sumi`, `sumi-store`, `sumi-self`, `sumi-safe-close` vào `~/.local/bin/`, ghi `~/.local/share/sumi/install.json` (`version`, `sha`, `repo`, `lib`, `installed_at`). Không chạm `~/.config/sumi`, không sửa Hyprland/Noctalia. Từ chối cài khi hub hoặc app đang chạy. `--apps`: với mỗi id hiện nguồn, tag, SHA, lệnh shell rồi hỏi `y/N` (hoặc `--yes`; không có terminal và thiếu `--yes` thì bỏ qua), cài bằng đúng SHA đã hiện (`sumi store install --sha`).
- **Re-vendor lib**: mỗi lần cài/cập nhật lõi, lib mới chỉ được copy vào app khi thoả `requires_lib` của app; không thoả thì app giữ lib cũ và installer cảnh báo.
- **Phát hành lõi**: file `VERSION` ở gốc repo `sumi` (`X.Y.Z`) phải bằng tag annotated `vX.Y.Z` (`git tag -a vX.Y.Z`). Tag nhẹ bị bỏ qua.
- **`sumi version`**: in version đã cài. **`sumi update [--check] [--yes]`**: `git ls-remote` tìm tag annotated `vX.Y.Z` lớn nhất; `--check` chỉ báo (`--json`: `{installed, latest, tag, sha, available}`); `--yes` clone đúng tag vào thư mục tạm, kiểm `HEAD` = commit của tag, kiểm `VERSION` = tag, rồi chạy `install.sh --update` của bản đó. Từ chối khi hub/app đang chạy (mã 3), khi offline (6), khi kiểm tra thất bại (5). Bản cài bằng `install-dev.sh` (`version: "dev"`) không dùng `sumi update`. Cập nhật app đi qua `sumi store`.
- **`sumi uninstall [--yes] [--purge]`**: không `--yes` chỉ in kế hoạch (mã 2). Gỡ `~/.local/share/sumi` và 4 lệnh; **giữ** `~/.config/sumi` (config, backup) trừ khi `--purge`. Chỉ xoá thư mục tên `.../sumi`; không đụng file khác trong `~/.local/bin`. Phần SUMI không sửa nên không gỡ: user template Noctalia, bind Hyprland, cấu hình quickshell cũ.

## 15. CRT của hub và thông báo bản mới (GĐ4b)
- **Bật máy**: card của hub mở bằng `Scale` transform: đường kẻ ngang dài ra (0 → 28% tiến độ), mở theo chiều dọc (28% → 70%), nội dung rõ hẳn (55% → 100%), nhấp nháy nhẹ ở đầu. **Tắt máy** (`finish()`): co dọc rồi co ngang, nền tối mờ dần, glitch ở tiêu đề lúc đầu; xong mới `Qt.quit()`. Lúc đang tắt máy hub nhả focus bàn phím (`keyboardFocus: None`, để app vừa chạy nhận phím ngay) và nuốt phím. Mọi đường thoát của hub (Esc, bấm nền, chạy app, hoàn tác auto-revert) đều qua `finish()`.
- **Cấu hình**: OPTIONS > HUB: `crtBootMs` (0..3000, mặc định 600) và `crtOutroMs` (0..3000, mặc định 360); **0 = tắt hiệu ứng tương ứng** (hiện/đóng ngay). Scanline, độ đậm scanline và glitch theo look như các app: `scanlines`, `scanlineOpacity`, `glitch` (scope global trong config).
- **Thông báo bản mới**: 0,8 giây sau khi mở hub chạy nền `sumi update --check --json` rồi `sumi store registry --json`; có bản mới thì thanh trên của trang APPS hiện `UPDATE   SUMI v1.1.0  ·  2 APPS   (G)`. Offline, bản cài dev, hay lỗi thì im lặng. Số app được cập nhật lại khi vào tab Store.
- **Cache `sumi update --check`**: `~/.config/sumi/core-update-cache.json`, hạn `hub.checkUpdateHours` (mặc định 6 giờ); `--refresh` bỏ qua cache; offline mà còn cache thì dùng cache cũ (`stale: true`). `sumi update --yes` không dùng cache.
- Cài đặt HUB (mục 13) nay gồm 6 mục: `autoRevert`, `autoRevertSec`, `maxBackups`, `checkUpdateHours`, `crtBootMs`, `crtOutroMs`.

## 16. Tạo app mới và skill (GĐ4c)
- **`bash tools/new-app.sh <id> [--kind oneshot|daemon] [--name TÊN] [--kanji 漢字] [--desc "..."] [--out DIR]`** sinh khung `sumi-<id>` từ `templates/app/` (mặc định đặt cạnh repo `sumi` để `install-dev.sh` nhận ra). Id khớp `^[a-z][a-z0-9-]{1,31}$`; tên/kanji/mô tả không được chứa `"`, `\`, `&`, `|`. Không ghi đè thư mục đã có.
- Khung oneshot: dialog Enter = mã thoát 0, Esc hoặc bấm ra ngoài = mã 1, biến môi trường `<ID>_TEXT` và `SUMI_MONITOR`. Khung daemon: tiến trình nền, IPC `main()` mở thẻ và `reload()`, đóng thẻ không thoát tiến trình. Cả hai có IPC `reload()`, options CRT (`crtBootMs`, `crtOutroMs`, `acceptKeysDelayMs`), keybind `accept` và `cancel` (khoá), font title/label/data, namespace layer-shell `sumi-<id>`.
- `View.qml` của khung giữ đúng danh sách thuộc tính chuẩn mà preview của hub gán (mục 12), nên app mới preview được ngay.
- **Skill cho Claude**: `skills/sumi/SKILL.md` ghi quy ước làm việc (quyết định đã khoá, quy tắc code, cách kiểm chứng trong sandbox, quy trình phát hành, checklist). Cài vào Claude bằng cách thêm thư mục `skills/sumi` làm một skill.

## 17. Phát hành bằng một lệnh và `sumi doctor` (GĐ4d)
- **`bash tools/release.sh <thư mục repo> <X.Y.Z> [--message "..."] [--index DIR] [--no-pin] [--dry-run] [--yes] [--force]`** phát hành app (repo có `manifest.json`) hoặc lõi (repo có `VERSION` + `install.sh`). Kiểm tra trước: đang ở nhánh `main`, version mới lớn hơn hiện tại, tag chưa có (local và remote), kết nối được `origin`, manifest qua `validate.py`, repo `sumi-index` sạch (mặc định `../sumi-index`). Sau đó: sửa version, commit (**mọi thay đổi đang chờ vào chung commit**: xem danh sách và xác nhận, hoặc `--yes`), tag annotated, push `main`, push tag (thử lại 3 lần khi GitHub lỗi tạm), xác minh tag trên remote trỏ đúng commit, rồi (app) chạy `pin.sh` của `sumi-index`, kiểm `index.json` ghim đúng SHA, commit và push. Dừng ngay ở bước lỗi và in lệnh để làm tiếp; **không ghim** nếu xác minh remote sai. `--dry-run` chỉ kiểm tra và in kế hoạch.
- `pin.sh` nhận `SUMI_GIT_BASE` (mặc định `https://github.com`, chỉ đổi khi test).
- **`sumi doctor`** (mã thoát 1 nếu có `FAIL`): lõi (`install.json`, `jq/git/curl`, `quickshell` hoặc `qs`, `hyprctl`, `flock`, PATH, `sumi-store`/`sumi-self`), lib chung và lib trong hub, `colors.json` (đủ 7 màu), `config.json` (JSON hợp lệ, version 1), `installed.json`, từng app (manifest hợp lệ và khớp tên thư mục, có `View.qml`/`shell.qml`, lib vendored thoả `requires_lib`), thư mục tạm cũ, số bản sao lưu.
