#!/usr/bin/env bash
# Phát hành một repo SUMI (app hoặc lõi) bằng một lệnh, có kiểm tra từng bước và dừng ngay khi sai.
#
#   bash tools/release.sh <thư mục repo> <X.Y.Z> [--message "..."] [--index THƯ_MỤC_SUMI_INDEX] [--no-pin] [--dry-run] [--yes] [--force]
#
# Tự nhận loại repo:  có manifest.json (id, version) = APP;  có VERSION + install.sh = LÕI (repo sumi).
# Các bước: kiểm tra (nhánh main, version tăng, tag chưa có cả local lẫn remote, manifest hợp lệ) -> sửa version
#   -> commit (git add -A, gồm cả thay đổi đang chờ) -> tag annotated vX.Y.Z -> push main -> push tag (thử lại khi GitHub lỗi tạm)
#   -> xác minh tag trên remote trỏ đúng commit -> (APP) ghim vào sumi-index bằng tools/pin.sh rồi commit + push index.
# Thay đổi đang chờ trong repo sẽ vào chung commit phát hành: xem danh sách và xác nhận (hoặc --yes).
# --dry-run: chỉ kiểm tra và in kế hoạch, không sửa/commit/push gì.
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUMI_ROOT="$(cd "$HERE/.." && pwd)"
die() { echo "release: $*" >&2; exit 1; }
say() { echo "• $*"; }

TARGET="${1:-}"; VER="${2:-}"; [ "$#" -ge 2 ] && shift 2 || { sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 2; }
MSG=""; INDEX=""; PIN=1; DRY=0; YES=0; FORCE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --message) shift; MSG="${1:-}" ;;
        --index) shift; INDEX="${1:-}" ;;
        --no-pin) PIN=0 ;;
        --dry-run) DRY=1 ;;
        --yes|-y) YES=1 ;;
        --force) FORCE=1 ;;
        *) die "tuỳ chọn không biết: $1" ;;
    esac
    shift || true
done

