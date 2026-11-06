#!/usr/bin/env bash
# SUMI 墨 - cài đặt (chạy từ một bản clone của repo `sumi`).
#
#   git clone https://github.com/DasNiemand/sumi && cd sumi && bash install.sh
#   bash install.sh --apps kakunin,jigen --yes     # cài luôn app từ registry (xem SHA, tag, lệnh shell trước khi cài)
#
# Việc nó làm: copy lib + hub + lệnh (sumi, sumi-store, sumi-self, sumi-safe-close) vào
#   ~/.local/share/sumi/{lib,hub}  và  ~/.local/bin ; ghi ~/.local/share/sumi/install.json.
# Không chạm cấu hình của bạn (~/.config/sumi), không sửa Hyprland/Noctalia, không chạy script nào khác.
# Chạy lại để cài lại; cập nhật dùng `sumi update`. Gỡ: `sumi uninstall`.
set -eu

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUMI_HOME="${SUMI_HOME:-$HOME/.local/share/sumi}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sumi"
BIN_DIR="${SUMI_BIN_DIR:-$HOME/.local/bin}"
DEFAULT_REPO="github.com/DasNiemand/sumi"
MODE=install; APPS=""; YES=0; SHA=""; REPO=""

die() { echo "install: $*" >&2; exit 1; }
warn() { echo "lưu ý: $*" >&2; }
usage() {
    cat <<'X'
dùng: bash install.sh [--apps id1,id2] [--yes]
  --apps a,b   sau khi cài lõi, cài các app đó từ registry (hiện nguồn/tag/SHA/lệnh shell; hỏi xác nhận, hoặc --yes)
  --yes        không hỏi xác nhận khi cài app
  --update     (do `sumi update` dùng) cài không hỏi, ghi lại SHA/repo
X
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apps) shift; APPS="${1:-}" ;;
        --yes|-y) YES=1 ;;
        --update) MODE=update ;;
        --sha) shift; SHA="${1:-}" ;;
        --repo) shift; REPO="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "tuỳ chọn không biết: $1" ;;
    esac
    shift || true
done

# ---------- kiểm tra môi trường ----------
for c in jq git curl; do command -v "$c" >/dev/null 2>&1 || die "thiếu lệnh '$c'"; done
if ! command -v quickshell >/dev/null 2>&1 && ! command -v qs >/dev/null 2>&1; then
    die "thiếu Quickshell (quickshell hoặc qs). Xem https://quickshell.org"
fi
command -v hyprctl >/dev/null 2>&1 || warn "không thấy hyprctl: SUMI nhắm tới Hyprland, hub không chọn được màn hình theo focus"
command -v flock >/dev/null 2>&1 || warn "không thấy flock (util-linux): ghi config sẽ không có khoá"

for f in bin/sumi bin/sumi-store bin/sumi-self hub/shell.qml lib/VERSION lib/SumiTheme.qml contrib/safe-close.sh VERSION; do
    [ -f "$SRC/$f" ] || die "không thấy $SRC/$f (chạy install.sh từ thư mục repo sumi)"
done
VER="$(tr -d '[:space:]' <"$SRC/VERSION")"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION không hợp lệ: $VER"
LIBV="$(tr -d '[:space:]' <"$SRC/lib/VERSION")"

# ---------- đang chạy thì không cài đè ----------
if pgrep -f -- "-p $SUMI_HOME/(hub|apps/[^ /]+)/shell\\.qml" >/dev/null 2>&1; then
    die "hub hoặc một app SUMI đang chạy. Tắt chúng rồi cài lại (cài đè file đang chạy làm Quickshell nạp lại giữa chừng)."
fi

ver_num() { local IFS=.; set -- $1; echo $(( 10#${1:-0} * 1000000 + 10#${2:-0} * 1000 + 10#${3:-0} )); }
lib_satisfies() {  # lib_satisfies <version> <range>
    local v="$1" range="$2" c op n vn rn
    vn="$(ver_num "$v")"
    for c in $range; do
        op="${c%%[0-9]*}"; n="${c#"$op"}"; rn="$(ver_num "$n")"
        [ -n "$op" ] || op="="
        case "$op" in
            ">=") [ "$vn" -ge "$rn" ] ;;  ">") [ "$vn" -gt "$rn" ] ;;
            "<=") [ "$vn" -le "$rn" ] ;;  "<") [ "$vn" -lt "$rn" ] ;;
            "=") [ "$vn" -eq "$rn" ] ;;   *) return 1 ;;
        esac || return 1
    done
    return 0
}

swap_dir() {  # swap_dir <nguồn> <đích>: copy sang chỗ tạm cùng thư mục rồi đổi tên (đích cũ chỉ mất sau khi bản mới đã sẵn)
    local src="$1" dst="$2" tmp old
    tmp="$dst.new.$$"; old="$dst.old.$$"
    rm -rf "$tmp" "$old"; mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$tmp" && rm -rf "$tmp/.git" || { rm -rf "$tmp"; die "copy $src thất bại"; }
    [ ! -e "$dst" ] || mv "$dst" "$old"
    mv "$tmp" "$dst" || { [ ! -e "$old" ] || mv "$old" "$dst"; die "không đặt được $dst"; }
    rm -rf "$old"
}

# ---------- cài lõi ----------
mkdir -p "$SUMI_HOME" "$CFG_DIR" "$BIN_DIR"
PREV=""; [ -f "$SUMI_HOME/install.json" ] && PREV="$(jq -r '.version // empty' "$SUMI_HOME/install.json" 2>/dev/null || true)"

