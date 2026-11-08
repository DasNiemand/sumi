# SUMI 墨

Hub launcher + store + settings cho các app Quickshell (NieR-style) trên Hyprland + Noctalia.

## Cài đặt

```
git clone https://github.com/DasNiemand/sumi && cd sumi && bash install.sh
bash install.sh --apps kakunin,jigen        # tuỳ chọn: cài luôn app từ registry (hiện SHA, tag, lệnh shell trước khi hỏi)
sumi hub                                    # G = cửa hàng app
```

Cần: Quickshell (`quickshell` hoặc `qs`), `jq`, `git`, `curl`; nên có Hyprland (`hyprctl`) và `flock`.
Cập nhật lõi: `sumi update --check` rồi `sumi update --yes`. Cập nhật app: trong hub bấm `G`, hoặc `sumi store`. Gỡ: `sumi uninstall` (không `--yes` chỉ in kế hoạch; `--purge` xoá cả cấu hình).

## Cấu trúc repo

```
docs/            hợp đồng (schema, CONVENTIONS, APP_API, OBJECT_API)
examples/        manifest, index, config mẫu
tools/           validate.py, tests/ (chạy: bash tools/tests/run.sh)
lib/             SumiTheme, SumiColors, SumiConfig, SumiConfigEdit, SumiStoreLogic, SumiKeyMap, ScrambleText
hub/             hub: toàn màn hình; dashboard APPS, settings gộp theo phạm vi (theme/font/keys/options+objects, preview luôn bật, auto-revert), store (phím G)
bin/sumi         sumi <app> [function] | hub | list | reset | config | store | version | update | uninstall | doctor
bin/sumi-store   backend của store (registry, inspect, install, update, remove, restore)
bin/sumi-self    cập nhật / gỡ lõi (version, update, uninstall)
contrib/         safe-close.sh (cài thành sumi-safe-close), clockwidget-run.sh (shim jigen)
skills/sumi      skill cho Claude (cách làm việc với SUMI: quy ước, kiểm chứng, phát hành)
templates/app    khung app mới; tạo bằng `bash tools/new-app.sh <id>`
install.sh       cài lõi từ bản clone; VERSION = version lõi (tag annotated vX.Y.Z phải khớp)
install-dev.sh   cài kiểu dev: copy lib + hub + app từ các repo cạnh nhau vào ~/.local/share/sumi
```

Phát hành: `bash tools/release.sh ../sumi-<id> X.Y.Z` (app) hoặc `bash tools/release.sh . X.Y.Z` (lõi); chẩn đoán: `sumi doctor`.
Kiểm tra hợp đồng: `python3 tools/validate.py all` (cần `jsonschema`).
Phát triển: `bash install-dev.sh ~/dev/sumi` (chạy lại sau mỗi lần sửa code), rồi `sumi hub`.
