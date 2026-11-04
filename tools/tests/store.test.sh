#!/usr/bin/env bash
# Test tích hợp cho `sumi store` bằng repo git giả trong thư mục tạm (không đụng mạng, không đụng ~/.local).
# Cần: bash, git, jq, flock. Dùng: bash tools/tests/store.test.sh
set -u
D="$(cd "$(dirname "$0")" && pwd)"
STORE="$D/../../bin/sumi-store"
SUMI="$D/../../bin/sumi"
T="$(mktemp -d)"
trap 'pkill -f -- "-p $T/home/apps" 2>/dev/null; rm -rf "$T"' EXIT

export HOME="$T/h" SUMI_HOME="$T/home" XDG_CONFIG_HOME="$T/cfg" SUMI_STORE_TEST=1
export SUMI_GIT_BASE="file://$T/git" SUMI_REGISTRY_URL="file://$T/reg/index.json"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$SUMI_HOME/lib" "$XDG_CONFIG_HOME/sumi" "$T/reg" "$T/git/o"
echo "1.2.0" >"$SUMI_HOME/lib/VERSION"; echo "// lib" >"$SUMI_HOME/lib/SumiTheme.qml"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; [ -n "${2:-}" ] && echo "      $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
S() { "$STORE" "$@"; }        # chạy, giữ stdout
J() { "$STORE" "$@" --json; } # chạy chế độ JSON

mkmanifest() {  # mkmanifest <id> <version> [jq-filter]
    jq -n --arg id "$1" --arg v "$2" '{id:$id,name:("App "+$id),kanji:"墨",description:"test",version:$v,kind:"oneshot",
        requires_lib:">=1.0 <2.0",config_version:1,run:"qs -p {dir}/shell.qml",ipc_target:("sumi-"+$id),
        functions:[{id:"main",label:"Main",objects:[]}],options:[],keybinds:[],fonts:[],
        requires:["definitely-not-installed-pkg"],shell_commands:["echo hi"]}' | jq "${3:-.}"
}

# mkrepo <id> <tag> <version> [jq-filter] [extra-shell-cmd] -> in SHA commit
mkrepo() {
    local id="$1" tag="$2" ver="$3" filt="${4:-.}" extra="${5:-:}" w="$T/work-$1"
    local bare="$T/git/o/sumi-$id.git"
    if [ ! -d "$bare" ]; then git init -q --bare "$bare"; fi
    rm -rf "$w"; mkdir -p "$w"; git -C "$w" init -q -b main
    mkmanifest "$id" "$ver" "$filt" >"$w/manifest.json"
    echo "// view $ver" >"$w/View.qml"; echo "// shell $ver" >"$w/shell.qml"
    (cd "$w" && eval "$extra")
    git -C "$w" add -A; git -C "$w" commit -q -m "v$ver"
    git -C "$w" tag -a "$tag" -m "$tag"
    git -C "$w" push -q "$bare" "main:refs/heads/main" "refs/tags/$tag" -f 2>/dev/null
    git -C "$w" rev-parse "$tag^{commit}"
}

writereg() {  # writereg <id:ref:sha> ...
    local apps='[]' x
    for x in "$@"; do
        IFS=: read -r id ref sha <<<"$x"
        apps="$(jq -c --arg id "$id" --arg ref "$ref" --arg sha "$sha" '. + [{id:$id,repo:("github.com/o/sumi-"+$id),ref:$ref,sha:$sha}]' <<<"$apps")"
    done
    jq -n --argjson a "$apps" '{version:1,apps:$a}' >"$T/reg/index.json"
    rm -f "$XDG_CONFIG_HOME/sumi/registry-cache.json"
}

code() { "$@" >/dev/null 2>&1; echo $?; }

# ---------- chuẩn bị ----------
SHA_A1="$(mkrepo alpha v1.0.0 1.0.0)"
SHA_B1="$(mkrepo beta v1.0.0 1.0.0)"
writereg "alpha:v1.0.0:$SHA_A1" "beta:v1.0.0:$SHA_B1"

