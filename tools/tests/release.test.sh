#!/usr/bin/env bash
# Test tools/release.sh bằng remote git giả (thư mục bare cục bộ): thành công, từ chối đúng chỗ, thử lại khi GitHub lỗi tạm, không ghim khi xác minh sai.
# Cần: bash, git, jq. Tuỳ chọn: python3+jsonschema (kiểm manifest).
set -u
D="$(cd "$(dirname "$0")" && pwd)"; ROOT="$D/../.."; REL="$ROOT/tools/release.sh"
[ -f "$ROOT/../sumi-index/tools/pin.sh" ] || { echo "bỏ qua release.test.sh: không thấy ../sumi-index/tools/pin.sh (đặt repo sumi-index cạnh repo sumi)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export SUMI_GIT_BASE="file://$T/git" SUMI_RELEASE_RETRY_SLEEP=0
P=0; F=0
ok() { P=$((P+1)); echo "ok    $1"; }
bad() { F=$((F+1)); echo "FAIL  $1  ${2:-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
mkdir -p "$T/git/DasNiemand" "$T/w"

# mkrepo <tên> <kiểu app|core> -> tạo bare + work, commit đầu, push main
mkrepo() {
    local name="$1" kind="$2" bare="$T/git/DasNiemand/$1.git" w="$T/w/$1"
    git init -q --bare -b main "$bare"; git init -q -b main "$w"; git -C "$w" remote add origin "$bare"
    if [ "$kind" = app ]; then
        jq -n --arg id "${name#sumi-}" '{id:$id,name:("App "+$id),version:"1.0.0",kind:"oneshot",requires_lib:">=1.0 <2.0",config_version:1,run:"quickshell -p {dir}/shell.qml",ipc_target:("sumi-"+$id),functions:[{id:"main",label:"Main",objects:[]}],options:[],keybinds:[{action:"cancel",default:"Escape",label:"CANCEL",locked:true}],fonts:[],requires:[],shell_commands:[]}' >"$w/manifest.json"
        echo "// v" >"$w/View.qml"; echo "// s" >"$w/shell.qml"
    elif [ "$kind" = core ]; then
        echo "1.0.0" >"$w/VERSION"; echo "# install" >"$w/install.sh"
    else echo x >"$w/file"; fi
    git -C "$w" add -A; git -C "$w" commit -q -m init; git -C "$w" push -q origin main 2>/dev/null
}
mkindex() {
    local bare="$T/git/DasNiemand/sumi-index.git" w="$T/w/sumi-index"
    git init -q --bare -b main "$bare"; git init -q -b main "$w"; git -C "$w" remote add origin "$bare"
    mkdir -p "$w/tools"; cp "$ROOT/../sumi-index/tools/pin.sh" "$w/tools/pin.sh"
    echo '{"version":1,"apps":[]}' >"$w/index.json"
    git -C "$w" add -A; git -C "$w" commit -q -m init; git -C "$w" push -q origin main 2>/dev/null
}
R() { bash "$REL" "$@"; }
idx() { jq -r --arg id "$1" '.apps[] | select(.id==$id) | .ref + " " + .sha' "$T/w/sumi-index/index.json" 2>/dev/null; }

mkindex; mkrepo sumi-foo app
A="$T/w/sumi-foo"; BARE="$T/git/DasNiemand/sumi-foo.git"; IX="$T/w/sumi-index"
H0="$(git -C "$A" rev-parse HEAD)"

# ---------- dry-run ----------
out="$(R "$A" 1.1.0 --dry-run 2>&1)"; c=$?
check "dry-run: mã 0, in kế hoạch" '[ "$c" = 0 ] && grep -q "dry-run" <<<"$out"' "$out"
check "dry-run: không đổi gì" '[ "$(git -C "$A" rev-parse HEAD)" = "$H0" ] && [ "$(jq -r .version "$A/manifest.json")" = 1.0.0 ] && [ -z "$(git -C "$A" tag)" ]'

# ---------- từ chối ----------
check "version sai định dạng" '! R "$A" 1.1 >/dev/null 2>&1 && ! R "$A" v1.1.0 >/dev/null 2>&1'
check "version không lớn hơn hiện tại" '! R "$A" 1.0.0 >/dev/null 2>&1 && ! R "$A" 0.9.0 >/dev/null 2>&1'
check "thư mục không phải repo" '! R "$T" 1.1.0 >/dev/null 2>&1'
mkdir -p "$T/w/other"; git -C "$T/w/other" init -q -b main; check "repo không nhận ra loại" '! R "$T/w/other" 1.1.0 >/dev/null 2>&1'
git -C "$A" checkout -q -b feature; check "không ở nhánh main" '! R "$A" 1.1.0 >/dev/null 2>&1 && [ -z "$(git -C "$A" tag)" ]'; git -C "$A" checkout -q main
echo "// pending" >"$A/pending.qml"
out="$(R "$A" 1.1.0 </dev/null 2>&1)"; c=$?
check "có thay đổi đang chờ, không terminal, thiếu --yes -> từ chối, không đổi gì" '[ "$c" != 0 ] && grep -q "\-\-yes" <<<"$out" && [ "$(jq -r .version "$A/manifest.json")" = 1.0.0 ] && [ -z "$(git -C "$A" tag)" ]' "$out"
echo "x" >>"$IX/index.json.dirty"; check "index có thay đổi chưa commit -> từ chối trước khi đổi gì" '! R "$A" 1.1.0 --yes >/dev/null 2>&1 && [ "$(jq -r .version "$A/manifest.json")" = 1.0.0 ]'; rm -f "$IX/index.json.dirty"
check "--index sai chỗ -> từ chối" '! R "$A" 1.1.0 --yes --index "$T/nope" >/dev/null 2>&1 && [ "$(jq -r .version "$A/manifest.json")" = 1.0.0 ]'
if python3 -c 'import jsonschema' 2>/dev/null; then
    cp "$A/manifest.json" "$T/m.keep"; jq 'del(.kind)' "$T/m.keep" >"$A/manifest.json"
    check "manifest sai schema -> từ chối trước khi commit" '! R "$A" 1.1.0 --yes >/dev/null 2>&1 && [ -z "$(git -C "$A" tag)" ] && [ "$(git -C "$A" rev-parse HEAD)" = "$H0" ]'
    cp "$T/m.keep" "$A/manifest.json"
else echo "bỏ qua kiểm manifest (thiếu jsonschema)"; fi

# ---------- thành công (kèm thay đổi đang chờ) ----------
out="$(R "$A" 1.1.0 --yes --message "v1.1.0: thử nghiệm" 2>&1)"; c=$?
check "release app: mã 0" '[ "$c" = 0 ]' "$out"
check "manifest đã lên 1.1.0, phần còn lại không đổi" '[ "$(jq -r .version "$A/manifest.json")" = 1.1.0 ] && [ "$(jq -r .id "$A/manifest.json")" = foo ] && [ "$(jq -r .kind "$A/manifest.json")" = oneshot ]'
check "thay đổi đang chờ vào chung commit phát hành" 'git -C "$A" show --stat --format=%s HEAD | grep -q pending.qml && [ "$(git -C "$A" log -1 --format=%s)" = "v1.1.0: thử nghiệm" ]'
check "tag annotated v1.1.0 trỏ commit mới" '[ "$(git -C "$A" cat-file -t v1.1.0)" = tag ] && [ "$(git -C "$A" rev-parse "v1.1.0^{commit}")" = "$(git -C "$A" rev-parse HEAD)" ]'
check "remote có main và tag đúng commit" '[ "$(git --git-dir="$BARE" rev-parse main)" = "$(git -C "$A" rev-parse HEAD)" ] && [ "$(git --git-dir="$BARE" rev-parse "v1.1.0^{commit}")" = "$(git -C "$A" rev-parse HEAD)" ]'
SHA110="$(git -C "$A" rev-parse HEAD)"
check "index.json ghim đúng tag + SHA" '[ "$(idx foo)" = "v1.1.0 $SHA110" ]' "$(idx foo)"
check "index đã commit + push" '[ "$(git -C "$IX" log -1 --format=%s)" = "pin foo v1.1.0" ] && [ "$(git --git-dir="$T/git/DasNiemand/sumi-index.git" rev-parse main)" = "$(git -C "$IX" rev-parse HEAD)" ] && [ -z "$(git -C "$IX" status --porcelain)" ]'
check "release lần hai cùng version bị từ chối (tag đã có)" '! R "$A" 1.1.0 --yes >/dev/null 2>&1'
git -C "$A" tag -d v1.1.0 >/dev/null
out="$(R "$A" 1.1.0 --force --yes 2>&1)"; c=$?
check "tag chỉ có trên remote cũng bị từ chối (đúng lý do, trước khi đổi gì)" '[ "$c" != 0 ] && grep -q "đã có trên remote" <<<"$out" && [ "$(git -C "$A" rev-parse HEAD)" = "$SHA110" ]' "$out"
git -C "$A" tag -a v1.1.0 "$SHA110" -m v1.1.0

# ---------- GitHub lỗi tạm: git giả hỏng lần push tag đầu ----------
mkdir -p "$T/shim"; REALGIT="$(command -v git)"
cat >"$T/shim/git" <<X
#!/bin/bash
if [[ "\$*" == *"push -q origin v1.2.0"* ]] && [ ! -e "$T/shim/failed" ]; then touch "$T/shim/failed"; echo "remote: Internal Server Error" >&2; exit 1; fi
exec "$REALGIT" "\$@"
X
chmod +x "$T/shim/git"
out="$(PATH="$T/shim:$PATH" R "$A" 1.2.0 --yes 2>&1)"; c=$?
check "push tag lỗi tạm 1 lần: tự thử lại và thành công" '[ "$c" = 0 ] && [ -e "$T/shim/failed" ] && grep -q "thử lại" <<<"$out" && [ "$(git --git-dir="$BARE" rev-parse "v1.2.0^{commit}")" = "$(git -C "$A" rev-parse HEAD)" ]' "$out"
check "...và đã ghim v1.2.0" '[ "$(idx foo | cut -d" " -f1)" = v1.2.0 ]'

# ---------- xác minh sai: không được ghim ----------
cat >"$T/shim/git" <<X
#!/bin/bash
if [[ "\$*" == *"ls-remote origin refs/tags/v1.3.0^{}"* ]]; then printf '0000000000000000000000000000000000000000\trefs/tags/v1.3.0^{}\n'; exit 0; fi
exec "$REALGIT" "\$@"
X
IXH="$(git -C "$IX" rev-parse HEAD)"
out="$(PATH="$T/shim:$PATH" R "$A" 1.3.0 --yes 2>&1)"; c=$?
check "tag remote trỏ sai commit -> lỗi, KHÔNG ghim" '[ "$c" != 0 ] && grep -q "KHÔNG ghim" <<<"$out" && [ "$(git -C "$IX" rev-parse HEAD)" = "$IXH" ] && [ "$(idx foo | cut -d" " -f1)" = v1.2.0 ]' "$out"
git -C "$A" tag -d v1.3.0 >/dev/null 2>&1; git -C "$A" push -q origin ":refs/tags/v1.3.0" 2>/dev/null

# ---------- pin.sh trả SHA khác: không commit index, hoàn lại index.json ----------
cat >"$T/shim/git" <<X
#!/bin/bash
if [[ "\$*" == *"ls-remote"* && "\$*" == *"file://"* && "\$*" == *"refs/tags/v1.5.0^{}"* ]]; then printf '1111111111111111111111111111111111111111\trefs/tags/v1.5.0^{}\n'; exit 0; fi
exec "$REALGIT" "\$@"
X
IXH="$(git -C "$IX" rev-parse HEAD)"
out="$(PATH="$T/shim:$PATH" R "$A" 1.5.0 --yes 2>&1)"; c=$?
check "pin.sh ghim SHA khác commit -> không commit index, index.json được hoàn lại" '[ "$c" != 0 ] && grep -q "KHÔNG commit index" <<<"$out" && [ "$(git -C "$IX" rev-parse HEAD)" = "$IXH" ] && [ -z "$(git -C "$IX" status --porcelain)" ]' "$out"
git -C "$A" tag -d v1.5.0 >/dev/null 2>&1; git -C "$A" push -q origin ":refs/tags/v1.5.0" 2>/dev/null; git -C "$A" reset -q --hard HEAD~1 2>/dev/null; git -C "$A" push -q -f origin main 2>/dev/null

# ---------- --no-pin, lõi, remote hỏng ----------
echo 'x' >"$A/more"; git -C "$A" add -A; git -C "$A" commit -q -m more
out="$(R "$A" 1.4.0 --yes --no-pin --index "$T/khong-co" 2>&1)"; c=$?
check "--no-pin: không đụng index (kể cả khi --index sai)" '[ "$c" = 0 ] && [ "$(idx foo | cut -d" " -f1)" = v1.2.0 ]' "$out"
mkrepo sumi-core core; C="$T/w/sumi-core"
out="$(R "$C" 1.0.1 --yes 2>&1)"; c=$?
check "release lõi: VERSION + tag, không ghim index" '[ "$c" = 0 ] && [ "$(cat "$C/VERSION")" = 1.0.1 ] && [ "$(git -C "$C" cat-file -t v1.0.1)" = tag ] && grep -q "sumi update" <<<"$out" && [ "$(git --git-dir="$T/git/DasNiemand/sumi-core.git" rev-parse "v1.0.1^{commit}")" = "$(git -C "$C" rev-parse HEAD)" ]' "$out"
git -C "$C" remote set-url origin "$T/khong-ton-tai.git"
check "remote không kết nối được -> từ chối trước khi đổi gì" '! R "$C" 1.0.2 --yes >/dev/null 2>&1 && [ "$(cat "$C/VERSION")" = 1.0.1 ] && [ "$(git -C "$C" tag | wc -l)" = 1 ]'

echo "-----"; echo "pass=$P fail=$F"; [ "$F" -eq 0 ]