swap_dir "$SRC/lib" "$SUMI_HOME/lib"
HUBTMP="$(mktemp -d "$SUMI_HOME/.hub.XXXXXX")"
trap 'rm -rf "$HUBTMP"' EXIT
cp -a "$SRC/hub/." "$HUBTMP/" && rm -rf "$HUBTMP/lib" && cp -a "$SRC/lib" "$HUBTMP/lib" || die "không dựng được hub"
rm -rf "$HUBTMP/.git"
swap_dir "$HUBTMP" "$SUMI_HOME/hub"

# Quickshell chỉ nhận type trong thư mục chứa shell.qml -> mỗi app giữ một bản lib vendored.
# Chỉ thay lib của app khi lib mới thoả requires_lib của nó; không thoả thì giữ bản cũ (app vẫn chạy).
REV=0; KEEP=0
for d in "$SUMI_HOME"/apps/*/; do
    [ -f "${d}manifest.json" ] || continue
    d="${d%/}"; req="$(jq -r '.requires_lib // ""' "$d/manifest.json" 2>/dev/null || true)"
    if [ -n "$req" ] && lib_satisfies "$LIBV" "$req"; then
        swap_dir "$SRC/lib" "$d/lib"; REV=$((REV + 1))
    else
        warn "app $(basename "$d") cần lib '$req', lib mới là $LIBV: giữ bản lib cũ của app (nên cập nhật app: sumi store)"
        KEEP=$((KEEP + 1))
    fi
done

for b in sumi sumi-store sumi-self; do install -m 0755 "$SRC/bin/$b" "$BIN_DIR/$b"; done
install -m 0755 "$SRC/contrib/safe-close.sh" "$BIN_DIR/sumi-safe-close"

# nguồn để `sumi update` biết lấy bản mới ở đâu
if [ -z "$REPO" ]; then
    REPO="$DEFAULT_REPO"
    url="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
    if [[ "$url" =~ github\.com[:/]([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)$ ]]; then REPO="github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"; fi
fi
[[ "$REPO" =~ ^github\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "repo không hợp lệ: $REPO"
if [ -z "$SHA" ]; then SHA="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)"; fi
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || SHA=""
tmpj="$(mktemp "$SUMI_HOME/install.json.XXXXXX")"
jq -n --arg v "$VER" --arg s "$SHA" --arg r "$REPO" --arg l "$LIBV" --arg t "$(date -u +%FT%TZ)" \
    '{version:$v, sha:$s, repo:$r, lib:$l, installed_at:$t, source:"clone"}' >"$tmpj" && mv -f "$tmpj" "$SUMI_HOME/install.json"

if [ -n "$PREV" ] && [ "$PREV" != "$VER" ]; then echo "đã cập nhật SUMI $PREV -> $VER (lib $LIBV)"; else echo "đã cài SUMI $VER (lib $LIBV)"; fi
echo "  hub     $SUMI_HOME/hub"
echo "  lệnh    $BIN_DIR/{sumi,sumi-store,sumi-self,sumi-safe-close}"
[ "$REV" -eq 0 ] || echo "  lib của $REV app đã được làm mới"
[ "$KEEP" -eq 0 ] || echo "  $KEEP app giữ lib cũ (xem lưu ý ở trên)"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR chưa nằm trong PATH" ;; esac

# ---------- app từ registry (tuỳ chọn) ----------
if [ -n "$APPS" ] && [ "$MODE" = install ]; then
    export SUMI_HOME
    for id in ${APPS//,/ }; do
        [[ "$id" =~ ^[a-z][a-z0-9-]{1,31}$ ]] || { warn "bỏ qua id không hợp lệ: $id"; continue; }
        if ! info="$("$BIN_DIR/sumi-store" inspect "$id" --json 2>/dev/null)" || [ "$(jq -r '.ok' <<<"$info")" != true ]; then
            warn "không kiểm tra được '$id' từ registry: $(jq -r '.message // "lỗi"' <<<"$info" 2>/dev/null)"; continue
        fi
        echo
        echo "App: $(jq -r '.name' <<<"$info") v$(jq -r '.version' <<<"$info")  ($(jq -r '.url' <<<"$info"))"
        echo "  tag $(jq -r '.ref' <<<"$info")   SHA $(jq -r '.sha' <<<"$info")"
        echo "  lệnh shell app có thể chạy: $(jq -r '(.shell_commands | if length==0 then "(không có)" else join(" | ") end)' <<<"$info")"
        if [ "$(jq -r '.lib.compatible' <<<"$info")" != true ]; then warn "$id không tương thích với lib hiện có, bỏ qua"; continue; fi
        if [ "$YES" -ne 1 ]; then
            if [ -t 0 ]; then read -r -p "Cài $id? [y/N] " a; [[ "$a" =~ ^[Yy]$ ]] || { echo "bỏ qua $id"; continue; }
            else warn "không có terminal và thiếu --yes: bỏ qua $id"; continue; fi
        fi
        "$BIN_DIR/sumi-store" install "$id" --sha "$(jq -r '.sha' <<<"$info")" || warn "cài $id thất bại"
    done
fi

echo
[ -f "$CFG_DIR/colors.json" ] || echo "Chưa có $CFG_DIR/colors.json: app dùng màu mặc định. Muốn lấy màu từ Noctalia, cho một user template của Noctalia ghi 7 màu (primary, on_primary, surface, on_surface, surface_variant, on_surface_variant, outline) vào file đó (xem docs/CONVENTIONS.md)."
echo "Thử: sumi hub    (trong hub: G = cửa hàng app)"
echo "Bind đóng cửa sổ có xác nhận: trỏ phím vào $BIN_DIR/sumi-safe-close (danh sách app được bảo vệ chỉnh trong hub: O > kakunin)."
