import QtQuick

// Text "giải mã" kiểu Cyberpunk 2077: mỗi lần `full` đổi (hoặc `active` bật lên) các ký tự
// chưa giải mã xong sẽ nhấp nháy thành glyph ngẫu nhiên rồi chốt dần từ trái sang phải.
Text {
    id: st

    property string full: ""
    property bool active: true
    property int steps: 10                // số nhịp để giải mã xong (mỗi nhịp 36ms)
    property string glyphs: "#@%&$0123456789ABCDEF<>/|+=*"
    property int tick: steps
    property int trigger: 0               // đổi giá trị này để giải mã lại cùng một chuỗi (chuyển trang)

    function render() {
        const n = full.length
        if (tick >= steps) { text = full; return }
        const k = Math.floor(tick * n / steps)
        let out = ""
        for (let i = 0; i < n; i++) {
            const c = full.charAt(i)
            if (i < k || c === " " || c === "\n") out += c
            else out += glyphs.charAt(Math.floor(Math.random() * glyphs.length))
        }
        text = out
    }
    function scramble() {
        tick = 0
        render()
        stepTimer.restart()
    }
    function settle() {
        stepTimer.stop()
        tick = steps
        render()
    }

    onFullChanged: { if (active) scramble(); else settle() }
    onActiveChanged: { if (active) scramble(); else settle() }
    onTriggerChanged: { if (active) scramble() }
    Component.onCompleted: settle()

    Timer {
        id: stepTimer
        interval: 36
        repeat: true
        onTriggered: {
            st.tick += 1
            st.render()
            if (st.tick >= st.steps) stepTimer.stop()
        }
    }
}
