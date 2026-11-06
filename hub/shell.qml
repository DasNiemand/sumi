import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "lib"

// SUMI 墨 - hub (GĐ2a launcher + GĐ2b theme/font/keys/options/objects/preview + GĐ3b store). Liệt kê app đã cài qua `sumi list --json`, chạy app / function.
// Mở bằng `sumi hub`. Trang APPS: W/S chọn app, A/D chọn function (app daemon), Enter chạy, T/F/K mở cài đặt (theme/font/keys), Esc/Q đóng.
// Cài đặt có 3 tab (Tab / Shift+Tab / phím 1-3 để đổi), Q/E đổi phạm vi, Space áp dụng, Esc quay lại:
//   THEME: W/S phạm vi, A/D preset, -/= tint, ,/. độ đậm mực, Enter áp dụng, R kế thừa.
//   FONT : W/S vai trò, Enter mở bộ chọn (gõ để lọc, mũi tên chọn, Tab đổi lọc JA/MONO), R đặt lại hàng, X đặt lại hết.
//   KEYS : W/S action, Enter rồi bấm phím để gán, R về mặc định hàng, X về mặc định hết. Trùng phím chỉ cảnh báo.
//   OPTIONS: W/S hàng, A/D chỉnh (bool/enum/số), Enter sửa (bool/enum đổi giá trị; số/danh sách mở ô nhập, Enter lưu nháp, Esc huỷ), R về mặc định hàng, X hết.
//            Option do manifest khai báo (apps.<id>.options); chỉ ghi phần khác mặc định; Space = apply như các tab khác.
//   PREVIEW: phím V (trang APPS và settings) bật/tắt khung 16:9 ở góc dưới trái: nạp View.qml của app (previewMode) ở 1920x1080 thu nhỏ,
//            phản ánh BẢN NHÁP theme/font/object đang sửa. Chỉ một preview một lúc. Hub (scope HUB) và Store không có preview.
//   AUTO-REVERT: OPTIONS > scope HUB > AUTO-REVERT (tắt mặc định). Bật thì sau mỗi Apply có thanh đếm ngược 10/15/30 s: Enter giữ, Esc hoặc hết giờ
//            hoặc đóng hub = hoàn tác (áp lại config trước đó qua `sumi config apply`). Các phím khác bị chặn trong lúc đếm.
//   CRT:     bật máy (đường kẻ -> mở ra) và tắt máy (thu lại) cho cửa sổ hub, scanline + thanh quét + glitch ở tiêu đề.
//            OPTIONS > HUB: CRT BOOT MS / CRT OUTRO MS (0 = tắt hiệu ứng tương ứng); scanlines, scanlineOpacity, glitch lấy từ look (global).
//   NOTICE:  mở hub thì chạy nền `sumi update --check` và `sumi store registry` (có cache); có bản mới thì hiện ở thanh trên trang APPS.
// Trang APPS bấm G mở STORE (registry sumi-index qua `sumi store ... --json`): W/S chọn, Enter cài/cập nhật (qua màn xác nhận),
//   X gỡ, B xem bản sao lưu để khôi phục, R tải lại registry, Esc quay lại. Mọi thao tác ghi do `sumi store` làm; hub chỉ hiển thị.
ShellRoot {
    id: root

    // ===== Màu Noctalia + config (appId "hub") =====
    SumiColors { id: colors }
    SumiConfig { id: cfg; appId: "hub" }
    SumiConfigEdit { id: ce }
    SumiStoreLogic { id: sl }
    // theme của hub: hub.theme -> global.theme -> paper
    readonly property string hubTheme: {
        const h = cfg.data.hub
        return (h !== null && typeof h === "object" && typeof h.theme === "string") ? h.theme : cfg.look("theme", "paper")
    }
    SumiTheme {
        id: th
        preset: root.hubTheme
        bgColor: colors.adapter.surface
        fgColor: colors.adapter.on_surface
        accentColor: colors.adapter.primary
        tint: cfg.lookNum("tint", 0, 0.6, 0.12)
        inkDarken: cfg.lookNum("inkDarken", 1, 2.5, 1.5)
    }

    readonly property string fontTitle: cfg.font("title", "sans-serif")
    readonly property string fontLabel: cfg.font("label", "sans-serif")
    readonly property string fontData: cfg.font("data", "monospace")
    readonly property string fontKanji: cfg.font("kanji", Qt.application.font.family)

    readonly property string sumiBin: Quickshell.env("HOME") + "/.local/bin/sumi"
    readonly property string monName: Quickshell.env("SUMI_MONITOR") || ""
    readonly property var targetScreen: {
        const sc = Quickshell.screens
        for (let i = 0; i < sc.length; i++) if (sc[i].name === monName) return sc[i]
        return sc.length > 0 ? sc[0] : null
    }

    // ===== Danh sách app =====
    property var apps: []
    property int sel: 0
    property int fnSel: 0
    property string errorText: ""
    readonly property var cur: (apps.length > 0 && sel >= 0 && sel < apps.length) ? apps[sel] : null
    readonly property var curFns: (cur && Array.isArray(cur.functions)) ? cur.functions : []

    property string lastAppsJson: ""
    function parseApps(t) {
        if (t === root.lastAppsJson && root.errorText === "") return     // không đổi -> không dựng lại list
        root.lastAppsJson = t
        let a = []
        try { a = JSON.parse(t) } catch (e) { root.errorText = "sumi list trả về JSON không hợp lệ"; return }
        if (!Array.isArray(a)) { root.errorText = "sumi list trả về dữ liệu lạ"; return }
        root.errorText = ""
        const keepId = (root.cur !== null) ? root.cur.id : ""
        root.apps = a
        let i = -1
        for (let k = 0; k < a.length; k++) if (a[k].id === keepId) { i = k; break }
        root.sel = i >= 0 ? i : Math.max(0, Math.min(root.sel, a.length - 1))
        root.fnSel = Math.max(0, Math.min(root.fnSel, root.curFns.length - 1))
    }
    function move(d) {
        if (apps.length === 0) return
        sel = (sel + d + apps.length) % apps.length
        fnSel = 0
    }
    function moveFn(d) {
        if (curFns.length === 0 || !cur || cur.kind !== "daemon") return
        fnSel = (fnSel + d + curFns.length) % curFns.length
    }
    function runSelected() {
        if (!cur) return
        const cmd = [sumiBin, cur.id]
        if (cur.kind === "daemon") {
            if (curFns.length === 0) return
            cmd.push(curFns[Math.max(0, Math.min(fnSel, curFns.length - 1))].id)
        }
        Quickshell.execDetached(cmd)
        quitTimer.restart()           // đóng hub để app nhận focus bàn phím
    }
    // Đang cài/gỡ thì không đóng hub giữa chừng. Đang đếm ngược auto-revert mà đóng hub = chưa xác nhận -> hoàn tác.
    function dismiss() {
        if (storeBusy) return
        if (revertActive) { revertActive = false; Quickshell.execDetached([sumiBin, "config", "apply", revertPrev]) }
        finish()
    }

    // ===== Trang cài đặt: THEME (2b-1), FONT + KEYS (2b-2) =====
    property string page: "apps"            // apps | theme | font | keys
    readonly property bool inSettings: page === "theme" || page === "font" || page === "keys" || page === "options" || page === "objects"
    readonly property var tabIds: ["theme", "font", "keys", "options", "objects"]
    property int scopeSel: 0
    property string keepScope: "global"     // phạm vi người dùng chọn gần nhất; đổi tab thì dùng lại (trang không có thì lấy mục đầu)
    function appById(id) {
        for (let i = 0; i < apps.length; i++) if (apps[i].id === id) return apps[i]
        return null
    }
    function hasKeybinds(a) { return a !== null && Array.isArray(a.keybinds) && a.keybinds.length > 0 }
    function hasOptions(a) { return a !== null && Array.isArray(a.options) && a.options.length > 0 }
    function hasObjects(a) { return a !== null && ce.objectOptsOf(a).length > 0 }
    // THEME: global, hub, các app. FONT: global + các app (hub theo global). KEYS / OPTIONS: chỉ app có keybind / option.
    function scopeListFor(p) {
        const l = []
        if (p === "theme") { l.push({ id: "global", name: "GLOBAL" }); l.push({ id: "hub", name: "HUB" }) }
        else if (p === "font") l.push({ id: "global", name: "GLOBAL" })
        else if (p === "options") l.push({ id: "hub", name: "HUB" })
        for (let i = 0; i < apps.length; i++) {
            if (p === "keys" && !hasKeybinds(apps[i])) continue
            if (p === "options" && !hasOptions(apps[i])) continue
            if (p === "objects" && !hasObjects(apps[i])) continue
            l.push({ id: apps[i].id, name: String(apps[i].name).toUpperCase() })
        }
        return l
    }
    readonly property var scopes: scopeListFor(page)
    readonly property bool hasScope: scopes.length > 0
    readonly property string scopeId: hasScope ? scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].id : ""
    readonly property string scopeName: hasScope ? scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].name : ""
    readonly property var scopeApp: appById(scopeId)

    property string applyMsg: ""
    property string applyErr: ""
    property bool applyOk: false

    // ----- THEME -----
    property var draft: ({ theme: null, tint: null, inkDarken: null })
    readonly property var stored: ce.lookOf(cfg.data, scopeId)
    readonly property var inh: ce.inherited(cfg.data, scopeId)
    readonly property string effTheme: draft.theme !== null ? draft.theme : inh.theme
    readonly property real effTint: draft.tint !== null ? draft.tint : inh.tint
    readonly property real effInk: draft.inkDarken !== null ? draft.inkDarken : inh.inkDarken
    readonly property var curDerived: th.derive(effTheme, effTint, effInk)
    readonly property bool tintEditable: scopeId !== "hub"
    readonly property bool dirty: !ce.sameLook(draft, stored)
    readonly property bool blocked: curDerived.contrast < th.minContrast
    readonly property bool weak: !blocked && curDerived.contrast < th.goodContrast

    // ----- FONT -----
    property var fontDraft: ({ title: null, label: null, data: null, numeral: null, kanji: null })
    property int fontSel: 0
    readonly property var fontStored: ce.fontsOf(cfg.data, scopeId)
    readonly property var fontInh: ce.fontsInherited(cfg.data, scopeId)
    readonly property bool fontDirty: !ce.sameFonts(fontDraft, fontStored)
    readonly property var fontRows: scopeId === "global" ? ce.roles : ce.fontRolesOf(scopeApp)
    readonly property string pickRole: fontRows.length > 0 ? fontRows[Math.max(0, Math.min(fontSel, fontRows.length - 1))] : ""
    property var fontList: []
    property bool fontListLoaded: false
    readonly property var fontIndex: {
        const m = ({})
        for (let i = 0; i < fontList.length; i++) m[fontList[i].name.toLowerCase()] = fontList[i]
        return m
    }
    property bool pickOpen: false
    property string pickQuery: ""
    property bool pickFilter: true
    property int pickIdx: 0
    readonly property string pickKind: ce.filterKind(pickRole)
    readonly property var pickItems: [{ name: "", isDefault: true, mono: false, ja: false }].concat(ce.filterFonts(fontList, pickQuery, pickFilter ? pickKind : ""))

    function fontEff(role) { return fontDraft[role] !== null ? fontDraft[role] : fontInh[role] }
    // family thực dùng để vẽ ("" = mặc định hệ thống cho kanji)
    function fam(role) {
        const v = fontEff(role)
        return v !== "" ? v : (role === "kanji" ? Qt.application.font.family : ce.fontDefaults[role])
    }
    function fontShown(role) {
        const v = fontEff(role)
        return v !== "" ? v : (role === "kanji" ? "SYSTEM DEFAULT" : ce.fontDefaults[role])
    }
    function fontGeneric(v) { return v === "sans-serif" || v === "serif" || v === "monospace" }
    function fontMissing(role) {
        const v = fontEff(role)
        return fontListLoaded && v !== "" && !fontGeneric(v) && fontIndex[v.toLowerCase()] === undefined
    }
    function fontNoJa(role) {
        const v = fontEff(role)
        if (role !== "kanji" || !fontListLoaded || v === "" || fontGeneric(v)) return false
        const f = fontIndex[v.toLowerCase()]
        return f !== undefined && !f.ja
    }
    readonly property string fontWarn: {
        let w = ""
        for (let i = 0; i < fontRows.length; i++) {
            const r = fontRows[i]
            if (fontMissing(r)) { w = r.toUpperCase() + ": font không còn trong hệ thống"; break }
            if (fontNoJa(r)) { w = "KANJI: font không có glyph tiếng Nhật, chữ 墨 紙 sẽ bị ô vuông"; break }
        }
        return w
    }
    function ensureFonts() { if (!fontListLoaded && !fcProc.running) fcProc.running = true }
    function setFont(role, v) {
        const d = JSON.parse(JSON.stringify(fontDraft))
        d[role] = v
        fontDraft = d
        applyMsg = ""; applyErr = ""
    }
    function resetFontRow() { if (pickRole !== "") setFont(pickRole, null) }
    function resetFontAll() {
        fontDraft = { title: null, label: null, data: null, numeral: null, kanji: null }
        applyMsg = ""; applyErr = ""
    }
    function moveFontRow(d) { if (fontRows.length > 0) fontSel = (fontSel + d + fontRows.length) % fontRows.length }
    function openPicker() {
        if (pickRole === "") return
        ensureFonts()
        pickQuery = ""; pickFilter = true
        pickOpen = true
        const cur = fontDraft[pickRole]
        let i = 0
        if (cur !== null) for (let k = 0; k < pickItems.length; k++) if (pickItems[k].name === cur) { i = k; break }
        pickIdx = i
    }
    function pickMove(d) { pickIdx = Math.max(0, Math.min(pickItems.length - 1, pickIdx + d)) }
    function choosePicked() {
        const it = pickItems[Math.max(0, Math.min(pickIdx, pickItems.length - 1))]
        if (it) setFont(pickRole, it.isDefault ? null : it.name)
        pickOpen = false
    }
    function pickerKey(event) {
        const k = event.key
        const ar = event.isAutoRepeat
        if (k === Qt.Key_Escape) { if (!ar) pickOpen = false }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) choosePicked() }
        else if (k === Qt.Key_Up) pickMove(-1)
        else if (k === Qt.Key_Down) pickMove(1)
        else if (k === Qt.Key_PageUp) pickMove(-7)
        else if (k === Qt.Key_PageDown) pickMove(7)
        else if (k === Qt.Key_Home) pickIdx = 0
        else if (k === Qt.Key_End) pickIdx = pickItems.length - 1
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { if (!ar && pickKind !== "") { pickFilter = !pickFilter; pickIdx = 0 } }
        else if (k === Qt.Key_Backspace) { if (pickQuery.length > 0) { pickQuery = pickQuery.slice(0, -1); pickIdx = 0 } }
        else if (event.text.length === 1 && event.text >= " " && event.text !== "\u007f"
                 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) { pickQuery += event.text; pickIdx = 0 }
    }

    // ----- KEYS -----
    property var keyDraft: ({})
    property int keySel: 0
    property bool capturing: false
    property string capMsg: ""
    readonly property var kbList: hasKeybinds(scopeApp) ? scopeApp.keybinds : []
    readonly property var keyStored: ce.keysOf(cfg.data, scopeId)
    readonly property bool keyDirty: !ce.sameKeys(keyDraft, keyStored)
    readonly property bool multiFn: scopeApp !== null && Array.isArray(scopeApp.functions) && scopeApp.functions.length > 1
    readonly property var keyConf: ce.keyConflicts(kbList, keyDraft, multiFn)
    readonly property int keyConfCount: Object.keys(keyConf).length
    readonly property var curKb: (kbList.length > 0 && keySel >= 0 && keySel < kbList.length) ? kbList[keySel] : null
    function keyShown(kbItem) { return ce.keyEff(kbItem, keyDraft) }
    function setKey(action, key) {
        let item = null
        for (let i = 0; i < kbList.length; i++) if (kbList[i].action === action) item = kbList[i]
        if (item === null) return
        if (item.locked === true) { capMsg = "LOCKED"; return }
        const d = JSON.parse(JSON.stringify(keyDraft))
        if (key === item.default) delete d[action]; else d[action] = key
        keyDraft = d
        applyMsg = ""; applyErr = ""
    }
    function moveKeyRow(d) { if (kbList.length > 0) keySel = (keySel + d + kbList.length) % kbList.length }
    function startCapture() {
        if (curKb === null) return
        if (curKb.locked === true) { capMsg = "LOCKED: " + curKb.action + " không gán lại được"; return }
        capMsg = ""; capturing = true
    }
    function captureEvent(event) {
        if (event.isAutoRepeat) return
        const k = event.key
        if (k === Qt.Key_Escape) { capturing = false; capMsg = ""; return }
        if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Meta
            || k === Qt.Key_AltGr || k === Qt.Key_CapsLock || k === Qt.Key_Super_L || k === Qt.Key_Super_R) return
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) { capMsg = "KHÔNG DÙNG CTRL / ALT / SUPER"; return }
        const r = ce.captureResult(k)
        if (!r.ok) { capMsg = r.msg.toUpperCase(); return }
        setKey(curKb.action, r.key)
        capturing = false; capMsg = ""
    }
    function resetKeyRow() {
        if (curKb === null || curKb.locked === true) return
        const d = JSON.parse(JSON.stringify(keyDraft))
        delete d[curKb.action]
        keyDraft = d
        applyMsg = ""; applyErr = ""
    }
    function resetKeyAll() { keyDraft = ({}); applyMsg = ""; applyErr = "" }

    // ----- OPTIONS (option theo manifest) -----
    property var optDraft: ({})
    property int optSel: 0
    property bool optEditing: false
    property string optBuf: ""
    property string optMsg: ""
    // OPTIONS: option khai trong manifest. OBJECTS: danh sách "ảo" sinh từ manifest.functions[] (xem SumiConfigEdit.objectOptsOf).
    readonly property var optList: page === "objects" ? (hasObjects(scopeApp) ? ce.objectOptsOf(scopeApp) : []) : ((page === "options" && scopeId === "hub") ? ce.hubOptsList() : (hasOptions(scopeApp) ? scopeApp.options : []))
    readonly property var optStored: page === "objects" ? ce.objectsOf(cfg.data, scopeId, optList) : ((page === "options" && scopeId === "hub") ? ce.hubOptionsOf(cfg.data) : ce.optionsOf(cfg.data, scopeId, optList))
    readonly property bool optDirty: !ce.sameOptions(optDraft, optStored)
    readonly property var optConf: ce.optConflicts(optList, optDraft)
    readonly property var curOpt: (optList.length > 0 && optSel >= 0 && optSel < optList.length) ? optList[optSel] : null
    function optShown(o) { return ce.optEff(o, optDraft) }
    function setOpt(opt, v) {
        if (opt.locked === true) { optMsg = "LOCKED"; return }
        const d = JSON.parse(JSON.stringify(optDraft))
        if (ce.optSame(v, opt.default)) delete d[opt.key]; else d[opt.key] = v
        optDraft = d
        optMsg = ""; applyMsg = ""; applyErr = ""
    }
    function moveOptRow(d) {
        if (optList.length === 0) return
        optSel = (optSel + d + optList.length) % optList.length
        optMsg = ""
    }
    function nudgeOpt(dir) {
        const o = curOpt
        if (o === null) return
        if (o.locked === true) { optMsg = "LOCKED"; return }
        if (!(o.type === "bool" || o.type === "enum" || o.type === "int" || o.type === "float")) { optMsg = "KIỂU NÀY SỬA BẰNG ENTER"; return }
        setOpt(o, ce.optNudge(o, optShown(o), dir))
    }
    function enterOpt() {
        const o = curOpt
        if (o === null) return
        if (o.locked === true) { optMsg = "LOCKED: " + o.key + " không đổi được"; return }
        if (o.type === "bool" || o.type === "enum") { setOpt(o, ce.optNudge(o, optShown(o), 1)); return }
        optBuf = ce.optEditText(o, optShown(o)); optMsg = ""; optEditing = true
    }
    function optEditKey(event) {
        const k = event.key
        const o = curOpt
        if (o === null) { optEditing = false; return }
        if (event.isAutoRepeat && k !== Qt.Key_Backspace) return
        if (k === Qt.Key_Escape) { optEditing = false; optMsg = ""; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            const r = ce.optParse(o, optBuf)
            if (!r.ok) { optMsg = r.msg; return }
            setOpt(o, r.value)
            optEditing = false
            return
        }
        if (k === Qt.Key_Backspace) { optBuf = optBuf.slice(0, -1); optMsg = ""; return }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        const ch = event.text
        if (ce.optInputOk(o, ch)) {
            if (optBuf.length < 200) { optBuf += ch; optMsg = "" }
        } else if (typeof ch === "string" && ch.length === 1 && ch.charCodeAt(0) >= 32) {
            optMsg = "KÝ TỰ KHÔNG HỢP LỆ: " + ch
        }
    }
    function resetOptRow() {
        const o = curOpt
        if (o === null || o.locked === true) return
        const d = JSON.parse(JSON.stringify(optDraft))
        delete d[o.key]
        optDraft = d
        optMsg = ""; applyMsg = ""; applyErr = ""
    }
    function resetOptAll() { optDraft = ({}); optMsg = ""; applyMsg = ""; applyErr = "" }

    // ----- chung -----
    function presetKanji(n) {
        return n === "paper" ? "紙" : n === "ink" ? "墨" : n === "mono-white" ? "白" : n === "mono-black" ? "黒" : n === "accent" ? "彩" : "随"
    }
    function scopeTag(p, id) {
        if (p === "theme") { const lk = ce.lookOf(cfg.data, id); return lk.theme !== null ? lk.theme.toUpperCase() : "INHERIT" }
        if (p === "font") {
            const f = ce.fontsOf(cfg.data, id)
            let n = 0
            for (let i = 0; i < ce.roles.length; i++) if (f[ce.roles[i]] !== null) n++
            return n > 0 ? (n + " SET") : "INHERIT"
        }
        if (p === "objects") {
            const ao = appById(id)
            const n4 = Object.keys(ce.objectsOf(cfg.data, id, ao !== null ? ce.objectOptsOf(ao) : [])).length
            return n4 > 0 ? (n4 + " CUSTOM") : "DEFAULT"
        }
        if (p === "options" && id === "hub") return Object.keys(ce.hubOptionsOf(cfg.data)).length > 0 ? (Object.keys(ce.hubOptionsOf(cfg.data)).length + " CUSTOM") : "DEFAULT"
        if (p === "options") {
            const a = appById(id)
            const n3 = Object.keys(ce.optionsOf(cfg.data, id, a !== null && Array.isArray(a.options) ? a.options : [])).length
            return n3 > 0 ? (n3 + " CUSTOM") : "DEFAULT"
        }
        const n2 = Object.keys(ce.keysOf(cfg.data, id)).length
        return n2 > 0 ? (n2 + " CUSTOM") : "DEFAULT"
    }
    function tabDirty(id) { return id === "theme" ? dirty : (id === "font" ? fontDirty : (id === "keys" ? keyDirty : (id === page ? optDirty : false))) }
    function loadDraft() {
        draft = ce.lookOf(cfg.data, scopeId)
        fontDraft = ce.fontsOf(cfg.data, scopeId)
        keyDraft = ce.keysOf(cfg.data, scopeId)
        optDraft = optStored
        fontSel = 0; keySel = 0; optSel = 0
        pickOpen = false; capturing = false; capMsg = ""
        optEditing = false; optBuf = ""; optMsg = ""
        applyMsg = ""; applyErr = ""
    }
    // Vào trang p với phạm vi id (không có trong danh sách thì về phần tử đầu).
    function enterPage(p, id) {
        page = p
        const ids = scopeListFor(p).map(s => s.id)
        const i = ids.indexOf(id)
        scopeSel = i >= 0 ? i : 0
        if (p === "font") ensureFonts()
        loadDraft()
    }
    function openSettings(p) { enterPage(p, ((p === "keys" || p === "options" || p === "objects") && cur !== null) ? cur.id : keepScope) }
    function closeSettings() { page = "apps"; pickOpen = false; capturing = false; optEditing = false }
    function cycleTab(d) {
        const i = tabIds.indexOf(page)
        enterPage(tabIds[(i + d + tabIds.length) % tabIds.length], keepScope)
    }
    function setScope(i) {
        if (scopes.length === 0) return
        scopeSel = Math.max(0, Math.min(i, scopes.length - 1))
        keepScope = scopeId
        loadDraft()
    }
    function moveScope(d) { if (scopes.length > 0) setScope((scopeSel + d + scopes.length) % scopes.length) }

    function setPreset(name) {
        draft = { theme: name, tint: draft.tint, inkDarken: draft.inkDarken }
        applyMsg = ""; applyErr = ""
    }
    function movePreset(d) {
        const l = ce.themes
        let i = l.indexOf(effTheme)
        if (i < 0) i = 0
        setPreset(l[(i + d + l.length) % l.length])
    }
    function nudge(key, d) {
        if (!tintEditable) return
        if (key === "tint") draft = { theme: draft.theme, tint: Math.max(0, Math.min(0.6, ce.round(effTint + d, 2))), inkDarken: draft.inkDarken }
        else draft = { theme: draft.theme, tint: draft.tint, inkDarken: Math.max(1, Math.min(2.5, ce.round(effInk + d, 1))) }
        applyMsg = ""; applyErr = ""
    }
    function inheritScope() {
        draft = { theme: null, tint: null, inkDarken: null }
        applyMsg = ""; applyErr = ""
    }

    // ===== CRT (GĐ4b): bật máy / tắt máy cho cửa sổ hub =====
    // Hub dùng Scale transform lên card (đường kẻ ngang -> mở theo chiều dọc), nên không phải bọc lại toàn bộ nội dung.
    readonly property var hubOpt: ce.hubOptsEff(cfg.data)
    readonly property int crtBootMs: hubOpt.crtBootMs
    readonly property int crtOutroMs: hubOpt.crtOutroMs
    readonly property bool crtScan: cfg.lookBool("scanlines", true)
    readonly property real crtScanOpacity: cfg.lookNum("scanlineOpacity", 0, 0.3, 0.05)
    readonly property bool crtGlitch: cfg.lookBool("glitch", true)
    property real bp: 0                       // 0..1: tiến độ bật máy
    property real outP: 0                     // 0..1: tiến độ tắt máy
    property bool closing: false
    property real bdIn: 0                     // nền tối hiện dần
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }
    readonly property real crtLineW: crtBootMs <= 0 ? 1 : Math.min(1, bp / 0.28)
    readonly property real crtOpenH: crtBootMs <= 0 ? 1 : clamp01((bp - 0.28) / 0.42)
    readonly property real crtContentP: crtBootMs <= 0 ? 1 : clamp01((bp - 0.55) / 0.45)
    readonly property real crtVCollapse: clamp01((outP - 0.34) / 0.40)
    readonly property real crtHCollapse: clamp01((outP - 0.74) / 0.26)
    readonly property real crtXs: Math.max(0.002, crtLineW * (1 - crtHCollapse))
    readonly property real crtYs: Math.max(0.004, crtOpenH * (1 - crtVCollapse))
    readonly property real crtFlicker: (crtBootMs > 0 && bp < 0.04) ? 0 : ((crtBootMs > 0 && bp < 0.4 && Math.floor(bp * 70) % 2 === 1) ? 0.5 : 1)
    property bool glitchOn: false
    property real gdx: 3
    readonly property bool glitchNow: glitchOn || (closing && outP < 0.34)
    NumberAnimation { id: bootAnim; target: root; property: "bp"; from: 0; to: 1; duration: Math.max(1, root.crtBootMs); running: root.crtBootMs > 0 }
    NumberAnimation { id: bdAnim; target: root; property: "bdIn"; from: 0; to: 1; duration: 180; running: true }
    NumberAnimation { id: outAnim; target: root; property: "outP"; from: 0; to: 1; duration: Math.max(1, root.crtOutroMs); onFinished: Qt.quit() }
    Timer {
        id: glitchTimer
        interval: 2400; repeat: true
        running: root.crtGlitch && root.crtContentP >= 1 && !root.closing
        onTriggered: {
            root.gdx = 2 + Math.random() * 4
            root.glitchOn = true
            glitchOff.restart()
            glitchTimer.interval = 1800 + Math.random() * 3200
        }
    }
    Timer { id: glitchOff; interval: 110; repeat: false; onTriggered: root.glitchOn = false }
    // Thoát hub: có hiệu ứng tắt máy thì phát rồi mới thoát (outAnim.onFinished -> Qt.quit()).
    function finish() {
        if (closing) return
        if (crtOutroMs <= 0) { Qt.quit(); return }
        closing = true; outP = 0
        outAnim.start()
    }

    // ===== THÔNG BÁO BẢN MỚI (GĐ4b): chạy nền một lần sau khi mở hub; offline hoặc lỗi thì im lặng =====
    property string noteCore: ""
    property int noteApps: 0
    readonly property string noteText: sl.noteLine(noteCore, noteApps)
    Process {
        id: noteCoreProc
        command: [root.sumiBin, "update", "--check", "--json"]
        stdout: StdioCollector { onStreamFinished: { root.noteCore = sl.coreNote(this.text); noteAppsProc.running = true } }
    }
    Process {
        id: noteAppsProc
        command: [root.sumiBin, "store", "registry", "--json"]
        stdout: StdioCollector { onStreamFinished: root.noteApps = sl.appsNote(this.text) }
    }
    Timer { interval: 800; running: true; repeat: false; onTriggered: noteCoreProc.running = true }

    // ===== AUTO-REVERT (GĐ2b-6): sau Apply, không xác nhận trong vài giây thì hoàn tác =====
    // Bật bằng OPTIONS > HUB > AUTO-REVERT (config.hub.autoRevert, hub.autoRevertSec 10/15/30). Mặc định tắt.
    // Hoàn tác = áp lại bản config trước đó qua chính `sumi config apply` (có backup như mọi lần ghi).
    property string applyKind: "apply"          // apply | revert (loại lệnh applyProc đang chạy)
    property string revertPrev: ""              // JSON config trước lần apply gần nhất
    property bool revertArm: false              // lần apply đang chạy có bật đếm ngược sau khi xong không
    property bool revertActive: false
    property int revertLeft: 0
    property int revertTotal: 0
    function revertArmed() {
        if (page === "options" && scopeId === "hub") return false    // đổi chính cài đặt auto-revert thì không tự hoàn tác
        return ce.autoRevertOf(cfg.data).on
    }
    function applyDone(code) {
        applyOk = (code === 0)
        if (applyKind === "revert") {
            applyMsg = code === 0 ? "REVERTED" : ("REVERT FAILED (" + code + ")")
            if (code === 0) applyErr = ""
            applyKind = "apply"
            return
        }
        applyMsg = code === 0 ? "APPLIED" : ("FAILED (" + code + ")")
        if (code === 0) {
            applyErr = ""
            if (revertArm) {
                revertTotal = ce.autoRevertOf(cfg.data).sec
                revertLeft = revertTotal
                revertActive = true
            }
        }
        revertArm = false
    }
    function revertTick() {
        if (!revertActive) return
        revertLeft = revertLeft - 1
        if (revertLeft <= 0) doRevert()
    }
    function keepConfig() {
        if (!revertActive) return
        revertActive = false
        applyOk = true; applyMsg = "KEPT"; applyErr = ""
    }
    function doRevert() {
        if (!revertActive) return
        revertActive = false
        if (applyProc.running) { applyOk = false; applyMsg = "REVERT FAILED"; applyErr = "đang bận ghi config"; return }
        applyKind = "revert"; applyOk = false; applyErr = ""; applyMsg = "REVERTING..."
        applyProc.command = [sumiBin, "config", "apply", revertPrev]
        applyProc.running = true
    }
    function revertKey(event) {
        const k = event.key
        if (event.isAutoRepeat) return
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) keepConfig()
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Delete) doRevert()
    }
    Timer { id: revertTimer; interval: 1000; repeat: true; running: root.revertActive; onTriggered: root.revertTick() }

    function fail(msg, err) { applyOk = false; applyMsg = msg; applyErr = err || "" }
    // Ghi config mới qua `sumi config apply` (backup + tmp/rename nằm trong lệnh đó).
    function commitConfig(next) {
        if (applyProc.running) return
        // config.json hiện có nhưng đọc không ra JSON: không ghi đè (tránh làm mất phần còn lại)
        let raw = ""
        try { raw = cfg.text() } catch (e) { raw = "" }
        if (raw.trim() !== "") {
            try { JSON.parse(raw) } catch (e) { fail("CONFIG HỎNG", "config.json không đọc được; chạy: sumi config restore"); return }
        }
        applyErr = ""; applyOk = false; applyMsg = "WRITING..."
        applyKind = "apply"
        revertPrev = JSON.stringify(ce.revertSnapshot(cfg.data))
        revertArm = revertArmed()
        applyProc.command = [sumiBin, "config", "apply", JSON.stringify(next)]
        applyProc.running = true
    }
    function applyCurrent() {
        if (applyProc.running) return
        if (page === "theme") applyTheme()
        else if (page === "font") applyFonts()
        else if (page === "keys") applyKeys()
        else if (page === "options" || page === "objects") applyOptions()
    }
    function applyTheme() {
        if (!dirty) { fail("NO CHANGES"); return }
        if (blocked) { fail("BLOCKED", "tương phản dưới 4.5, không cho áp dụng"); return }
        const errs = ce.validateLook(draft, scopeId)
        if (errs.length > 0) { fail("REJECTED", errs.join("; ")); return }
        commitConfig(ce.withLook(cfg.data, scopeId, draft))
    }
    function applyFonts() {
        if (scopeId === "hub" || !hasScope) { fail("REJECTED", "chọn GLOBAL hoặc một app"); return }
        if (!fontDirty) { fail("NO CHANGES"); return }
        const errs = ce.validateFonts(fontDraft, scopeId)
        if (errs.length > 0) { fail("REJECTED", errs.join("; ")); return }
        commitConfig(ce.withFonts(cfg.data, scopeId, fontDraft))
    }
    function applyOptions() {
        if (!hasScope) { fail("REJECTED", "không có app nào có option"); return }
        if (!optDirty) { fail("NO CHANGES"); return }
        const errs = ce.validateOptions(optDraft, optList, scopeId)
        if (errs.length > 0) { fail("REJECTED", errs.join("; ")); return }
        commitConfig(page === "objects" ? ce.withObjects(cfg.data, scopeId, optDraft, optList)
                     : (scopeId === "hub" ? ce.withHubOptions(cfg.data, optDraft) : ce.withOptions(cfg.data, scopeId, optDraft, optList)))
    }
    function applyKeys() {
        if (!hasScope) { fail("REJECTED", "không có app nào có keybind"); return }
        if (!keyDirty) { fail("NO CHANGES"); return }
        const errs = ce.validateKeys(keyDraft, kbList, scopeId)
        if (errs.length > 0) { fail("REJECTED", errs.join("; ")); return }
        commitConfig(ce.withKeys(cfg.data, scopeId, keyDraft, kbList))
    }
    Process {
        id: applyProc
        stderr: StdioCollector { onStreamFinished: if (root.applyMsg !== "APPLIED") root.applyErr = this.text.trim() }
        onExited: (code, status) => root.applyDone(code)
    }
    // Danh sách font hệ thống: A = mọi font (+ spacing, 100/110 là mono), J = font có glyph tiếng Nhật.
    Process {
        id: fcProc
        command: ["sh", "-c", "fc-list -f 'A|%{family[0]}|%{spacing}\\n'; fc-list -f 'J|%{family[0]}\\n' ':lang=ja'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.fontList = ce.parseFontList(this.text)
                root.fontListLoaded = true
            }
        }
    }


    // ===== PREVIEW (GĐ2b-5): khung thu nhỏ nạp View.qml của app ở previewMode =====
    property bool previewOn: false
    readonly property var pvApp: {
        if (page === "store") return null
        if (page === "apps") return cur
        if ((page === "theme" || page === "options") && scopeId === "hub") return null
        if (scopeApp !== null && scopeId !== "global") return scopeApp
        return cur !== null ? cur : (apps.length > 0 ? apps[0] : null)
    }
    readonly property var pvFns: (pvApp !== null && Array.isArray(pvApp.functions)) ? pvApp.functions : []
    // function đang xem: trang APPS theo A/D; tab OBJECTS theo hàng đang chọn; còn lại function đầu tiên
    readonly property var pvFnObj: {
        if (pvFns.length === 0) return null
        if (page === "objects" && curOpt !== null) {
            const kk = ce.splitObjKey(curOpt.key)
            if (kk !== null) for (let i = 0; i < pvFns.length; i++) if (pvFns[i].id === kk[0]) return pvFns[i]
        }
        if (page === "apps" && cur !== null) return pvFns[Math.max(0, Math.min(fnSel, pvFns.length - 1))]
        return pvFns[0]
    }
    readonly property string pvFn: pvFnObj !== null ? pvFnObj.id : ""
    readonly property string pvMode: pvFnObj !== null ? String(pvFnObj.ipc_name || pvFnObj.id) : ""
    readonly property var pvLookS: pvApp !== null ? ce.lookOf(cfg.data, pvApp.id) : ({ theme: null, tint: null, inkDarken: null })
    readonly property var pvInh: pvApp !== null ? ce.inherited(cfg.data, pvApp.id) : ({ theme: "paper", tint: 0.12, inkDarken: 1.5 })
    readonly property var pvObjectCfg: {
        if (pvApp === null) return ({})
        let d = cfg.data
        if (page === "objects" && scopeId === pvApp.id) d = ce.withObjects(cfg.data, pvApp.id, optDraft, optList)
        const a = (d !== null && typeof d === "object" && d.apps !== null && typeof d.apps === "object" && d.apps[pvApp.id] !== undefined) ? d.apps[pvApp.id] : null
        return (a !== null && typeof a === "object" && a.objects !== null && typeof a.objects === "object") ? a.objects : ({})
    }
    // Giá trị look hiệu lực cho app đang preview; đang sửa chính scope đó (hoặc global mà app không ghi đè) thì lấy bản nháp.
    function pvPick(key, eff) {
        if (page === "theme" && pvApp !== null) {
            if (scopeId === pvApp.id) return eff
            if (scopeId === "global") return pvLookS[key] !== null ? pvLookS[key] : eff
        }
        return pvLookS[key] !== null ? pvLookS[key] : pvInh[key]
    }
    function pvFam(role) {
        if (pvApp === null) return ce.fontDefaults[role]
        const own = ce.fontsOf(cfg.data, pvApp.id)[role]
        let v
        if (page === "font" && scopeId === pvApp.id) v = fontEff(role)
        else if (page === "font" && scopeId === "global") v = own !== null ? own : fontEff(role)
        else v = own !== null ? own : ce.fontsInherited(cfg.data, pvApp.id)[role]
        return v !== "" ? v : (role === "kanji" ? Qt.application.font.family : ce.fontDefaults[role])
    }
    function pvLook(key, def) {
        const d = cfg.data
        const a = (d !== null && typeof d === "object" && d.apps !== null && typeof d.apps === "object" && pvApp !== null && d.apps[pvApp.id] !== null && typeof d.apps[pvApp.id] === "object") ? d.apps[pvApp.id] : ({})
        if (a[key] !== undefined) return a[key]
        const g = (d !== null && typeof d === "object" && d.global !== null && typeof d.global === "object") ? d.global : ({})
        return g[key] !== undefined ? g[key] : def
    }
    // Thuộc tính gán cho View.qml (chỉ gán những thuộc tính View thật sự có). Thứ tự quan trọng: `active` cuối cùng.
    readonly property var pvProps: ({
        bootMs: 1, outroMs: 1,
        bgColor: String(colors.adapter.surface), fgColor: String(colors.adapter.on_surface),
        mutedColor: String(colors.adapter.outline), accentColor: String(colors.adapter.primary), dangerColor: "#E63946",
        fontTitle: pvFam("title"), fontLabel: pvFam("label"), fontData: pvFam("data"), fontNumeral: pvFam("numeral"), fontKanji: pvFam("kanji"),
        preset: String(pvPick("theme", effTheme)), tint: Number(pvPick("tint", effTint)), inkDarken: Number(pvPick("inkDarken", effInk)),
        scanOpacity: Number(pvLook("scanlineOpacity", 0.05)), scanlinesEnabled: pvLook("scanlines", true) !== false, glitchEnabled: pvLook("glitch", true) !== false,
        scaleBoost: 1, previewMode: true, closing: false,
        mode: pvMode, objectCfg: pvObjectCfg,
        appName: "ZEN BROWSER", appTitle: "Example window title", appWs: "1", userName: "arzur",
        standby: false, managing: false, active: true
    })
    onPvPropsChanged: pvApply()
    function pvApply() {
        const it = pvLoader.item
        if (it === null) return
        const p = pvProps
        for (const k in p) if (typeof it[k] !== "undefined" && it[k] !== p[k]) it[k] = p[k]
    }

    // ===== STORE (GĐ3b): registry, inspect, cài/cập nhật/gỡ/khôi phục qua `sumi store ... --json` =====
    property var storeApps: []
    property int storeSel: 0
    property string storeView: "list"        // list | confirm | backups
    property bool storeBusy: false
    property string storeBusyText: ""
    property string storeKind: ""            // registry | inspect | op | removed
    property bool storeStale: false
    property bool storeLoaded: false
    property string storeMsg: ""
    property bool storeOk: true
    property var insData: null               // kết quả `inspect` (SHA người dùng xác nhận lấy từ đây)
    property string confirmOp: ""            // install | update | remove | restore
    property string confirmFrom: "list"
    property string pendingId: ""
    property string pendingStamp: ""
    property var backups: []
    property int bkSel: 0
    readonly property var storeCur: (storeApps.length > 0 && storeSel >= 0 && storeSel < storeApps.length) ? storeApps[storeSel] : null
    readonly property var confirmRows: sl.confirmRows(confirmOp, insData, pendingId, pendingStamp, 14)
    readonly property bool confirmOk: sl.canConfirm(confirmOp, insData)

    Process {
        id: storeProc
        stdout: StdioCollector { onStreamFinished: root.storeDone(this.text) }
    }
    // Chạy lại làm mới registry sau một thao tác (tiến trình cũ có thể chưa kịp báo đã thoát).
    Timer {
        id: storeRetry
        property bool force: false
        interval: 120; repeat: false
        onTriggered: root.storeRefresh(force)
    }

    function storeRun(kind, args, text) {
        if (storeBusy || storeProc.running) return false
        storeKind = kind; storeBusy = true; storeBusyText = text
        storeProc.command = [sumiBin, "store"].concat(args).concat(["--json"])
        storeProc.running = true
        return true
    }
    function storeRefresh(force) {
        if (storeBusy) return
        if (storeProc.running) { storeRetry.force = force; storeRetry.restart(); return }
        storeRun("registry", force ? ["registry", "--refresh"] : ["registry"], "LOADING REGISTRY ...")
    }
    function storeDone(text) {
        storeBusy = false
        const r = sl.parse(text)
        const kind = storeKind
        if (kind === "registry") {
            if (r.ok && r.data !== null && Array.isArray(r.data.apps)) {
                const keep = storeCur !== null ? storeCur.id : ""
                storeApps = r.data.apps
                storeStale = r.data.stale === true
                storeLoaded = true
                noteApps = sl.updatesIn(r.data.apps)
                let i = -1
                for (let k = 0; k < r.data.apps.length; k++) if (r.data.apps[k].id === keep) { i = k; break }
                storeSel = i >= 0 ? i : Math.max(0, Math.min(storeSel, r.data.apps.length - 1))
            } else {
                storeOk = false; storeMsg = r.msg
            }
        } else if (kind === "inspect") {
            if (r.ok) { insData = r.data; storeView = "confirm" }
            else { storeOk = false; storeMsg = r.msg; storeView = "list" }
        } else if (kind === "removed") {
            if (r.ok && Array.isArray(r.data)) { backups = r.data; bkSel = 0; storeView = "backups" }
            else { storeOk = false; storeMsg = r.msg; storeView = "list" }
        } else if (kind === "op") {
            storeView = "list"
            if (r.ok) {
                storeOk = true; storeMsg = sl.opText(r.data)
                storeRetry.force = false; storeRetry.restart()
            } else {
                storeOk = false; storeMsg = r.msg
            }
        }
    }
    function openStore() {
        page = "store"; storeView = "list"; storeMsg = ""; storeOk = true
        storeRefresh(false)
    }
    function closeStore() { page = "apps" }
    function storeMove(d) {
        if (storeApps.length === 0) return
        storeSel = (storeSel + d + storeApps.length) % storeApps.length
        storeMsg = ""
    }
    function storeAction() {
        const a = storeCur
        if (a === null) return
        const op = sl.opFor(a)
        if (op === "") { storeOk = true; storeMsg = "ĐÃ Ở BẢN MỚI NHẤT"; return }
        const blk = sl.runningBlock(a, op)
        if (blk !== "") { storeOk = false; storeMsg = blk; return }
        storeMsg = ""
        confirmOp = op; pendingId = a.id; confirmFrom = "list"; insData = null
        storeRun("inspect", ["inspect", a.id], "INSPECTING " + a.id.toUpperCase() + " ...")
    }
    function storeRemoveAsk() {
        const a = storeCur
        if (a === null) return
        if (!sl.canRemove(a)) {
            storeOk = false
            storeMsg = a.state === "dev" ? "BẢN DEV KHÔNG DO STORE QUẢN LÝ, KHÔNG GỠ Ở ĐÂY" : "APP CHƯA CÀI"
            return
        }
        const blk = sl.runningBlock(a, "remove")
        if (blk !== "") { storeOk = false; storeMsg = blk; return }
        storeMsg = ""
        confirmOp = "remove"; pendingId = a.id; insData = null; confirmFrom = "list"; storeView = "confirm"
    }
    function storeBackupsOpen() {
        const a = storeCur
        if (a === null) return
        storeMsg = ""; pendingId = a.id
        storeRun("removed", ["removed", a.id], "READING BACKUPS ...")
    }
    function storeRestoreAsk() {
        if (backups.length === 0) return
        const b = backups[Math.max(0, Math.min(bkSel, backups.length - 1))]
        const a = (storeCur !== null && storeCur.id === pendingId) ? storeCur : null
        const blk = sl.runningBlock(a, "restore")
        if (blk !== "") { storeOk = false; storeMsg = blk; return }
        storeMsg = ""
        confirmOp = "restore"; pendingStamp = b.stamp; insData = null; confirmFrom = "backups"; storeView = "confirm"
    }
    function storeConfirm() {
        if (!confirmOk) return
        storeRun("op", sl.opArgs(confirmOp, insData, pendingId, pendingStamp), confirmOp.toUpperCase() + " " + pendingId.toUpperCase() + " ...")
    }
    function storeKey(event) {
        const k = event.key
        const ar = event.isAutoRepeat
        event.accepted = true
        if (storeBusy) return
        const enter = (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
        const up = (k === Qt.Key_W || k === Qt.Key_Up)
        const down = (k === Qt.Key_S || k === Qt.Key_Down)
        if (storeView === "confirm") {
            if (k === Qt.Key_Escape) { if (!ar) storeView = confirmFrom }
            else if (enter) { if (!ar) storeConfirm() }
            return
        }
        if (storeView === "backups") {
            if (k === Qt.Key_Escape) { if (!ar) { storeView = "list"; storeMsg = "" } }
            else if (up) { if (backups.length > 0) bkSel = (bkSel - 1 + backups.length) % backups.length }
            else if (down) { if (backups.length > 0) bkSel = (bkSel + 1) % backups.length }
            else if (enter) { if (!ar) storeRestoreAsk() }
            return
        }
        if (k === Qt.Key_Escape || k === Qt.Key_Q) { if (!ar) closeStore() }
        else if (up) storeMove(-1)
        else if (down) storeMove(1)
        else if (enter) { if (!ar) storeAction() }
        else if (k === Qt.Key_R) { if (!ar) storeRefresh(true) }
        else if (k === Qt.Key_X) { if (!ar) storeRemoveAsk() }
        else if (k === Qt.Key_B) { if (!ar) storeBackupsOpen() }
    }

    readonly property string footerText: {
        if (revertActive) return "ENTER KEEP   ESC REVERT NOW"
        if (page === "apps") return "W/S APP  A/D FUNC  ENTER RUN  T THEME  F FONT  K KEYS  O OPTION  J OBJECT  V PREVIEW  G STORE  ESC"
        if (page === "store") {
            if (storeBusy) return "WORKING ...   PLEASE WAIT"
            if (storeView === "confirm") return confirmOk ? "ENTER CONFIRM   ESC CANCEL" : "BLOCKED   ESC BACK"
            if (storeView === "backups") return "W/S SELECT   ENTER RESTORE   ESC BACK"
            return "W/S APP   ENTER INSTALL/UPDATE   X REMOVE   B BACKUPS   R REFRESH   ESC BACK"
        }
        if (optEditing) return "TYPE VALUE   ENTER OK   ESC CANCEL   BACKSPACE DELETE"
        if (capturing) return "PRESS A KEY   ESC CANCEL"
        if (pickOpen) return "TYPE FILTER   UP/DOWN MOVE   ENTER SELECT   TAB " + (pickKind === "ja" ? "JA ONLY" : (pickKind === "mono" ? "MONO ONLY" : "-")) + "   ESC CANCEL"
        if (page === "theme") return "W/S SCOPE  A/D PRESET  -/= TINT  ,/. INK  ENTER APPLY  R INHERIT  TAB NEXT  ESC BACK"
        if (page === "font") return "W/S ROLE  Q/E SCOPE  ENTER PICK  SPACE APPLY  R RESET  X ALL  TAB NEXT  ESC BACK"
        if (page === "options" || page === "objects") return "W/S ROW  A/D CHANGE  ENTER EDIT  Q/E APP  SPACE APPLY  R DEFAULT  X ALL  TAB NEXT  ESC BACK"
        return "W/S ACTION  Q/E APP  ENTER REBIND  SPACE APPLY  R DEFAULT  X ALL  TAB NEXT  ESC BACK"
    }

    Timer { id: quitTimer; interval: 150; repeat: false; onTriggered: root.finish() }

    Process {
        id: listProc
        command: [root.sumiBin, "list", "--json"]
        stdout: StdioCollector { onStreamFinished: root.parseApps(this.text) }
    }
    // Làm mới lúc mở và mỗi 2 giây (để cập nhật trạng thái đang chạy)
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: if (!listProc.running) listProc.running = true
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sumi-hub"
        WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        // nền tối; bấm ra ngoài = đóng
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.5 * root.bdIn * (1 - root.outP)
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        }

        Item {
            id: card
            anchors.centerIn: parent
            readonly property real u: Math.max(0.6, Math.min(win.width / 1920, win.height / 1080))
            function px(n) { return Math.max(1, Math.round(n * u)) }
            function fs(n) { return Math.max(8, Math.round(n * u)) }
            width: px(1000)
            height: px(600)
            opacity: root.crtFlicker
            transform: Scale {
                origin.x: card.width / 2; origin.y: card.height / 2
                xScale: root.crtXs; yScale: root.crtYs
            }
            readonly property real m: px(26)
            readonly property real pvW: px(340)
            readonly property real pvH: Math.round(pvW * 9 / 16)
            readonly property real pvReserve: (root.previewOn && root.page !== "store") ? (pvH + px(34)) : 0

            // Chặn phím ~150ms đầu để không ăn nhầm phím vừa bấm để mở hub
            property bool inputReady: false
            Timer { interval: 150; running: true; repeat: false; onTriggered: card.inputReady = true }

            focus: true
            Keys.onPressed: (event) => {
                if (!card.inputReady) return
                if (root.closing) { event.accepted = true; return }
                const k = event.key
                const ar = event.isAutoRepeat
                if (root.revertActive) { root.revertKey(event); event.accepted = true; return }
                if (root.page === "apps") {
                    if (k === Qt.Key_Escape || k === Qt.Key_Q) { if (!ar) root.dismiss(); event.accepted = true }
                    else if (k === Qt.Key_T || k === Qt.Key_Tab) { if (!ar) root.openSettings("theme"); event.accepted = true }
                    else if (k === Qt.Key_F) { if (!ar) root.openSettings("font"); event.accepted = true }
                    else if (k === Qt.Key_K) { if (!ar) root.openSettings("keys"); event.accepted = true }
                    else if (k === Qt.Key_O) { if (!ar) root.openSettings("options"); event.accepted = true }
                    else if (k === Qt.Key_J) { if (!ar) root.openSettings("objects"); event.accepted = true }
                    else if (k === Qt.Key_G) { if (!ar) root.openStore(); event.accepted = true }
                    else if (k === Qt.Key_V) { if (!ar) root.previewOn = !root.previewOn; event.accepted = true }
                    else if (k === Qt.Key_W || k === Qt.Key_Up) { root.move(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { root.move(1); event.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left) { root.moveFn(-1); event.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right) { root.moveFn(1); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (!ar) root.runSelected(); event.accepted = true }
                    return
                }
                if (root.page === "store") { root.storeKey(event); return }
                // ----- trang cài đặt -----
                if (root.optEditing) { root.optEditKey(event); event.accepted = true; return }
                if (root.capturing) { root.captureEvent(event); event.accepted = true; return }
                if (root.pickOpen) { root.pickerKey(event); event.accepted = true; return }
                if (k === Qt.Key_Escape) { if (!ar) root.closeSettings(); event.accepted = true; return }
                if (k === Qt.Key_Tab) { if (!ar) root.cycleTab(1); event.accepted = true; return }
                if (k === Qt.Key_Backtab) { if (!ar) root.cycleTab(-1); event.accepted = true; return }
                if (k === Qt.Key_V) { if (!ar) root.previewOn = !root.previewOn; event.accepted = true; return }
                if (k >= Qt.Key_1 && k <= Qt.Key_5) { if (!ar) root.enterPage(root.tabIds[k - Qt.Key_1], root.keepScope); event.accepted = true; return }
                if (k === Qt.Key_Q) { if (!ar) root.moveScope(-1); event.accepted = true; return }
                if (k === Qt.Key_E) { if (!ar) root.moveScope(1); event.accepted = true; return }
                if (k === Qt.Key_Space) { if (!ar) root.applyCurrent(); event.accepted = true; return }
                if (root.page === "theme") {
                    if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveScope(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveScope(1); event.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left) { if (!ar) root.movePreset(-1); event.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right) { if (!ar) root.movePreset(1); event.accepted = true }
                    else if (k === Qt.Key_Minus) { root.nudge("tint", -0.02); event.accepted = true }
                    else if (k === Qt.Key_Equal || k === Qt.Key_Plus) { root.nudge("tint", 0.02); event.accepted = true }
                    else if (k === Qt.Key_Comma) { root.nudge("ink", -0.1); event.accepted = true }
                    else if (k === Qt.Key_Period) { root.nudge("ink", 0.1); event.accepted = true }
                    else if (k === Qt.Key_R) { if (!ar) root.inheritScope(); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.applyCurrent(); event.accepted = true }
                } else if (root.page === "font") {
                    if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveFontRow(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveFontRow(1); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.openPicker(); event.accepted = true }
                    else if (k === Qt.Key_R) { if (!ar) root.resetFontRow(); event.accepted = true }
                    else if (k === Qt.Key_X) { if (!ar) root.resetFontAll(); event.accepted = true }
                } else if (root.page === "keys") {
                    if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveKeyRow(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveKeyRow(1); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.startCapture(); event.accepted = true }
                    else if (k === Qt.Key_R) { if (!ar) root.resetKeyRow(); event.accepted = true }
                    else if (k === Qt.Key_X) { if (!ar) root.resetKeyAll(); event.accepted = true }
                } else if (root.page === "options" || root.page === "objects") {
                    if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveOptRow(-1); event.accepted = true }
                    else if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveOptRow(1); event.accepted = true }
                    else if (k === Qt.Key_A || k === Qt.Key_Left) { root.nudgeOpt(-1); event.accepted = true }
                    else if (k === Qt.Key_D || k === Qt.Key_Right) { root.nudgeOpt(1); event.accepted = true }
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.enterOpt(); event.accepted = true }
                    else if (k === Qt.Key_R) { if (!ar) root.resetOptRow(); event.accepted = true }
                    else if (k === Qt.Key_X) { if (!ar) root.resetOptAll(); event.accepted = true }
                }
            }

            // nền giấy + khung vát góc dưới phải
            Shape {
                anchors.fill: parent
                ShapePath {
                    id: bodySP
                    readonly property real c: card.px(44)
                    fillColor: th.paper
                    strokeColor: th.ink
                    strokeWidth: 1.5
                    startX: 0; startY: 0
                    PathLine { x: card.width; y: 0 }
                    PathLine { x: card.width; y: card.height - bodySP.c }
                    PathLine { x: card.width - bodySP.c; y: card.height }
                    PathLine { x: 0; y: card.height }
                    PathLine { x: 0; y: 0 }
                }
            }

            // ---------- thanh trên ----------
            Item {
                x: card.m; y: card.px(18)
                width: card.width - 2 * card.m; height: card.px(34)
                Rectangle {
                    width: card.px(150); height: parent.height; color: th.ink
                    Text {
                        anchors.centerIn: parent; anchors.horizontalCenterOffset: card.px(root.gdx) * 1.5
                        visible: root.glitchNow; text: "SUMI 墨"; color: th.danger; opacity: 0.75
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 3
                    }
                    Text {
                        anchors.centerIn: parent; anchors.horizontalCenterOffset: -card.px(root.gdx) * 1.5
                        visible: root.glitchNow; text: "SUMI 墨"; color: th.paper; opacity: 0.45
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 3
                    }
                    Text {
                        anchors.centerIn: parent; text: "SUMI 墨"; color: th.paper
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 3
                    }
                }
                Text {
                    x: card.px(168); anchors.verticalCenter: parent.verticalCenter
                    visible: !root.inSettings
                    text: root.page === "store" ? "STORE" : "APPS"; color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                }
                Row {
                    x: card.px(168); anchors.verticalCenter: parent.verticalCenter
                    visible: root.inSettings
                    spacing: card.px(6)
                    Repeater {
                        model: root.tabIds
                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            readonly property bool on: modelData === root.page
                            width: card.px(112); height: card.px(26)
                            color: on ? th.ink : "transparent"
                            border.width: 1; border.color: on ? th.ink : th.rule
                            Text {
                                anchors.centerIn: parent
                                text: (index + 1) + " " + modelData.toUpperCase() + (root.tabDirty(modelData) ? " *" : "")
                                color: parent.on ? th.paper : th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true; font.letterSpacing: 1.5
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.enterPage(parent.modelData, root.keepScope)
                            }
                        }
                    }
                }
                Text {
                    anchors.right: topRight.left; anchors.rightMargin: card.px(28); anchors.verticalCenter: parent.verticalCenter
                    visible: root.page === "apps" && root.noteText !== ""
                    text: root.noteText + "   (G)"; color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1; font.bold: true
                }
                Text {
                    id: topRight
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: root.inSettings ? root.scopeName : (root.page === "store" ? (root.storeApps.length + " IN REGISTRY") : (root.apps.length + " INSTALLED")); color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -card.px(8); width: parent.width; height: 1; color: th.rule }
            }

            // ---------- danh sách app (trái) ----------
            ListView {
                id: list
                visible: root.page === "apps"
                x: card.m; y: card.px(76)
                width: card.px(340); height: card.height - card.px(76) - card.px(96) - card.pvReserve
                clip: true
                interactive: false
                model: root.apps
                currentIndex: root.sel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool on: index === root.sel
                    width: list.width
                    height: card.px(56)
                    Rectangle {
                        anchors.fill: parent; anchors.bottomMargin: 1
                        color: row.on ? th.ink : (rowMouse.containsMouse ? th.wash : "transparent")
                    }
                    Text {
                        x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - card.px(150)
                        elide: Text.ElideRight
                        text: row.modelData.name
                        color: row.on ? th.paper : th.ink
                        font.family: root.fontLabel; font.pixelSize: card.fs(21); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: card.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.running ? "● RUNNING" : ("v" + row.modelData.version)
                        color: row.on ? th.paper : (row.modelData.running ? th.ink : th.soft)
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: row.modelData.running
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.sel = row.index; root.fnSel = 0 }
                    }
                }
            }
            Rectangle { visible: root.page === "apps"; x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }

            // ---------- chi tiết (phải) ----------
            Item {
                id: rc
                x: card.m + card.px(340) + card.px(30)
                y: card.px(76)
                width: card.width - x - card.m
                height: list.height
                visible: root.page === "apps" && root.cur !== null

                Rectangle { width: parent.width; height: 1; color: th.ink }
                ScrambleText {
                    x: card.px(2); y: card.px(6)
                    width: rc.width - card.px(150); height: card.px(84)
                    verticalAlignment: Text.AlignVCenter
                    full: root.cur ? root.cur.name.toUpperCase() : ""
                    active: root.cur !== null
                    color: th.ink
                    font.family: root.fontTitle; font.bold: true
                    font.pixelSize: card.fs(56); fontSizeMode: Text.Fit; minimumPixelSize: card.fs(24)
                }
                ScrambleText {
                    anchors.right: parent.right; y: card.px(2)
                    full: root.cur ? root.cur.kanji : ""
                    active: root.cur !== null
                    color: th.rule
                    font.family: root.fontKanji; font.pixelSize: card.fs(88)
                }
                Rectangle { y: card.px(96); width: parent.width; height: 1; color: th.ink }

                Text {
                    y: card.px(108); width: parent.width
                    wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    text: root.cur ? root.cur.description : ""
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(18)
                }

                Repeater {
                    model: root.cur ? [
                        ["VERSION", root.cur.version],
                        ["KIND", root.cur.kind === "daemon" ? "DAEMON (giữ trạng thái)" : "ONESHOT (chạy xong thoát)"],
                        ["STATUS", root.cur.running ? "RUNNING" : "IDLE"]
                    ] : []
                    delegate: Item {
                        required property int index
                        required property var modelData
                        y: card.px(190) + index * card.px(36)
                        width: rc.width; height: card.px(36)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]; color: th.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15); font.letterSpacing: 1.5
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; color: th.ink
                            font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.7 }
                    }
                }

                // function của app daemon (A/D để chọn) hoặc gợi ý cho app oneshot
                Text {
                    y: card.px(312)
                    text: root.cur && root.cur.kind === "daemon" ? "FUNCTION" : "CHẠY THỬ"
                    color: th.soft
                    font.family: root.fontLabel; font.pixelSize: card.fs(15); font.letterSpacing: 1.5
                }
                Row {
                    y: card.px(338)
                    spacing: card.px(10)
                    visible: root.cur !== null && root.cur.kind === "daemon"
                    Repeater {
                        model: root.curFns
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            readonly property bool on: index === root.fnSel
                            width: card.px(150); height: card.px(44)
                            color: on ? th.ink : "transparent"
                            border.width: 1; border.color: th.ink
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(16); font.bold: true; font.letterSpacing: 1
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.fnSel = parent.index }
                        }
                    }
                }
                Text {
                    y: card.px(338); width: parent.width
                    visible: root.cur !== null && root.cur.kind !== "daemon"
                    wrapMode: Text.WordWrap
                    text: "Enter mở thử dialog với dữ liệu mẫu (thoát mã 0 = Yes, 1 = No)."
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(17)
                }
            }

            // ---------- trạng thái rỗng / lỗi ----------
            Text {
                x: card.m + card.px(340) + card.px(30); y: card.px(96)
                visible: root.page === "apps" && root.cur === null
                text: root.errorText !== "" ? root.errorText : "KHÔNG CÓ APP NÀO ĐÃ CÀI"
                color: th.ink
                font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true
            }
            Text {
                x: card.m; y: card.height - card.px(86); width: card.width - 2 * card.m
                visible: root.page === "apps" && root.errorText !== "" && root.cur !== null
                text: root.errorText; color: th.ink
                font.family: root.fontData; font.pixelSize: card.fs(14)
            }

            // ---------- trang THEME (2b-1) ----------
            Item {
                id: tp
                visible: root.inSettings
                anchors.fill: parent

                // danh sách phạm vi (trái)
                ListView {
                    id: scopeList
                    x: card.m; y: card.px(76)
                    width: card.px(340); height: card.height - card.px(76) - card.px(96) - card.pvReserve
                    clip: true
                    interactive: false
                    model: root.scopes
                    currentIndex: root.scopeSel
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Item {
                        id: srow
                        required property int index
                        required property var modelData
                        readonly property bool on: index === root.scopeSel
                        readonly property string tag: root.scopeTag(root.page, modelData.id)
                        width: scopeList.width
                        height: card.px(48)
                        Rectangle {
                            anchors.fill: parent; anchors.bottomMargin: 1
                            color: srow.on ? th.ink : (smouse.containsMouse ? th.wash : "transparent")
                        }
                        Text {
                            x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - card.px(150)
                            elide: Text.ElideRight
                            text: srow.modelData.name
                            color: srow.on ? th.paper : th.ink
                            font.family: root.fontLabel; font.pixelSize: card.fs(19); font.bold: true
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(16)
                            anchors.verticalCenter: parent.verticalCenter
                            text: srow.tag
                            color: srow.on ? th.paper : th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13)
                        }
                        MouseArea {
                            id: smouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setScope(srow.index)
                        }
                    }
                }
                Rectangle { x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }
                Text {
                    x: card.m + card.px(16); y: card.px(96); width: card.px(310)
                    visible: !root.hasScope
                    wrapMode: Text.WordWrap
                    text: root.page === "options" ? "Chưa có app nào khai báo option." : (root.page === "objects" ? "Chưa có app nào cho chọn object." : "Chưa có app nào khai báo keybind.")
                    color: th.soft
                    font.family: root.fontLabel; font.pixelSize: card.fs(16)
                }

                // bảng chỉnh (phải)
                Item {
                    id: tr
                    visible: root.page === "theme"
                    x: card.m + card.px(340) + card.px(30)
                    y: card.px(76)
                    width: card.width - x - card.m
                    height: scopeList.height

                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(8)
                        text: "THEME / " + root.scopeName
                        color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.draft.theme === null && root.draft.tint === null && root.draft.inkDarken === null
                              ? "INHERIT" : (root.dirty ? "DRAFT" : "SAVED")
                        color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                    }

                    // 6 thẻ preset
                    Row {
                        y: card.px(48)
                        spacing: card.px(8)
                        Repeater {
                            model: ce.themes
                            delegate: Item {
                                id: pc
                                required property int index
                                required property string modelData
                                readonly property var dv: th.derive(modelData, root.effTint, root.effInk)
                                readonly property bool on: modelData === root.effTheme
                                readonly property bool bad: dv.contrast < th.minContrast
                                readonly property bool weak: !bad && dv.contrast < th.goodContrast
                                width: Math.floor((tr.width - 5 * card.px(8)) / 6)
                                height: card.px(112)
                                Rectangle {
                                    anchors.fill: parent
                                    color: pc.dv.paper
                                    border.width: pc.on ? 3 : 1
                                    border.color: pc.on ? th.ink : th.rule
                                    opacity: pc.bad ? 0.55 : 1
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(6)
                                    text: root.presetKanji(pc.modelData); color: pc.dv.ink
                                    font.family: root.fontKanji; font.pixelSize: card.fs(34)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(54)
                                    width: parent.width - card.px(6); horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: pc.modelData.toUpperCase(); color: pc.dv.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(11); font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(72)
                                    text: pc.dv.contrast.toFixed(1) + (pc.bad ? " ✕" : (pc.weak ? " !" : ""))
                                    color: pc.dv.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(11)
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter; y: card.px(94)
                                    spacing: card.px(2)
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.ink }
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.soft }
                                    Rectangle { width: card.px(14); height: card.px(6); color: pc.dv.rule }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setPreset(pc.modelData)
                                }
                            }
                        }
                    }

                    // xem trước (màu của bản nháp)
                    Item {
                        id: pv
                        y: card.px(172)
                        width: parent.width; height: card.px(118)
                        readonly property var dv: root.curDerived
                        Rectangle { anchors.fill: parent; color: pv.dv.paper; border.width: 1; border.color: pv.dv.ink }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(12); y: card.px(4)
                            text: "墨"; color: pv.dv.rule
                            font.family: root.fontKanji; font.pixelSize: card.fs(76)
                        }
                        Text {
                            x: card.px(14); y: card.px(8)
                            text: "KAKUNIN"; color: pv.dv.ink
                            font.family: root.fontTitle; font.pixelSize: card.fs(30); font.bold: true
                        }
                        Text {
                            x: card.px(14); y: card.px(50)
                            text: "Đóng cửa sổ này?"; color: pv.dv.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15)
                        }
                        Rectangle {
                            x: card.px(14); y: card.px(80); width: card.px(84); height: card.px(28); color: pv.dv.ink
                            Text { anchors.centerIn: parent; text: "YES"; color: pv.dv.paper; font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true }
                        }
                        Rectangle {
                            x: card.px(106); y: card.px(80); width: card.px(84); height: card.px(28); color: "transparent"
                            border.width: 1; border.color: pv.dv.ink
                            Text { anchors.centerIn: parent; text: "NO"; color: pv.dv.ink; font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true }
                        }
                        Rectangle {
                            x: card.px(198); y: card.px(80); width: card.px(84); height: card.px(28); color: th.danger
                            Text { anchors.centerIn: parent; text: "DANGER"; color: "white"; font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true }
                        }
                        Rectangle { x: card.px(290); y: card.px(93); width: card.px(40); height: card.px(2); color: pv.dv.ghostB }
                    }

                    // thanh TINT và INK DARKEN
                    Repeater {
                        model: [
                            { key: "tint", label: "TINT", lo: 0, hi: 0.6, step: 0.02, nd: 2 },
                            { key: "ink", label: "INK DARKEN", lo: 1, hi: 2.5, step: 0.1, nd: 1 }
                        ]
                        delegate: Item {
                            id: cr
                            required property int index
                            required property var modelData
                            readonly property real v: modelData.key === "tint" ? root.effTint : root.effInk
                            readonly property bool isInh: modelData.key === "tint" ? root.draft.tint === null : root.draft.inkDarken === null
                            y: card.px(302) + index * card.px(34)
                            width: tr.width; height: card.px(34)
                            opacity: root.tintEditable ? 1 : 0.35
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cr.modelData.label; color: th.soft
                                font.family: root.fontLabel; font.pixelSize: card.fs(14); font.letterSpacing: 1.5
                            }
                            Rectangle {
                                x: card.px(130); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(240); height: card.px(8)
                                color: th.wash; border.width: 1; border.color: th.rule
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, (cr.v - cr.modelData.lo) / (cr.modelData.hi - cr.modelData.lo)))
                                    height: parent.height; color: th.ink
                                }
                            }
                            Text {
                                x: card.px(384); anchors.verticalCenter: parent.verticalCenter
                                text: cr.v.toFixed(cr.modelData.nd) + (cr.isInh ? "  inh" : "")
                                color: th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                            }
                            Rectangle {
                                x: tr.width - card.px(64); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(28); height: card.px(24); color: "transparent"; border.width: 1; border.color: th.ink
                                Text { anchors.centerIn: parent; text: "-"; color: th.ink; font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nudge(cr.modelData.key, -cr.modelData.step) }
                            }
                            Rectangle {
                                x: tr.width - card.px(30); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(28); height: card.px(24); color: "transparent"; border.width: 1; border.color: th.ink
                                Text { anchors.centerIn: parent; text: "+"; color: th.ink; font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.nudge(cr.modelData.key, cr.modelData.step) }
                            }
                        }
                    }
                    Text {
                        y: card.px(302) + card.px(34) * 2 - card.px(2)
                        visible: !root.tintEditable
                        text: "HUB dùng tint và độ đậm của GLOBAL"
                        color: th.soft
                        font.family: root.fontLabel; font.pixelSize: card.fs(12)
                    }

                    // tương phản + trạng thái áp dụng
                    Rectangle { y: card.px(374); width: parent.width; height: 1; color: th.rule }
                    Text {
                        y: card.px(382)
                        text: "CONTRAST  " + root.curDerived.contrast.toFixed(2) + " : 1   "
                              + (root.blocked ? "BLOCKED (<4.5)" : (root.weak ? "WEAK (<7)" : "OK"))
                        color: root.blocked ? th.danger : th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true
                    }
                    Text {
                        y: card.px(404)
                        width: parent.width; elide: Text.ElideRight
                        text: root.applyErr !== "" ? (root.applyMsg + "  " + root.applyErr) : root.applyMsg
                        color: root.applyOk ? th.ink : th.danger
                        font.family: root.fontData; font.pixelSize: card.fs(13)
                    }
                }

                // ---------- pane FONT (2b-2) ----------
                Item {
                    id: fr
                    visible: root.page === "font"
                    x: card.m + card.px(340) + card.px(30)
                    y: card.px(76)
                    width: card.width - x - card.m
                    height: scopeList.height

                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(8)
                        text: "FONT / " + root.scopeName
                        color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.fontDirty ? "DRAFT" : (root.scopeTag("font", root.scopeId) === "INHERIT" ? "INHERIT" : "SAVED")
                        color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                    }

                    Repeater {
                        model: root.fontRows
                        delegate: Item {
                            id: frow
                            required property int index
                            required property string modelData
                            readonly property bool on: index === root.fontSel
                            readonly property bool own: root.fontDraft[modelData] !== null
                            readonly property bool bad: root.fontMissing(modelData) || root.fontNoJa(modelData)
                            y: card.px(48) + index * card.px(46)
                            width: fr.width; height: card.px(46)
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 1
                                color: frow.on ? th.ink : (frm.containsMouse ? th.wash : "transparent")
                            }
                            Text {
                                x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                text: frow.modelData.toUpperCase()
                                color: frow.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                            }
                            Text {
                                x: card.px(112); anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - card.px(112) - card.px(110)
                                elide: Text.ElideRight
                                text: root.fontShown(frow.modelData)
                                color: frow.on ? th.paper : th.ink
                                font.family: root.fam(frow.modelData); font.pixelSize: card.fs(20)
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: card.px(14)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.fontMissing(frow.modelData) ? "MISSING" : (root.fontNoJa(frow.modelData) ? "NO JA" : (frow.own ? "OWN" : "inh"))
                                color: frow.bad ? th.danger : (frow.on ? th.paper : th.soft)
                                font.family: root.fontData; font.pixelSize: card.fs(12); font.bold: frow.bad
                            }
                            MouseArea {
                                id: frm
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.fontSel === frow.index) root.openPicker(); else root.fontSel = frow.index }
                            }
                        }
                    }

                    // xem trước bằng font của bản nháp (kiểm tra luôn dấu tiếng Việt và kanji)
                    Item {
                        y: card.px(48) + 5 * card.px(46) + card.px(8)
                        width: parent.width; height: card.px(80)
                        Rectangle { anchors.fill: parent; color: th.paper; border.width: 1; border.color: th.ink }
                        Text {
                            x: card.px(14); y: card.px(6)
                            text: "KAKUNIN"; color: th.ink
                            font.family: root.fam("title"); font.pixelSize: card.fs(28); font.bold: true
                        }
                        Text {
                            x: card.px(14); y: card.px(46)
                            text: "Đóng cửa sổ này?"; color: th.soft
                            font.family: root.fam("label"); font.pixelSize: card.fs(15)
                        }
                        Text {
                            x: card.px(300); y: card.px(6)
                            text: "確認 時限 墨"; color: th.ink
                            font.family: root.fam("kanji"); font.pixelSize: card.fs(30)
                        }
                        Text {
                            x: card.px(300); y: card.px(50)
                            text: "[Y] YES  0x3F2A"; color: th.ink
                            font.family: root.fam("data"); font.pixelSize: card.fs(14)
                        }
                        Text {
                            x: card.px(450); y: card.px(44)
                            text: "T-12:34"; color: th.ink
                            font.family: root.fam("numeral"); font.pixelSize: card.fs(22); font.bold: true
                        }
                    }

                    Rectangle { y: card.px(374); width: parent.width; height: 1; color: th.rule }
                    Text {
                        y: card.px(382)
                        width: parent.width; elide: Text.ElideRight
                        text: root.fontWarn !== "" ? root.fontWarn : (root.fontListLoaded ? (root.fontList.length + " FONTS INSTALLED") : "LOADING FONT LIST...")
                        color: root.fontWarn !== "" ? th.danger : th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: root.fontWarn !== ""
                    }
                    Text {
                        y: card.px(404)
                        width: parent.width; elide: Text.ElideRight
                        text: root.applyErr !== "" ? (root.applyMsg + "  " + root.applyErr) : root.applyMsg
                        color: root.applyOk ? th.ink : th.danger
                        font.family: root.fontData; font.pixelSize: card.fs(13)
                    }

                    // ----- bộ chọn font: gõ để lọc, mũi tên để chọn -----
                    Rectangle {
                        id: pk
                        visible: root.pickOpen
                        z: 5
                        y: card.px(40); width: parent.width; height: card.px(332)
                        color: th.paper; border.width: 2; border.color: th.ink
                        readonly property var curItem: root.pickItems.length > 0 ? root.pickItems[Math.max(0, Math.min(root.pickIdx, root.pickItems.length - 1))] : null
                        readonly property string inhFam: {
                            const v = root.fontInh[root.pickRole]
                            return v !== "" ? v : (root.pickRole === "kanji" ? Qt.application.font.family : ce.fontDefaults[root.pickRole])
                        }
                        readonly property string prevFam: (curItem !== null && !curItem.isDefault) ? curItem.name : inhFam
                        Text {
                            x: card.px(14); y: card.px(8)
                            text: "PICK / " + root.pickRole.toUpperCase(); color: th.ink
                            font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true; font.letterSpacing: 2
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(14); y: card.px(8)
                            text: (root.pickKind === "" ? "ALL FONTS" : (root.pickFilter ? (root.pickKind === "ja" ? "JA ONLY" : "MONO ONLY") : "ALL FONTS"))
                                  + "  (" + (root.pickItems.length - 1) + ")"
                            color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1
                        }
                        Text {
                            x: card.px(14); y: card.px(32)
                            text: "FILTER  " + root.pickQuery + "_"; color: th.ink
                            font.family: root.fontData; font.pixelSize: card.fs(15)
                        }
                        Rectangle { x: card.px(14); y: card.px(54); width: parent.width - card.px(28); height: 1; color: th.rule }
                        ListView {
                            id: pkList
                            x: card.px(8); y: card.px(58)
                            width: parent.width - card.px(16); height: card.px(210)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.pickItems
                            currentIndex: root.pickIdx
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            delegate: Item {
                                id: pr
                                required property int index
                                required property var modelData
                                readonly property bool on: index === root.pickIdx
                                width: pkList.width; height: card.px(30)
                                Rectangle { anchors.fill: parent; color: pr.on ? th.ink : (prm.containsMouse ? th.wash : "transparent") }
                                Text {
                                    x: card.px(8); anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - card.px(110)
                                    elide: Text.ElideRight
                                    text: pr.modelData.isDefault ? "— DEFAULT / INHERIT —" : pr.modelData.name
                                    color: pr.on ? th.paper : th.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(15)
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: card.px(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (pr.modelData.mono ? "MONO " : "") + (pr.modelData.ja ? "JA" : "")
                                    color: pr.on ? th.paper : th.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(12)
                                }
                                MouseArea {
                                    id: prm
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.pickIdx = pr.index; root.choosePicked() }
                                }
                            }
                        }
                        Rectangle { x: card.px(14); y: card.px(272); width: parent.width - card.px(28); height: 1; color: th.rule }
                        Text {
                            x: card.px(14); y: card.px(282); width: parent.width - card.px(28)
                            elide: Text.ElideRight
                            text: "Aa Đóng cửa sổ 0123 [Y] 墨紙 確認"; color: th.ink
                            font.family: pk.prevFam; font.pixelSize: card.fs(22)
                        }
                    }
                }

                // ---------- pane KEYS (2b-2) ----------
                Item {
                    id: kr
                    visible: root.page === "keys" && root.hasScope
                    x: card.m + card.px(340) + card.px(30)
                    y: card.px(76)
                    width: card.width - x - card.m
                    height: scopeList.height

                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(8)
                        text: "KEYS / " + root.scopeName
                        color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.keyDirty ? "DRAFT" : (root.scopeTag("keys", root.scopeId) === "DEFAULT" ? "DEFAULT" : "SAVED")
                        color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                    }

                    ListView {
                        id: keyList
                        y: card.px(46); width: parent.width; height: card.px(320)
                        clip: true
                        interactive: false
                        model: root.kbList
                        currentIndex: root.keySel
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        delegate: Item {
                            id: krow
                            required property int index
                            required property var modelData
                            readonly property bool on: index === root.keySel
                            readonly property bool locked: modelData.locked === true
                            readonly property bool changed: !locked && root.keyDraft[modelData.action] !== undefined
                            readonly property bool conf: root.keyConf[modelData.action] !== undefined
                            readonly property bool capHere: on && root.capturing
                            width: keyList.width; height: card.px(34)
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 1
                                color: krow.on ? th.ink : (krm.containsMouse ? th.wash : "transparent")
                            }
                            Text {
                                x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(170); elide: Text.ElideRight
                                text: krow.modelData.label
                                color: krow.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(16); font.bold: true
                            }
                            Text {
                                x: card.px(196); anchors.verticalCenter: parent.verticalCenter
                                text: krow.modelData.action
                                color: krow.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(12)
                            }
                            Text {
                                anchors.right: keycap.left; anchors.rightMargin: card.px(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: krow.locked ? "LOCK" : (krow.changed ? ("def " + krow.modelData.default) : "")
                                color: krow.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(12)
                            }
                            Rectangle {
                                id: keycap
                                anchors.right: parent.right; anchors.rightMargin: card.px(12)
                                anchors.verticalCenter: parent.verticalCenter
                                width: card.px(104); height: card.px(24)
                                color: krow.capHere ? th.paper : "transparent"
                                border.width: krow.conf ? 2 : 1
                                border.color: krow.conf ? th.danger : (krow.on ? th.paper : th.ink)
                                Text {
                                    anchors.centerIn: parent
                                    text: krow.capHere ? "PRESS KEY" : root.keyShown(krow.modelData).toUpperCase()
                                    color: krow.capHere ? th.ink : (krow.on ? th.paper : th.ink)
                                    font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                }
                            }
                            MouseArea {
                                id: krm
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.keySel === krow.index) root.startCapture(); else { root.keySel = krow.index; root.capturing = false; root.capMsg = "" } }
                            }
                        }
                    }

                    Rectangle { y: card.px(374); width: parent.width; height: 1; color: th.rule }
                    Text {
                        y: card.px(382)
                        width: parent.width; elide: Text.ElideRight
                        readonly property var cm: (root.curKb !== null && root.keyConf[root.curKb.action] !== undefined) ? root.keyConf[root.curKb.action] : []
                        text: root.capMsg !== "" ? root.capMsg
                              : (root.capturing ? ("ĐANG GÁN: " + (root.curKb ? root.curKb.action : ""))
                              : (cm.length > 0 ? ("CẢNH BÁO: " + cm.join("; "))
                              : (root.keyConfCount > 0 ? (root.keyConfCount + " ACTION CÓ CẢNH BÁO") : "KHÔNG TRÙNG PHÍM")))
                        color: (root.capMsg !== "" || cm.length > 0 || root.keyConfCount > 0) ? th.danger : th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: root.capMsg !== "" || cm.length > 0
                    }
                    Text {
                        y: card.px(404)
                        width: parent.width; elide: Text.ElideRight
                        text: root.applyErr !== "" ? (root.applyMsg + "  " + root.applyErr) : root.applyMsg
                        color: root.applyOk ? th.ink : th.danger
                        font.family: root.fontData; font.pixelSize: card.fs(13)
                    }
                }

                // ---------- pane OPTIONS ----------
                Item {
                    id: orp
                    visible: (root.page === "options" || root.page === "objects") && root.hasScope
                    x: card.m + card.px(340) + card.px(30)
                    y: card.px(76)
                    width: card.width - x - card.m
                    height: scopeList.height

                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(8)
                        text: (root.page === "objects" ? "OBJECTS / " : "OPTIONS / ") + root.scopeName
                        color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.optDirty ? "DRAFT" : (root.scopeTag(root.page, root.scopeId) === "DEFAULT" ? "DEFAULT" : "SAVED")
                        color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                    }

                    ListView {
                        id: optListView
                        y: card.px(46); width: parent.width; height: card.px(320)
                        clip: true
                        interactive: false
                        model: root.optList
                        currentIndex: root.optSel
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        delegate: Item {
                            id: orow
                            required property int index
                            required property var modelData
                            readonly property bool on: index === root.optSel
                            readonly property bool locked: modelData.locked === true
                            readonly property bool changed: !locked && root.optDraft[modelData.key] !== undefined
                            readonly property bool conf: root.optConf[modelData.key] !== undefined
                            readonly property bool editHere: on && root.optEditing
                            width: optListView.width; height: card.px(34)
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 1
                                color: orow.on ? th.ink : (orm.containsMouse ? th.wash : "transparent")
                            }
                            Text {
                                x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(200); elide: Text.ElideRight
                                text: orow.modelData.label
                                color: orow.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(15); font.bold: true
                            }
                            Text {
                                anchors.right: ocap.left; anchors.rightMargin: card.px(10)
                                anchors.verticalCenter: parent.verticalCenter
                                width: card.px(130); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                text: orow.locked ? "LOCK" : (orow.changed ? ("def " + ce.optFormat(orow.modelData, orow.modelData.default)) : "")
                                color: orow.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(12)
                            }
                            Rectangle {
                                id: ocap
                                anchors.right: parent.right; anchors.rightMargin: card.px(12)
                                anchors.verticalCenter: parent.verticalCenter
                                width: card.px(190); height: card.px(24)
                                color: orow.editHere ? th.paper : "transparent"
                                border.width: orow.conf ? 2 : 1
                                border.color: orow.conf ? th.danger : (orow.on ? th.paper : th.ink)
                                Text {
                                    anchors.fill: parent; anchors.leftMargin: card.px(6); anchors.rightMargin: card.px(6)
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: orow.editHere ? Text.AlignLeft : Text.AlignHCenter
                                    elide: orow.editHere ? Text.ElideLeft : Text.ElideRight
                                    text: orow.editHere ? (root.optBuf + "_") : ce.optFormat(orow.modelData, root.optShown(orow.modelData))
                                    color: orow.editHere ? th.ink : (orow.on ? th.paper : th.ink)
                                    font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                }
                            }
                            MouseArea {
                                id: orm
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.optSel === orow.index) { if (!root.optEditing) root.enterOpt() }
                                    else { root.optEditing = false; root.optSel = orow.index; root.optMsg = "" }
                                }
                            }
                        }
                    }

                    Rectangle { y: card.px(374); width: parent.width; height: 1; color: th.rule }
                    Text {
                        y: card.px(382)
                        width: parent.width; elide: Text.ElideRight
                        readonly property var cm: (root.curOpt !== null && root.optConf[root.curOpt.key] !== undefined) ? root.optConf[root.curOpt.key] : []
                        text: root.optMsg !== "" ? root.optMsg
                              : (cm.length > 0 ? ("CẢNH BÁO: " + cm.join("; "))
                              : ce.optHint(root.curOpt))
                        color: (root.optMsg !== "" || cm.length > 0) ? th.danger : th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: root.optMsg !== "" || cm.length > 0
                    }
                    Text {
                        y: card.px(404)
                        width: parent.width; elide: Text.ElideRight
                        text: root.applyErr !== "" ? (root.applyMsg + "  " + root.applyErr) : root.applyMsg
                        color: root.applyOk ? th.ink : th.danger
                        font.family: root.fontData; font.pixelSize: card.fs(13)
                    }
                }
            }

            // ---------- trang STORE (GĐ3b) ----------
            ListView {
                id: storeList
                visible: root.page === "store" && root.storeView !== "confirm"
                x: card.m; y: card.px(76)
                width: card.px(340); height: card.height - card.px(76) - card.px(96)
                clip: true
                interactive: false
                model: root.storeApps
                currentIndex: root.storeSel
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: srw
                    required property int index
                    required property var modelData
                    readonly property bool on: index === root.storeSel
                    width: storeList.width
                    height: card.px(56)
                    Rectangle {
                        anchors.fill: parent; anchors.bottomMargin: 1
                        color: srw.on ? th.ink : (srwm.containsMouse ? th.wash : "transparent")
                    }
                    Text {
                        x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - card.px(170)
                        elide: Text.ElideRight
                        text: srw.modelData.id.toUpperCase()
                        color: srw.on ? th.paper : th.ink
                        font.family: root.fontLabel; font.pixelSize: card.fs(21); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: card.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        text: sl.badge(srw.modelData)
                        color: srw.on ? th.paper : (srw.modelData.state === "update" ? th.ink : th.soft)
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: srw.modelData.state === "update"
                    }
                    MouseArea {
                        id: srwm
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (!root.storeBusy && root.storeView === "list") { root.storeSel = srw.index; root.storeMsg = "" } }
                    }
                }
            }
            Rectangle { visible: root.page === "store" && root.storeView !== "confirm"; x: card.m; y: card.px(76); width: card.px(340); height: 1; color: th.ink }

            // chi tiết app đang chọn
            Item {
                id: stp
                visible: root.page === "store" && root.storeView === "list" && root.storeCur !== null
                x: card.m + card.px(340) + card.px(30)
                y: card.px(76)
                width: card.width - x - card.m
                height: storeList.height

                Rectangle { width: parent.width; height: 1; color: th.ink }
                Text {
                    x: card.px(2); y: card.px(10); width: stp.width - card.px(2)
                    elide: Text.ElideRight
                    text: root.storeCur ? root.storeCur.id.toUpperCase() : ""
                    color: th.ink
                    font.family: root.fontTitle; font.bold: true; font.pixelSize: card.fs(48)
                }
                Rectangle { y: card.px(78); width: parent.width; height: 1; color: th.ink }
                Repeater {
                    model: root.storeCur ? [
                        ["STATE", sl.stateText(root.storeCur)],
                        ["TAG", root.storeCur.ref],
                        ["SHA", sl.short(root.storeCur.sha)],
                        ["SOURCE", root.storeCur.repo],
                        ["INSTALLED", root.storeCur.installed_version !== "" ? ("v" + root.storeCur.installed_version + (root.storeCur.state === "update" ? ("  >  " + root.storeCur.ref) : "")) : "-"],
                        ["RUNNING", root.storeCur.running ? "YES" : "NO"]
                    ] : []
                    delegate: Item {
                        required property int index
                        required property var modelData
                        y: card.px(88) + index * card.px(34)
                        width: stp.width; height: card.px(34)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]; color: th.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15); font.letterSpacing: 1.5
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: stp.width - card.px(150); horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                            text: modelData[1]; color: th.ink
                            font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.7 }
                    }
                }
                Text {
                    y: card.px(306); width: parent.width; elide: Text.ElideRight
                    text: sl.hint(root.storeCur)
                    color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true
                }
                Text {
                    y: card.px(332)
                    text: "B  BACKUPS      R  REFRESH"
                    color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14)
                }
                Text {
                    y: card.px(366); width: parent.width
                    wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    text: root.storeMsg
                    color: root.storeOk ? th.ink : th.danger
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: !root.storeOk
                }
                Text {
                    y: card.px(408); width: parent.width
                    visible: root.storeStale
                    text: "OFFLINE: ĐANG DÙNG CACHE CŨ"
                    color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(13)
                }
            }
            // registry trống / lỗi tải
            Text {
                x: card.m + card.px(340) + card.px(30); y: card.px(96)
                width: card.width - x - card.m
                visible: root.page === "store" && root.storeView === "list" && root.storeCur === null && !root.storeBusy
                wrapMode: Text.WordWrap
                text: root.storeLoaded ? "REGISTRY TRỐNG" : (root.storeMsg !== "" ? root.storeMsg : "ĐANG TẢI ...")
                color: root.storeOk ? th.ink : th.danger
                font.family: root.fontLabel; font.pixelSize: card.fs(20); font.bold: true
            }

            // màn hình xác nhận (cài / cập nhật / gỡ / khôi phục)
            Item {
                id: scp
                visible: root.page === "store" && root.storeView === "confirm"
                x: card.m; y: card.px(76)
                width: card.width - 2 * card.m
                height: storeList.height

                Rectangle { width: parent.width; height: 1; color: th.ink }
                Text {
                    y: card.px(8)
                    text: "CONFIRM " + root.confirmOp.toUpperCase() + " / " + root.pendingId.toUpperCase()
                    color: th.ink
                    font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                }
                Text {
                    anchors.right: parent.right; y: card.px(14)
                    text: root.confirmOk ? "REVIEW, THEN CONFIRM" : "BLOCKED"
                    color: root.confirmOk ? th.soft : th.danger
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2; font.bold: !root.confirmOk
                }
                Rectangle { y: card.px(46); width: parent.width; height: 1; color: th.rule }
                Column {
                    y: card.px(54); width: parent.width
                    Repeater {
                        model: root.confirmRows
                        delegate: Item {
                            required property var modelData
                            width: scp.width; height: card.px(26)
                            Text {
                                x: card.px(2); width: card.px(130); anchors.verticalCenter: parent.verticalCenter
                                text: modelData[0]; color: th.soft
                                font.family: root.fontLabel; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                            }
                            Text {
                                x: card.px(140); width: parent.width - card.px(140); anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData[1]
                                color: modelData[2] ? th.danger : th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: modelData[2] === true
                            }
                        }
                    }
                }
            }

            // bản sao lưu để khôi phục
            Item {
                id: sbp
                visible: root.page === "store" && root.storeView === "backups"
                x: card.m + card.px(340) + card.px(30)
                y: card.px(76)
                width: card.width - x - card.m
                height: storeList.height

                Rectangle { width: parent.width; height: 1; color: th.ink }
                Text {
                    y: card.px(8)
                    text: "BACKUPS / " + root.pendingId.toUpperCase()
                    color: th.ink
                    font.family: root.fontTitle; font.pixelSize: card.fs(24); font.bold: true
                }
                Text {
                    anchors.right: parent.right; y: card.px(14)
                    text: root.backups.length + " FOUND"
                    color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                }
                ListView {
                    id: sbl
                    y: card.px(46); width: parent.width; height: card.px(300)
                    clip: true
                    interactive: false
                    model: root.backups
                    currentIndex: root.bkSel
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Item {
                        id: sbr
                        required property int index
                        required property var modelData
                        readonly property bool on: index === root.bkSel
                        width: sbl.width; height: card.px(34)
                        Rectangle {
                            anchors.fill: parent; anchors.bottomMargin: 1
                            color: sbr.on ? th.ink : (sbm.containsMouse ? th.wash : "transparent")
                        }
                        Text {
                            x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                            text: "v" + sbr.modelData.version
                            color: sbr.on ? th.paper : th.ink
                            font.family: root.fontLabel; font.pixelSize: card.fs(16); font.bold: true
                        }
                        Text {
                            x: card.px(130); anchors.verticalCenter: parent.verticalCenter
                            text: sbr.modelData.stamp
                            color: sbr.on ? th.paper : th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(14)
                        }
                        MouseArea {
                            id: sbm
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (!root.storeBusy) root.bkSel = sbr.index }
                        }
                    }
                }
                Text {
                    y: card.px(60); visible: root.backups.length === 0
                    text: "KHÔNG CÓ BẢN SAO LƯU"
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(18); font.bold: true
                }
                Text {
                    y: card.px(360); width: parent.width
                    wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                    text: root.storeMsg
                    color: root.storeOk ? th.ink : th.danger
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: !root.storeOk
                }
            }

            // đang chạy lệnh store: che vùng nội dung, chặn chuột
            Item {
                id: sbusy
                visible: root.page === "store" && root.storeBusy
                x: card.m; y: card.px(76)
                width: card.width - 2 * card.m
                height: storeList.height
                Rectangle { anchors.fill: parent; color: th.paper; opacity: 0.94 }
                MouseArea { anchors.fill: parent }
                Text {
                    anchors.centerIn: parent
                    text: root.storeBusyText
                    color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(20); font.letterSpacing: 2; font.bold: true
                }
            }

            // ---------- PREVIEW (góc dưới trái; V bật/tắt) ----------
            Item {
                id: pvFrame
                visible: root.previewOn && root.page !== "store"
                x: card.m
                y: card.px(76) + (card.height - card.px(76) - card.px(96)) - card.pvH
                width: card.pvW; height: card.pvH

                Text {
                    anchors.bottom: parent.top; anchors.bottomMargin: card.px(6)
                    width: parent.width - card.px(70); elide: Text.ElideRight
                    text: root.pvApp === null ? "NO PREVIEW FOR THIS SCOPE"
                          : (pvLoader.status === Loader.Error ? "PREVIEW UNAVAILABLE (VIEW.QML)"
                          : ("PREVIEW   " + String(root.pvApp.name).toUpperCase() + (root.pvFn !== "" ? (" / " + root.pvFn.toUpperCase()) : "")))
                    color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                }
                Text {
                    anchors.bottom: parent.top; anchors.bottomMargin: card.px(6)
                    anchors.right: parent.right
                    text: "V HIDE"
                    color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                }
                Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: th.ink; z: 2 }
                Item {
                    anchors.fill: parent; anchors.margins: 1
                    clip: true
                    // Sân khấu 1920x1080 thu nhỏ: View tính kích thước theo u = min(w/1920, h/1080) nên hình giống hệt khi chạy thật
                    Item {
                        id: pvStage
                        width: 1920; height: 1080
                        scale: (card.pvW - 2) / 1920
                        transformOrigin: Item.TopLeft
                        Loader {
                            id: pvLoader
                            anchors.fill: parent
                            active: root.previewOn && root.page !== "store" && root.pvApp !== null
                            source: root.pvApp !== null ? encodeURI("file://" + root.pvApp.dir + "/View.qml") : ""
                            onLoaded: root.pvApply()
                        }
                    }
                }
                MouseArea { anchors.fill: parent; z: 3 }     // preview chỉ để xem, không nhận chuột
            }

            // ---------- CRT: scanline + thanh quét (chỉ trang trí, không bắt chuột) ----------
            Repeater {
                model: root.crtScan ? Math.ceil(card.height / Math.max(3, Math.round(3 * card.u))) : 0
                delegate: Rectangle {
                    required property int index
                    y: index * Math.max(3, Math.round(3 * card.u))
                    width: card.width; height: 1
                    color: th.ink; opacity: root.crtScanOpacity; z: 40
                }
            }
            Rectangle {
                id: scanBar
                visible: root.crtScan && root.crtContentP > 0 && !root.closing
                width: card.width; height: card.px(110); z: 39
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(th.ink.r, th.ink.g, th.ink.b, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(th.ink.r, th.ink.g, th.ink.b, 0.06) }
                    GradientStop { position: 1.0; color: Qt.rgba(th.ink.r, th.ink.g, th.ink.b, 0.0) }
                }
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: scanBar.visible
                    NumberAnimation { from: -scanBar.height; to: card.height; duration: 3200; easing.type: Easing.Linear }
                    PauseAnimation { duration: 1200 }
                }
            }

            // ---------- AUTO-REVERT: thanh đếm ngược sau Apply ----------
            Item {
                id: revBar
                visible: root.revertActive
                z: 20
                x: card.m; width: card.width - 2 * card.m
                y: card.height - card.px(96) - card.px(52)
                height: card.px(48)
                Rectangle { anchors.fill: parent; color: th.ink }
                Rectangle {
                    anchors.bottom: parent.bottom
                    height: card.px(4)
                    width: root.revertTotal > 0 ? parent.width * (root.revertLeft / root.revertTotal) : 0
                    color: th.danger
                }
                Text {
                    x: card.px(16); anchors.verticalCenter: parent.verticalCenter
                    text: "KEEP THIS SETTING?   REVERTING IN " + root.revertLeft + " s"
                    color: th.paper
                    font.family: root.fontData; font.pixelSize: card.fs(17); font.bold: true; font.letterSpacing: 1.5
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: card.px(16); anchors.verticalCenter: parent.verticalCenter
                    text: "ENTER  KEEP      ESC  REVERT NOW"
                    color: th.paper
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 1.5
                }
            }

            // ---------- chân trang ----------
            Rectangle { x: card.m; y: card.height - card.px(66); width: card.width - 2 * card.m; height: 1; color: th.rule }
            Text {
                x: card.m; y: card.height - card.px(52)
                text: root.footerText
                color: th.soft
                font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 1
            }
        }
    }
}
