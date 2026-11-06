#!/usr/bin/env bash
# Chạy toàn bộ test logic (trích hàm JS từ QML, giả lập Qt) và test shell. Cần: bash, git, jq, node. Dùng: bash tools/tests/run.sh
# Tách repo app: đặt các repo cạnh nhau (…/sumi, …/sumi-jigen, …/sumi-kakunin), bài test option đọc manifest thật của chúng.
set -e
D="$(cd "$(dirname "$0")" && pwd)"; R="$D/../.."; A="$R/.."
bash "$D/store.test.sh" | tail -2
bash "$D/safeclose.test.sh" | tail -2
bash "$D/self.test.sh" | tail -2
node "$D/theme.test.js" "$R/lib/SumiTheme.qml" | tail -3
node "$D/edit.test.js" "$R/lib/SumiConfigEdit.qml"
node "$D/prefs.test.js" "$R/lib/SumiConfigEdit.qml"
node "$D/options.test.js" "$R/lib/SumiConfigEdit.qml" "$A"
node "$D/options-ui.test.js" "$R/lib/SumiConfigEdit.qml" "$R/hub/shell.qml" "$A/sumi-jigen/manifest.json"
node "$D/store-ui.test.js" "$R/lib/SumiStoreLogic.qml" "$R/hub/shell.qml"
node "$D/jigen-objects.test.js" "$A/sumi-jigen"
node "$D/preview.test.js" "$R/lib/SumiConfigEdit.qml" "$R/hub/shell.qml"
node "$D/revert.test.js" "$R/lib/SumiConfigEdit.qml" "$R/hub/shell.qml"
node "$D/crt.test.js" "$R/hub/shell.qml"
