#!/usr/bin/env bash
# Test contrib/safe-close.sh với hyprctl/sumi giả (không cần Hyprland). Cần: bash, jq, pgrep.
D="$(cd "$(dirname "$0")" && pwd)"; SC="$D/../../contrib/safe-close.sh"
T="$(mktemp -d)"; trap 'pkill -f -- "-p $T/home" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/cfg" LOG="$T/log" KAK_EXIT=0
mkdir -p "$HOME/.local/bin" "$T/bin" "$XDG_CONFIG_HOME/sumi"
cat >"$T/bin/hyprctl" <<'X'
#!/bin/bash
case "$1 $2" in
  "activewindow -j") printf '{"class":"%s","title":"t","workspace":{"name":"1"},"monitor":0}\n' "$FAKE_CLASS" ;;
  "monitors -j") echo '[{"id":0,"name":"DP-1"}]' ;;
  dispatch*) echo close >>"$LOG" ;;
esac
X
cat >"$HOME/.local/bin/sumi" <<'X'
#!/bin/bash
echo "ask:$CONFIRM_APP" >>"$LOG"; exit "${KAK_EXIT:-0}"
X
chmod +x "$T/bin/hyprctl" "$HOME/.local/bin/sumi"
export PATH="$T/bin:/home/claude/bin:$PATH"
P=0; F=0
run() {  # run <class> -> in log
    : >"$LOG"; FAKE_CLASS="$1" bash "$SC" >/dev/null 2>&1; tr '\n' ' ' <"$LOG" | sed 's/ $//'
}
t() { local got; got="$(run "$2")"; if [ "$got" = "$3" ]; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FAIL  $1: got [$got] want [$3]"; fi; }
cfg() { printf '%s' "$1" >"$XDG_CONFIG_HOME/sumi/config.json"; }

rm -f "$XDG_CONFIG_HOME/sumi/config.json"
t "mặc định: zen bị hỏi rồi đóng"          zen-browser   "ask:zen-browser close"
t "mặc định: Minecraft bị hỏi"             "Minecraft*"  "ask:Minecraft* close"
t "mặc định: firefox đóng thẳng"           firefox       "close"
KAK_EXIT=1 t "kakunin trả 1 thì không đóng" zen-browser  "ask:zen-browser"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":["firefox"]}}}}'
t "tuỳ chỉnh: firefox bị hỏi"              firefox       "ask:firefox close"
t "tuỳ chỉnh: zen không còn bị hỏi"        zen-browser   "close"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":[]}}}}'
t "danh sách rỗng: không bảo vệ gì"        zen-browser   "close"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":["a;rm -rf x","$(id)","org.kde.*"]}}}}'
t "mục sai định dạng bị bỏ qua, glob còn lại chạy" org.kde.dolphin "ask:org.kde.dolphin close"
t "mục sai không khớp thành lệnh"          zen-browser   "close"
cfg '{"version":1,"apps":{"kakunin":{"options":{"crtBootMs":100}}}}'
t "có config nhưng chưa đặt protectedClasses -> mặc định" zen-browser "ask:zen-browser close"
cfg '{ not json'
t "JSON hỏng -> mặc định"                  zen-browser   "ask:zen-browser close"
cfg '{"apps":{"kakunin":{"options":{"protectedClasses":"zen*"}}}}'
t "sai kiểu (chuỗi) -> mặc định"           zen-browser   "ask:zen-browser close"
cfg '{"apps":{"kakunin":{"options":{"protectedClasses":["zen*"]}}}}'
# dialog đang mở -> thoát im lặng (kakunin chạy bằng `qs -p`)
mkdir -p "$HOME/.local/share/sumi/apps/kakunin"
bash -c 'sleep 20; true' -p "$HOME/.local/share/sumi/apps/kakunin/shell.qml" & sleep 0.3
t "đang có dialog kakunin: không hỏi, không đóng" zen-browser ""
kill %1 2>/dev/null; wait 2>/dev/null
echo "-----"; echo "pass=$P fail=$F"; [ "$F" -eq 0 ]
