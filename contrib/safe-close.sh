#!/bin/bash
# safe-close.sh: đóng cửa sổ đang focus. Cửa sổ có class khớp "protectedClasses" thì hỏi kakunin trước.
# Danh sách lấy từ ~/.config/sumi/config.json -> apps.kakunin.options.protectedClasses (chỉnh trong hub: tab OPTION).
#   - Chưa đặt / file thiếu / JSON hỏng : mặc định zen* và Minecraft*
#   - Đặt thành []                       : không bảo vệ app nào
# Mỗi mục là glob (chữ, số và _ . * ? -); mục sai định dạng bị bỏ qua.
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/sumi/config.json"
PROTECTED=('zen*' 'Minecraft*')

load_protected() {
    local out line first=1
    out="$(jq -r '
        (.apps.kakunin.options.protectedClasses) as $p
        | if ($p | type) == "array"
          then "SET", ($p[] | select(type == "string" and test("^[A-Za-z0-9_.*?-]{1,64}$")))
          else "UNSET" end' "$CFG" 2>/dev/null)" || return 0
    [[ "$out" == SET* ]] || return 0
    PROTECTED=()
    while IFS= read -r line; do
        if (( first )); then first=0; continue; fi
        [[ -n "$line" ]] && PROTECTED+=("$line")
    done <<<"$out"
}

is_protected() {
    local p
    for p in "${PROTECTED[@]}"; do
        # shellcheck disable=SC2254
        case "$1" in $p) return 0 ;; esac
    done
    return 1
}

load_protected

WIN_JSON=$(hyprctl activewindow -j)
ACTIVE_CLASS=$(jq -r '.class // empty' <<<"$WIN_JSON")

close_window() {
    hyprctl dispatch "hl.dsp.window.close()" 2>/dev/null || hyprctl dispatch killactive ""
}

if [[ -n "$ACTIVE_CLASS" ]] && is_protected "$ACTIVE_CLASS"; then
    # Không cho mở nhiều dialog cùng lúc (kakunin chạy bằng `qs -p` hoặc `quickshell -p`)
    pgrep -f -- '-p [^ ]*/apps/kakunin/shell\.qml' >/dev/null && exit 0

    # Thông tin thật của cửa sổ để dialog hiển thị + đặt dialog đúng màn hình chứa cửa sổ đó
    CONFIRM_TITLE=$(jq -r '.title // empty' <<<"$WIN_JSON")
    CONFIRM_WS=$(jq -r '.workspace.name // empty' <<<"$WIN_JSON")
    MON_ID=$(jq -r '.monitor // -1' <<<"$WIN_JSON")
    CONFIRM_MONITOR=$(hyprctl monitors -j | jq -r --argjson id "$MON_ID" '.[] | select(.id == $id) | .name' | head -n1)

    CONFIRM_APP="$ACTIVE_CLASS" CONFIRM_TITLE="$CONFIRM_TITLE" CONFIRM_WS="$CONFIRM_WS" \
    CONFIRM_MONITOR="$CONFIRM_MONITOR" "$HOME/.local/bin/sumi" kakunin
    [[ $? -eq 0 ]] && close_window
    exit 0
fi

close_window