# 1. registry
out="$(J registry)"
check "registry: 2 app, đều available" '[ "$(jq -r "[.apps[].state]|join(\",\")" <<<"$out")" = "available,available" ]' "$out"
check "registry: ghi cache" '[ -f "$XDG_CONFIG_HOME/sumi/registry-cache.json" ]'
rm -f "$T/reg/index.json"
out="$(J registry)"
check "registry: cache còn hạn -> không tải lại (file nguồn đã xoá vẫn OK)" '[ "$(jq -r .ok <<<"$out")" = true ] && [ "$(jq -r .stale <<<"$out")" = false ]' "$out"
out="$(J registry --refresh)"; c=$?
check "registry --refresh khi nguồn mất -> dùng cache cũ, stale=true" '[ "$(jq -r .stale <<<"$out")" = true ]' "$out"
writereg "alpha:v1.0.0:$SHA_A1" "beta:v1.0.0:$SHA_B1"

# 2. inspect
out="$(J inspect alpha)"
check "inspect: trường cơ bản" '[ "$(jq -r ".sha,.ref,.version,.name" <<<"$out" | tr "\n" " ")" = "$SHA_A1 v1.0.0 1.0.0 App alpha " ]' "$out"
check "inspect: shell_commands + requires thiếu" '[ "$(jq -r ".shell_commands[0]" <<<"$out")" = "echo hi" ] && [ "$(jq -r ".requires[0].name" <<<"$out")" = "definitely-not-installed-pkg" ]' "$out"
check "inspect: lib tương thích" '[ "$(jq -r .lib.compatible <<<"$out")" = true ]'
check "inspect: không để lại thư mục tạm" '[ -z "$(ls -A "$SUMI_HOME/.staging" 2>/dev/null)" ]'
check "inspect: không cài gì" '[ ! -e "$SUMI_HOME/apps/alpha" ]'
check "inspect (người đọc) chạy được" 'S inspect alpha | grep -q "App alpha"'

# 3. install
check "install: thiếu --sha -> 2" '[ "$(code S install alpha)" = 2 ]'
check "install: sha sai -> 5 registry_changed" 'out="$(J install alpha --sha 0000000000000000000000000000000000000000)"; [ "$(jq -r .code <<<"$out")" = registry_changed ]' "$out"
out="$(J install alpha --sha "$SHA_A1")"
check "install: ok" '[ "$(jq -r .ok <<<"$out")" = true ] && [ -f "$SUMI_HOME/apps/alpha/manifest.json" ]' "$out"
check "install: lib được vendored" '[ "$(cat "$SUMI_HOME/apps/alpha/lib/VERSION")" = 1.2.0 ]'
check "install: .git đã bỏ" '[ ! -e "$SUMI_HOME/apps/alpha/.git" ]'
check "install: installed.json có bản ghi" '[ "$(jq -r ".apps.alpha.sha" "$XDG_CONFIG_HOME/sumi/installed.json")" = "$SHA_A1" ]'
check "install: staging sạch" '[ -z "$(ls -A "$SUMI_HOME/.staging" 2>/dev/null)" ]'
check "install lần hai -> 7 already_installed" '[ "$(jq -r .code <<<"$(J install alpha --sha "$SHA_A1")")" = already_installed ]'
out="$(J registry)"
check "registry: alpha=installed, beta=available" '[ "$(jq -r "[.apps[].state]|join(\",\")" <<<"$out")" = "installed,available" ]' "$out"
out="$("$SUMI" list --json 2>/dev/null || true)"
echo '[]' >/dev/null

