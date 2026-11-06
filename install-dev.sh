#!/usr/bin/env bash
# Cài kiểu DEV: COPY lib và các app từ các repo cạnh nhau vào ~/.local/share/sumi.
# Chạy lại sau mỗi lần sửa code. lib được copy vào từng app (apps/<id>/lib) vì Quickshell
# không nhận import nằm ngoài thư mục chứa shell.qml.
#
# Dùng:  bash install-dev.sh [thư mục chứa các repo, mặc định ~/dev/sumi]
set -eu

SRC="${1:-$HOME/dev/sumi}"
SUMI_HOME="${SUMI_HOME:-$HOME/.local/share/sumi}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sumi"
QS_OLD="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
BIN_DIR="$HOME/.local/bin"

[ -d "$SRC/sumi/lib" ] || { echo "không thấy $SRC/sumi/lib" >&2; exit 1; }

copy_dir() {  # $1 nguồn, $2 đích (xoá đích cũ, bỏ .git)
    rm -rf "$2"; mkdir -p "$(dirname "$2")"; cp -a "$1" "$2"; rm -rf "$2/.git"
}

mkdir -p "$SUMI_HOME/apps" "$CFG_DIR/backups" "$BIN_DIR"

# 1. Sao lưu cấu hình cũ MỘT LẦN (không xoá bản gốc, rollback = dùng lại bản cũ)
BK="$CFG_DIR/backups/pre-sumi"
if [ ! -d "$BK" ]; then
    mkdir -p "$BK"
    for d in confirm clockwidget; do
        [ -d "$QS_OLD/$d" ] && cp -a "$QS_OLD/$d" "$BK/$d"
    done
    echo "đã sao lưu cấu hình cũ vào $BK"
fi

# 2. Palette thô: lấy từ bản cũ nếu chưa có (Noctalia sẽ ghi đè khi bạn đổi output_path)
if [ ! -f "$CFG_DIR/colors.json" ]; then
    for c in "$QS_OLD/confirm/colors.json" "$QS_OLD/clockwidget/colors.json"; do
        if [ -f "$c" ]; then cp "$c" "$CFG_DIR/colors.json"; echo "colors.json: lấy từ $c"; break; fi
    done
fi

# 3. lib + hub + app
copy_dir "$SRC/sumi/lib" "$SUMI_HOME/lib"
if [ -d "$SRC/sumi/hub" ]; then
    copy_dir "$SRC/sumi/hub" "$SUMI_HOME/hub"
    copy_dir "$SRC/sumi/lib" "$SUMI_HOME/hub/lib"
    echo "đã cài hub (lib $(cat "$SRC/sumi/lib/VERSION" 2>/dev/null || echo '?'))"
fi
for r in "$SRC"/sumi-*/; do
    r="${r%/}"
    [ -f "$r/manifest.json" ] || continue
    id="$(jq -r .id "$r/manifest.json")"
    copy_dir "$r" "$SUMI_HOME/apps/$id"
    # Quickshell chỉ nhận type trong thư mục chứa shell.qml -> mỗi app giữ một bản lib/ riêng (vendored).
    copy_dir "$SRC/sumi/lib" "$SUMI_HOME/apps/$id/lib"
    echo "đã cài app: $id (lib $(cat "$SRC/sumi/lib/VERSION" 2>/dev/null || echo '?'))"
    # Bản dev ghi đè bản store: bỏ bản ghi trong installed.json để store coi đây là app dev.
    if [ -f "$CFG_DIR/installed.json" ]; then
        jq --arg id "$id" 'del(.apps[$id])' "$CFG_DIR/installed.json" >"$CFG_DIR/installed.json.tmp" \
            && mv -f "$CFG_DIR/installed.json.tmp" "$CFG_DIR/installed.json"
    fi
done

# 4. lệnh sumi
install -m 0755 "$SRC/sumi/bin/sumi" "$BIN_DIR/sumi"
install -m 0755 "$SRC/sumi/bin/sumi-store" "$BIN_DIR/sumi-store"
install -m 0755 "$SRC/sumi/bin/sumi-self" "$BIN_DIR/sumi-self"
install -m 0755 "$SRC/sumi/contrib/safe-close.sh" "$BIN_DIR/sumi-safe-close"
# Bản cài dev: `sumi update` từ chối (cập nhật = chạy lại install-dev.sh)
printf '{"version":"dev","lib":"%s","source":"install-dev","installed_at":"%s"}\n' "$(tr -d '[:space:]' <"$SUMI_HOME/lib/VERSION" 2>/dev/null)" "$(date -u +%FT%TZ)" >"$SUMI_HOME/install.json"
echo "đã cài $BIN_DIR/sumi và $BIN_DIR/sumi-store"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "lưu ý: $BIN_DIR chưa nằm trong PATH" ;; esac
