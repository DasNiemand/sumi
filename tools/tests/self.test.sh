#!/usr/bin/env bash
# Test install.sh + sumi-self (update/uninstall/version) bằng repo git giả (không mạng, không đụng ~/.local). Cần: bash, git, jq.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$D/../.."
T="$(mktemp -d)"
trap 'pkill -f -- "-p $T/home" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/h" SUMI_HOME="$T/home/sumi" XDG_CONFIG_HOME="$T/cfg" SUMI_BIN_DIR="$T/bin" SUMI_STORE_TEST=1 SUMI_GIT_BASE="file://$T/git"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$T/stub" "$T/git/DasNiemand" "$T/git/o"
printf '#!/bin/sh\nexit 0\n' >"$T/stub/qs"; chmod +x "$T/stub/qs"
export PATH="$T/stub:$T/bin:$PATH"
BARE="$T/git/DasNiemand/sumi.git"; git init -q --bare -b main "$BARE"
P=0; F=0
ok() { P=$((P+1)); echo "ok    $1"; }
bad() { F=$((F+1)); echo "FAIL  $1  ${2:-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
code() { "$@" >/dev/null 2>&1; echo $?; }
S() { "$T/bin/sumi" "$@"; }

# mkcore <version> [lệnh sửa trong thư mục work] [tag-name]
mkcore() {
    local ver="$1" mod="${2:-:}" tag="${3:-v$1}" w="$T/work-core"
    rm -rf "$w"; mkdir -p "$w"
    cp -r "$ROOT/bin" "$ROOT/hub" "$ROOT/lib" "$ROOT/contrib" "$ROOT/install.sh" "$w/"
    echo "$ver" >"$w/VERSION"
    (cd "$w" && eval "$mod")
    git -C "$w" init -q -b main; git -C "$w" add -A; git -C "$w" commit -q -m "v$ver"
    git -C "$w" tag -a "$tag" -m "$tag"
    git -C "$w" push -q "$BARE" main:refs/heads/main "refs/tags/$tag" -f 2>/dev/null
    git -C "$w" rev-parse "$tag^{commit}"
}

# ---------- 1. cài mới từ bản clone ----------
SHA1="$(mkcore 1.0.0)"
git clone -q "$BARE" "$T/clone" 2>/dev/null
out="$(bash "$T/clone/install.sh" 2>&1)"; c=$?
check "install.sh chạy được" '[ "$c" = 0 ]' "$out"
check "cài: lệnh + hub + lib" '[ -x "$T/bin/sumi" ] && [ -x "$T/bin/sumi-store" ] && [ -x "$T/bin/sumi-self" ] && [ -x "$T/bin/sumi-safe-close" ] && [ -f "$SUMI_HOME/hub/shell.qml" ] && [ -f "$SUMI_HOME/lib/VERSION" ]'
check "cài: hub có lib vendored" '[ -f "$SUMI_HOME/hub/lib/VERSION" ] && cmp -s "$SUMI_HOME/hub/lib/VERSION" "$SUMI_HOME/lib/VERSION"'
check "cài: install.json" '[ "$(jq -r .version "$SUMI_HOME/install.json")" = 1.0.0 ] && [ "$(jq -r .sha "$SUMI_HOME/install.json")" = "$SHA1" ] && [ "$(jq -r .repo "$SUMI_HOME/install.json")" = github.com/DasNiemand/sumi ]' "$(cat "$SUMI_HOME/install.json")"
check "cài: không tạo config" '[ ! -e "$XDG_CONFIG_HOME/sumi/config.json" ]'
check "cài: không có .git trong hub" '[ ! -e "$SUMI_HOME/hub/.git" ]'
check "cài: không để rác tạm" '[ -z "$(ls -A "$SUMI_HOME" | grep -E "\.new\.|\.old\.|^\.hub\.")" ]'
check "sumi version" 'S version | grep -q "SUMI 1.0.0"' "$(S version 2>&1)"
check "sumi version --json" '[ "$(S version --json | jq -r .version)" = 1.0.0 ]'
check "doctor in version lõi" 'S doctor 2>&1 | grep -q "SUMI 1.0.0"'

# ---------- 2. kiểm tra bản mới ----------
out="$(S update --check --refresh --json)"
check "update --check: đã mới nhất" '[ "$(jq -r .available <<<"$out")" = false ] && [ "$(jq -r .latest <<<"$out")" = 1.0.0 ]' "$out"
# thêm app có lib vendored để thử re-vendor
mkapp() { mkdir -p "$SUMI_HOME/apps/$1/lib"; echo "1.3.0" >"$SUMI_HOME/apps/$1/lib/VERSION"; jq -n --arg id "$1" --arg r "$2" '{id:$id,requires_lib:$r}' >"$SUMI_HOME/apps/$1/manifest.json"; }
mkapp appa ">=1.0 <2.0"; mkapp appb ">=1.0 <1.4"

SHA2="$(mkcore 1.1.0 'echo "// v110" >> hub/shell.qml; echo 1.4.0 > lib/VERSION')"
out="$(S update --check --refresh --json)"
check "update --check: thấy 1.1.0" '[ "$(jq -r .available <<<"$out")" = true ] && [ "$(jq -r .latest <<<"$out")" = 1.1.0 ] && [ "$(jq -r .sha <<<"$out")" = "$SHA2" ]' "$out"
out="$(S update --json)"; c=$?
check "update không --yes: chỉ báo, mã 2, không đổi gì" '[ "$c" = 2 ] && [ "$(S version --json | jq -r .version)" = 1.0.0 ] && ! grep -q "v110" "$SUMI_HOME/hub/shell.qml"' "$out"

# ---------- 3. đang chạy thì từ chối ----------
bash -c 'sleep 30; true' -p "$SUMI_HOME/hub/shell.qml" & HUBPID=$!; sleep 0.3
check "update khi hub đang chạy -> 3" '[ "$(code S update --yes)" = 3 ]'
check "uninstall khi hub đang chạy -> 3" '[ "$(code S uninstall --yes)" = 3 ]'
check "install.sh khi hub đang chạy bị chặn" '! bash "$T/clone/install.sh" >/dev/null 2>&1'
kill $HUBPID 2>/dev/null; wait $HUBPID 2>/dev/null; sleep 0.2

# ---------- 4. cập nhật thật ----------
out="$(S update --yes --json)"; c=$?
check "update --yes: ok" '[ "$c" = 0 ] && [ "$(jq -r .to <<<"$out")" = 1.1.0 ]' "$out"
check "update: hub mới" 'grep -q "v110" "$SUMI_HOME/hub/shell.qml"'
check "update: install.json 1.1.0 + sha" '[ "$(jq -r .version "$SUMI_HOME/install.json")" = 1.1.0 ] && [ "$(jq -r .sha "$SUMI_HOME/install.json")" = "$SHA2" ]'
check "update: lệnh được cập nhật (sumi version)" '[ "$(S version --json | jq -r .version)" = 1.1.0 ]'
check "update: lib mới = 1.4.0, hub vendored theo" '[ "$(cat "$SUMI_HOME/lib/VERSION")" = 1.4.0 ] && [ "$(cat "$SUMI_HOME/hub/lib/VERSION")" = 1.4.0 ]'
check "update: app tương thích được làm mới lib" '[ "$(cat "$SUMI_HOME/apps/appa/lib/VERSION")" = 1.4.0 ]'
check "update: app không tương thích GIỮ lib cũ" '[ "$(cat "$SUMI_HOME/apps/appb/lib/VERSION")" = 1.3.0 ]'
check "update: staging sạch" '[ -z "$(ls -A "$SUMI_HOME/.staging" 2>/dev/null)" ]'
out="$(S update --yes --json)"
check "update lần nữa: đã mới nhất" '[ "$(jq -r .ok <<<"$out")" = true ] && [ "$(jq -r .updated <<<"$out")" != true ]' "$out"

# ---------- 5. bản xấu ----------
mkcore 1.2.0 'echo 1.1.9 > VERSION' >/dev/null
out="$(S update --yes --json)"; c=$?
check "tag v1.2.0 nhưng VERSION=1.1.9 -> 5 version_mismatch" '[ "$c" = 5 ] && [ "$(jq -r .code <<<"$out")" = version_mismatch ]' "$out"
check "bản xấu không làm đổi gì" '[ "$(S version --json | jq -r .version)" = 1.1.0 ]'
mkcore 1.3.0 'rm install.sh' >/dev/null
out="$(S update --yes --json)"; c=$?
check "tag thiếu install.sh -> 5 layout" '[ "$c" = 5 ] && [ "$(jq -r .code <<<"$out")" = layout ]' "$out"
mkcore 1.3.0 'sed -i "s/^set -eu/set -eu; exit 9/" install.sh' >/dev/null     # tag v1.3.0 bị đẩy lại (force) với install.sh lỗi
out="$(S update --yes --json)"; c=$?
check "install.sh của bản mới lỗi -> báo lỗi, không đổi version" '[ "$c" = 1 ] && [ "$(jq -r .code <<<"$out")" = install ] && [ "$(S version --json | jq -r .version)" = 1.1.0 ]' "$out"
# tag nhẹ (lightweight) bị bỏ qua
w="$T/work-core"; git -C "$w" tag v9.9.9 && git -C "$w" push -q "$BARE" refs/tags/v9.9.9 2>/dev/null
out="$(S update --check --refresh --json)"
check "tag nhẹ vX.Y.Z bị bỏ qua (chỉ nhận annotated)" '[ "$(jq -r .latest <<<"$out")" = 1.3.0 ]' "$out"

# tag bị dời giữa lúc ls-remote và clone: giả lập bằng git giả trả SHA khác cho ls-remote
mkcore 1.5.0 >/dev/null
mkdir -p "$T/stub2"; REALGIT="$(command -v git)"
cat >"$T/stub2/git" <<X
#!/bin/bash
for a in "\$@"; do
  if [ "\$a" = ls-remote ]; then printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/v1.5.0^{}\n'; exit 0; fi
done
exec "$REALGIT" "\$@"
X
chmod +x "$T/stub2/git"
out="$(PATH="$T/stub2:$PATH" S update --yes --json)"; c=$?
check "SHA bản clone khác SHA của tag -> 5 sha_mismatch, không đổi gì" '[ "$c" = 5 ] && [ "$(jq -r .code <<<"$out")" = sha_mismatch ] && [ "$(S version --json | jq -r .version)" = 1.1.0 ]' "$out"
git -C "$T/work-core" push -q "$BARE" ":refs/tags/v1.5.0" 2>/dev/null; git -C "$T/work-core" tag -d v1.5.0 >/dev/null 2>&1
# cache của --check (hub gọi mỗi lần mở)
rm -f "$XDG_CONFIG_HOME/sumi/core-update-cache.json"
S update --check --refresh --json >/dev/null
mkcore 1.6.0 >/dev/null
out="$(S update --check --json)"
check "update --check dùng cache (chưa thấy 1.6.0)" '[ "$(jq -r .latest <<<"$out")" = 1.3.0 ] && [ "$(jq -r .stale <<<"$out")" = false ]' "$out"
out="$(S update --check --refresh --json)"
check "update --check --refresh bỏ qua cache (thấy 1.6.0)" '[ "$(jq -r .latest <<<"$out")" = 1.6.0 ]' "$out"
out="$(SUMI_GIT_BASE="file://$T/nope" S update --check --refresh --json)"; c=$?
check "offline nhưng có cache: dùng cache cũ, stale=true, mã 0" '[ "$c" = 0 ] && [ "$(jq -r .stale <<<"$out")" = true ] && [ "$(jq -r .latest <<<"$out")" = 1.6.0 ]' "$out"
rm -f "$XDG_CONFIG_HOME/sumi/core-update-cache.json"
out="$(SUMI_GIT_BASE="file://$T/nope" S update --check --json)"; c=$?
check "offline và chưa có cache -> 6" '[ "$c" = 6 ]' "$out"
echo '{"version":1,"global":{},"hub":{"checkUpdateHours":1}}' >"$XDG_CONFIG_HOME/sumi/config.json"
S update --check --refresh --json >/dev/null
jq '.fetched_at -= 7200' "$XDG_CONFIG_HOME/sumi/core-update-cache.json" >"$T/c.json" && mv "$T/c.json" "$XDG_CONFIG_HOME/sumi/core-update-cache.json"
mkcore 1.7.0 >/dev/null
out="$(S update --check --json)"
check "cache quá hạn (hub.checkUpdateHours=1) thì hỏi lại" '[ "$(jq -r .latest <<<"$out")" = 1.7.0 ]' "$out"
rm -f "$XDG_CONFIG_HOME/sumi/config.json"
check "update --yes không dùng cache (luôn thật)" 'out="$(S update --yes --json)"; [ "$(jq -r .to <<<"$out")" = 1.7.0 ]' "$out"
# (đã lên 1.7.0: các mục sau chạy trên bản này)
# ---------- 6. offline / bản dev ----------
rm -f "$XDG_CONFIG_HOME/sumi/core-update-cache.json"
out="$(SUMI_GIT_BASE="file://$T/nope" S update --check --refresh --json)"; c=$?
check "offline -> 6" '[ "$c" = 6 ] && [ "$(jq -r .code <<<"$out")" = offline ]' "$out"
cp "$SUMI_HOME/install.json" "$T/install.json.bak"; echo '{"version":"dev","source":"install-dev"}' >"$SUMI_HOME/install.json"
out="$(S update --check --refresh --json)"
check "bản cài dev: từ chối update" '[ "$(jq -r .code <<<"$out")" = dev_install ]' "$out"
cp "$T/install.json.bak" "$SUMI_HOME/install.json"
out="$(SUMI_HOME="$T/none/sumi" S update --check --refresh --json)"
check "chưa cài: báo rõ" '[ "$(jq -r .code <<<"$out")" = not_installed ]' "$out"

# ---------- 7. cài app qua installer ----------
mkdir -p "$XDG_CONFIG_HOME/sumi"
mkrepo() {
    local id="$1" w="$T/work-$1" bare="$T/git/o/sumi-$1.git"
    git init -q --bare "$bare"; rm -rf "$w"; mkdir -p "$w"; git -C "$w" init -q -b main
    jq -n --arg id "$id" '{id:$id,name:("App "+$id),version:"1.0.0",kind:"oneshot",requires_lib:">=1.0 <2.0",config_version:1,run:"qs -p {dir}/shell.qml",ipc_target:("sumi-"+$id),functions:[{id:"main",label:"Main",objects:[]}],options:[],keybinds:[],fonts:[],requires:[],shell_commands:["echo hi"]}' >"$w/manifest.json"
    echo "// v" >"$w/View.qml"; echo "// s" >"$w/shell.qml"
    git -C "$w" add -A; git -C "$w" commit -q -m v; git -C "$w" tag -a v1.0.0 -m v1.0.0
    git -C "$w" push -q "$bare" main:refs/heads/main refs/tags/v1.0.0 2>/dev/null; git -C "$w" rev-parse 'v1.0.0^{commit}'
}
ASHA="$(mkrepo zed)"; mkdir -p "$T/reg"
jq -n --arg s "$ASHA" '{version:1,apps:[{id:"zed",repo:"github.com/o/sumi-zed",ref:"v1.0.0",sha:$s}]}' >"$T/reg/index.json"
export SUMI_REGISTRY_URL="file://$T/reg/index.json"
out="$(bash "$T/clone/install.sh" --apps zed --yes 2>&1)"; c=$?
check "install.sh --apps zed --yes cài app qua store" '[ "$c" = 0 ] && [ -f "$SUMI_HOME/apps/zed/manifest.json" ] && [ "$(jq -r ".apps.zed.sha" "$XDG_CONFIG_HOME/sumi/installed.json")" = "$ASHA" ]' "$out"
check "installer in SHA và lệnh shell trước khi cài" 'grep -q "$ASHA" <<<"$out" && grep -q "echo hi" <<<"$out"' "$out"
rm -rf "$SUMI_HOME/apps/zed"; rm -f "$XDG_CONFIG_HOME/sumi/installed.json"
out="$(bash "$T/clone/install.sh" --apps zed </dev/null 2>&1)"
check "không có terminal và thiếu --yes: bỏ qua app" '[ ! -e "$SUMI_HOME/apps/zed" ] && grep -q "thiếu --yes" <<<"$out"' "$out"
out="$(bash "$T/clone/install.sh" --apps ghost --yes 2>&1)"; c=$?
check "app không có trong registry: cảnh báo, lõi vẫn ok" '[ "$c" = 0 ] && grep -q "ghost" <<<"$out"' "$out"

# ---------- 8. gỡ cài đặt ----------
echo '{"version":1,"global":{}}' >"$XDG_CONFIG_HOME/sumi/config.json"
out="$(S uninstall)"; c=$?
check "uninstall không --yes: chỉ in kế hoạch, mã 2, không xoá" '[ "$c" = 2 ] && [ -d "$SUMI_HOME/hub" ] && [ -x "$T/bin/sumi" ] && grep -q "Giữ nguyên" <<<"$out"' "$out"
check "uninstall: kế hoạch liệt kê app" 'grep -q "appa" <<<"$out"'
check "uninstall: từ chối khi SUMI_HOME lạ" '[ "$(SUMI_HOME="$T/danger" code S uninstall --yes)" = 1 ] && [ -d "$T/bin" ]'
cp "$T/bin/sumi-self" "$T/sumi-self.keep"
out="$(S uninstall --yes --json)"; c=$?
check "uninstall --yes: gỡ lõi, giữ config" '[ "$c" = 0 ] && [ ! -e "$SUMI_HOME" ] && [ ! -e "$T/bin/sumi" ] && [ ! -e "$T/bin/sumi-store" ] && [ ! -e "$T/bin/sumi-self" ] && [ ! -e "$T/bin/sumi-safe-close" ] && [ -f "$XDG_CONFIG_HOME/sumi/config.json" ]' "$out"
# cài lại rồi purge
bash "$T/clone/install.sh" >/dev/null 2>&1
out="$(S uninstall --yes --purge --json)"
check "uninstall --purge: xoá luôn config" '[ ! -e "$XDG_CONFIG_HOME/sumi" ] && [ ! -e "$SUMI_HOME" ]' "$out"
check "uninstall không đụng file của người dùng trong bin" 'touch "$T/bin/other" && bash "$T/clone/install.sh" >/dev/null 2>&1 && S uninstall --yes >/dev/null 2>&1; [ -e "$T/bin/other" ]'

echo "-----"; echo "pass=$P fail=$F"; [ "$F" -eq 0 ]