ver_num() { local IFS=.; set -- $1; echo $(( 10#${1:-0} * 1000000 + 10#${2:-0} * 1000 + 10#${3:-0} )); }
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version phải dạng X.Y.Z (nhận: $VER)"
TAG="v$VER"
[ -d "$TARGET/.git" ] || die "$TARGET không phải repo git"
TARGET="$(cd "$TARGET" && pwd)"
G() { git -C "$TARGET" "$@"; }
for c in git jq; do command -v "$c" >/dev/null 2>&1 || die "thiếu lệnh '$c'"; done

# ---------- nhận loại repo ----------
KIND=""; ID=""; CUR=""
if [ -f "$TARGET/manifest.json" ] && jq -e '.id and .version' "$TARGET/manifest.json" >/dev/null 2>&1; then
    KIND=app; ID="$(jq -r .id "$TARGET/manifest.json")"; CUR="$(jq -r .version "$TARGET/manifest.json")"
elif [ -f "$TARGET/VERSION" ] && [ -f "$TARGET/install.sh" ]; then
    KIND=core; ID=sumi; CUR="$(tr -d '[:space:]' <"$TARGET/VERSION")"
else
    die "không nhận ra loại repo (cần manifest.json có id+version, hoặc VERSION + install.sh)"
fi
[[ "$CUR" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version hiện tại không hợp lệ: $CUR"
say "$KIND '$ID': $CUR -> $VER ($TARGET)"

# ---------- kiểm tra ----------
branch="$(G rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$branch" = main ] || die "đang ở nhánh '$branch', phát hành chỉ từ nhánh main"
if [ "$FORCE" != 1 ] && [ "$(ver_num "$VER")" -le "$(ver_num "$CUR")" ]; then die "version mới ($VER) phải lớn hơn hiện tại ($CUR) (--force để bỏ qua)"; fi
G remote get-url origin >/dev/null 2>&1 || die "repo chưa có remote 'origin'"
G rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && die "tag $TAG đã có ở local (xoá: git tag -d $TAG nếu là tag lỡ tạo)"
if G ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q .; then die "tag $TAG đã có trên remote"; fi
if ! G ls-remote origin HEAD >/dev/null 2>&1; then die "không kết nối được remote origin (mạng hoặc quyền: thử 'gh auth status')"; fi
if [ "$KIND" = app ] && [ -f "$SUMI_ROOT/tools/validate.py" ] && command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
    jq --arg v "$VER" '.version = $v' "$TARGET/manifest.json" >"${TMPDIR:-/tmp}/rel-manifest.$$.json"
    python3 "$SUMI_ROOT/tools/validate.py" manifest "${TMPDIR:-/tmp}/rel-manifest.$$.json" >/dev/null || { rm -f "${TMPDIR:-/tmp}/rel-manifest.$$.json"; die "manifest không qua validate.py (xem: python3 tools/validate.py manifest $TARGET/manifest.json)"; }
    rm -f "${TMPDIR:-/tmp}/rel-manifest.$$.json"
    say "manifest hợp lệ"
fi
if [ "$KIND" = app ] && [ "$PIN" = 1 ]; then
    [ -n "$INDEX" ] || INDEX="$(dirname "$TARGET")/sumi-index"
    [ -f "$INDEX/tools/pin.sh" ] && [ -d "$INDEX/.git" ] || die "không thấy repo sumi-index tại $INDEX (dùng --index, hoặc --no-pin)"
    INDEX="$(cd "$INDEX" && pwd)"
    [ -z "$(git -C "$INDEX" status --porcelain)" ] || die "repo sumi-index có thay đổi chưa commit: $INDEX"
fi
PENDING="$(G status --porcelain)"
if [ -n "$PENDING" ]; then
    say "thay đổi đang chờ sẽ vào chung commit phát hành:"; echo "$PENDING" | sed 's/^/    /'
fi
if [ "$DRY" = 1 ]; then
    say "[dry-run] sẽ: sửa version -> commit -> tag $TAG -> push main + tag -> xác minh$( [ "$KIND" = app ] && [ "$PIN" = 1 ] && echo " -> ghim vào $INDEX")"
    exit 0
fi
if [ -n "$PENDING" ] && [ "$YES" != 1 ]; then
    if [ -t 0 ]; then read -r -p "Phát hành $TAG cùng các thay đổi trên? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || die "đã huỷ"
    else die "có thay đổi đang chờ và không có terminal: thêm --yes để xác nhận"; fi
fi

# ---------- sửa version, commit, tag ----------
if [ "$KIND" = app ]; then
    sed -i "0,/\"version\": \"$CUR\"/s//\"version\": \"$VER\"/" "$TARGET/manifest.json"
    [ "$(jq -r .version "$TARGET/manifest.json")" = "$VER" ] || die "không sửa được version trong manifest.json (định dạng lạ?). Chưa commit gì."
else
    printf '%s\n' "$VER" >"$TARGET/VERSION"
fi
G add -A
G commit -q -m "${MSG:-$TAG}" || die "commit thất bại"
G tag -a "$TAG" -m "$TAG"
SHA="$(G rev-parse "$TAG^{commit}")"
say "đã commit và tag $TAG (${SHA:0:12})"

# ---------- push + xác minh ----------
retry() {  # retry <lần> <lệnh...>
    local n="$1" i=1; shift
    until "$@"; do
        [ "$i" -lt "$n" ] || return 1
        echo "  lỗi, thử lại ($i/$n) sau ${SUMI_RELEASE_RETRY_SLEEP:-5}s (GitHub đôi khi trả lỗi tạm)..." >&2
        sleep "${SUMI_RELEASE_RETRY_SLEEP:-5}"; i=$((i + 1))
    done
}
retry 3 G push -q origin main || die "push main thất bại. Commit và tag $TAG đã có ở local; sau khi sửa kết nối: git -C $TARGET push origin main && git -C $TARGET push origin $TAG"
retry 3 G push -q origin "$TAG" || die "push tag thất bại. Sau khi sửa kết nối: git -C $TARGET push origin $TAG (rồi pin: bash $INDEX/tools/pin.sh $ID $TAG)"
REMOTE="$(G ls-remote origin "refs/tags/$TAG^{}" | awk '{print $1; exit}')"
[ "$REMOTE" = "$SHA" ] || die "tag $TAG trên remote (${REMOTE:-không có}) không trỏ đúng commit ${SHA:0:12}. KHÔNG ghim vào index."
say "remote đã có $TAG -> ${SHA:0:12}"

# ---------- ghim vào registry (app) ----------
if [ "$KIND" = app ] && [ "$PIN" = 1 ]; then
    (cd "$INDEX" && bash tools/pin.sh "$ID" "$TAG" >/dev/null) || die "pin.sh thất bại (app đã phát hành, index chưa ghim)"
    pinned="$(jq -r --arg id "$ID" '.apps[] | select(.id == $id) | .sha' "$INDEX/index.json")"
    if [ "$pinned" != "$SHA" ]; then git -C "$INDEX" checkout -q -- index.json 2>/dev/null; die "index.json ghim ${pinned:-trống}, khác ${SHA:0:12}. Đã hoàn lại index.json, KHÔNG commit index (app đã phát hành)."; fi
    git -C "$INDEX" add index.json
    git -C "$INDEX" commit -q -m "pin $ID $TAG" || die "commit index thất bại"
    retry 3 git -C "$INDEX" push -q origin main || die "push index thất bại. Sau khi sửa kết nối: git -C $INDEX push origin main"
    say "đã ghim $ID $TAG vào sumi-index"
fi
echo "xong: $ID $VER"
[ "$KIND" = core ] && echo "Người dùng cập nhật bằng: sumi update --check --refresh && sumi update --yes" || true
