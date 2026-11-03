#!/usr/bin/env bash
# Chạy test logic thuần (trích hàm JS từ QML, giả lập Qt). Cần node. Dùng: bash tools/tests/run.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"; R="$D/../.."
node "$D/theme.test.js" "$R/lib/SumiTheme.qml" | tail -3
node "$D/edit.test.js" "$R/lib/SumiConfigEdit.qml"
node "$D/prefs.test.js" "$R/lib/SumiConfigEdit.qml"