# 4. update
SHA_A2="$(mkrepo alpha v1.1.0 1.1.0)"
writereg "alpha:v1.1.0:$SHA_A2" "beta:v1.0.0:$SHA_B1"
out="$(J registry)"
check "registry: alpha=update" '[ "$(jq -r ".apps[0].state" <<<"$out")" = update ]' "$out"
# app đang chạy -> từ chối
bash -c 'sleep 30; true' -p "$SUMI_HOME/apps/alpha/shell.qml" &
RUNPID=$!; sleep 0.3
check "update khi app đang chạy -> 3" '[ "$(code S update alpha --sha "$SHA_A2")" = 3 ]'
check "remove khi app đang chạy -> 3" '[ "$(code S remove alpha)" = 3 ]'
kill $RUNPID 2>/dev/null; wait $RUNPID 2>/dev/null; sleep 0.2
out="$(J update alpha --sha "$SHA_A2")"
check "update: ok, lên 1.1.0" '[ "$(jq -r .version <<<"$out")" = 1.1.0 ] && [ "$(jq -r .version "$SUMI_HOME/apps/alpha/manifest.json")" = 1.1.0 ]' "$out"
check "update: bản cũ nằm trong backups/removed" '[ "$(ls "$XDG_CONFIG_HOME/sumi/backups/removed" | grep -c "^alpha-")" = 1 ]'
check "update: record mới" '[ "$(jq -r ".apps.alpha.sha" "$XDG_CONFIG_HOME/sumi/installed.json")" = "$SHA_A2" ]'
out="$(J update alpha --sha "$SHA_A2")"
check "update lại cùng bản -> noop" '[ "$(jq -r .noop <<<"$out")" = true ]' "$out"

# 5. restore (rollback)
out="$(J removed alpha)"
check "removed: liệt kê 1 bản v1.0.0" '[ "$(jq -r "length, .[0].version" <<<"$out" | tr "\n" " ")" = "1 1.0.0 " ]' "$out"
sleep 1
out="$(J restore alpha)"
check "restore: về 1.0.0" '[ "$(jq -r .version "$SUMI_HOME/apps/alpha/manifest.json")" = 1.0.0 ] && [ "$(jq -r .ok <<<"$out")" = true ]' "$out"
check "restore: record khôi phục (sha v1.0.0)" '[ "$(jq -r ".apps.alpha.sha" "$XDG_CONFIG_HOME/sumi/installed.json")" = "$SHA_A1" ]'
check "restore: bản 1.1.0 được giữ lại trong backups" '[ "$(ls "$XDG_CONFIG_HOME/sumi/backups/removed" | grep -c "^alpha-")" -ge 2 ]'

# 6. remove + restore sau khi gỡ
out="$(J remove alpha)"
check "remove: ok, thư mục mất, record mất" '[ ! -e "$SUMI_HOME/apps/alpha" ] && [ "$(jq -r ".apps|has(\"alpha\")" "$XDG_CONFIG_HOME/sumi/installed.json")" = false ]' "$out"
sleep 1
out="$(J restore alpha)"
check "restore sau remove: app quay lại, record quay lại" '[ -f "$SUMI_HOME/apps/alpha/manifest.json" ] && [ "$(jq -r ".apps|has(\"alpha\")" "$XDG_CONFIG_HOME/sumi/installed.json")" = true ]' "$out"
st="$(J removed alpha | jq -r '.[0].stamp')"; sleep 1
out="$(J restore alpha "$st")"
check "restore <id> <stamp> chỉ định rõ" '[ "$(jq -r .ok <<<"$out")" = true ] && [ "$(jq -r .restored <<<"$out")" = "$st" ]' "$out"
check "restore stamp sai -> usage 2" '[ "$(code S restore alpha not-a-stamp)" = 2 ]'
check "restore thừa đối số -> 2" '[ "$(code S restore alpha a b)" = 2 ]'
check "remove id không tồn tại -> 7" '[ "$(code S remove nope)" = 7 ]'

# 7. bản dev (không có record)
mkdir -p "$SUMI_HOME/apps/beta"; cp "$T/work-beta/manifest.json" "$SUMI_HOME/apps/beta/"
out="$(J registry)"
check "registry: beta=dev" '[ "$(jq -r ".apps[1].state" <<<"$out")" = dev ]' "$out"
check "install đè bản dev không --replace -> 7 dev_installed" '[ "$(jq -r .code <<<"$(J install beta --sha "$SHA_B1")")" = dev_installed ]'
check "remove bản dev không --force -> 7" '[ "$(code S remove beta)" = 7 ]'
out="$(J install beta --sha "$SHA_B1" --replace)"
check "install --replace: ok + backup bản dev" '[ "$(jq -r .ok <<<"$out")" = true ] && [ "$(jq -r .source "$SUMI_HOME/apps/beta/../../../cfg/sumi/backups/removed"/beta-*/.sumi-record.json)" = dev ]' "$out"

