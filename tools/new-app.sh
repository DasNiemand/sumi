#!/usr/bin/env bash
# Tạo khung một app SUMI mới theo chuẩn (repo sumi-<id>) từ templates/app/.
#
#   bash tools/new-app.sh <id> [--kind oneshot|daemon] [--name TÊN] [--kanji 漢字] [--desc "mô tả"] [--out THƯ_MỤC]
#
# Mặc định: kind oneshot, đặt repo mới cạnh repo sumi (cùng chỗ với sumi-kakunin, sumi-jigen) để install-dev.sh nhận ra.
# Khung có sẵn: manifest.json hợp lệ (options CRT, keybind accept/cancel, font), View.qml thuần (previewMode, bật/tắt máy CRT),
# shell.qml (layer-shell, config, IPC reload, exit code hoặc IPC hàm main), README, .gitignore (lib/ không commit).
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/app"
die() { echo "new-app: $*" >&2; exit 1; }

ID="${1:-}"; [ "$#" -gt 0 ] && shift
KIND=oneshot; NAME=""; KANJI=""; DESC=""; OUT="$(dirname "$ROOT")"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --kind) shift; KIND="${1:-}" ;;
        --name) shift; NAME="${1:-}" ;;
        --kanji) shift; KANJI="${1:-}" ;;
        --desc) shift; DESC="${1:-}" ;;
        --out) shift; OUT="${1:-}" ;;
        -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "tuỳ chọn không biết: $1" ;;
    esac
    shift || true
done

[[ "$ID" =~ ^[a-z][a-z0-9-]{1,31}$ ]] || die "id phải khớp ^[a-z][a-z0-9-]{1,31}$ (chữ thường, số, gạch ngang; 2-32 ký tự). Dùng: bash tools/new-app.sh <id>"
case "$KIND" in oneshot|daemon) ;; *) die "--kind phải là oneshot hoặc daemon" ;; esac
[ -n "$NAME" ] || NAME="$(printf '%s' "$ID" | tr 'a-z' 'A-Z')"
[ -n "$DESC" ] || DESC="Mô tả ngắn của app $ID (sửa trong manifest.json)."
# Các chuỗi này được chèn vào QML/README bằng thay thế văn bản: không cho ký tự có thể phá chuỗi.
for pair in "name:$NAME" "kanji:$KANJI" "desc:$DESC"; do
    v="${pair#*:}"
    case "$v" in *\"*|*\\*|*\&*|*\|*|*$'\n'*) die "--${pair%%:*} không được chứa dấu nháy kép, \\, &, | hoặc xuống dòng" ;; esac
done
[ "${#NAME}" -le 32 ] || die "--name tối đa 32 ký tự"
[ "${#KANJI}" -le 16 ] || die "--kanji tối đa 16 ký tự"
for f in View.qml shell.oneshot.qml shell.daemon.qml README.md gitignore; do [ -f "$TPL/$f" ] || die "thiếu $TPL/$f"; done
command -v jq >/dev/null 2>&1 || die "thiếu lệnh 'jq'"

DEST="$OUT/sumi-$ID"
[ ! -e "$DEST" ] || die "$DEST đã tồn tại, không ghi đè"
LIBV="$(tr -d '[:space:]' <"$ROOT/lib/VERSION" 2>/dev/null || true)"
[[ "$LIBV" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || die "không đọc được $ROOT/lib/VERSION"
REQLIB=">=${BASH_REMATCH[1]}.${BASH_REMATCH[2]} <$((BASH_REMATCH[1] + 1)).0"

ENVP="$(printf '%s' "$ID" | tr 'a-z-' 'A-Z_')"
FULL="$NAME"; [ -z "$KANJI" ] || FULL="$NAME $KANJI"
if [ "$KIND" = daemon ]; then RUNARG=" main"; RUNNOTE=" (tự khởi động tiến trình nền nếu chưa chạy, rồi gọi IPC \`main()\`)."; else RUNARG=""; RUNNOTE=". Thoát mã 0 = đồng ý, 1 = huỷ."; fi

fill() {  # fill <file mẫu> <file đích>
    local c; c="$(cat "$1")"
    c="${c//@ID@/$ID}"; c="${c//@NAME@/$NAME}"; c="${c//@KANJI@/$KANJI}"; c="${c//@DESC@/$DESC}"
    c="${c//@KIND@/$KIND}"; c="${c//@ENV@/$ENVP}"; c="${c//@IPC@/sumi-$ID}"; c="${c//@RUNARG@/$RUNARG}"; c="${c//@RUNNOTE@/$RUNNOTE}"
    printf '%s\n' "$c" >"$2"
}

mkdir -p "$DEST"
fill "$TPL/View.qml" "$DEST/View.qml"
fill "$TPL/shell.$KIND.qml" "$DEST/shell.qml"
fill "$TPL/README.md" "$DEST/README.md"
cp "$TPL/gitignore" "$DEST/.gitignore"
jq -n --arg id "$ID" --arg name "$FULL" --arg kanji "$KANJI" --arg desc "$DESC" --arg kind "$KIND" --arg lib "$REQLIB" '
  {id:$id, name:$name} + (if $kanji != "" then {kanji:$kanji} else {} end) + {
    description:$desc, version:"0.1.0", kind:$kind, requires_lib:$lib, config_version:1,
    run:"quickshell -p {dir}/shell.qml", ipc_target:("sumi-" + $id),
    functions:[{id:"main", label:"MAIN", objects:[]}],
    options:[
      {key:"acceptKeysDelayMs", type:"int", default:180, min:0, max:1000, label:"KEY GUARD MS"},
      {key:"crtBootMs", type:"int", default:800, min:0, max:3000, label:"CRT BOOT MS"},
      {key:"crtOutroMs", type:"int", default:460, min:0, max:3000, label:"CRT OUTRO MS"}],
    keybinds:[
      {action:"accept", default:"Return", label:"ACCEPT"},
      {action:"cancel", default:"Escape", label:"CANCEL", locked:true}],
    fonts:["title","label","data"], requires:[], shell_commands:[]}' >"$DEST/manifest.json"

git -C "$DEST" init -q -b main 2>/dev/null || true
echo "đã tạo $DEST ($KIND)"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1; then
    python3 "$ROOT/tools/validate.py" manifest "$DEST/manifest.json" >/dev/null || die "manifest sinh ra không qua validate.py (lỗi trong template?)"
    echo "manifest hợp lệ (validate.py)"
else
    echo "lưu ý: chưa có python3 + jsonschema nên chưa kiểm manifest bằng validate.py"
fi
cat <<X

Bước tiếp:
  cd $DEST
  bash $ROOT/install-dev.sh $OUT        # cài vào ~/.local/share/sumi (cùng các app khác trong $OUT)
  sumi $ID$RUNARG                       # thử chạy; sumi hub để chỉnh theme/font/phím/option
  sửa View.qml (giao diện) và shell.qml (hành động); thêm option/keybind vào manifest.json rồi chạy lại install-dev.sh
Phát hành: git add -A; git commit; git tag -a v0.1.0; push; ghim vào sumi-index (tools/pin.sh).
X
