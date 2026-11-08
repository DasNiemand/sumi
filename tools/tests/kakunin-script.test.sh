#!/usr/bin/env bash
# Test sumi-kakunin/kakunin.sh (filter -> execute -> dialog) với hyprctl/quickshell giả, không cần Hyprland. Cần: bash, jq, pgrep.
D="$(cd "$(dirname "$0")" && pwd)"; KD="${KAKUNIN_DIR:-$D/../../../sumi-kakunin}"; KD="$(cd "$KD" && pwd)"; SC="$KD/kakunin.sh"
T="$(mktemp -d)"; trap 'pkill -f -- "-p $KD/shell.qml" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/cfg" LOG="$T/log" SUMI_KAKUNIN_LOG="$T/klog" KAK_EXIT=0 FAKE_ADDR=0xabc123
mkdir -p "$HOME" "$T/bin" "$XDG_CONFIG_HOME/sumi"
cat >"$T/bin/hyprctl" <<'X'
#!/bin/bash
case "$1 $2" in
  "activewindow -j") [ -n "$FAKE_FAIL" ] && exit 1
                     if [ -z "$FAKE_CLASS" ]; then echo '{}'; else printf '{"address":"%s","class":"%s","title":"t","workspace":{"name":"1"},"monitor":0}\n' "$FAKE_ADDR" "$FAKE_CLASS"; fi ;;
  "monitors -j") echo '[{"id":0,"name":"DP-1"}]' ;;
  dispatch*) echo "close:$(sed -n 's/.*address:\([0-9a-fx]*\).*/\1/p' <<<"$2")" >>"$LOG" ;;
esac
X
cat >"$T/bin/quickshell" <<'X'
#!/bin/bash
echo "ask:$CONFIRM_APP/$CONFIRM_MONITOR" >>"$LOG"; exit "${KAK_EXIT:-0}"
X
chmod +x "$T/bin/hyprctl" "$T/bin/quickshell"
export PATH="$T/bin:$PATH"
P=0; F=0
run() { : >"$LOG"; FAKE_CLASS="$1" bash "$SC" >/dev/null 2>&1; echo "rc=$?" >>"$LOG"; tr '\n' ' ' <"$LOG" | sed 's/ $//'; }
t() { local got; got="$(run "$2")"; if [ "$got" = "$3" ]; then P=$((P+1)); echo "ok    $1"; else F=$((F+1)); echo "FAIL  $1: got [$got] want [$3]"; fi; }
cfg() { printf '%s' "$1" >"$XDG_CONFIG_HOME/sumi/config.json"; }

rm -f "$XDG_CONFIG_HOME/sumi/config.json"
t "mặc định: zen bị hỏi rồi đóng theo địa chỉ"  zen-browser  "ask:zen-browser/DP-1 close:0xabc123 rc=0"
t "mặc định: Minecraft bị hỏi"                  "Minecraft*" "ask:Minecraft*/DP-1 close:0xabc123 rc=0"
t "mặc định: firefox đóng thẳng, KHÔNG chạy dialog" firefox  "close:0xabc123 rc=0"
KAK_EXIT=1 t "No/Esc (mã 1): không đóng, thoát 1" zen-browser "ask:zen-browser/DP-1 rc=1"
t "không có cửa sổ: không làm gì, mã 1"         ""           "rc=1"
FAKE_FAIL=1 t "hyprctl lỗi: không làm gì, mã 1" zen-browser  "rc=1"
FAKE_ADDR="0x1;rm" t "địa chỉ lạ: không làm gì"  firefox      "rc=1"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":["firefox"]}}}}'
t "tuỳ chỉnh: firefox bị hỏi"                   firefox      "ask:firefox/DP-1 close:0xabc123 rc=0"
t "tuỳ chỉnh: zen không còn bị hỏi"             zen-browser  "close:0xabc123 rc=0"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":[]}}}}'
t "danh sách rỗng: không bảo vệ gì"             zen-browser  "close:0xabc123 rc=0"
cfg '{"version":1,"apps":{"kakunin":{"options":{"protectedClasses":["a;rm -rf x","$(id)","org.kde.*"]}}}}'
t "mục sai định dạng bị bỏ, glob còn lại chạy"  org.kde.dolphin "ask:org.kde.dolphin/DP-1 close:0xabc123 rc=0"
t "mục sai không khớp thành lệnh"               zen-browser  "close:0xabc123 rc=0"
cfg '{"version":1,"apps":{"kakunin":{"options":{"crtBootMs":100}}}}'
t "có config nhưng chưa đặt protectedClasses -> mặc định" zen-browser "ask:zen-browser/DP-1 close:0xabc123 rc=0"
cfg '{ not json'
t "JSON hỏng -> mặc định"                       zen-browser  "ask:zen-browser/DP-1 close:0xabc123 rc=0"
cfg '{"apps":{"kakunin":{"options":{"protectedClasses":"zen*"}}}}'
t "sai kiểu (chuỗi) -> mặc định"                zen-browser  "ask:zen-browser/DP-1 close:0xabc123 rc=0"
cfg '{"apps":{"kakunin":{"options":{"protectedClasses":["zen*"]}}}}'
# dialog đang mở -> thoát im lặng, không mở thêm, không đóng
bash -c 'sleep 20; true' -p "$KD/shell.qml" & sleep 0.3
t "đang có dialog: không hỏi, không đóng"       zen-browser  "rc=1"
kill %1 2>/dev/null; wait 2>/dev/null
echo "-----"; echo "pass=$P fail=$F"; [ "$F" -eq 0 ]
