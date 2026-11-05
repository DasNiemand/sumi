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

    // ======================= 2b-3: OPTION theo manifest =======================
    // Lưu: config.apps.<id>.options = { "<key>": giá trị } chỉ chứa phần khác mặc định. Thiếu = mặc định của manifest.
    // opt = manifest.options[i] = {key, type, default, min?, max?, values?, label, locked?}.
    // Kiểu: bool, int, float, enum, intlist (1..16 số nguyên trong [min,max]), string (0..64 ký tự, không điều khiển),
    //       stringlist (0..32 chuỗi, mỗi chuỗi 1..64 ký tự gồm chữ/số và _ . * ? -; dùng cho glob class cửa sổ).
    readonly property var textTypes: ["int", "float", "intlist", "string", "stringlist"]
    readonly property var listItemRe: /^[A-Za-z0-9_.*?-]{1,64}$/

    function optSame(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    function isTextOpt(opt) { return textTypes.indexOf(opt.type) >= 0 }
    function isNum(v) { return typeof v === "number" && isFinite(v) }
    function noCtl(str) { for (let i = 0; i < str.length; i++) { const c = str.charCodeAt(i); if (c < 32 || c === 127) return false } return true }
    function optOk(opt, v) {
        switch (opt.type) {
        case "bool": return typeof v === "boolean"
        case "int": return isNum(v) && Math.floor(v) === v && v >= opt.min && v <= opt.max
        case "float": return isNum(v) && v >= opt.min && v <= opt.max
        case "enum": return typeof v === "string" && Array.isArray(opt.values) && opt.values.indexOf(v) >= 0
        case "intlist":
            if (!Array.isArray(v) || v.length < 1 || v.length > 16) return false
            for (let i = 0; i < v.length; i++) if (!isNum(v[i]) || Math.floor(v[i]) !== v[i] || v[i] < opt.min || v[i] > opt.max) return false
            return true
        case "string": return typeof v === "string" && v.length <= 64 && noCtl(v)
        case "stringlist":
            if (!Array.isArray(v) || v.length > 32) return false
            for (let i = 0; i < v.length; i++) if (typeof v[i] !== "string" || !listItemRe.test(v[i])) return false
            return true
        }
        return false
    }
    // Giá trị hiệu lực: khoá thì luôn mặc định; draft hợp lệ thì dùng; còn lại mặc định.
    function optEff(opt, draft) {
        return (opt.locked !== true && draft[opt.key] !== undefined && optOk(opt, draft[opt.key])) ? draft[opt.key] : opt.default
    }
    function optionsOf(data, app, optList) {
        const d = isObj(data) ? data : ({})
        const src = (isObj(d.apps) && isObj(d.apps[app])) ? d.apps[app] : ({})
        const o = isObj(src.options) ? src.options : ({})
        const out = ({})
        const l = Array.isArray(optList) ? optList : []
        for (let i = 0; i < l.length; i++) {
            const k = l[i].key
            if (o[k] !== undefined && optOk(l[i], o[k]) && !optSame(o[k], l[i].default)) out[k] = o[k]
        }
        return out
    }
    // Giữ nguyên mọi key option lạ (app khác phiên bản) và mọi key khác trong app.
    function withOptions(data, app, draft, optList) {
        const out = isObj(data) ? clone(data) : ({})
        out.version = 1
        if (!isObj(out.global)) out.global = ({})
        if (!isObj(out.apps)) out.apps = ({})
        if (!isObj(out.apps[app])) out.apps[app] = ({})
        const tgt = out.apps[app]
        const o = isObj(tgt.options) ? tgt.options : ({})
        for (let i = 0; i < optList.length; i++) {
            const opt = optList[i]
            if (opt.locked === true) continue
            const v = draft[opt.key]
            if (v !== undefined && optOk(opt, v) && !optSame(v, opt.default)) o[opt.key] = v
            else delete o[opt.key]
        }
        if (Object.keys(o).length === 0) delete tgt.options; else tgt.options = o
        tidyApp(out, app)
        return out
    }
    function validateOptions(draft, optList, app) {
        const e = []
        if (!/^[a-z][a-z0-9-]{1,31}$/.test(app)) e.push("tên app không hợp lệ: " + app)
        const known = ({})
        for (let i = 0; i < optList.length; i++) known[optList[i].key] = optList[i]
        for (var k in draft) {
            if (!known[k]) e.push("option lạ: " + k)
            else if (known[k].locked === true) e.push("option bị khoá: " + k)
            else if (!optOk(known[k], draft[k])) e.push("giá trị không hợp lệ cho " + k)
        }
        return e
    }
    function sameOptions(a, b) {
        const ka = Object.keys(a).sort(), kb2 = Object.keys(b).sort()
        if (ka.length !== kb2.length) return false
        for (let i = 0; i < ka.length; i++) if (ka[i] !== kb2[i] || !optSame(a[ka[i]], b[kb2[i]])) return false
        return true
    }
    function fmtNum(v) { return String(Math.round(v * 1000) / 1000) }
    function optFormat(opt, v) {
        switch (opt.type) {
        case "bool": return v === true ? "ON" : "OFF"
        case "float": return isNum(v) ? fmtNum(v) : String(v)
        case "intlist": return Array.isArray(v) ? v.join(", ") : String(v)
        case "stringlist": return (Array.isArray(v) && v.length > 0) ? v.join(", ") : "(NONE)"
        }
        return String(v)
    }
    // Văn bản ban đầu khi mở ô nhập.
    function optEditText(opt, v) {
        if (opt.type === "intlist" || opt.type === "stringlist") return Array.isArray(v) ? v.join(", ") : ""
        if (opt.type === "float") return isNum(v) ? fmtNum(v) : ""
        return String(v)
    }
    // Phân tích văn bản người nhập -> { ok, value, msg }
    function optParse(opt, text) {
        const t = String(text).trim()
        const bad = (m) => ({ ok: false, value: null, msg: m })
        if (opt.type === "int") {
            if (!/^-?[0-9]+$/.test(t)) return bad("CẦN SỐ NGUYÊN")
            const n = parseInt(t, 10)
            return optOk(opt, n) ? { ok: true, value: n, msg: "" } : bad("NGOÀI KHOẢNG " + opt.min + ".." + opt.max)
        }
        if (opt.type === "float") {
            if (!/^-?([0-9]+\.?[0-9]*|\.[0-9]+)$/.test(t)) return bad("CẦN SỐ (VD 0.32)")
            const n = Math.round(parseFloat(t) * 1000) / 1000
            return optOk(opt, n) ? { ok: true, value: n, msg: "" } : bad("NGOÀI KHOẢNG " + opt.min + ".." + opt.max)
        }
        if (opt.type === "intlist") {
            const parts = t.split(/[,\s]+/).filter(x => x !== "")
            if (parts.length < 1) return bad("CẦN ÍT NHẤT 1 SỐ")
            if (parts.length > 16) return bad("TỐI ĐA 16 SỐ")
            const v = []
            for (let i = 0; i < parts.length; i++) {
                if (!/^-?[0-9]+$/.test(parts[i])) return bad("KHÔNG PHẢI SỐ NGUYÊN: " + parts[i])
                const n = parseInt(parts[i], 10)
                if (n < opt.min || n > opt.max) return bad(parts[i] + " NGOÀI KHOẢNG " + opt.min + ".." + opt.max)
                v.push(n)
            }
            return { ok: true, value: v, msg: "" }
        }
        if (opt.type === "stringlist") {
            const parts = t.split(/[,\s]+/).filter(x => x !== "")
            const v = []
            for (let i = 0; i < parts.length; i++) {
                if (!listItemRe.test(parts[i])) return bad("KHÔNG HỢP LỆ: " + parts[i] + " (CHỈ CHỮ/SỐ _ . * ? -)")
                if (v.indexOf(parts[i]) < 0) v.push(parts[i])
            }
            if (v.length > 32) return bad("TỐI ĐA 32 MỤC")
            return { ok: true, value: v, msg: "" }
        }
        if (opt.type === "string") return optOk(opt, t) ? { ok: true, value: t, msg: "" } : bad("TỐI ĐA 64 KÝ TỰ, KHÔNG KÝ TỰ ĐIỀU KHIỂN")
        return bad("KIỂU NÀY KHÔNG NHẬP BẰNG TAY")
    }
    // Bước chỉnh bằng A/D: int ~ range/20 làm tròn xuống lũy thừa 10; float ~ range/50 (tối thiểu 0.01).
    function optStep(opt) {
        const range = opt.max - opt.min
        if (opt.type === "int") return Math.max(1, Math.pow(10, Math.floor(Math.log(range / 20) / Math.LN10 + 1e-9)))
        if (opt.type === "float") return Math.max(0.01, Math.round(range / 50 * 100) / 100)
        return 0
    }
    // Chỉnh một nấc theo dir = -1 | +1. Kiểu không chỉnh được thì trả nguyên giá trị.
    function optNudge(opt, v, dir) {
        if (opt.type === "bool") return !(v === true)
        if (opt.type === "enum") {
            const l = opt.values
            const i = l.indexOf(v)
            return l[((i < 0 ? 0 : i) + dir + l.length) % l.length]
        }
        if (opt.type === "int" || opt.type === "float") {
            const base = isNum(v) ? v : opt.default
            const n = Math.max(opt.min, Math.min(opt.max, base + dir * optStep(opt)))
            return opt.type === "int" ? Math.round(n) : Math.round(n * 1000) / 1000
        }
        return v
    }
    // Ký tự được phép gõ vào ô nhập của kiểu opt.
    function optInputOk(opt, ch) {
        if (typeof ch !== "string" || ch.length !== 1) return false
        const c = ch.charCodeAt(0)
        if (c < 32 || c === 127) return false
        switch (opt.type) {
        case "int": return /[0-9-]/.test(ch)
        case "float": return /[0-9.-]/.test(ch)
        case "intlist": return /[0-9, -]/.test(ch)
        case "stringlist": return /[A-Za-z0-9_.*?, -]/.test(ch)
        case "string": return true
        }
        return false
    }
    // Dòng gợi ý khoảng/định dạng cho option đang chọn.
    function optHint(opt) {
        if (!opt) return ""
        let h = opt.key + "   "
        if (opt.type === "int" || opt.type === "float") h += opt.min + ".." + opt.max
        else if (opt.type === "intlist") h += "1-16 SỐ, MỖI SỐ " + opt.min + ".." + opt.max
        else if (opt.type === "enum") h += opt.values.join(" / ")
        else if (opt.type === "stringlist") h += "GLOB CÁCH NHAU BẰNG DẤU PHẨY (CHỮ/SỐ _ . * ? -)"
        else if (opt.type === "string") h += "TỐI ĐA 64 KÝ TỰ"
        else h += "BẬT / TẮT"
        return h
    }
    // Cảnh báo chéo giữa các option (chỉ cảnh báo, không chặn): { key: [thông báo] }.
    // Khớp luật của tools/validate.py: timer.defaultMinutes nên nằm trong timer.presets.
    function optConflicts(optList, draft) {
        const res = ({})
        let pres = null, def = null
        for (let i = 0; i < optList.length; i++) {
            if (optList[i].key === "timer.presets") pres = optList[i]
            if (optList[i].key === "timer.defaultMinutes") def = optList[i]
        }
        if (pres !== null && def !== null) {
            const pv = optEff(pres, draft), dv = optEff(def, draft)
            if (Array.isArray(pv) && pv.indexOf(dv) < 0) res["timer.defaultMinutes"] = [dv + " không nằm trong timer.presets"]
        }
        return res
    }

    // ======================= 2b-4: OBJECT theo function =======================
    // Lưu: config.apps.<id>.objects[<function>] = { id, speed, interactive } (grid, nếu có, giữ nguyên: hub không sửa).
    // Hub dùng lại giao diện OPTIONS với danh sách option "ảo" sinh từ manifest.functions[]: khoá "<function>.<field>".
    function objectOptsOf(app) {
        const l = []
        const fns = (app !== null && app !== undefined && Array.isArray(app.functions)) ? app.functions : []
        for (let i = 0; i < fns.length; i++) {
            const f = fns[i]
            const objs = Array.isArray(f.objects) ? f.objects : []
            if (objs.length === 0 || typeof f.id !== "string") continue
            const lab = String(f.label || f.id).toUpperCase().slice(0, 18)
            if (objs.length >= 2) l.push({ key: f.id + ".id", type: "enum", values: objs, default: objs.indexOf(f.defaultObject) >= 0 ? f.defaultObject : objs[0], label: lab + " OBJECT", locked: false })
            l.push({ key: f.id + ".speed", type: "float", default: 1, min: 0, max: 5, label: lab + " SPEED", locked: false })
            l.push({ key: f.id + ".interactive", type: "bool", default: true, label: lab + " DRAG", locked: false })
        }
        return l
    }
    function splitObjKey(key) { const i = key.lastIndexOf("."); return i > 0 ? [key.slice(0, i), key.slice(i + 1)] : null }
    function objectsOf(data, app, optList) {
        const d = isObj(data) ? data : ({})
        const src = (isObj(d.apps) && isObj(d.apps[app]) && isObj(d.apps[app].objects)) ? d.apps[app].objects : ({})
        const out = ({})
        for (let i = 0; i < optList.length; i++) {
            const kk = splitObjKey(optList[i].key)
            if (kk === null || !isObj(src[kk[0]])) continue
            const v = src[kk[0]][kk[1]]
            if (v !== undefined && optOk(optList[i], v) && !optSame(v, optList[i].default)) out[optList[i].key] = v
        }
        return out
    }
    function withObjects(data, app, draft, optList) {
        const out = isObj(data) ? clone(data) : ({})
        out.version = 1
        if (!isObj(out.global)) out.global = ({})
        if (!isObj(out.apps)) out.apps = ({})
        if (!isObj(out.apps[app])) out.apps[app] = ({})
        const tgt = out.apps[app]
        const objs = isObj(tgt.objects) ? tgt.objects : ({})
        for (let i = 0; i < optList.length; i++) {
            const opt = optList[i]
            const kk = splitObjKey(opt.key)
            if (kk === null || opt.locked === true) continue
            const v = draft[opt.key]
            if (!isObj(objs[kk[0]])) objs[kk[0]] = ({})
            if (v !== undefined && optOk(opt, v) && !optSame(v, opt.default)) objs[kk[0]][kk[1]] = v
            else delete objs[kk[0]][kk[1]]
        }
        for (var fnk in objs) if (!isObj(objs[fnk]) || Object.keys(objs[fnk]).length === 0) delete objs[fnk]
        if (Object.keys(objs).length === 0) delete tgt.objects; else tgt.objects = objs
        tidyApp(out, app)
        return out
    }
}