# 8. từ chối bản xấu
bad_case() {  # bad_case <mô tả> <id> <filter> <extra> <mã mong đợi>
    local sha out
    sha="$(mkrepo "$2" v1.0.0 1.0.0 "$3" "$4")"
    writereg "$2:v1.0.0:$sha"
    out="$(J install "$2" --sha "$sha")"; local c=$?
    check "$1 -> $5" "[ \"$c\" = \"$5\" ] && [ ! -e \"$SUMI_HOME/apps/$2\" ]" "code=$c $out"
}
bad_case "manifest run là lệnh lạ"            evil1 '.run="bash -c evil {dir}/shell.qml"' ':' 5
bad_case "manifest chứa .. trong chuỗi"        evil2 '.shell_commands=["cat ../../x"]' ':' 5
bad_case "thiếu View.qml"                      evil3 '.' 'rm View.qml' 5
bad_case "có symlink"                          evil4 '.' 'ln -s /etc/passwd link.qml' 5
bad_case "object khai báo nhưng thiếu file"    evil5 '.functions[0].objects=["Ghost"]' ':' 5
bad_case "ipc_target sai"                      evil6 '.ipc_target="clock-widget"' ':' 5
bad_case "lib không tương thích"               evil7 '.requires_lib=">=9.0"' ':' 4
check "lỗi không để rác trong staging" '[ -z "$(ls -A "$SUMI_HOME/.staging" 2>/dev/null)" ]'

# 9. SHA/tag bị giả mạo
sha="$(mkrepo tamper v1.0.0 1.0.0)"
writereg "tamper:v1.0.0:1111111111111111111111111111111111111111"
out="$(J install tamper --sha 1111111111111111111111111111111111111111)"; c=$?
check "registry ghim sha khác tag -> 5 tag_moved" '[ "$c" = 5 ] && [ "$(jq -r .code <<<"$out")" = tag_moved ]' "$out"
writereg "tamper:v9.9.9:$sha"
out="$(J install tamper --sha "$sha")"
check "tag không tồn tại -> tag_missing" '[ "$(jq -r .code <<<"$out")" = tag_missing ]' "$out"

# 10. index hỏng / offline
echo '{"version":1,"apps":[{"id":"x","repo":"github.com/o/sumi-x","ref":"v1.0.0","sha":"zz"}]}' >"$T/reg/index.json"; rm -f "$XDG_CONFIG_HOME/sumi/registry-cache.json"
check "index sai sha -> 5 registry_invalid" '[ "$(jq -r .code <<<"$(J registry)")" = registry_invalid ]'
rm -f "$T/reg/index.json" "$XDG_CONFIG_HOME/sumi/registry-cache.json"
check "offline không cache -> 6" '[ "$(code S registry)" = 6 ]'

# 11. sumi list thấy source
writereg "alpha:v1.0.0:$SHA_A1" "beta:v1.0.0:$SHA_B1"
mkdir -p "$SUMI_HOME/apps/alpha"   # (đã có sau restore)
check "sumi store qua launcher chạy được" 'cp "$SUMI" "$T/h/sumi" && cp "$STORE" "$T/h/sumi-store" && [ "$("$T/h/sumi" store registry --json | jq -r .ok)" = true ]'

# 12. URL registry không hợp lệ khi không ở chế độ test
check "registryUrl lạ bị từ chối ngoài chế độ test" '[ "$(SUMI_STORE_TEST=0 SUMI_REGISTRY_URL="https://evil.example/index.json" bash -c "\"$STORE\" registry --json | jq -r .code")" = registry_url ]'

echo "-----"; echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
