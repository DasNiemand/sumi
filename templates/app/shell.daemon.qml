import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "lib"

// @NAME@ - app daemon của SUMI: `sumi @ID@ main` tự khởi động file này nếu chưa chạy rồi gọi IPC `main()`.
// Tiến trình sống nền; mỗi lần gọi hiện thẻ trên màn chứa con trỏ (hoặc SUMI_MONITOR), Enter/Esc/bấm ra ngoài thì ẩn thẻ (không thoát tiến trình).
// Biến môi trường tuỳ chọn: @ENV@_TEXT (nội dung hiện trong thẻ), SUMI_MONITOR (tên màn hình).
// reload() chỉ đọc lại config; không bao giờ đụng trạng thái đang chạy.
ShellRoot {
    id: root

    // ===== Config (~/.config/sumi/config.json) + màu Noctalia (~/.config/sumi/colors.json) =====
    SumiColors { id: colors }
    SumiConfig { id: cfg; appId: "@ID@" }

    readonly property string fontTitle: cfg.font("title", "sans-serif")
    readonly property string fontLabel: cfg.font("label", "sans-serif")
    readonly property string fontData: cfg.font("data", "monospace")
    readonly property color dangerColor: "#E63946"
    readonly property string themePreset: cfg.look("theme", "paper")
    readonly property real tint: cfg.lookNum("tint", 0, 0.6, 0.12)
    readonly property real inkDarken: cfg.lookNum("inkDarken", 1, 2.5, 1.5)
    readonly property real scanOpacity: cfg.lookNum("scanlineOpacity", 0, 0.2, 0.05)
    readonly property bool scanlinesEnabled: cfg.lookBool("scanlines", true)
    readonly property bool glitchEnabled: cfg.lookBool("glitch", true)
    readonly property real scaleBoost: cfg.lookNum("scaleBoost", 0.5, 2, 1)
    readonly property int bootMs: cfg.optionNum("crtBootMs", 0, 3000, 800)
    readonly property int outroMs: cfg.optionNum("crtOutroMs", 0, 3000, 460)
    readonly property int inputDelayMs: cfg.optionNum("acceptKeysDelayMs", 0, 1000, 180)

    readonly property string message: Quickshell.env("@ENV@_TEXT") || "Sửa nội dung trong shell.qml hoặc đặt biến @ENV@_TEXT."
    // Màn hiện thẻ: SUMI_MONITOR nếu có, không thì màn đầu tiên (đổi sang màn chứa con trỏ như jigen nếu cần).
    property string targetName: ""
    readonly property string primaryName: {
        const sc = Quickshell.screens
        const want = targetName !== "" ? targetName : (Quickshell.env("SUMI_MONITOR") || "")
        for (let i = 0; i < sc.length; i++) if (sc[i].name === want) return want
        return sc.length > 0 ? sc[0].name : ""
    }

    // Tên IPC theo manifest; tối thiểu có reload() (hub gọi sau Apply, app oneshot không cần làm gì thêm).
    // Mỗi function trong manifest = một hàm IPC (tên = ipc_name hoặc id). Thử: `qs ipc call @IPC@ main`.
    IpcHandler {
        target: "@IPC@"
        function main(): void { root.open() }
        function reload(): void { cfg.reload(); cfg.refresh() }
    }

    // ===== Mở / đóng thẻ (tiến trình vẫn sống) =====
    property bool shown: false
    property bool resolving: false
    function open() {
        if (shown && !resolving) return
        resolving = false
        shown = true
    }
    function resolve(accept) {
        if (!shown || resolving) return
        resolving = true
        // accept = true: chỗ để làm việc thật (chạy Process...) ; ở đây chỉ đóng thẻ
        hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: Math.max(480, root.outroMs + 20)
        repeat: false
        onTriggered: { root.shown = false; root.resolving = false }
    }

    // ===== Một cửa sổ layer-shell phủ mỗi màn hình; thẻ chỉ hiện ở màn chính =====
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool primary: modelData.name === root.primaryName
            visible: root.shown

            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "sumi-@ID@"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // nền tối; bấm ra ngoài = huỷ
            Rectangle {
                id: dim
                anchors.fill: parent
                color: "#000000"
                opacity: 0
                MouseArea { anchors.fill: parent; onClicked: root.resolve(false) }
                NumberAnimation on opacity { to: 0.5; duration: 180; running: true }
                states: State { name: "out"; when: root.resolving; PropertyChanges { target: dim; opacity: 0 } }
                transitions: Transition { to: "out"; NumberAnimation { property: "opacity"; duration: 380 } }
            }

            View {
                visible: win.primary
                active: root.shown
                anchors.fill: parent
                scaleU: Math.max(0.6, Math.min(win.width / 1920, win.height / 1080)) * root.scaleBoost
                closing: root.resolving
                message: root.message
                bgColor: colors.adapter.surface
                fgColor: colors.adapter.on_surface
                accentColor: colors.adapter.primary
                dangerColor: root.dangerColor
                fontTitle: root.fontTitle
                fontLabel: root.fontLabel
                fontData: root.fontData
                preset: root.themePreset
                tint: root.tint
                inkDarken: root.inkDarken
                bootMs: root.bootMs
                outroMs: root.outroMs
                inputDelayMs: root.inputDelayMs
                scanOpacity: root.scanOpacity
                scanlinesEnabled: root.scanlinesEnabled
                glitchEnabled: root.glitchEnabled
                keyAccept: cfg.keyFor("accept", "Return")
                onAccepted: root.resolve(true)
                onRejected: root.resolve(false)
            }
        }
    }
}
