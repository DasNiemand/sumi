#!/usr/bin/env bash
# Test `sumi doctor`: máy khoẻ báo sạch; từng lỗi/cảnh báo được phát hiện đúng chỗ và mã thoát phản ánh lỗi. Cần: bash, jq.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$D/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/h" SUMI_HOME="$T/home/sumi" XDG_CONFIG_HOME="$T/cfg"
CFG="$XDG_CONFIG_HOME/sumi"; BIN="$T/bin"
mkdir -p "$HOME" "$BIN" "$T/stub" "$CFG"
for b in sumi sumi-store sumi-self; do cp "$ROOT/bin/$b" "$BIN/$b"; done
JQ="$(command -v jq)"; ln -s "$JQ" "$T/stub/jq"
for c in git curl flock hyprctl qs; do printf '#!/bin/sh\nexit 0\n' >"$T/stub/$c"; chmod +x "$T/stub/$c"; done
# PATH chỉ gồm các lệnh doctor thật sự cần, để việc "xoá một lệnh" không bị lệnh thật trong /usr/bin che mất
for c in bash cat tr find wc dirname readlink basename sed awk grep head date env sort cut; do p="$(command -v "$c")" && ln -sf "$p" "$T/stub/$c"; done
P=0; F=0
ok() { P=$((P+1)); echo "ok    $1"; }
bad() { F=$((F+1)); echo "FAIL  $1  ${2:-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
DOC() { PATH="$BIN:$T/stub" bash "$BIN/sumi" doctor 2>&1; }
mkhealthy() {
    rm -rf "$SUMI_HOME" "$CFG"; mkdir -p "$SUMI_HOME/lib" "$SUMI_HOME/hub/lib" "$SUMI_HOME/apps/foo/lib" "$CFG"
    echo 1.3.0 >"$SUMI_HOME/lib/VERSION"; echo 1.3.0 >"$SUMI_HOME/hub/lib/VERSION"; echo 1.3.0 >"$SUMI_HOME/apps/foo/lib/VERSION"
    echo "// h" >"$SUMI_HOME/hub/shell.qml"; echo "// v" >"$SUMI_HOME/apps/foo/View.qml"; echo "// s" >"$SUMI_HOME/apps/foo/shell.qml"
    jq -n '{id:"foo",version:"1.0.0",kind:"oneshot",requires_lib:">=1.0 <2.0",run:"qs -p {dir}/shell.qml"}' >"$SUMI_HOME/apps/foo/manifest.json"
    echo '{"version":"1.0.0","lib":"1.3.0"}' >"$SUMI_HOME/install.json"
    jq -n '{primary:"#111111",on_primary:"#eeeeee",surface:"#101010",on_surface:"#cccccc",surface_variant:"#222222",on_surface_variant:"#aaaaaa",outline:"#555555"}' >"$CFG/colors.json"
    echo '{"version":1,"global":{}}' >"$CFG/config.json"
}

mkhealthy
out="$(DOC)"; c=$?
check "máy khoẻ: mã 0, 0 lỗi" '[ "$c" = 0 ] && grep -q "^0 lỗi" <<<"$out" && ! grep -q "^FAIL" <<<"$out"' "$out"
check "máy khoẻ: liệt kê app + lib" 'grep -q "^ok    app foo 1.0.0 (oneshot) lib 1.3.0" <<<"$out" && grep -q "ok    hub (lib 1.3.0)" <<<"$out"'
check "máy khoẻ: nhận quickshell qua qs" 'grep -q "ok    quickshell (qs)" <<<"$out"'

t() {  # t <mô tả> <lệnh sửa> <regex phải có> <mã mong đợi 0|1>
    mkhealthy; eval "$2"; out="$(DOC)"; local c=$?
    if grep -qE "$3" <<<"$out" && [ "$c" = "$4" ]; then ok "$1"; else bad "$1" "mã=$c / mong $4 / $(grep -E '^(FAIL|warn)' <<<"$out" | head -3 | tr '\n' '|')"; fi
}
t "app thiếu lib vendored -> FAIL"             'rm -rf "$SUMI_HOME/apps/foo/lib"'                              '^FAIL  app foo: thiếu lib vendored' 1
t "lib của app không thoả requires_lib -> FAIL" 'echo 2.1.0 >"$SUMI_HOME/apps/foo/lib/VERSION"'                  "^FAIL  app foo: cần lib '>=1.0 <2.0' nhưng lib trong app là 2.1.0" 1
t "app thiếu View.qml -> FAIL"                  'rm "$SUMI_HOME/apps/foo/View.qml"'                             '^FAIL  app foo: thiếu View.qml' 1
t "manifest app hỏng -> FAIL"                   'echo "{ không json" >"$SUMI_HOME/apps/foo/manifest.json"'     '^FAIL  app foo: manifest.json thiếu hoặc không hợp lệ' 1
t "manifest ghi id khác thư mục -> FAIL"        'jq ".id=\"bar\"" "$SUMI_HOME/apps/foo/manifest.json" >"$T/m" && mv "$T/m" "$SUMI_HOME/apps/foo/manifest.json"' "^FAIL  app foo: manifest ghi id 'bar'" 1
t "config.json hỏng -> FAIL"                    'echo "{ hỏng" >"$CFG/config.json"'                             '^FAIL  config.json hỏng' 1
t "config.json sai version -> warn, không lỗi"  'echo "{\"version\":2}" >"$CFG/config.json"'                    '^warn  config.json có version khác 1' 0
t "installed.json hỏng -> FAIL"                 'echo "[]" >"$CFG/installed.json"'                              '^FAIL  installed.json hỏng' 1
t "installed.json tốt -> ok"                    'echo "{\"version\":1,\"apps\":{}}" >"$CFG/installed.json"'     '^ok    installed.json' 0
t "colors.json thiếu màu -> warn"               'jq "del(.outline,.primary)" "$CFG/colors.json" >"$T/c" && mv "$T/c" "$CFG/colors.json"' '^warn  colors.json thiếu màu: .*outline.*primary|^warn  colors.json thiếu màu: .*primary.*outline' 0
t "colors.json không phải object -> FAIL"       'echo "[1]" >"$CFG/colors.json"'                                '^FAIL  colors.json không phải JSON object' 1
t "chưa có colors.json -> warn"                 'rm "$CFG/colors.json"'                                         '^warn  chưa có colors.json' 0
t "hub lib khác lib chung -> warn"              'echo 1.2.0 >"$SUMI_HOME/hub/lib/VERSION"'                      '^warn  lib trong hub \(1.2.0\) khác lib chung \(1.3.0\)' 0
t "hub thiếu lib -> FAIL"                       'rm -rf "$SUMI_HOME/hub/lib"'                                   '^FAIL  hub thiếu lib vendored' 1
t "thiếu lib chung -> FAIL"                     'rm -rf "$SUMI_HOME/lib"'                                       '^FAIL  thiếu lib' 1
t "thư mục tạm cũ -> warn"                      'mkdir -p "$SUMI_HOME/.staging/x.123"'                          '^warn  1 thư mục tạm' 0
t "chưa cài app nào -> ok"                      'rm -rf "$SUMI_HOME/apps/foo"'                                  '^ok    chưa cài app nào' 0
t "thiếu install.json -> warn"                  'rm "$SUMI_HOME/install.json"'                                  '^warn  chưa có install.json' 0
# môi trường
mkhealthy; rm "$T/stub/qs"; out="$(DOC)"; c=$?
check "thiếu cả quickshell và qs -> FAIL" '[ "$c" = 1 ] && grep -q "^FAIL  thiếu quickshell" <<<"$out"' "$out"
printf '#!/bin/sh\nexit 0\n' >"$T/stub/quickshell"; chmod +x "$T/stub/quickshell"; out="$(DOC)"
check "chỉ có quickshell -> ok" 'grep -q "ok    quickshell (quickshell)" <<<"$out"'
rm "$T/stub/hyprctl" "$T/stub/flock"; out="$(DOC)"; c=$?
check "thiếu hyprctl/flock -> chỉ cảnh báo" '[ "$c" = 0 ] && grep -q "^warn  thiếu hyprctl" <<<"$out" && grep -q "^warn  thiếu flock" <<<"$out"' "$out"
rm "$T/stub/git"; out="$(DOC)"; c=$?
check "thiếu git -> FAIL" '[ "$c" = 1 ] && grep -q "^FAIL  thiếu git" <<<"$out"' "$out"
rm "$BIN/sumi-self"; out="$(DOC)"
check "thiếu sumi-self -> FAIL" 'grep -q "^FAIL  thiếu .*sumi-self" <<<"$out"' "$out"

echo "-----"; echo "pass=$P fail=$F"; [ "$F" -eq 0 ]
