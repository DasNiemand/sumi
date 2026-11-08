---
name: sumi
description: Làm việc với hệ thống SUMI 墨 (hub + store + settings cho app Quickshell phong cách NieR trên Hyprland + Noctalia): tạo app mới theo chuẩn, sửa hub/lib/app, phát hành, viết test. Dùng khi người dùng nhắc SUMI, kakunin, jigen, sumi-index, hub, store, manifest, hoặc muốn làm một app Quickshell mới theo cùng phong cách.
---

# SUMI 墨: cách làm việc

## Bối cảnh
- Người dùng `arzur` (GitHub `DasNiemand`). Nhắn tiếng Việt **không dấu**; trả lời cũng không dấu. Dùng **fish shell**: mọi lệnh đưa cho họ phải là cú pháp fish (`set x (cmd)`, `; and`, `; or`, đặt `'v1.0.0^{commit}'` trong nháy, không dùng `<...>` làm chỗ giữ chỗ vì fish hiểu là chuyển hướng). Hyprland + Noctalia + Quickshell (`quickshell` và `qs`), có `jq`, không có `node`.
- Repo (public, cạnh nhau ở `~/dev/sumi`): `sumi` (lõi: hub, lib, bin, docs, tools), `sumi-index` (registry `index.json`), và mỗi app một repo `sumi-<id>` (`sumi-kakunin`, `sumi-jigen`).
- Hợp đồng chi tiết nằm trong `sumi/docs/` (`CONVENTIONS.md`, `APP_API.md`, `OBJECT_API.md`, các schema). **Đọc docs trước khi sửa, đừng dựa vào trí nhớ.**

## Quyết định đã khóa (không hỏi lại)
- Tên: hub **SUMI**, registry **sumi-index**, app **kakunin**, **jigen**. Cài app qua `git clone` từ GitHub của người dùng, **ghim tag + SHA commit**, không script post-install, không nguồn ngoài registry, không `curl | sh`.
- Màu chỉ derive từ palette Noctalia qua `SumiTheme`, không hex tùy ý; `danger` cố định `#E63946`. Preset theme: `paper, ink, mono-white, mono-black, accent, follow`. Tương phản ink/paper: chặn Apply nếu < 4.5, cảnh báo nếu < 7.
- Font theo 5 vai trò `title, label, data, numeral, kanji`.
- Hub từ chối cập nhật/xóa/reset app đang chạy. Keybind chỉ là phím trong app, không sinh bind Hyprland. Mỗi lần chỉ một preview, **luôn bật** (không có phím bật/tắt).
- Ngoài phạm vi: hex tùy ý, post-install, thay launcher hệ thống, nhiều preview cùng lúc.

## Làm app mới
1. `bash tools/new-app.sh <id> [--kind oneshot|daemon] [--name TÊN] [--kanji 漢字] [--desc "..."]` (trong repo `sumi`). Sinh `../sumi-<id>/` gồm `manifest.json` hợp lệ, `View.qml`, `shell.qml`, `README.md`, `.gitignore` (`lib/`), đã `git init`.
2. Thêm giao diện vào `View.qml`, hành động thật vào `shell.qml`; thêm `options`/`keybinds`/`functions` vào manifest (theo `docs/manifest.schema.json`; `python3 tools/validate.py manifest <file>`).
3. `bash install-dev.sh ~/dev/sumi` (chạy lại sau mỗi lần sửa), `sumi <id>`, `sumi hub`.
4. Phát hành bằng `bash tools/release.sh ../sumi-<id> X.Y.Z` (sửa version, commit, tag **annotated**, push, xác minh remote, ghim `sumi-index`; thêm `--dry-run` để xem trước, `--yes` khi có thay đổi chờ). Lõi: `bash tools/release.sh . X.Y.Z` (sửa `VERSION`).

