import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "lib"

// SUMI 墨 - hub (GĐ2a: launcher). Liệt kê app đã cài qua `sumi list --json`, chạy app / function.
// Mở bằng `sumi hub`. Phím: W/S chọn app, A/D chọn function (app daemon), Enter chạy, Esc/Q đóng.
ShellRoot {
    id: root

    // ===== Màu Noctalia + config (appId "hub") =====
    SumiColors { id: colors }
    SumiConfig { id: cfg; appId: "hub" }
    SumiTheme {
        id: th
        bgColor: colors.adapter.surface
        fgColor: colors.adapter.on_surface
        accentColor: colors.adapter.primary
        tint: cfg.lookNum("tint", 0, 0.6, 0.12)
        inkDarken: cfg.lookNum("inkDarken", 1, 2.5, 1.5)
    }

    readonly property string fontTitle: cfg.font("title", "sans-serif")
    readonly property string fontLabel: cfg.font("label", "sans-serif")
    readonly property string fontData: cfg.font("data", "monospace")
    readonly property string fontKanji: cfg.font("kanji", Qt.application.font.family)

    readonly property string sumiBin: Quickshell.env("HOME") + "/.local/bin/sumi"
    readonly property string monName: Quickshell.env("SUMI_MONITOR") || ""
    readonly property var targetScreen: {
        const sc = Quickshell.screens
        for (let i = 0; i < sc.length; i++) if (sc[i].name === monName) return sc[i]
        return sc.length > 0 ? sc[0] : null
    }

    // ===== Danh sách app =====
    property var apps: []
    property int sel: 0
    property int fnSel: 0
    property string errorText: ""
    readonly property var cur: (apps.length > 0 && sel >= 0 && sel < apps.length) ? apps[sel] : null
    readonly property var curFns: (cur && Array.isArray(cur.functions)) ? cur.functions : []

    function parseApps(t) {
        let a = []
        try { a = JSON.parse(t) } catch (e) { root.errorText = "sumi list trả về JSON không hợp lệ"; return }
        if (!Array.isArray(a)) { root.errorText = "sumi list trả về dữ liệu lạ"; return }
        root.errorText = ""
        const keepId = (root.cur !== null) ? root.cur.id : ""
        root.apps = a
        let i = -1
        for (let k = 0; k < a.length; k++) if (a[k].id === keepId) { i = k; break }
        root.sel = i >= 0 ? i : Math.max(0, Math.min(root.sel, a.length - 1))
        root.fnSel = Math.max(0, Math.min(root.fnSel, root.curFns.length - 1))
    }
    function move(d) {
        if (apps.length === 0) return
        sel = (sel + d + apps.length) % apps.length
        fnSel = 0
    }
    function moveFn(d) {
        if (curFns.length === 0 || !cur || cur.kind !== "daemon") return
        fnSel = (fnSel + d + curFns.length) % curFns.length
    }
    function runSelected() {
        if (!cur) return
        const cmd = [sumiBin, cur.id]
        if (cur.kind === "daemon") {
            if (curFns.length === 0) return
            cmd.push(curFns[Math.max(0, Math.min(fnSel, curFns.length - 1))].id)
        }
        Quickshell.execDetached(cmd)
        quitTimer.restart()           // đóng hub để app nhận focus bàn phím
    }
    function dismiss() { Qt.quit() }

    Timer { id: quitTimer; interval: 150; repeat: false; onTriggered: Qt.quit() }

    Process {
        id: listProc
        command: [root.sumiBin, "list", "--json"]
        stdout: StdioCollector { onStreamFinished: root.parseApps(this.text) }
    }
    // Làm mới lúc mở và mỗi 2 giây (để cập nhật trạng thái đang chạy)
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!listProc.running) listProc.running = true
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sumi-hub"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // nền tối; bấm ra ngoài = đóng
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
            NumberAnimation on opacity { to: 0.5; duration: 180; running: true }
        }

        Item {
            id: card
            anchors.centerIn: parent
            readonly property real u: Math.max(0.6, Math.min(win.width / 1920, win.height / 1080))
            function px(n) { return Math.max(1, Math.round(n * u)) }
            function fs(n) { return Math.max(8, Math.round(n * u)) }
            width: px(1000)
            height: px(600)
            readonly property real m: px(26)

            // Chặn phím ~150ms đầu để không ăn nhầm phím vừa bấm để mở hub
            property bool inputReady: false
            Timer { interval: 150; running: true; repeat: false; onTriggered: card.inputReady = true }

            focus: true
            Keys.onPressed: (event) => {
                if (!card.inputReady) return
                const k = event.key
                const ar = event.isAutoRepeat
                if (k === Qt.Key_Escape || k === Qt.Key_Q) { if (!ar) root.dismiss(); event.accepted = true }
                else if (k === Qt.Key_W || k === Qt.Key_Up) { root.move(-1); event.accepted = true }
                else if (k === Qt.Key_S || k === Qt.Key_Down) { root.move(1); event.accepted = true }
                else if (k === Qt.Key_A || k === Qt.Key_Left) { root.moveFn(-1); event.accepted = true }
                else if (k === Qt.Key_D || k === Qt.Key_Right) { root.moveFn(1); event.accepted = true }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (!ar) root.runSelected(); event.accepted = true }
            }

            // nền giấy + khung vát góc dưới phải
            Shape {
                anchors.fill: parent
                ShapePath {
                    id: bodySP
                    readonly property real c: card.px(44)
                    fillColor: th.paper
                    strokeColor: th.ink
                    strokeWidth: 1.5
                    startX: 0; startY: 0
                    PathLine { x: card.width; y: 0 }
                    PathLine { x: card.width; y: card.height - bodySP.c }
                    PathLine { x: card.width - bodySP.c; y: card.height }
                    PathLine { x: 0; y: card.height }
                    PathLine { x: 0; y: 0 }
                }
            }

            // ---------- thanh trên ----------
            Item {
                x: card.m; y: card.px(18)
                width: card.width - 2 * card.m; height: card.px(34)
                Rectangle {
                    width: card.px(150); height: parent.height; color: th.ink
                    Text {
                        anchors.centerIn: parent; text: "SUMI 墨"; color: th.paper
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 3
                    }
                }
                Text {
                    x: card.px(168); anchors.verticalCenter: parent.verticalCenter
                    text: "APPS"; color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: root.apps.length + " INSTALLED"; color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -card.px(8); width: parent.width; height: 1; color: th.rule }
            }

            // ---------- danh sách app (trái) ----------
            ListView {
                id: list
                x: card.m; y: card.px(76)
                width: card.px(340); height: card.height - card.px(76) - card.px(96)
                clip: true
                interactive: false
                model: root.apps
                currentIndex: root.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool on: index === root.sel
                    width: list.width
                    height: card.px(56)
                    Rectangle {
                        anchors.fill: parent; anchors.bottomMargin: 1
                        color: row.on ? th.ink : (rowMouse.containsMouse ? th.wash : "transparent")
                    }
                    Text {
                        x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - card.px(150)
                        elide: Text.ElideRight
                        text: row.modelData.name
                        color: row.on ? th.paper : th.ink
                        font.family: root.fontLabel; font.pixelSize: card.fs(21); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: card.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.running ? "● RUNNING" : ("v" + row.modelData.version)
                        color: row.on ? th.paper : (row.modelData.running ? th.ink : th.soft)
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: row.modelData.running
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.sel = row.index; root.fnSel = 0 }
                    }
                }
            }
            Rectangle { x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }

            // ---------- chi tiết (phải) ----------
            Item {
                id: rc
                x: card.m + card.px(340) + card.px(30)
                y: card.px(76)
                width: card.width - x - card.m
                height: list.height
                visible: root.cur !== null

                Rectangle { width: parent.width; height: 1; color: th.ink }
                ScrambleText {
                    x: card.px(2); y: card.px(6)
                    width: rc.width - card.px(150); height: card.px(84)
                    verticalAlignment: Text.AlignVCenter
                    full: root.cur ? root.cur.name.toUpperCase() : ""
                    active: root.cur !== null
                    color: th.ink
                    font.family: root.fontTitle; font.bold: true
                    font.pixelSize: card.fs(56); fontSizeMode: Text.Fit; minimumPixelSize: card.fs(24)
                }
                ScrambleText {
                    anchors.right: parent.right; y: card.px(2)
                    full: root.cur ? root.cur.kanji : ""
                    active: root.cur !== null
                    color: th.rule
                    font.family: root.fontKanji; font.pixelSize: card.fs(88)
                }
                Rectangle { y: card.px(96); width: parent.width; height: 1; color: th.ink }

                Text {
                    y: card.px(108); width: parent.width
                    wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    text: root.cur ? root.cur.description : ""
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(18)
                }

                Repeater {
                    model: root.cur ? [
                        ["VERSION", root.cur.version],
                        ["KIND", root.cur.kind === "daemon" ? "DAEMON (giữ trạng thái)" : "ONESHOT (chạy xong thoát)"],
                        ["STATUS", root.cur.running ? "RUNNING" : "IDLE"]
                    ] : []
                    delegate: Item {
                        required property int index
                        required property var modelData
                        y: card.px(190) + index * card.px(36)
                        width: rc.width; height: card.px(36)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]; color: th.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15); font.letterSpacing: 1.5
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; color: th.ink
                            font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.7 }
                    }
                }

                // function của app daemon (A/D để chọn) hoặc gợi ý cho app oneshot
                Text {
                    y: card.px(312)
                    text: root.cur && root.cur.kind === "daemon" ? "FUNCTION" : "CHẠY THỬ"
                    color: th.soft
                    font.family: root.fontLabel; font.pixelSize: card.fs(15); font.letterSpacing: 1.5
                }
                Row {
                    y: card.px(338)
                    spacing: card.px(10)
                    visible: root.cur !== null && root.cur.kind === "daemon"
                    Repeater {
                        model: root.curFns
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            readonly property bool on: index === root.fnSel
                            width: card.px(150); height: card.px(44)
                            color: on ? th.ink : "transparent"
                            border.width: 1; border.color: th.ink
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(16); font.bold: true; font.letterSpacing: 1
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fnSel = parent.index }
                        }
                    }
                }
                Text {
                    y: card.px(338); width: parent.width
                    visible: root.cur !== null && root.cur.kind !== "daemon"
                    wrapMode: Text.WordWrap
                    text: "Enter mở thử dialog với dữ liệu mẫu (thoát mã 0 = Yes, 1 = No)."
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(17)
                }
            }

            // ---------- trạng thái rỗng / lỗi ----------
            Text {
                x: card.m + card.px(340) + card.px(30); y: card.px(96)
                visible: root.cur === null
                text: root.errorText !== "" ? root.errorText : "KHÔNG CÓ APP NÀO ĐÃ CÀI"
                color: th.ink
                font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true
            }
            Text {
                x: card.m; y: card.height - card.px(86); width: card.width - 2 * card.m
                visible: root.errorText !== "" && root.cur !== null
                text: root.errorText; color: th.ink
                font.family: root.fontData; font.pixelSize: card.fs(14)
            }

            // ---------- chân trang ----------
            Rectangle { x: card.m; y: card.height - card.px(66); width: card.width - 2 * card.m; height: 1; color: th.rule }
            Text {
                x: card.m; y: card.height - card.px(52)
                text: "W/S  APP      A/D  FUNCTION      ENTER  RUN      ESC  CLOSE"
                color: th.soft
                font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 1
            }
        }
    }
}
