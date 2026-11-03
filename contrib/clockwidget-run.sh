#!/usr/bin/env bash
# Shim tương thích: bind Hyprland / nút Noctalia cũ vẫn gọi file này như trước.
# Dùng: clockwidget-run.sh <shutdown|reboot|shutdown30>
# Nếu jigen (SUMI) đã cài thì chuyển cho `sumi jigen`; chưa cài thì chạy đúng cách cũ (qs -c clockwidget).
set -u

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
    echo "Dùng: $0 <shutdown|reboot|shutdown30>" >&2
    exit 1
fi

SUMI_HOME="${SUMI_HOME:-$HOME/.local/share/sumi}"
if [ -x "$HOME/.local/bin/sumi" ] && [ -f "$SUMI_HOME/apps/jigen/manifest.json" ]; then
    exec "$HOME/.local/bin/sumi" jigen "$ACTION"
fi

# ---- Đường cũ (giữ nguyên hành vi bản gốc) ----
if ! pgrep -f "qs -c clockwidget" > /dev/null 2>&1; then
    setsid qs -c clockwidget > /tmp/clockwidget.log 2>&1 &
    disown
fi
for _ in $(seq 1 166); do
    if qs -c clockwidget ipc call clock-widget "$ACTION" 2>/dev/null; then
        exit 0
    fi
    sleep 0.03
done
echo "clockwidget-run.sh: không kết nối được tới clock-widget sau khi khởi động." >&2
echo "Xem log tại /tmp/clockwidget.log để biết chi tiết lỗi." >&2
exit 1
