#!/usr/bin/env bash
# Test tools/new-app.sh: file sinh ra, thay thế đủ, manifest hợp lệ, qua kiểm tra của sumi-store (inspect), từ chối đầu vào xấu.
# Cần: bash, git, jq. Tuỳ chọn: python3+jsonschema (validate.py), pyside6-qmllint.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$D/../.."; GEN="$ROOT/tools/new-app.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P=0; F=0; SK=0
ok() { P=$((P+1)); echo "ok    $1"; }
bad() { F=$((F+1)); echo "FAIL  $1  ${2:-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
HAVE_VAL=0; python3 -c 'import jsonschema' 2>/dev/null && HAVE_VAL=1
HAVE_LINT=0; command -v pyside6-qmllint >/dev/null 2>&1 && HAVE_LINT=1

# ---------- oneshot mặc định ----------
out="$(bash "$GEN" hello-box --out "$T" 2>&1)"; c=$?
check "oneshot: tạo được" '[ "$c" = 0 ] && [ -d "$T/sumi-hello-box" ]' "$out"
A="$T/sumi-hello-box"
check "oneshot: đủ file" '[ -f "$A/manifest.json" ] && [ -f "$A/View.qml" ] && [ -f "$A/shell.qml" ] && [ -f "$A/README.md" ] && [ "$(cat "$A/.gitignore")" = "lib/" ] && [ -d "$A/.git" ]'
check "oneshot: không còn @PLACEHOLDER@" '! grep -rqE "@[A-Z]+@" "$A" --exclude-dir=.git' "$(grep -rnE '@[A-Z]+@' "$A" --exclude-dir=.git | head -3)"
check "oneshot: manifest đúng các trường chuẩn" '[ "$(jq -r "[.id,.kind,.ipc_target,.version,.run] | join(\"|\")" "$A/manifest.json")" = "hello-box|oneshot|sumi-hello-box|0.1.0|quickshell -p {dir}/shell.qml" ]'
check "oneshot: requires_lib theo lib hiện có" '[ "$(jq -r .requires_lib "$A/manifest.json")" = ">=$(cut -d. -f1,2 "$ROOT/lib/VERSION") <$(( $(cut -d. -f1 "$ROOT/lib/VERSION") + 1 )).0" ]' "$(jq -r .requires_lib "$A/manifest.json")"
check "oneshot: cancel khoá, là Escape" '[ "$(jq -r ".keybinds[] | select(.action==\"cancel\") | [.default,.locked] | join(\"|\")" "$A/manifest.json")" = "Escape|true" ]'
check "oneshot: tên không kanji = chỉ tên, không có trường kanji" '[ "$(jq -r .name "$A/manifest.json")" = "HELLO-BOX" ] && [ "$(jq -r "has(\"kanji\")" "$A/manifest.json")" = false ]'
check "oneshot: shell có IPC reload đúng target + biến môi trường" 'grep -q "target: \"sumi-hello-box\"" "$A/shell.qml" && grep -q "function reload()" "$A/shell.qml" && grep -q "HELLO_BOX_TEXT" "$A/shell.qml"'
check "oneshot: exit code 0/1" 'grep -q "exitCode = accept ? 0 : 1" "$A/shell.qml" && grep -q "Qt.exit(root.exitCode)" "$A/shell.qml"'
check "oneshot: namespace layer-shell sumi-<id>" 'grep -q "WlrLayershell.namespace: \"sumi-hello-box\"" "$A/shell.qml"'
check "View thuần: không Process/FileView/Qt.quit/Qt.exit (bỏ qua chú thích)" '! sed "s#//.*##" "$A/View.qml" | grep -qE "Process|FileView|Qt\.quit|Qt\.exit|execDetached"'
check "View có thuộc tính chuẩn cho preview" 'for p in closing active previewMode mode bgColor fgColor accentColor dangerColor fontTitle fontLabel fontData preset tint inkDarken bootMs outroMs scanOpacity scanlinesEnabled glitchEnabled scaleU; do grep -qE "property \w+ $p:" "$A/View.qml" || { echo "thiếu $p"; exit 1; }; done'
check "View: previewMode chặn phím" 'grep -q "card.previewMode || !inputReady || closing" "$A/View.qml" && grep -q "focus: !card.previewMode" "$A/View.qml"'
if [ "$HAVE_VAL" = 1 ]; then check "oneshot: validate.py manifest" 'python3 "$ROOT/tools/validate.py" manifest "$A/manifest.json" >/dev/null'; else SK=$((SK+1)); echo "bỏ qua validate.py (thiếu jsonschema)"; fi
if [ "$HAVE_LINT" = 1 ]; then
    check "oneshot: qmllint không lỗi cú pháp" '! { pyside6-qmllint "$A/View.qml" "$A/shell.qml" 2>&1 | grep -E "^Error|syntax"; }'
else SK=$((SK+1)); echo "bỏ qua qmllint"; fi

# ---------- daemon + tên + kanji ----------
bash "$GEN" note-pad --kind daemon --name "NOTE PAD" --kanji 注 --desc "Ghi chú nhanh" --out "$T" >/dev/null 2>&1
B="$T/sumi-note-pad"
check "daemon: manifest" '[ "$(jq -r "[.kind,.name,.kanji,.description] | join(\"|\")" "$B/manifest.json")" = "daemon|NOTE PAD 注|注|Ghi chú nhanh" ]'
check "daemon: IPC main() + reload() đúng target, khớp function trong manifest" 'grep -q "target: \"sumi-note-pad\"" "$B/shell.qml" && grep -q "function main()" "$B/shell.qml" && grep -q "function reload()" "$B/shell.qml" && [ "$(jq -r ".functions[0].id" "$B/manifest.json")" = main ]'
check "daemon: không thoát tiến trình khi đóng thẻ" '! grep -q "Qt.exit" "$B/shell.qml" && grep -q "root.shown = false" "$B/shell.qml"'
check "daemon: View nhận active từ shell" 'grep -q "active: root.shown" "$B/shell.qml"'
check "daemon: README ghi cách chạy" 'grep -q "sumi note-pad main" "$B/README.md"'
check "tên có kanji hiện trong View/README" 'grep -q "NOTE PAD" "$B/View.qml" && grep -q "注" "$B/README.md"'
if [ "$HAVE_VAL" = 1 ]; then check "daemon: validate.py manifest" 'python3 "$ROOT/tools/validate.py" manifest "$B/manifest.json" >/dev/null'; fi
if [ "$HAVE_LINT" = 1 ]; then check "daemon: qmllint không lỗi cú pháp" '! { pyside6-qmllint "$B/View.qml" "$B/shell.qml" 2>&1 | grep -E "^Error|syntax"; }'; fi

# ---------- qua kiểm tra của sumi-store (clone repo giả, inspect) ----------
export HOME="$T/h" SUMI_HOME="$T/home/sumi" XDG_CONFIG_HOME="$T/cfg" SUMI_STORE_TEST=1 SUMI_GIT_BASE="file://$T/git" SUMI_REGISTRY_URL="file://$T/reg/index.json"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$SUMI_HOME" "$XDG_CONFIG_HOME/sumi" "$T/reg" "$T/git/o"
cp -r "$ROOT/lib" "$SUMI_HOME/lib"
for id in hello-box note-pad; do
    W="$T/sumi-$id"; bare="$T/git/o/sumi-$id.git"
    git init -q --bare -b main "$bare"
    git -C "$W" add -A; git -C "$W" commit -q -m v; git -C "$W" tag -a v0.1.0 -m v0.1.0
    git -C "$W" push -q "$bare" main:refs/heads/main refs/tags/v0.1.0 2>/dev/null
done
reg='[]'
for id in hello-box note-pad; do reg="$(jq -c --arg id "$id" --arg s "$(git -C "$T/sumi-$id" rev-parse 'v0.1.0^{commit}')" '. + [{id:$id,repo:("github.com/o/sumi-"+$id),ref:"v0.1.0",sha:$s}]' <<<"$reg")"; done
jq -n --argjson a "$reg" '{version:1,apps:$a}' >"$T/reg/index.json"
for id in hello-box note-pad; do
    out="$(bash "$ROOT/bin/sumi-store" inspect "$id" --json)"
    check "store inspect $id: hợp lệ, lib tương thích" '[ "$(jq -r .ok <<<"$out")" = true ] && [ "$(jq -r .lib.compatible <<<"$out")" = true ] && [ "$(jq -r ".warnings | length" <<<"$out")" = 0 ]' "$out"
done
out="$(bash "$ROOT/bin/sumi-store" install note-pad --sha "$(git -C "$T/sumi-note-pad" rev-parse 'v0.1.0^{commit}')" --json)"
check "store install app sinh ra: được, có lib vendored" '[ "$(jq -r .ok <<<"$out")" = true ] && [ -f "$SUMI_HOME/apps/note-pad/lib/VERSION" ] && [ -f "$SUMI_HOME/apps/note-pad/View.qml" ]' "$out"
out="$(bash "$ROOT/bin/sumi" list --json)"
check "sumi list thấy app sinh ra (kind daemon, function main)" '[ "$(jq -r ".[] | select(.id==\"note-pad\") | [.kind, .functions[0].id] | join(\"|\")" <<<"$out")" = "daemon|main" ]' "$out"

# ---------- đầu vào xấu ----------
check "id rỗng bị từ chối" '! bash "$GEN" --out "$T" >/dev/null 2>&1'
check "id viết hoa bị từ chối" '! bash "$GEN" Bad --out "$T" >/dev/null 2>&1 && [ ! -e "$T/sumi-Bad" ]'
check "id có ký tự lạ bị từ chối" '! bash "$GEN" "a;rm" --out "$T" >/dev/null 2>&1 && ! bash "$GEN" "../x" --out "$T" >/dev/null 2>&1'
check "id quá ngắn bị từ chối" '! bash "$GEN" a --out "$T" >/dev/null 2>&1'
check "kind lạ bị từ chối" '! bash "$GEN" okid --kind service --out "$T" >/dev/null 2>&1 && [ ! -e "$T/sumi-okid" ]'
check "không ghi đè thư mục đã có" 'echo giữ >"$A/mark" && ! bash "$GEN" hello-box --out "$T" >/dev/null 2>&1 && [ "$(cat "$A/mark")" = giữ ]'
check "tên có dấu nháy kép bị từ chối" '! bash "$GEN" okid --name "A\"B" --out "$T" >/dev/null 2>&1 && [ ! -e "$T/sumi-okid" ]'
check "tên có & hoặc | hoặc \\ bị từ chối" '! bash "$GEN" okid --name "A&B" --out "$T" >/dev/null 2>&1 && ! bash "$GEN" okid --kanji "a|b" --out "$T" >/dev/null 2>&1 && ! bash "$GEN" okid --desc "x\\y" --out "$T" >/dev/null 2>&1'
check "tên quá dài bị từ chối" '! bash "$GEN" okid --name "$(printf "x%.0s" {1..40})" --out "$T" >/dev/null 2>&1'

echo "-----"; echo "pass=$P fail=$F skip=$SK"; [ "$F" -eq 0 ]
