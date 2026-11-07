# sumi-@ID@ @KANJI@

@DESC@

- Loại: **@KIND@** (xem `docs/APP_API.md` của repo `sumi`).
- Chạy: `sumi @ID@@RUNARG@`@RUNNOTE@
- Cấu hình ở `~/.config/sumi/config.json` (`apps.@ID@`), màu ở `~/.config/sumi/colors.json`; chỉnh trong hub (`sumi hub`: THEME, FONT, KEYS, OPTIONS).
- `View.qml` là giao diện thuần (không Process, không ghi file, không thoát tiến trình); `shell.qml` nối signal với hành động thật.

## Phát triển

```
bash ../sumi/install-dev.sh ~/dev/sumi     # copy app + lib vendored vào ~/.local/share/sumi (chạy lại sau mỗi lần sửa)
python3 ../sumi/tools/validate.py manifest manifest.json
```

Phát hành: sửa `version` trong `manifest.json`, commit, `git tag -a vX.Y.Z -m vX.Y.Z`, push tag, rồi ghim vào registry
(`bash tools/pin.sh @ID@ vX.Y.Z` trong repo `sumi-index`).
