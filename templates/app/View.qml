import QtQuick
import QtQuick.Shapes
import "lib"

// @NAME@ - giao diện thẻ (View thuần: không Process, không ghi file, không thoát tiến trình).
// Hành động ra qua signal accepted() / rejected(); shell.qml nối signal với hành động thật.
// Tên thuộc tính vào dùng chung với hub: preview trong hub chỉ gán những thuộc tính View có (docs/CONVENTIONS.md mục 12),
// nên giữ nguyên tên các thuộc tính "chuẩn" bên dưới. View lấp đầy cha của nó; thẻ nằm giữa.
Item {
    id: card

    // ----- đầu vào chuẩn (tên khớp hub/preview) -----
    property bool closing: false            // true: chạy hoạt cảnh tắt máy
    property bool active: true              // daemon: false -> true thì chạy lại hoạt cảnh bật máy
    property bool previewMode: false        // true: không nhận phím, không giữ focus (khung preview trong hub)
    property string mode: ""                // function đang xem (hub gán theo ipc_name/id của function)
    property string bgColor: "#14161a"
    property string fgColor: "#e3e1e6"
    property string accentColor: "#a9b8f0"
    property string dangerColor: "#E63946"
    property string fontTitle: "sans-serif"
    property string fontLabel: "sans-serif"
    property string fontData: "monospace"
    property string preset: "paper"         // paper|ink|mono-white|mono-black|accent|follow
    property real tint: 0.12
    property real inkDarken: 1.5
    property int bootMs: 800
    property int outroMs: 460
    property int inputDelayMs: 180
    property real scanOpacity: 0.05
    property bool scanlinesEnabled: true
    property bool glitchEnabled: true
    property real scaleU: 1

    // ----- nội dung riêng của app -----
    property string headline: "@NAME@"
    property string message: ""
    property string keyAccept: "Return"
    signal accepted()
    signal rejected()

    function px(n) { return Math.max(1, Math.round(n * scaleU)) }
    function fs(n) { return Math.max(8, Math.round(n * scaleU)) }
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    // ----- bảng màu giấy/mực: công thức nằm ở lib/SumiTheme.qml -----
    SumiTheme { id: th; bgColor: card.bgColor; fgColor: card.fgColor; accentColor: card.accentColor; tint: card.tint; inkDarken: card.inkDarken; preset: card.preset }
    SumiKeyMap { id: km }

    // ----- bật máy / tắt máy (CRT) -----
    property real bp: 0
    property real outP: 0
    property bool inputReady: false
    readonly property real lineW: bootMs <= 0 ? 1 : Math.min(1, bp / 0.28)
    readonly property real openH: bootMs <= 0 ? 1 : clamp01((bp - 0.28) / 0.42)
    readonly property real vCollapse: clamp01((outP - 0.34) / 0.40)
    readonly property real hCollapse: clamp01((outP - 0.74) / 0.26)
    function boot() {
        inputReady = false
        outP = 0
        if (bootMs > 0) { bp = 0; bootAnim.restart() } else bp = 1
        inputTimer.restart()
    }
    Component.onCompleted: boot()
    onActiveChanged: if (active) boot()
    onClosingChanged: if (closing) { outP = 0; if (outroMs > 0) outAnim.restart(); else outP = 1 }
    NumberAnimation { id: bootAnim; target: card; property: "bp"; from: 0; to: 1; duration: Math.max(1, card.bootMs); easing.type: Easing.Linear }
    NumberAnimation { id: outAnim; target: card; property: "outP"; from: 0; to: 1; duration: Math.max(1, card.outroMs); easing.type: Easing.Linear }
    Timer { id: inputTimer; interval: Math.max(1, card.inputDelayMs); repeat: false; onTriggered: card.inputReady = true }

    // ----- phím: Enter (hoặc phím accept cấu hình được) = đồng ý; Esc luôn là huỷ -----
    focus: !card.previewMode
    Keys.onPressed: (event) => {
        if (card.previewMode || !inputReady || closing) return
        const ar = event.isAutoRepeat
        if (event.key === Qt.Key_Escape) { if (!ar) card.rejected(); event.accepted = true }
        else if (km.match(event, card.keyAccept) || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (!ar) card.accepted()
            event.accepted = true
        }
    }

    // ==================================================================
    Item {
        id: box
        anchors.centerIn: parent
        width: px(720); height: px(360)
        opacity: (card.bootMs > 0 && card.bp < 0.04) ? 0 : ((card.bootMs > 0 && card.bp < 0.4 && Math.floor(card.bp * 70) % 2 === 1) ? 0.5 : 1)
        visible: card.active || card.closing
        transform: Scale {
            origin.x: box.width / 2; origin.y: box.height / 2
            xScale: Math.max(0.002, card.lineW * (1 - card.hCollapse))
            yScale: Math.max(0.004, card.openH * (1 - card.vCollapse))
        }

        // nền giấy + khung vát góc dưới phải
        Shape {
            anchors.fill: parent
            ShapePath {
                id: bodySP
                readonly property real c: px(36)
                fillColor: th.paper
                strokeColor: th.ink
                strokeWidth: 1.5
                startX: 0; startY: 0
                PathLine { x: box.width; y: 0 }
                PathLine { x: box.width; y: box.height - bodySP.c }
                PathLine { x: box.width - bodySP.c; y: box.height }
                PathLine { x: 0; y: box.height }
                PathLine { x: 0; y: 0 }
            }
        }

        // thanh trên
        Rectangle {
            x: px(24); y: px(20); width: px(130); height: px(30); color: th.ink
            Text {
                anchors.centerIn: parent; text: "SUMI 墨"; color: th.paper
                font.family: card.fontData; font.pixelSize: fs(14); font.bold: true; font.letterSpacing: 3
            }
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: px(24); y: px(26)
            text: card.mode !== "" ? card.mode.toUpperCase() : ""; color: th.soft
            font.family: card.fontData; font.pixelSize: fs(13); font.letterSpacing: 2
        }
        Rectangle { x: px(24); y: px(62); width: box.width - px(48); height: 1; color: th.rule }

        // nội dung
        Text {
            x: px(24); y: px(100); width: box.width - px(48)
            text: card.headline; color: th.ink; elide: Text.ElideRight
            font.family: card.fontTitle; font.pixelSize: fs(52); font.bold: true
        }
        Text {
            x: px(24); y: px(184); width: box.width - px(48); height: px(100)
            text: card.message; color: th.soft; wrapMode: Text.WordWrap; elide: Text.ElideRight
            font.family: card.fontLabel; font.pixelSize: fs(20)
        }

        // chân trang
        Rectangle { x: px(24); y: box.height - px(62); width: box.width - px(48); height: 1; color: th.rule }
        Text {
            x: px(24); y: box.height - px(46)
            text: "ENTER  ACCEPT      ESC  CANCEL"; color: th.soft
            font.family: card.fontData; font.pixelSize: fs(13); font.letterSpacing: 1
        }

        // scanline (trang trí)
        Repeater {
            model: card.scanlinesEnabled ? Math.ceil(box.height / Math.max(3, Math.round(3 * card.scaleU))) : 0
            delegate: Rectangle {
                required property int index
                y: index * Math.max(3, Math.round(3 * card.scaleU))
                width: box.width; height: 1
                color: th.ink; opacity: card.scanOpacity; z: 50
            }
        }
    }
}
