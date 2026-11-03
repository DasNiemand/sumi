import QtQuick

// Bảng màu "giấy + mực" dẫn xuất từ palette Noctalia (surface / on_surface / primary).
// Công thức giữ NGUYÊN từ bản gốc (trước đây chép tay ở ConfirmCard, PowerOverlay, PaperPalette).
// GĐ1 chưa có preset: chỉ có chế độ "follow Noctalia".
QtObject {
    id: th

    property string bgColor: "#14161a"
    property string fgColor: "#e3e1e6"
    property string accentColor: "#a9b8f0"
    property real tint: 0.12          // 0..0.6, độ ám màu accent vào giấy
    property real inkDarken: 1.5      // 1..2.5, độ đậm của mực

    function mix(a, b, t) { return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1) }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    readonly property color cBg: bgColor
    readonly property color cFg: fgColor
    readonly property color cAcc: accentColor
    readonly property bool bgIsLighter: lum(cBg) > lum(cFg)
    readonly property color lightC: bgIsLighter ? cBg : cFg
    readonly property color darkC: bgIsLighter ? cFg : cBg

    readonly property color paper: Qt.tint(Qt.darker(lightC, 1.16), Qt.rgba(cAcc.r, cAcc.g, cAcc.b, tint))
    readonly property color ink: Qt.darker(darkC, inkDarken)
    readonly property color soft: mix(ink, paper, 0.42)
    readonly property color rule: mix(ink, paper, 0.58)
    readonly property color wash: mix(ink, paper, 0.90)
    readonly property color ghostB: Qt.darker(cAcc, 1.6)
}
