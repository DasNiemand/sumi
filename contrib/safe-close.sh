#!/bin/bash
# Các app cần xác nhận (glob pattern)
is_protected() {
    case "$1" in
        zen*|Minecraft*) return 0 ;;
        *) return 1 ;;
    esac
}

WIN_JSON=$(hyprctl activewindow -j)
ACTIVE_CLASS=$(jq -r '.class // empty' <<<"$WIN_JSON")

close_window() {
    hyprctl dispatch "hl.dsp.window.close()" 2>/dev/null || hyprctl dispatch killactive ""
}

if [[ -n "$ACTIVE_CLASS" ]] && is_protected "$ACTIVE_CLASS"; then
    # Không cho mở nhiều dialog cùng lúc
    pgrep -f "quickshell.*apps/kakunin/shell.qml" >/dev/null && exit 0

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
