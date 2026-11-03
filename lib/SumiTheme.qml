import QtQuick

// Bảng màu "giấy + mực" dẫn xuất từ palette Noctalia (surface / on_surface / primary).
// Preset (config: theme): paper | ink | mono-white | mono-black | accent | follow.
//   paper       giấy sáng + mực tối. Công thức GIỮ NGUYÊN bản gốc (mặc định, giao diện cũ).
//   ink         đảo lại: giấy tối + mực sáng.
//   mono-white  như paper nhưng xám trung tính (không ám màu accent).
//   mono-black  như ink nhưng xám trung tính.
//   accent      giấy và mực đều ám mạnh màu primary.
//   follow      theo chế độ của Noctalia: palette tối thì "ink", sáng thì "paper".
// Mọi màu chỉ derive từ palette Noctalia, không có hex tùy ý (trừ danger cố định).
// Tương phản ink/paper theo WCAG: dưới minContrast (4.5) thì preset bị từ chối và rơi về "paper".
QtObject {
    id: th

    property string bgColor: "#14161a"
    property string fgColor: "#e3e1e6"
    property string accentColor: "#a9b8f0"
    property real tint: 0.12          // 0..0.6, độ ám màu accent vào giấy
    property real inkDarken: 1.5      // 1..2.5, độ đậm của mực
    property string preset: "paper"
    property bool guardContrast: true // false chỉ dùng để xem trước preset bị chặn

    readonly property real minContrast: 4.5
    readonly property real goodContrast: 7.0
    readonly property color danger: "#E63946"
    readonly property var presets: ["paper", "ink", "mono-white", "mono-black", "accent", "follow"]

    function mix(a, b, t) { return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1) }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function lin(x) { return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
    function relLum(c) { return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
    function contrastOf(a, b) {
        const la = relLum(a), lb = relLum(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    function gray(l) { const g = Math.max(0, Math.min(1, l)); return Qt.rgba(g, g, g, 1) }

    readonly property color cBg: bgColor
    readonly property color cFg: fgColor
    readonly property color cAcc: accentColor
    readonly property bool bgIsLighter: lum(cBg) > lum(cFg)
    readonly property color lightC: bgIsLighter ? cBg : cFg
    readonly property color darkC: bgIsLighter ? cFg : cBg

    // Tính một preset bất kỳ (t, k tùy chọn: tint và inkDarken khác với giá trị hiện tại, hub dùng để xem trước).
    // Trả về { name, paper, ink, soft, rule, wash, ghostB, contrast }.
    function derive(name, t, k) {
        const tt = (t === undefined) ? tint : t
        const kk = (k === undefined) ? inkDarken : k
        const n = (name === "follow") ? (bgIsLighter ? "paper" : "ink") : name
        const a = Qt.rgba(cAcc.r, cAcc.g, cAcc.b, tt)
        let p, i, g
        if (n === "ink") {
            p = Qt.tint(Qt.darker(darkC, 1.25), a)
            i = Qt.lighter(lightC, 1 + (kk - 1) * 0.2)
            g = cAcc
        } else if (n === "mono-white") {
            p = gray(lum(Qt.darker(lightC, 1.16)))
            i = gray(lum(Qt.darker(darkC, kk)))
            g = gray(lum(Qt.darker(cAcc, 1.6)))
        } else if (n === "mono-black") {
            p = gray(lum(Qt.darker(darkC, 1.25)))
            i = gray(lum(Qt.lighter(lightC, 1 + (kk - 1) * 0.2)))
            g = gray(lum(cAcc))
        } else if (n === "accent") {
            p = mix(Qt.darker(lightC, 1.16), cAcc, 0.22 + tt * 0.5)
            i = Qt.darker(mix(darkC, cAcc, 0.28), kk)
            g = Qt.darker(cAcc, 1.6)
        } else {
            // "paper" và mọi tên lạ: công thức gốc
            p = Qt.tint(Qt.darker(lightC, 1.16), a)
            i = Qt.darker(darkC, kk)
            g = Qt.darker(cAcc, 1.6)
        }
        return {
            name: (n === "ink" || n === "mono-white" || n === "mono-black" || n === "accent") ? n : "paper",
            paper: p, ink: i,
            soft: mix(i, p, 0.42), rule: mix(i, p, 0.58), wash: mix(i, p, 0.90),
            ghostB: g, contrast: contrastOf(p, i)
        }
    }

    readonly property var dReq: derive(preset)
    readonly property bool fellBack: guardContrast && dReq.contrast < minContrast && dReq.name !== "paper"
    readonly property var d: fellBack ? derive("paper") : dReq
    readonly property string effectivePreset: d.name
    readonly property real contrast: d.contrast

    readonly property color paper: d.paper
    readonly property color ink: d.ink
    readonly property color soft: d.soft
    readonly property color rule: d.rule
    readonly property color wash: d.wash
    readonly property color ghostB: d.ghostB
}
