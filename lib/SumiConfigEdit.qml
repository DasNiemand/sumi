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

    // ======================= 2b-2: FONT theo vai trò =======================
    // Lưu: config.global.fonts / config.apps.<id>.fonts = { <role>: "<family>" }. Thiếu role = kế thừa. Hub dùng font của global.
    readonly property var roles: ["title", "label", "data", "numeral", "kanji"]
    readonly property var fontDefaults: ({ title: "sans-serif", label: "sans-serif", data: "monospace", numeral: "monospace", kanji: "" })

    function validFamily(v) {
        return typeof v === "string" && v.length > 0 && v.length <= 80 && !/[\u0000-\u001f\u007f"\\]/.test(v)
    }
    function tidyApp(out, scope) {
        if (scope !== "global" && scope !== "hub" && isObj(out.apps) && isObj(out.apps[scope]) && Object.keys(out.apps[scope]).length === 0) delete out.apps[scope]
        if (isObj(out.apps) && Object.keys(out.apps).length === 0) delete out.apps
    }
    // Font đang ghi riêng tại scope; null = chưa đặt. Scope "hub" luôn null (hub theo global).
    function fontsOf(data, scope) {
        const d = isObj(data) ? data : ({})
        let src = ({})
        if (scope === "global") src = isObj(d.global) ? d.global : ({})
        else if (scope !== "hub" && isObj(d.apps) && isObj(d.apps[scope])) src = d.apps[scope]
        const f = isObj(src.fonts) ? src.fonts : ({})
        const out = ({})
        for (let i = 0; i < roles.length; i++) out[roles[i]] = validFamily(f[roles[i]]) ? f[roles[i]] : null
        return out
    }
    // Giá trị scope kế thừa nếu bỏ ghi riêng ("" = mặc định hệ thống, dùng cho kanji).
    function fontsInherited(data, scope) {
        const out = clone(fontDefaults)
        if (scope === "global") return out
        const g = fontsOf(data, "global")
        for (let i = 0; i < roles.length; i++) if (g[roles[i]] !== null) out[roles[i]] = g[roles[i]]
        return out
    }
    // fonts = { role: string|null }, null = xóa (kế thừa). Giữ nguyên mọi key khác trong fonts và trong scope.
    function withFonts(data, scope, fonts) {
        const out = isObj(data) ? clone(data) : ({})
        out.version = 1
        if (!isObj(out.global)) out.global = ({})
        if (scope === "hub") return out
        let tgt
        if (scope === "global") tgt = out.global
        else {
            if (!isObj(out.apps)) out.apps = ({})
            if (!isObj(out.apps[scope])) out.apps[scope] = ({})
            tgt = out.apps[scope]
        }
        const f = isObj(tgt.fonts) ? tgt.fonts : ({})
        for (let i = 0; i < roles.length; i++) {
            if (validFamily(fonts[roles[i]])) f[roles[i]] = fonts[roles[i]]
            else delete f[roles[i]]
        }
        if (Object.keys(f).length === 0) delete tgt.fonts; else tgt.fonts = f
        tidyApp(out, scope)
        return out
    }
    function validateFonts(fonts, scope) {
        const e = []
        if (scope === "hub") e.push("hub dùng font của global, không ghi riêng")
        else if (scope !== "global" && !/^[a-z][a-z0-9-]{1,31}$/.test(scope)) e.push("tên app không hợp lệ: " + scope)
        for (var k in fonts) {
            if (roles.indexOf(k) < 0) e.push("vai trò lạ: " + k)
            else if (fonts[k] !== null && !validFamily(fonts[k])) e.push("tên font không hợp lệ cho " + k)
        }
        return e
    }
    function sameFonts(a, b) {
        for (let i = 0; i < roles.length; i++) if (a[roles[i]] !== b[roles[i]]) return false
        return true
    }
    // Vai trò app thực sự dùng (manifest.fonts: mảng chuỗi hoặc {role|id}). Không rõ / rỗng thì cả 5.
    function fontRolesOf(app) {
        if (!app || !Array.isArray(app.fonts) || app.fonts.length === 0) return roles.slice()
        const set = ({})
        for (let i = 0; i < app.fonts.length; i++) {
            const e = app.fonts[i]
            const id = typeof e === "string" ? e : (isObj(e) ? (e.role || e.id) : "")
            if (typeof id === "string") set[id] = true
        }
        const out = roles.filter(r => set[r] === true)
        return out.length > 0 ? out : roles.slice()
    }
    // Đọc đầu ra của: fc-list -f 'A|%{family[0]}|%{spacing}\n'  và  fc-list -f 'J|%{family[0]}\n' :lang=ja
    function parseFontList(text) {
        const map = ({})
        const lines = String(text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].split("|")
            if (p.length < 2) continue
            const name = p[1].trim()
            if (name === "" || !validFamily(name)) continue
            if (!map[name]) map[name] = { name: name, mono: false, ja: false }
            if (p[0] === "A") { if (p.length >= 3 && (p[2].trim() === "100" || p[2].trim() === "110")) map[name].mono = true }
            else if (p[0] === "J") map[name].ja = true
        }
        const out = Object.keys(map).map(k => map[k])
        out.sort((a, b) => a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0))
        return out
    }
    // Bộ lọc mặc định theo vai trò: kanji cần glyph Nhật, data/numeral nên là mono.
    function filterKind(role) { return role === "kanji" ? "ja" : ((role === "data" || role === "numeral") ? "mono" : "") }
    function filterFonts(list, q, kind) {
        const s = String(q).trim().toLowerCase()
        const out = []
        for (let i = 0; i < list.length; i++) {
            const f = list[i]
            if (kind === "ja" && !f.ja) continue
            if (kind === "mono" && !f.mono) continue
            if (s !== "" && f.name.toLowerCase().indexOf(s) < 0) continue
            out.push(f)
        }
        return out
    }

    // ======================= 2b-2: KEYBIND =======================
    // Lưu: config.apps.<id>.keybinds = { <action>: "<Tên phím Qt, bỏ tiền tố Key_>" }. Thiếu = mặc định của manifest.
    // keyNames khớp SumiKeyMap (Qt["Key_" + tên]). Esc luôn là huỷ, Tab/Backtab cố định: không có trong danh sách.
    readonly property var keyNames: "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 0 1 2 3 4 5 6 7 8 9 F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 Return Enter Space Left Right Up Down Home End PageUp PageDown Comma Period Minus Equal Slash Semicolon Apostrophe BracketLeft BracketRight Backslash".split(" ")
    // Phím app tự xử lý cố định: gán cho action khác thì cảnh báo. Giá trị = action sở hữu phím đó.
    readonly property var fixedOwner: ({ "Return": ["confirm"], "Enter": ["confirm"], "Space": ["confirm"], "Left": ["nav.left"], "Right": ["nav.right"], "Up": ["nav.up"], "Down": ["nav.down"], "W": ["nav.up"], "S": ["nav.down"] })
    readonly property var jumpKeys: ["1", "2", "3"]

    function isKeyName(n) { return typeof n === "string" && keyNames.indexOf(n) >= 0 }
    function keyNameOf(code) {
        for (let i = 0; i < keyNames.length; i++) {
            const q = Qt["Key_" + keyNames[i]]
            if (q !== undefined && q === code) return keyNames[i]
        }
        return ""
    }
    // Kết quả khi bắt phím: { ok, key, msg }
    function captureResult(code) {
        if (code === Qt.Key_Escape) return { ok: false, key: "", msg: "ESC luôn là huỷ, không gán lại được" }
        if (code === Qt.Key_Tab || code === Qt.Key_Backtab) return { ok: false, key: "", msg: "TAB là phím cố định" }
        const n = keyNameOf(code)
        if (n === "") return { ok: false, key: "", msg: "phím này chưa hỗ trợ" }
        return { ok: true, key: n, msg: "" }
    }
    function keysOf(data, app) {
        const d = isObj(data) ? data : ({})
        const src = (isObj(d.apps) && isObj(d.apps[app])) ? d.apps[app] : ({})
        const k = isObj(src.keybinds) ? src.keybinds : ({})
        const out = ({})
        for (var a in k) if (isKeyName(k[a])) out[a] = k[a]
        return out
    }
    // kb = manifest.keybinds [{action, default, label, locked}]. keys = { action: key } chỉ chứa phần khác mặc định.
    function withKeys(data, app, keys, kb) {
        const out = isObj(data) ? clone(data) : ({})
        out.version = 1
        if (!isObj(out.global)) out.global = ({})
        if (!isObj(out.apps)) out.apps = ({})
        if (!isObj(out.apps[app])) out.apps[app] = ({})
        const tgt = out.apps[app]
        const k = isObj(tgt.keybinds) ? tgt.keybinds : ({})
        for (let i = 0; i < kb.length; i++) {
            const a = kb[i].action
            if (kb[i].locked === true) continue
            if (isKeyName(keys[a]) && keys[a] !== kb[i].default) k[a] = keys[a]
            else delete k[a]
        }
        if (Object.keys(k).length === 0) delete tgt.keybinds; else tgt.keybinds = k
        tidyApp(out, app)
        return out
    }
    function validateKeys(keys, kb, app) {
        const e = []
        if (!/^[a-z][a-z0-9-]{1,31}$/.test(app)) e.push("tên app không hợp lệ: " + app)
        const known = ({})
        for (let i = 0; i < kb.length; i++) known[kb[i].action] = kb[i]
        for (var a in keys) {
            if (!known[a]) e.push("action lạ: " + a)
            else if (known[a].locked === true) e.push("action bị khoá: " + a)
            else if (!isKeyName(keys[a])) e.push("phím không hợp lệ cho " + a)
        }
        return e
    }
    function sameKeys(a, b) {
        const ka = Object.keys(a).sort(), kb2 = Object.keys(b).sort()
        if (ka.length !== kb2.length) return false
        for (let i = 0; i < ka.length; i++) if (ka[i] !== kb2[i] || a[ka[i]] !== b[kb2[i]]) return false
        return true
    }
    // Phím hiệu lực của một action (draft nếu có, không thì mặc định; action khoá luôn là mặc định).
    function keyEff(kbItem, keys) {
        return (kbItem.locked !== true && isKeyName(keys[kbItem.action])) ? keys[kbItem.action] : kbItem.default
    }
    // Cảnh báo: { action: [thông báo...] }. Chỉ cảnh báo, không chặn Apply.
    function keyConflicts(kb, keys, multiFn) {
        const byKey = ({})
        for (let i = 0; i < kb.length; i++) {
            const k = keyEff(kb[i], keys)
            if (!byKey[k]) byKey[k] = []
            byKey[k].push(kb[i].action)
        }
        const res = ({})
        for (let i = 0; i < kb.length; i++) {
            const a = kb[i].action
            const k = keyEff(kb[i], keys)
            const msgs = []
            const others = (byKey[k] || []).filter(x => x !== a)
            if (others.length > 0) msgs.push("trùng với " + others.join(", "))
            const own = fixedOwner[k]
            if (own && own.indexOf(a) < 0) msgs.push(k + " là phím cố định của app")
            if (multiFn && jumpKeys.indexOf(k) >= 0) msgs.push("1-3 dùng để nhảy function")
            if (msgs.length > 0) res[a] = msgs
        }
        return res
    }
}
