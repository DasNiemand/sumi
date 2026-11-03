import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "lib"

// SUMI 墨 - hub (GĐ2a launcher + GĐ2b-1 settings theme). Liệt kê app đã cài qua `sumi list --json`, chạy app / function.
// Mở bằng `sumi hub`. Trang APPS: W/S chọn app, A/D chọn function (app daemon), Enter chạy, T cài đặt theme, Esc/Q đóng.
// Trang THEME: W/S chọn phạm vi, A/D chọn preset, -/= tint, ,/. độ đậm mực, Enter áp dụng, R kế thừa, Esc quay lại.
ShellRoot {
    id: root

    // ===== Màu Noctalia + config (appId "hub") =====
    SumiColors { id: colors }
    SumiConfig { id: cfg; appId: "hub" }
    SumiConfigEdit { id: ce }
    // theme của hub: hub.theme -> global.theme -> paper
    readonly property string hubTheme: {
        const h = cfg.data.hub
        return (h !== null && typeof h === "object" && typeof h.theme === "string") ? h.theme : cfg.look("theme", "paper")
    }
    SumiTheme {
        id: th
        preset: root.hubTheme
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

    property string lastAppsJson: ""
    function parseApps(t) {
        if (t === root.lastAppsJson && root.errorText === "") return     // không đổi -> không dựng lại list
        root.lastAppsJson = t
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

    // ===== Trang THEME (2b-1) =====
    property string page: "apps"            // apps | theme
    property int scopeSel: 0
    readonly property var scopes: {
        const l = [{ id: "global", name: "GLOBAL" }, { id: "hub", name: "HUB" }]
        for (let i = 0; i < apps.length; i++) l.push({ id: apps[i].id, name: String(apps[i].name).toUpperCase() })
        return l
    }
    readonly property string scopeId: scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].id
    readonly property string scopeName: scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].name
    property var draft: ({ theme: null, tint: null, inkDarken: null })
    property string applyMsg: ""
    property string applyErr: ""
    property bool applyOk: false

    readonly property var stored: ce.lookOf(cfg.data, scopeId)
    readonly property var inh: ce.inherited(cfg.data, scopeId)
    readonly property string effTheme: draft.theme !== null ? draft.theme : inh.theme
    readonly property real effTint: draft.tint !== null ? draft.tint : inh.tint
    readonly property real effInk: draft.inkDarken !== null ? draft.inkDarken : inh.inkDarken
    readonly property var curDerived: th.derive(effTheme, effTint, effInk)
    readonly property bool tintEditable: scopeId !== "hub"
    readonly property bool dirty: !ce.sameLook(draft, stored)
    readonly property bool blocked: curDerived.contrast < th.minContrast
    readonly property bool weak: !blocked && curDerived.contrast < th.goodContrast

    function presetKanji(n) {
        return n === "paper" ? "紙" : n === "ink" ? "墨" : n === "mono-white" ? "白" : n === "mono-black" ? "黒" : n === "accent" ? "彩" : "随"
    }
    function loadDraft() { draft = ce.lookOf(cfg.data, scopeId); applyMsg = ""; applyErr = "" }
    function openTheme() { page = "theme"; if (scopeSel >= scopes.length) scopeSel = 0; loadDraft() }
    function closeTheme() { page = "apps" }
    function setScope(i) { scopeSel = Math.max(0, Math.min(i, scopes.length - 1)); loadDraft() }
    function moveScope(d) { setScope((scopeSel + d + scopes.length) % scopes.length) }
    function setPreset(name) {
        draft = { theme: name, tint: draft.tint, inkDarken: draft.inkDarken }
        applyMsg = ""; applyErr = ""
    }
    function movePreset(d) {
        const l = ce.themes
        let i = l.indexOf(effTheme)
        if (i < 0) i = 0
        setPreset(l[(i + d + l.length) % l.length])
    }
    function nudge(key, d) {
        if (!tintEditable) return
        if (key === "tint") draft = { theme: draft.theme, tint: Math.max(0, Math.min(0.6, ce.round(effTint + d, 2))), inkDarken: draft.inkDarken }
        else draft = { theme: draft.theme, tint: draft.tint, inkDarken: Math.max(1, Math.min(2.5, ce.round(effInk + d, 1))) }
        applyMsg = ""; applyErr = ""
    }
    function inheritScope() {
        draft = { theme: null, tint: null, inkDarken: null }
        applyMsg = ""; applyErr = ""
    }
    function applyDraft() {
        if (applyProc.running) return
        if (!dirty) { applyOk = false; applyMsg = "NO CHANGES"; return }
        if (blocked) { applyOk = false; applyMsg = "BLOCKED"; applyErr = "tương phản dưới 4.5, không cho áp dụng"; return }
        // config.json hiện có nhưng đọc không ra JSON: không ghi đè (tránh làm mất phần còn lại)
        let raw = ""
        try { raw = cfg.text() } catch (e) { raw = "" }
        if (raw.trim() !== "") {
            try { JSON.parse(raw) } catch (e) {
                applyOk = false; applyMsg = "CONFIG HỎNG"; applyErr = "config.json không đọc được; chạy: sumi config restore"; return
            }
        }
        const errs = ce.validateLook(draft, scopeId)
        if (errs.length > 0) { applyOk = false; applyMsg = "REJECTED"; applyErr = errs.join("; "); return }
        const next = ce.withLook(cfg.data, scopeId, draft)
        applyErr = ""; applyOk = false; applyMsg = "WRITING..."
        applyProc.command = [sumiBin, "config", "apply", JSON.stringify(next)]
        applyProc.running = true
    }
    Process {
        id: applyProc
        stderr: StdioCollector { onStreamFinished: if (root.applyMsg !== "APPLIED") root.applyErr = this.text.trim() }
        onExited: (code, status) => {
            root.applyOk = (code === 0)
            root.applyMsg = code === 0 ? "APPLIED" : ("FAILED (" + code + ")")
            if (code === 0) root.applyErr = ""
        }
    }

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
                if (root.page === "theme") {
                    if (k === Qt.Key_Escape || k === Qt.Key_Q || k === Qt.Key_Tab) { if (!ar) root.closeTheme(); event.accepted = true }
                    else if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveScope(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveScope(1); event.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left) { if (!ar) root.movePreset(-1); event.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right) { if (!ar) root.movePreset(1); event.accepted = true }
                    else if (k === Qt.Key_Minus) { root.nudge("tint", -0.02); event.accepted = true }
                    else if (k === Qt.Key_Equal || k === Qt.Key_Plus) { root.nudge("tint", 0.02); event.accepted = true }
                    else if (k === Qt.Key_Comma) { root.nudge("ink", -0.1); event.accepted = true }
                    else if (k === Qt.Key_Period) { root.nudge("ink", 0.1); event.accepted = true }
                    else if (k === Qt.Key_R) { if (!ar) root.inheritScope(); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.applyDraft(); event.accepted = true }
                    return
                }
                if (k === Qt.Key_Escape || k === Qt.Key_Q) { if (!ar) root.dismiss(); event.accepted = true }
                else if (k === Qt.Key_T || k === Qt.Key_Tab) { if (!ar) root.openTheme(); event.accepted = true }
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
                    text: root.page === "theme" ? "THEME" : "APPS"; color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: root.page === "theme" ? root.scopeName : (root.apps.length + " INSTALLED"); color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -card.px(8); width: parent.width; height: 1; color: th.rule }
            }

            // ---------- danh sách app (trái) ----------
            ListView {
                id: list
                visible: root.page === "apps"
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
            Rectangle { visible: root.page === "apps"; x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }

            // ---------- chi tiết (phải) ----------
            Item {
                id: rc
                x: card.m + card.px(340) + card.px(30)
                y: card.px(76)
                width: card.width - x - card.m
                height: list.height
                visible: root.page === "apps" && root.cur !== null

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
                visible: root.page === "apps" && root.cur === null
                text: root.errorText !== "" ? root.errorText : "KHÔNG CÓ APP NÀO ĐÃ CÀI"
                color: th.ink
                font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true
            }
            Text {
                x: card.m; y: card.height - card.px(86); width: card.width - 2 * card.m
                visible: root.page === "apps" && root.errorText !== "" && root.cur !== null
                text: root.errorText; color: th.ink
                font.family: root.fontData; font.pixelSize: card.fs(14)
            }

            // ---------- trang THEME (2b-1) ----------
            Item {
                id: tp
                visible: root.page === "theme"
                anchors.fill: parent

                // danh sách phạm vi (trái)
                ListView {
                    id: scopeList
                    x: card.m; y: card.px(76)
                    width: card.px(340); height: card.height - card.px(76) - card.px(96)
                    clip: true
                    interactive: false
                    model: root.scopes
                    currentIndex: root.scopeSel
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Item {
                        id: srow
                        required property int index
                        required property var modelData
                        readonly property bool on: index === root.scopeSel
                        readonly property var lk: ce.lookOf(cfg.data, modelData.id)
                        width: scopeList.width
                        height: card.px(48)
                        Rectangle {
                            anchors.fill: parent; anchors.bottomMargin: 1
                            color: srow.on ? th.ink : (smouse.containsMouse ? th.wash : "transparent")
                        }
                        Text {
                            x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - card.px(150)
                            elide: Text.ElideRight
                            text: srow.modelData.name
                            color: srow.on ? th.paper : th.ink
                            font.family: root.fontLabel; font.pixelSize: card.fs(19); font.bold: true
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(16)
                            anchors.verticalCenter: parent.verticalCenter
                            text: srow.lk.theme !== null ? srow.lk.theme.toUpperCase() : "INHERIT"
                            color: srow.on ? th.paper : th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13)
                        }
                        MouseArea {
                            id: smouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setScope(srow.index)
                        }
                    }
                }
                Rectangle { x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }

                // bảng chỉnh (phải)
                Item {
                    id: tr
                    x: card.m + card.px(340) + card.px(30)
                    y: card.px(76)
                    width: card.width - x - card.m
                    height: scopeList.height

                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(8)
                        text: "THEME / " + root.scopeName
                        color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.draft.theme === null && root.draft.tint === null && root.draft.inkDarken === null
                              ? "INHERIT" : (root.dirty ? "DRAFT" : "SAVED")
                        color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                    }

                    // 6 thẻ preset
                    Row {
                        y: card.px(48)
                        spacing: card.px(8)
                        Repeater {
                            model: ce.themes
                            delegate: Item {
                                id: pc
                                required property int index
                                required property string modelData
                                readonly property var dv: th.derive(modelData, root.effTint, root.effInk)
                                readonly property bool on: modelData === root.effTheme
                                readonly property bool bad: dv.contrast < th.minContrast
                                readonly property bool weak: !bad && dv.contrast < th.goodContrast
                                width: Math.floor((tr.width - 5 * card.px(8)) / 6)
                                height: card.px(112)
                                Rectangle {
                                    anchors.fill: parent
                                    color: pc.dv.paper
                                    border.width: pc.on ? 3 : 1
                                    border.color: pc.on ? th.ink : th.rule
                                    opacity: pc.bad ? 0.55 : 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(6)
                                    text: root.presetKanji(pc.modelData); color: pc.dv.ink
                                    font.family: root.fontKanji; font.pixelSize: card.fs(34)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(54)
                                    width: parent.width - card.px(6); horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: pc.modelData.toUpperCase(); color: pc.dv.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(11); font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(72)
                                    text: pc.dv.contrast.toFixed(1) + (pc.bad ? " ✕" : (pc.weak ? " !" : ""))
                                    color: pc.dv.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(11)
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(94)
                                    spacing: card.px(2)
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.ink }
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.soft }
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.rule }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setPreset(pc.modelData)
                                }
                            }
                        }
                    }

                    // xem trước (màu của bản nháp)
                    Item {
                        id: pv
                        y: card.px(172)
                        width: parent.width; height: card.px(118)
                        readonly property var dv: root.curDerived
                        Rectangle { anchors.fill: parent; color: pv.dv.paper; border.width: 1; border.color: pv.dv.ink }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(12); y: card.px(4)
                            text: "墨"; color: pv.dv.rule
                            font.family: root.fontKanji; font.pixelSize: card.fs(76)
                        }
                        Text {
                            x: card.px(14); y: card.px(8)
                            text: "KAKUNIN"; color: pv.dv.ink
                            font.family: root.fontTitle; font.pixelSize: card.fs(30); font.bold: true
                        }
                        Text {
                            x: card.px(14); y: card.px(50)
                            text: "Đóng cửa sổ này?"; color: pv.dv.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15)
                        }
                        Rectangle {
                            x: card.px(14); y: card.px(80); width: card.px(84); height: card.px(28); color: pv.dv.ink
                            Text { anchors.centerIn: parent; text: "YES"; color: pv.dv.paper; font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true }
                        }
                        Rectangle {
                            x: card.px(106); y: card.px(80); width: card.px(84); height: card.px(28); color: "transparent"
                            border.width: 1; border.color: pv.dv.ink
                            Text { anchors.centerIn: parent; text: "NO"; color: pv.dv.ink; font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true }
                        }
                        Rectangle {
                            x: card.px(198); y: card.px(80); width: card.px(84); height: card.px(28); color: th.danger
                            Text { anchors.centerIn: parent; text: "DANGER"; color: "white"; font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true }
                        }
                        Rectangle { x: card.px(290); y: card.px(93); width: card.px(40); height: card.px(2); color: pv.dv.ghostB }
                    }

                    // thanh TINT và INK DARKEN
                    Repeater {
                        model: [
                            { key: "tint", label: "TINT", lo: 0, hi: 0.6, step: 0.02, nd: 2 },
                            { key: "ink", label: "INK DARKEN", lo: 1, hi: 2.5, step: 0.1, nd: 1 }
                        ]
                        delegate: Item {
                            id: cr
                            required property int index
                            required property var modelData
                            readonly property real v: modelData.key === "tint" ? root.effTint : root.effInk
                            readonly property bool isInh: modelData.key === "tint" ? root.draft.tint === null : root.draft.inkDarken === null
                            y: card.px(302) + index * card.px(34)
                            width: tr.width; height: card.px(34)
                            opacity: root.tintEditable ? 1 : 0.35
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cr.modelData.label; color: th.soft
                                font.family: root.fontLabel; font.pixelSize: card.fs(14); font.letterSpacing: 1.5
                            }
                            Rectangle {
                                x: card.px(130); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(240); height: card.px(8)
                                color: th.wash; border.width: 1; border.color: th.rule
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, (cr.v - cr.modelData.lo) / (cr.modelData.hi - cr.modelData.lo)))
                                    height: parent.height; color: th.ink
                                }
                            }
                            Text {
                                x: card.px(384); anchors.verticalCenter: parent.verticalCenter
                                text: cr.v.toFixed(cr.modelData.nd) + (cr.isInh ? "  inh" : "")
                                color: th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                            }
                            Rectangle {
                                x: tr.width - card.px(64); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(28); height: card.px(24); color: "transparent"; border.width: 1; border.color: th.ink
                                Text { anchors.centerIn: parent; text: "-"; color: th.ink; font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nudge(cr.modelData.key, -cr.modelData.step) }
                            }
                            Rectangle {
                                x: tr.width - card.px(30); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(28); height: card.px(24); color: "transparent"; border.width: 1; border.color: th.ink
                                Text { anchors.centerIn: parent; text: "+"; color: th.ink; font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nudge(cr.modelData.key, cr.modelData.step) }
                            }
                        }
                    }
                    Text {
                        y: card.px(302) + card.px(34) * 2 - card.px(2)
                        visible: !root.tintEditable
                        text: "HUB dùng tint và độ đậm của GLOBAL"
                        color: th.soft
                        font.family: root.fontLabel; font.pixelSize: card.fs(12)
                    }

                    // tương phản + trạng thái áp dụng
                    Rectangle { y: card.px(374); width: parent.width; height: 1; color: th.rule }
                    Text {
                        y: card.px(382)
                        text: "CONTRAST  " + root.curDerived.contrast.toFixed(2) + " : 1   "
                              + (root.blocked ? "BLOCKED (<4.5)" : (root.weak ? "WEAK (<7)" : "OK"))
                        color: root.blocked ? th.danger : th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true
                    }
                    Text {
                        y: card.px(404)
                        width: parent.width; elide: Text.ElideRight
                        text: root.applyErr !== "" ? (root.applyMsg + "  " + root.applyErr) : root.applyMsg
                        color: root.applyOk ? th.ink : th.danger
                        font.family: root.fontData; font.pixelSize: card.fs(13)
                    }
                }
            }

            // ---------- chân trang ----------
            Rectangle { x: card.m; y: card.height - card.px(66); width: card.width - 2 * card.m; height: 1; color: th.rule }
            Text {
                x: card.m; y: card.height - card.px(52)
                text: root.page === "theme"
                    ? "W/S  SCOPE   A/D  PRESET   -/=  TINT   ,/.  INK   ENTER  APPLY   R  INHERIT   ESC  BACK"
                    : "W/S  APP      A/D  FUNCTION      ENTER  RUN      T  THEME      ESC  CLOSE"
                color: th.soft
                font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 1
            }
        }
    }
}