## Quy tắc code (đều có test hoặc kiểm tra ở store)
- **Quickshell chỉ nhận type trong thư mục chứa `shell.qml`**: không `import "../../lib"`. lib được **vendored** vào từng app (`apps/<id>/lib/`) và hub; app dùng `import "lib"`; `lib/` không commit. File con ở `objects/` import bằng `import "objects"`.
- `View.qml` là giao diện **thuần**: không `Process`, không ghi file, không `Qt.quit/exit`; nhận `previewMode`; hành động ra qua signal. `shell.qml` giữ hành động thật. Giữ nguyên tên thuộc tính "chuẩn" (`closing, active, previewMode, mode, bgColor, fgColor, accentColor, dangerColor, fontTitle/Label/Data, preset, tint, inkDarken, bootMs, outroMs, scanOpacity, scanlinesEnabled, glitchEnabled, scaleU`) để preview trong hub gán được.
- **Phạm vi trong QML**: `PathLine` bên trong `ShapePath` không thấy property tự khai báo của `ShapePath`; đặt `id` và viết `<id>.<prop>` (nếu không toạ độ thành NaN và hình bị vẽ sai, `qmllint` chỉ báo "unqualified"). Có `tools/tests/shape.test.js`. Nhớ: `qmllint` không bắt được lỗi runtime kiểu này, nên giao diện mới luôn cần người dùng nhìn trên máy.
- Config đọc qua `SumiConfig` (`look`, `option`, `font`, `keyFor`); lỗi thì dùng mặc định, app không bao giờ không mở được. `cancel` luôn là Escape và khóa. Option có kiểu `bool,int,float,enum,intlist,string,stringlist` (xem CONVENTIONS mục 10).
- `run` trong manifest chỉ được là `qs -p {dir}/shell.qml` hoặc `quickshell -p {dir}/shell.qml` (store chặn mọi thứ khác). Không symlink, tối đa 5 MiB và 300 file.
- App chạy độc lập, không đòi hub, không đụng mạng. Daemon không bao giờ để reload làm hỏng trạng thái đang chạy.
- Giữ nguyên namespace layer-shell cũ (`clock-widget`, `clock-widget-confirm`, `confirm-close`) cho kakunin/jigen vì `layerrule` Hyprland của người dùng có thể khớp; app mới dùng `sumi-<id>`.
- Mọi đường thoát của hub qua `finish()`; thao tác ghi config qua `sumi config apply` (validate, backup, ghi atomic, khóa `sumi.lock`).

## Cách làm việc với người dùng
- **Mình không chạy được Quickshell trong sandbox.** Kiểm chứng bằng: `pyside6-qmllint` (cú pháp QML), script Node trích **hàm/property thật** từ QML rồi chạy với root giả (`tools/tests/*.test.js`), test bash với `quickshell/qs/hyprctl/git` giả hoặc repo git giả qua `file://` (`SUMI_STORE_TEST=1`, `SUMI_GIT_BASE`), `tools/validate.py`. Phần giao diện và runtime Quickshell/Hyprland bắt buộc người dùng thử trên máy; **nói rõ điểm chưa kiểm chứng**, không bao giờ khẳng định đã thử UI.
- Sau khi viết test, **đổi code có chủ ý (mutation) để chắc test bắt được lỗi**; test pass ngay lần đầu thì nghi ngờ.
- Giao theo từng đợt nhỏ: một zip chỉ gồm file đổi hoặc mới (người dùng giải nén vào `~/dev/sumi`), kèm lệnh fish chính xác để thử và để commit/tag/push, nêu điểm chưa kiểm chứng, rồi họ báo kết quả hoặc dán log. Không hỏi lại quyết định đã khóa. Chạy `bash tools/tests/run.sh` trước khi giao.
- Cẩn thận với `pgrep -f`: dòng lệnh của tiến trình bao ngoài (kể cả lệnh sandbox chứa nguyên script) có thể khớp pattern và làm test sai. Tạo file test ở một bước, chạy ở bước khác. `bash -c 'sleep 4'` tự `exec` mất đối số, dùng `'sleep 4; true'`. Lệnh bash dùng `<(...)` không chạy trong `/bin/sh` của sandbox, gọi qua `bash -c`. Sandbox cần `export PATH=/home/claude/bin:$PATH` để có `jq`.
- GitHub: tag annotated bắt buộc (tag nhẹ bị `pin.sh` và `sumi update` bỏ qua). Lỗi `Internal Server Error` khi push tag là tạm thời, chạy lại. Lỗi 403 `Permission denied to DasNiemand` thường là token fine-grained hết hạn: `gh auth logout; gh auth login`, `gh auth setup-git`.
- Khi người dùng gặp trục trặc: `sumi doctor` (mã thoát 1 nếu có `FAIL`) cho biết thiếu lib vendored, lib lệch, config hỏng, v.v.
- Phát hành lõi: `VERSION` ở gốc repo `sumi` phải bằng tag `vX.Y.Z`; người dùng cập nhật bằng `sumi update --yes`. Cài mới bằng `git clone ... && bash install.sh`.

## Checklist trước khi giao một app/tính năng
- [ ] `python3 tools/validate.py all` và `bash tools/tests/run.sh` đều xanh.
- [ ] `pyside6-qmllint` không có `Error`/lỗi cú pháp trên mọi QML mới.
- [ ] Manifest mới qua `sumi-store inspect` (không `warnings` bất thường) khi đặt vào repo git giả.
- [ ] Hub (nếu đổi): preview, auto-revert, màn hình cài đặt gộp (section/hàng/apply) vẫn có test; phím mới không trùng phím cũ; footer không dài quá ~100 ký tự.
- [ ] Tài liệu (`docs/CONVENTIONS.md`) và `README` cập nhật; version của app/lõi được tăng đúng; nhắc người dùng commit, tag annotated, ghim index.
