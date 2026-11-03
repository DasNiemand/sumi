import QtQuick

// So khớp tên phím trong config ("Y", "Return", "Left"...) với event.key của Qt.
QtObject {
    function code(spec) {
        if (typeof spec !== "string" || spec === "") return -1
        const n = spec.length === 1 ? spec.toUpperCase() : spec
        const v = Qt["Key_" + n]
        return v === undefined ? -1 : v
    }
    function match(event, spec) {
        const c = code(spec)
        return c >= 0 && event.key === c
    }
}
