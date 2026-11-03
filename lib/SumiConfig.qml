import Quickshell
import Quickshell.Io
import QtQuick

// Đọc ~/.config/sumi/config.json.
// Mọi lỗi (thiếu file, JSON hỏng, sai kiểu) -> trả về mặc định, KHÔNG BAO GIỜ làm app không mở được.
// Tra cứu:  option(key)  : apps.<id>.options[key]
//           look(key)    : apps.<id>[key] -> global[key]
//           font(role)   : apps.<id>.fonts[role] -> global.fonts[role]
//           keyFor(act)  : apps.<id>.keybinds[action]
FileView {
    id: cfg

    property string appId: ""
    property var data: ({})

    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/sumi/config.json"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: refresh()
    onLoadFailed: cfg.data = ({})
    Component.onCompleted: refresh()

    function refresh() {
        let parsed = ({})
        try { parsed = JSON.parse(cfg.text()) } catch (e) { parsed = ({}) }
        cfg.data = (parsed !== null && typeof parsed === "object") ? parsed : ({})
    }

    function isObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
    function appObj() {
        const a = cfg.data.apps
        return (isObj(a) && isObj(a[cfg.appId])) ? a[cfg.appId] : ({})
    }
    function clampNum(v, lo, hi, def) {
        return (typeof v === "number" && isFinite(v)) ? Math.max(lo, Math.min(hi, v)) : def
    }

    function look(key, def) {
        const a = appObj()
        if (a[key] !== undefined) return a[key]
        const g = cfg.data.global
        if (isObj(g) && g[key] !== undefined) return g[key]
        return def
    }
    function option(key, def) {
        const o = appObj().options
        return (isObj(o) && o[key] !== undefined) ? o[key] : def
    }
    function font(role, def) {
        const af = appObj().fonts
        if (isObj(af) && typeof af[role] === "string" && af[role] !== "") return af[role]
        const g = cfg.data.global
        if (isObj(g) && isObj(g.fonts) && typeof g.fonts[role] === "string" && g.fonts[role] !== "") return g.fonts[role]
        return def
    }
    function keyFor(action, def) {
        const k = appObj().keybinds
        return (isObj(k) && typeof k[action] === "string" && k[action] !== "") ? k[action] : def
    }

    // Tiện ích: số đã kẹp theo khoảng của schema
    function lookNum(key, lo, hi, def) { return clampNum(look(key, def), lo, hi, def) }
    function optionNum(key, lo, hi, def) { return clampNum(option(key, def), lo, hi, def) }
    function lookBool(key, def) { const v = look(key, def); return typeof v === "boolean" ? v : def }
}
