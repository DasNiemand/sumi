import QtQuick

// Hàm THUẦN để sửa config.json trong bộ nhớ (hub dùng). Không đọc/ghi file: ghi do `sumi config apply` lo
// (backup, tmp + rename). Mọi hàm trả bản sao mới, không sửa dữ liệu đầu vào.
// Scope: "global" | "hub" | <id app>.  "hub" chỉ có theme (config.hub.theme); tint/inkDarken của hub lấy từ global.
QtObject {
    readonly property var themes: ["paper", "ink", "mono-white", "mono-black", "accent", "follow"]
    readonly property var defaults: ({ theme: "paper", tint: 0.12, inkDarken: 1.5 })

    function isObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
    function clone(o) { return JSON.parse(JSON.stringify(o)) }
    function round(v, n) { const m = Math.pow(10, n); return Math.round(v * m) / m }

    // Phần look đang ghi riêng tại scope này; null = chưa đặt (kế thừa).
    function lookOf(data, scope) {
        const d = isObj(data) ? data : ({})
        let src = ({})
        if (scope === "global") src = isObj(d.global) ? d.global : ({})
        else if (scope === "hub") src = isObj(d.hub) ? d.hub : ({})
        else if (isObj(d.apps) && isObj(d.apps[scope])) src = d.apps[scope]
        return {
            theme: (typeof src.theme === "string" && themes.indexOf(src.theme) >= 0) ? src.theme : null,
            tint: (scope !== "hub" && typeof src.tint === "number" && isFinite(src.tint)) ? Math.max(0, Math.min(0.6, src.tint)) : null,
            inkDarken: (scope !== "hub" && typeof src.inkDarken === "number" && isFinite(src.inkDarken)) ? Math.max(1, Math.min(2.5, src.inkDarken)) : null
        }
    }
    // Giá trị hiệu lực của scope: chính nó -> global -> mặc định.
    function effective(data, scope) {
        const g = lookOf(data, "global")
        const own = scope === "global" ? ({ theme: null, tint: null, inkDarken: null }) : lookOf(data, scope)
        return {
            theme: own.theme !== null ? own.theme : (g.theme !== null ? g.theme : defaults.theme),
            tint: own.tint !== null ? own.tint : (g.tint !== null ? g.tint : defaults.tint),
            inkDarken: own.inkDarken !== null ? own.inkDarken : (g.inkDarken !== null ? g.inkDarken : defaults.inkDarken)
        }
    }
    // Giá trị mà scope sẽ kế thừa nếu bỏ ghi riêng.
    function inherited(data, scope) {
        if (scope === "global") return clone(defaults)
        return effective(data, "global")
    }

    // look = { theme: string|null, tint: number|null, inkDarken: number|null }, null = xóa key (kế thừa).
    function withLook(data, scope, look) {
        const out = isObj(data) ? clone(data) : ({})
        out.version = 1
        if (!isObj(out.global)) out.global = ({})
        let tgt
        if (scope === "global") tgt = out.global
        else if (scope === "hub") { if (!isObj(out.hub)) out.hub = ({}); tgt = out.hub }
        else {
            if (!isObj(out.apps)) out.apps = ({})
            if (!isObj(out.apps[scope])) out.apps[scope] = ({})
            tgt = out.apps[scope]
        }
        if (look.theme === null) delete tgt.theme; else tgt.theme = look.theme
        if (scope !== "hub") {
            if (look.tint === null) delete tgt.tint; else tgt.tint = round(Math.max(0, Math.min(0.6, look.tint)), 2)
            if (look.inkDarken === null) delete tgt.inkDarken; else tgt.inkDarken = round(Math.max(1, Math.min(2.5, look.inkDarken)), 1)
        }
        // dọn: scope app/hub rỗng thì bỏ hẳn (giữ file gọn)
        if (scope === "hub" && Object.keys(out.hub).length === 0) delete out.hub
        if (scope !== "global" && scope !== "hub" && Object.keys(out.apps[scope]).length === 0) delete out.apps[scope]
        if (isObj(out.apps) && Object.keys(out.apps).length === 0) delete out.apps
        return out
    }

    // Kiểm tra phần look của một scope trước khi ghi. Trả mảng lỗi (rỗng = hợp lệ).
    function validateLook(look, scope) {
        const e = []
        if (look.theme !== null && themes.indexOf(look.theme) < 0) e.push("theme không hợp lệ: " + look.theme)
        if (scope !== "hub") {
            if (look.tint !== null && !(typeof look.tint === "number" && look.tint >= 0 && look.tint <= 0.6)) e.push("tint ngoài [0, 0.6]")
            if (look.inkDarken !== null && !(typeof look.inkDarken === "number" && look.inkDarken >= 1 && look.inkDarken <= 2.5)) e.push("inkDarken ngoài [1, 2.5]")
        }
        if (scope !== "global" && scope !== "hub" && !/^[a-z][a-z0-9-]{1,31}$/.test(scope)) e.push("tên app không hợp lệ: " + scope)
        return e
    }

    function sameLook(a, b) { return a.theme === b.theme && a.tint === b.tint && a.inkDarken === b.inkDarken }
}
