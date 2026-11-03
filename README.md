# SUMI 墨

Hub launcher + store + settings cho các app Quickshell (NieR-style) trên Hyprland + Noctalia.

```
docs/            hợp đồng (schema, CONVENTIONS, APP_API, OBJECT_API)
examples/        manifest, index, config mẫu (jigen là bản mẫu cho tới GĐ1b)
tools/           validate.py
lib/             SumiTheme, SumiColors, SumiConfig, SumiKeyMap, ScrambleText
bin/sumi         launcher: sumi <app> [function] | reset | doctor
install-dev.sh   cài kiểu dev: copy lib + app từ các repo cạnh nhau vào ~/.local/share/sumi
```

Kiểm tra hợp đồng: `python3 tools/validate.py all` (cần `jsonschema`).
Cài để thử: `bash install-dev.sh ~/dev/sumi`.
