# SUMI 墨

Hub launcher + store + settings cho các app Quickshell (NieR-style) trên Hyprland + Noctalia.

```
docs/            hợp đồng (schema, CONVENTIONS, APP_API, OBJECT_API)
examples/        manifest, index, config mẫu
tools/           validate.py, tests/ (theme/edit/prefs/store)
lib/             SumiTheme, SumiColors, SumiConfig, SumiConfigEdit, SumiStoreLogic, SumiKeyMap, ScrambleText
hub/             hub: launcher, settings (theme/font/keys/options), store (phím G)
bin/sumi         sumi <app> [function] | hub | list [--json] | reset | config | store | doctor
bin/sumi-store   backend của store (registry, inspect, install, update, remove, restore)
contrib/         script tích hợp: safe-close.sh (kakunin), clockwidget-run.sh (shim jigen)
install-dev.sh   cài kiểu dev: copy lib + hub + app từ các repo cạnh nhau vào ~/.local/share/sumi
```

Kiểm tra hợp đồng: `python3 tools/validate.py all` (cần `jsonschema`).
Cài để thử: `bash install-dev.sh ~/dev/sumi`, rồi `sumi hub`.
