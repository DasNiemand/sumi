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
//   LAYOUT:  cửa sổ toàn màn hình; trang APPS là dashboard 3 cột (APPS/REGISTRY/LOG | chi tiết/FUNCTIONS/KEYBINDS/RUN | PREVIEW/SYSTEM/SHORTCUTS). Settings và STORE giữ bố cục cũ.
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

    // ===== DASHBOARD (trang APPS): dữ liệu dẫn xuất + số liệu hệ thống thật =====
    // Tên hiển thị: manifest.name có thể kèm kanji ("JIGEN 時限"); kanji đã có ô riêng nên bỏ khỏi tiêu đề.
    function titleOf(a) {
        if (a === null || a === undefined) return ""
        const n = String(a.name)
        const k = typeof a.kanji === "string" ? a.kanji : ""
        if (k !== "" && n.length > k.length && n.endsWith(k)) return n.slice(0, n.length - k.length).trim().toUpperCase()
        return n.toUpperCase()
    }
    // Object đang dùng cho một function: config.apps.<id>.objects.<fn>.id nếu hợp lệ, không thì defaultObject.
    function fnObjId(a, f) {
        const objs = (f !== null && f !== undefined && Array.isArray(f.objects)) ? f.objects : []
        const d = cfg.data
        const ap = (d !== null && typeof d === "object" && d.apps !== null && typeof d.apps === "object" && a !== null && a !== undefined) ? d.apps[a.id] : null
        const ob = (ap !== null && ap !== undefined && typeof ap === "object" && ap.objects !== null && typeof ap.objects === "object") ? ap.objects[f.id] : null
        const v = (ob !== null && ob !== undefined && typeof ob === "object") ? ob.id : undefined
        if (typeof v === "string" && objs.indexOf(v) >= 0) return v
        if (f !== null && f !== undefined && typeof f.defaultObject === "string" && f.defaultObject !== "") return f.defaultObject
        return objs.length > 0 ? objs[0] : "-"
    }
    readonly property int runningCount: {
        let n = 0
        for (let i = 0; i < apps.length; i++) if (apps[i].running === true) n++
        return n
    }
    readonly property var curInfo: {
        const a = cur
        if (a === null) return []
        const nopt = Array.isArray(a.options) ? a.options.length : 0
        const nkey = Array.isArray(a.keybinds) ? a.keybinds.length : 0
        return [
            ["VERSION", "v" + a.version],
            ["SOURCE", (a.source === "dev" || !a.source) ? "DEV (LOCAL)" : String(a.source)],
            ["KIND", a.kind === "daemon" ? "DAEMON" : "ONESHOT"],
            ["REF", a.ref ? String(a.ref) : "-"],
            ["STATUS", a.running ? "RUNNING" : "IDLE"],
            ["SHA", a.sha ? sl.short(a.sha) : "-"],
            ["FUNCTIONS", String(curFns.length)],
            ["OPTIONS / KEYS", nopt + " / " + nkey]
        ]
    }
    // Phím hiệu lực của app đang chọn (mặc định, hoặc phần người dùng đã đổi ở tab KEYS).
    readonly property var curKeys: {
        const a = cur
        if (a === null || !Array.isArray(a.keybinds)) return []
        const ks = ce.keysOf(cfg.data, a.id)
        return a.keybinds.map(k => ({ label: String(k.label).toUpperCase(), key: String(ce.keyEff(k, ks)) }))
    }
    readonly property string runLabel: {
        if (cur === null) return ""
        let s = "RUN   " + titleOf(cur)
        if (cur.kind === "daemon" && curFns.length > 0) s += "  /  " + String(curFns[Math.max(0, Math.min(fnSel, curFns.length - 1))].label)
        return s
    }
    // Phím tắt bằng chuột ở dashboard. Cùng điều kiện chặn như bàn phím: đang tắt máy / đếm ngược revert thì bỏ qua.
    function dashAct(id) {
        if (closing || revertActive || page !== "apps") return
        if (id === "T" || id === "TAB") openSettings("theme")
        else if (id === "F") openSettings("font")
        else if (id === "K") openSettings("keys")
        else if (id === "O") openSettings("options")
        else if (id === "G") openStore()
        else if (id === "ESC") dismiss()
        else if (id === "RUN") runSelected()
    }

    property int sysUp: -1
    property real sysMem: -1                // tỉ lệ đã dùng 0..1 (-1 = chưa có số liệu)
    property string sysMemText: ""
    property string sysLoad: ""
    property int sysBat: -1
    property string sysBatState: ""
    property int sysTemp: -1                // °C, max các cảm biến (không gọi là CPU)
    property var logLines: []
    property var logBuf: []
    // Mỗi dòng `khóa=giá trị` do sysProc in ra; `begin` mở lượt mới, `end` chốt lượt (log chỉ cập nhật khi đổi).
    function sysLine(line) {
        const i = line.indexOf("=")
        if (i < 0) return
        const k = line.slice(0, i)
        const v = line.slice(i + 1)
        if (k === "begin") logBuf = []
        else if (k === "up") { const n = parseInt(v); sysUp = isNaN(n) ? -1 : n }
        else if (k === "mem") {
            const p = v.split(" ")
            const t = parseInt(p[0])
            const av = parseInt(p[1])
            if (t > 0 && av >= 0 && av <= t) { sysMem = (t - av) / t; sysMemText = ((t - av) / 1048576).toFixed(1) + " / " + (t / 1048576).toFixed(1) + " GB" }
        }
        else if (k === "load") sysLoad = v
        else if (k === "bat") { const p = v.split(" "); const n = parseInt(p[0]); sysBat = isNaN(n) ? -1 : Math.max(0, Math.min(100, n)); sysBatState = p.slice(1).join(" ") }
        else if (k === "temp") { const n = parseInt(v); sysTemp = (isNaN(n) || n <= 0) ? -1 : Math.round(n / 1000) }
        else if (k === "log") logBuf = logBuf.concat([v])
        else if (k === "end") { if (JSON.stringify(logBuf) !== JSON.stringify(logLines)) logLines = logBuf.slice() }
    }
    function fmtUp(s) {
        if (s < 0) return "-"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        return (d > 0 ? d + "d " : "") + (h < 10 ? "0" : "") + h + "h " + (m < 10 ? "0" : "") + m + "m"
    }
    property string nowText: ""
    property string hexText: "0x0000 0000 0000"
    function hex4() { return ("0000" + Math.floor(Math.random() * 65536).toString(16)).slice(-4).toUpperCase() }

    // ===== Trang cài đặt: MỘT màn hình cho mỗi phạm vi (GLOBAL / HUB / từng app) gồm THEME + FONT + KEYS + OPTIONS (có OBJECTS) =====
    // `page` là section đang focus (theme | font | keys | options); mọi section áp dụng cho phạm vi hiện tại hiện cùng lúc.
    property string page: "apps"            // apps | store | theme | font | keys | options
    property int pageTok: 0                 // tăng mỗi lần đổi trang/section: các tiêu đề giải mã lại (scramble)
    onPageChanged: pageTok++
    readonly property var secIds: ["theme", "font", "keys", "options"]
    readonly property bool inSettings: secIds.indexOf(page) >= 0
    property int scopeSel: 0
    property string keepScope: "global"     // phạm vi người dùng chọn gần nhất
    function appById(id) {
        for (let i = 0; i < apps.length; i++) if (apps[i].id === id) return apps[i]
        return null
    }
    function hasKeybinds(a) { return a !== null && Array.isArray(a.keybinds) && a.keybinds.length > 0 }
    function hasOptions(a) { return a !== null && Array.isArray(a.options) && a.options.length > 0 }
    function hasObjects(a) { return a !== null && ce.objectOptsOf(a).length > 0 }
    // Phạm vi: GLOBAL, HUB, rồi mọi app. Section nào không áp dụng cho phạm vi thì ẩn (secCount = 0).
    readonly property var scopes: {
        const l = [{ id: "global", name: "GLOBAL" }, { id: "hub", name: "HUB" }]
        for (let i = 0; i < apps.length; i++) l.push({ id: apps[i].id, name: String(apps[i].name).toUpperCase() })
        return l
    }
    readonly property bool hasScope: scopes.length > 0
    readonly property string scopeId: hasScope ? scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].id : ""
    readonly property string scopeName: hasScope ? scopes[Math.max(0, Math.min(scopeSel, scopes.length - 1))].name : ""
    readonly property var scopeApp: appById(scopeId)

    property string applyMsg: ""
    property string applyErr: ""
    property bool applyOk: false

    // ----- SECTION: hàng của từng section, focus, di chuyển xuyên section -----
    property int themeSel: 0                // 0 = PRESET, 1 = TINT, 2 = INK DARKEN
    function secCount(s) {
        if (s === "theme") return tintEditable ? 3 : 1
        if (s === "font") return fontRows.length
        if (s === "keys") return kbList.length
        if (s === "options") return optList.length
        return 0
    }
    function secSel(s) { return s === "theme" ? themeSel : (s === "font" ? fontSel : (s === "keys" ? keySel : optSel)) }
    readonly property var secList: secIds.filter(s => secCount(s) > 0)
    function secTitle(s) {
        if (s === "options") return objOptList.length > 0 ? (plainOptList.length > 0 ? "OPTIONS / OBJECTS" : "OBJECTS") : "OPTIONS"
        return s.toUpperCase()
    }
    // Mô hình cho danh sách chính: tiêu đề section + từng hàng.
    readonly property var viewRows: {
        const out = []
        for (let s = 0; s < secIds.length; s++) {
            const n = secCount(secIds[s])
            if (n === 0) continue
            out.push({ kind: "head", sec: secIds[s], i: -1 })
            for (let i = 0; i < n; i++) out.push({ kind: "row", sec: secIds[s], i: i })
        }
        return out
    }
    readonly property int flatCount: {
        let n = 0
        for (let s = 0; s < secIds.length; s++) n += secCount(secIds[s])
        return n
    }
    // vị trí hàng đang focus trong viewRows (để ListView cuộn theo)
    readonly property int viewSel: {
        for (let k = 0; k < viewRows.length; k++) if (viewRows[k].kind === "row" && viewRows[k].sec === page && viewRows[k].i === secSel(page)) return k
        return 0
    }
    function focusRow(s, i) {
        capturing = false; pickOpen = false; optEditing = false; capMsg = ""; optMsg = ""
        const n = secCount(s)
        if (n === 0) return
        const j = Math.max(0, Math.min(i, n - 1))
        page = s
        if (s === "theme") themeSel = j; else if (s === "font") fontSel = j; else if (s === "keys") keySel = j; else optSel = j
    }
    // W/S: đi hàng kế tiếp, hết section thì sang section kế (vòng tròn)
    function moveRow(d) {
        const seq = []
        for (let s = 0; s < secIds.length; s++) for (let i = 0; i < secCount(secIds[s]); i++) seq.push([secIds[s], i])
        if (seq.length === 0) return
        let k = 0
        for (let q = 0; q < seq.length; q++) if (seq[q][0] === page && seq[q][1] === secSel(page)) { k = q; break }
        k = (k + d + seq.length) % seq.length
        focusRow(seq[k][0], seq[k][1])
    }
    function jumpSection(n) {
        const l = secList
        if (n < 0 || n >= l.length) return
        focusRow(l[n], secSel(l[n]))
    }
    function cycleSection(d) {
        const l = secList
        if (l.length === 0) return
        let i = l.indexOf(page)
        if (i < 0) i = 0
        jumpSection((i + d + l.length) % l.length)
    }

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
    readonly property var fontRows: scopeId === "global" ? ce.roles : (scopeApp !== null ? ce.fontRolesOf(scopeApp) : [])
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
    // OPTIONS gồm hai nhóm trong cùng một danh sách: OBJECTS (hàng "ảo" sinh từ manifest.functions[], xem SumiConfigEdit.objectOptsOf) rồi option khai trong manifest.
    // Ghi config thì tách lại: objects -> apps.<id>.objects, còn lại -> apps.<id>.options (hub: config.hub).
    readonly property var objOptList: (scopeId !== "hub" && hasObjects(scopeApp)) ? ce.objectOptsOf(scopeApp) : []
    readonly property var plainOptList: scopeId === "hub" ? ce.hubOptsList() : (hasOptions(scopeApp) ? optsWithout(scopeApp.options, objOptList) : [])
    readonly property var optList: objOptList.concat(plainOptList)
    function optsWithout(list, excl) {
        const ex = ({})
        for (let i = 0; i < excl.length; i++) ex[excl[i].key] = true
        return list.filter(o => ex[o.key] !== true)
    }
    function mergeOpts(a, b) {
        const o = ({})
        for (const k1 in a) o[k1] = a[k1]
        for (const k2 in b) o[k2] = b[k2]
        return o
    }
    readonly property var optStored: mergeOpts(ce.objectsOf(cfg.data, scopeId, objOptList), scopeId === "hub" ? ce.hubOptionsOf(cfg.data) : ce.optionsOf(cfg.data, scopeId, plainOptList))
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
    // Nhãn ở danh sách phạm vi: số mục đã tuỳ chỉnh (theme + font + phím + option + object) của phạm vi đó.
    function scopeTag(id) {
        const lk = ce.lookOf(cfg.data, id)
        let n = (lk.theme !== null || lk.tint !== null || lk.inkDarken !== null) ? 1 : 0
        const f = ce.fontsOf(cfg.data, id)
        for (let i = 0; i < ce.roles.length; i++) if (f[ce.roles[i]] !== null) n++
        n += Object.keys(ce.keysOf(cfg.data, id)).length
        if (id === "hub") n += Object.keys(ce.hubOptionsOf(cfg.data)).length
        else {
            const a = appById(id)
            if (a !== null) {
                n += Object.keys(ce.objectsOf(cfg.data, id, ce.objectOptsOf(a))).length
                n += Object.keys(ce.optionsOf(cfg.data, id, Array.isArray(a.options) ? a.options : [])).length
            }
        }
        return n > 0 ? (n + " SET") : "DEFAULT"
    }
    function tabDirty(id) { return id === "theme" ? dirty : (id === "font" ? fontDirty : (id === "keys" ? keyDirty : (id === "options" ? optDirty : false))) }
    readonly property bool anyDirty: dirty || fontDirty || keyDirty || optDirty
    readonly property var dirtyList: secIds.filter(s => secCount(s) > 0 && tabDirty(s))
    function loadDraft() {
        draft = ce.lookOf(cfg.data, scopeId)
        fontDraft = ce.fontsOf(cfg.data, scopeId)
        keyDraft = ce.keysOf(cfg.data, scopeId)
        optDraft = optStored
        themeSel = 0; fontSel = 0; keySel = 0; optSel = 0
        pickOpen = false; capturing = false; capMsg = ""
        optEditing = false; optBuf = ""; optMsg = ""
        applyMsg = ""; applyErr = ""
        if (secCount(page) === 0) page = "theme"
    }
    // Vào cài đặt ở section p với phạm vi id (không có trong danh sách thì về phần tử đầu).
    function enterPage(p, id) {
        page = secIds.indexOf(p) >= 0 ? p : "theme"
        const ids = scopes.map(s => s.id)
        const i = ids.indexOf(id)
        scopeSel = i >= 0 ? i : 0
        keepScope = scopeId
        ensureFonts()
        loadDraft()
    }
    // Từ dashboard: mở cài đặt của app đang chọn (p "objects" cũ = section options)
    function openSettings(p) { enterPage(p === "objects" ? "options" : p, cur !== null ? cur.id : keepScope) }
    function closeSettings() { page = "apps"; pickOpen = false; capturing = false; optEditing = false }
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
    function resetThemeRow() {
        if (themeSel === 0) draft = { theme: null, tint: draft.tint, inkDarken: draft.inkDarken }
        else if (themeSel === 1) draft = { theme: draft.theme, tint: null, inkDarken: draft.inkDarken }
        else draft = { theme: draft.theme, tint: draft.tint, inkDarken: null }
        applyMsg = ""; applyErr = ""
    }
    // A/D (và Enter) trên hàng đang focus; R = mặc định hàng; X = mặc định cả section
    function rowAdjust(d) {
        if (page === "theme") {
            if (themeSel === 0) movePreset(d)
            else if (themeSel === 1) nudge("tint", 0.02 * d)
            else nudge("ink", 0.1 * d)
        } else if (page === "options") nudgeOpt(d)
    }
    function rowEnter() {
        if (page === "theme") { if (themeSel === 0) movePreset(1) }
        else if (page === "font") openPicker()
        else if (page === "keys") startCapture()
        else if (page === "options") enterOpt()
    }
    function rowReset() {
        if (page === "theme") resetThemeRow()
        else if (page === "font") resetFontRow()
        else if (page === "keys") resetKeyRow()
        else if (page === "options") resetOptRow()
    }
    function sectionReset() {
        if (page === "theme") inheritScope()
        else if (page === "font") resetFontAll()
        else if (page === "keys") resetKeyAll()
        else if (page === "options") resetOptAll()
    }
    // Dòng chi tiết cho hàng đang focus (cột phải) + kết quả Apply.
    readonly property var detailLines: {
        const L = []
        if (page === "theme") {
            L.push({ t: "CONTRAST  " + curDerived.contrast.toFixed(2) + " : 1   " + (blocked ? "BLOCKED (<4.5)" : (weak ? "WEAK (<7)" : "OK")), bad: blocked })
            if (!tintEditable) L.push({ t: "HUB dùng tint và độ đậm của GLOBAL", bad: false })
            else L.push({ t: themeSel === 0 ? "A/D ĐỔI PRESET   R INHERIT" : (themeSel === 1 ? "A/D CHỈNH TINT (0..0.6)   R INHERIT" : "A/D CHỈNH INK DARKEN (1..2.5)   R INHERIT"), bad: false })
        } else if (page === "font") {
            if (fontWarn !== "") L.push({ t: fontWarn, bad: true })
            else L.push({ t: fontListLoaded ? (fontList.length + " FONTS INSTALLED") : "LOADING FONT LIST...", bad: false })
            L.push({ t: "ENTER MỞ BỘ CHỌN FONT   R INHERIT", bad: false })
        } else if (page === "keys") {
            const cm = (curKb !== null && keyConf[curKb.action] !== undefined) ? keyConf[curKb.action] : []
            if (capMsg !== "") L.push({ t: capMsg, bad: true })
            else if (capturing) L.push({ t: "ĐANG GÁN: " + (curKb !== null ? curKb.action : ""), bad: false })
            else if (cm.length > 0) L.push({ t: "CẢNH BÁO: " + cm.join("; "), bad: true })
            else if (keyConfCount > 0) L.push({ t: keyConfCount + " ACTION CÓ CẢNH BÁO", bad: true })
            else L.push({ t: "KHÔNG TRÙNG PHÍM", bad: false })
            L.push({ t: "ENTER GÁN PHÍM   R MẶC ĐỊNH", bad: false })
        } else if (page === "options") {
            const cm2 = (curOpt !== null && optConf[curOpt.key] !== undefined) ? optConf[curOpt.key] : []
            if (optMsg !== "") L.push({ t: optMsg, bad: true })
            else if (cm2.length > 0) L.push({ t: "CẢNH BÁO: " + cm2.join("; "), bad: true })
            else L.push({ t: String(ce.optHint(curOpt)), bad: false })
        }
        if (applyMsg !== "") L.push({ t: applyErr !== "" ? (applyMsg + "  " + applyErr) : applyMsg, bad: !applyOk })
        return L
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
        if (scopeId === "hub" && optDirty) return false    // đổi chính cài đặt auto-revert thì không tự hoàn tác
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
    // Apply gộp: mọi section đang có thay đổi của phạm vi hiện tại được ghi trong MỘT lần `sumi config apply`.
    function applyCurrent() {
        if (applyProc.running) return
        let next = cfg.data
        const done = []
        if (dirty) {
            if (blocked) { fail("BLOCKED", "THEME: tương phản dưới 4.5, không cho áp dụng"); return }
            const e1 = ce.validateLook(draft, scopeId)
            if (e1.length > 0) { fail("REJECTED", e1.join("; ")); return }
            next = ce.withLook(next, scopeId, draft); done.push("THEME")
        }
        if (fontDirty && fontRows.length > 0) {
            const e2 = ce.validateFonts(fontDraft, scopeId)
            if (e2.length > 0) { fail("REJECTED", e2.join("; ")); return }
            next = ce.withFonts(next, scopeId, fontDraft); done.push("FONT")
        }
        if (keyDirty && kbList.length > 0) {
            const e3 = ce.validateKeys(keyDraft, kbList, scopeId)
            if (e3.length > 0) { fail("REJECTED", e3.join("; ")); return }
            next = ce.withKeys(next, scopeId, keyDraft, kbList); done.push("KEYS")
        }
        if (optDirty && optList.length > 0) {
            const e4 = ce.validateOptions(optDraft, optList, scopeId)
            if (e4.length > 0) { fail("REJECTED", e4.join("; ")); return }
            if (scopeId === "hub") next = ce.withHubOptions(next, optDraft)
            else { next = ce.withObjects(next, scopeId, optDraft, objOptList); next = ce.withOptions(next, scopeId, optDraft, plainOptList) }
            done.push("OPTIONS")
        }
        if (done.length === 0) { fail("NO CHANGES"); return }
        commitConfig(next)
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
    readonly property var pvApp: {
        if (page === "store") return null
        if (page === "apps") return cur
        if (scopeId === "hub") return null
        if (scopeApp !== null && scopeId !== "global") return scopeApp
        return cur !== null ? cur : (apps.length > 0 ? apps[0] : null)
    }
    readonly property var pvFns: (pvApp !== null && Array.isArray(pvApp.functions)) ? pvApp.functions : []
    // function đang xem: trang APPS theo A/D; section OPTIONS theo hàng đang chọn (tiền tố function); còn lại function đầu tiên
    readonly property var pvFnObj: {
        if (pvFns.length === 0) return null
        if (page === "options" && curOpt !== null) {
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
        if (inSettings && scopeId === pvApp.id) d = ce.withObjects(cfg.data, pvApp.id, optDraft, objOptList)
        const a = (d !== null && typeof d === "object" && d.apps !== null && typeof d.apps === "object" && d.apps[pvApp.id] !== undefined) ? d.apps[pvApp.id] : null
        return (a !== null && typeof a === "object" && a.objects !== null && typeof a.objects === "object") ? a.objects : ({})
    }
    // Giá trị look hiệu lực cho app đang preview; đang sửa chính scope đó (hoặc global mà app không ghi đè) thì lấy bản nháp.
    function pvPick(key, eff) {
        if (inSettings && pvApp !== null) {
            if (scopeId === pvApp.id) return eff
            if (scopeId === "global") return pvLookS[key] !== null ? pvLookS[key] : eff
        }
        return pvLookS[key] !== null ? pvLookS[key] : pvInh[key]
    }
    function pvFam(role) {
        if (pvApp === null) return ce.fontDefaults[role]
        const own = ce.fontsOf(cfg.data, pvApp.id)[role]
        let v
        if (inSettings && scopeId === pvApp.id) v = fontEff(role)
        else if (inSettings && scopeId === "global") v = own !== null ? own : fontEff(role)
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
        if (page === "apps") return "W/S APP  A/D FUNC  ENTER RUN  TAB SETTINGS  T F K O JUMP  G STORE  ESC"
        if (page === "store") {
            if (storeBusy) return "WORKING ...   PLEASE WAIT"
            if (storeView === "confirm") return confirmOk ? "ENTER CONFIRM   ESC CANCEL" : "BLOCKED   ESC BACK"
            if (storeView === "backups") return "W/S SELECT   ENTER RESTORE   ESC BACK"
            return "W/S APP   ENTER INSTALL/UPDATE   X REMOVE   B BACKUPS   R REFRESH   ESC BACK"
        }
        if (optEditing) return "TYPE VALUE   ENTER OK   ESC CANCEL   BACKSPACE DELETE"
        if (capturing) return "PRESS A KEY   ESC CANCEL"
        if (pickOpen) return "TYPE FILTER   UP/DOWN MOVE   ENTER SELECT   TAB " + (pickKind === "ja" ? "JA ONLY" : (pickKind === "mono" ? "MONO ONLY" : "-")) + "   ESC CANCEL"
        return "W/S ROW  A/D CHANGE  ENTER EDIT  Q/E APP  TAB SECTION  SPACE APPLY  R DEFAULT  X SECTION  ESC BACK"
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


    // Số liệu hệ thống thật cho dashboard (kiểu skill: một Process + SplitParser, mỗi 2 s, chỉ khi đang ở trang APPS)
    Process {
        id: sysProc
        command: ["sh", "-c", [
            "echo begin=1",
            "echo up=$(cut -d. -f1 /proc/uptime 2>/dev/null)",
            "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print \"mem=\" t \" \" a}' /proc/meminfo 2>/dev/null",
            "echo load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)",
            "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && { echo \"bat=$(cat \"$b/capacity\") $(cat \"$b/status\" 2>/dev/null)\"; break; }; done",
            "t=0; for f in /sys/class/hwmon/hwmon*/temp1_input /sys/class/thermal/thermal_zone*/temp; do [ -r \"$f\" ] || continue; v=$(cat \"$f\" 2>/dev/null); [ \"${v:-0}\" -gt \"$t\" ] 2>/dev/null && t=$v; done; echo temp=$t",
            "tail -n 6 /tmp/sumi.log 2>/dev/null | sed 's/^/log=/'",
            "echo end=1"
        ].join("\n")]
        stdout: SplitParser { onRead: (line) => root.sysLine(line) }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.page === "apps" && !root.closing
        onTriggered: if (!sysProc.running) sysProc.running = true
    }
    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.nowText = Qt.formatDateTime(new Date(), "ddd dd MMM   HH:mm:ss").toUpperCase()
    }
    Timer {
        interval: 130; repeat: true
        running: root.page === "apps" && root.crtContentP >= 1 && !root.closing
        onTriggered: root.hexText = "0x" + root.hex4() + " " + root.hex4() + " " + root.hex4()
    }

    // Thanh ô vuông (PixelBar): ô cuối đang sáng nhấp nháy. Inline component không thấy id bên ngoài nên màu truyền qua property.
    component PixelBar: Item {
        id: pb
        property real value: 0
        property int cells: 20
        property color litColor: "#000000"
        property color dimColor: "#888888"
        property color alertColor: "#E63946"
        property bool alert: false
        property bool blink: true
        readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * cells)
        Timer { interval: 420; repeat: true; running: pb.visible && pb.lit > 0; onTriggered: pb.blink = !pb.blink }
        Row {
            spacing: 2
            Repeater {
                model: pb.cells
                delegate: Rectangle {
                    required property int index
                    width: Math.max(1, (pb.width - (pb.cells - 1) * 2) / pb.cells)
                    height: pb.height
                    color: index < pb.lit ? (pb.alert ? pb.alertColor : pb.litColor) : pb.dimColor
                    opacity: index >= pb.lit ? 0.45 : ((index === pb.lit - 1 && !pb.blink) ? 0.3 : 1)
                }
            }
        }
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
            anchors.fill: parent
            // Toàn màn hình. zoom nhân thêm vào u để chữ/khung dễ đọc ở 1080p; px()/fs() vẫn là đơn vị thiết kế 1920x1080.
            readonly property real zoom: 1.15
            readonly property real u: Math.max(0.6, Math.min(win.width / 1920, win.height / 1080) * zoom)
            function px(n) { return Math.max(1, Math.round(n * u)) }
            function fs(n) { return Math.max(8, Math.round(n * u)) }
            opacity: root.crtFlicker
            transform: Scale {
                origin.x: card.width / 2; origin.y: card.height / 2
                xScale: root.crtXs; yScale: root.crtYs
            }
            readonly property real m: px(44)
            // Hình học dashboard (trang APPS): vùng nội dung giữa thanh trên và chân trang, chia 3 cột A / B / C
            readonly property real gx: m
            readonly property real gy: px(76)
            readonly property real gw: width - 2 * m
            readonly property real gh: height - px(76) - px(96)
            readonly property real gg: px(30)
            readonly property real wA: Math.round(gw * 0.22)
            readonly property real wC: Math.round(gw * 0.30)
            readonly property real wB: gw - wA - wC - 2 * gg
            readonly property real dashPvY: px(36)
            // Preview luôn bật (trừ trang STORE): chiếm đầu cột C ở dashboard và ở màn hình cài đặt, không cao quá ~36% vùng nội dung để cột C luôn đủ chỗ.
            readonly property real pvW: root.page !== "store" ? Math.min(wC, Math.round(gh * 0.36 * 16 / 9)) : px(340)
            readonly property real pvH: Math.round(pvW * 9 / 16)

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
                    else if (k === Qt.Key_J) { if (!ar) root.openSettings("options"); event.accepted = true }
                    else if (k === Qt.Key_G) { if (!ar) root.openStore(); event.accepted = true }
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
                if (k === Qt.Key_Tab) { if (!ar) root.cycleSection(1); event.accepted = true; return }
                if (k === Qt.Key_Backtab) { if (!ar) root.cycleSection(-1); event.accepted = true; return }
                if (k >= Qt.Key_1 && k <= Qt.Key_4) { if (!ar) root.jumpSection(k - Qt.Key_1); event.accepted = true; return }
                if (k === Qt.Key_Q) { if (!ar) root.moveScope(-1); event.accepted = true; return }
                if (k === Qt.Key_E) { if (!ar) root.moveScope(1); event.accepted = true; return }
                if (k === Qt.Key_Space) { if (!ar) root.applyCurrent(); event.accepted = true; return }
                if (k === Qt.Key_W || k === Qt.Key_Up) { if (!ar) root.moveRow(-1); event.accepted = true; return }
                if (k === Qt.Key_S || k === Qt.Key_Down) { if (!ar) root.moveRow(1); event.accepted = true; return }
                if (k === Qt.Key_A || k === Qt.Key_Left) { root.rowAdjust(-1); event.accepted = true; return }
                if (k === Qt.Key_D || k === Qt.Key_Right) { root.rowAdjust(1); event.accepted = true; return }
                if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (!ar) root.rowEnter(); event.accepted = true; return }
                if (k === Qt.Key_R) { if (!ar) root.rowReset(); event.accepted = true; return }
                if (k === Qt.Key_X) { if (!ar) root.sectionReset(); event.accepted = true; return }
                if (root.page === "theme") {
                    if (k === Qt.Key_Minus) { root.nudge("tint", -0.02); event.accepted = true }
                    else if (k === Qt.Key_Equal || k === Qt.Key_Plus) { root.nudge("tint", 0.02); event.accepted = true }
                    else if (k === Qt.Key_Comma) { root.nudge("ink", -0.1); event.accepted = true }
                    else if (k === Qt.Key_Period) { root.nudge("ink", 0.1); event.accepted = true }
                }
            }

            // nền giấy toàn màn hình + khung mảnh 1 px thụt vào, vát góc dưới phải
            Rectangle { anchors.fill: parent; color: th.paper }
            Shape {
                anchors.fill: parent
                ShapePath {
                    id: bodySP
                    readonly property real c: card.px(48)
                    readonly property real ins: card.px(14)
                    fillColor: "transparent"
                    strokeColor: th.rule
                    strokeWidth: 1
                    startX: bodySP.ins; startY: bodySP.ins
                    PathLine { x: card.width - bodySP.ins; y: bodySP.ins }
                    PathLine { x: card.width - bodySP.ins; y: card.height - bodySP.ins - bodySP.c }
                    PathLine { x: card.width - bodySP.ins - bodySP.c; y: card.height - bodySP.ins }
                    PathLine { x: bodySP.ins; y: card.height - bodySP.ins }
                    PathLine { x: bodySP.ins; y: bodySP.ins }
                }
            }

            // ---------- thanh trên ----------
            Item {
                x: card.m; y: card.px(24)
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
                ScrambleText {
                    x: card.px(168); anchors.verticalCenter: parent.verticalCenter
                    visible: !root.inSettings
                    full: root.page === "store" ? "STORE" : "APPS  /  DASHBOARD"; trigger: root.pageTok; color: th.soft
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2
                }
                Row {
                    x: card.px(168); anchors.verticalCenter: parent.verticalCenter
                    visible: root.inSettings
                    spacing: card.px(6)
                    Repeater {
                        model: root.secList
                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            readonly property bool on: modelData === root.page
                            width: card.px(112); height: card.px(26)
                            color: on ? th.ink : "transparent"
                            border.width: 1; border.color: on ? th.ink : th.rule
                            ScrambleText {
                                anchors.centerIn: parent
                                full: (index + 1) + " " + modelData.toUpperCase() + (root.tabDirty(modelData) ? " *" : "")
                                active: parent.on
                                color: parent.on ? th.paper : th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true; font.letterSpacing: 1.5
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.jumpSection(index)
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
                    text: root.inSettings ? root.scopeName : (root.page === "store" ? (root.storeApps.length + " IN REGISTRY") : root.nowText); color: th.ink
                    font.family: root.fontData; font.pixelSize: card.fs(16); font.bold: true
                }
                Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -card.px(8); width: parent.width; height: 1; color: th.rule }
            }

            // ---------- DASHBOARD (trang APPS): 3 cột A (app/registry/log), B (chi tiết/function/keybind/RUN), C (preview/system/phím) ----------
            Item {
                id: dash
                visible: root.page === "apps"
                x: card.gx; y: card.gy; width: card.gw; height: card.gh
                readonly property real regH: card.px(132)
                readonly property real logH: card.px(168)
                readonly property real pg: card.px(22)

                // ===== cột A =====
                Item {
                    id: aCol
                    x: 0; width: card.wA; height: dash.height
                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    ScrambleText {
                        x: card.px(2); y: card.px(10)
                        full: "APPS"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(8)
                        text: root.apps.length + " INSTALLED"; color: th.ink
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                    }
                    ListView {
                        id: list
                        y: card.px(38); width: parent.width
                        height: Math.max(card.px(62), regPanel.y - dash.pg - card.px(38))
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
                            height: card.px(62)
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 1
                                color: row.on ? th.ink : (rowMouse.containsMouse ? th.wash : "transparent")
                            }
                            Rectangle {
                                x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                width: card.px(9); height: width
                                color: row.modelData.running ? (row.on ? th.paper : th.ink) : "transparent"
                                border.width: 1; border.color: row.on ? th.paper : th.soft
                            }
                            Text {
                                x: card.px(36); y: card.px(10)
                                width: parent.width - card.px(110)
                                elide: Text.ElideRight
                                text: root.titleOf(row.modelData)
                                color: row.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(20); font.bold: true
                            }
                            Text {
                                x: card.px(36); y: card.px(37)
                                text: (row.modelData.kind === "daemon" ? "DAEMON" : "ONESHOT") + " · " + (Array.isArray(row.modelData.functions) ? row.modelData.functions.length : 0) + " FN"
                                color: row.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: card.px(14)
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.running ? "RUNNING" : ("v" + row.modelData.version)
                                color: row.on ? th.paper : (row.modelData.running ? th.ink : th.soft)
                                font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: row.modelData.running === true
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

                    // REGISTRY
                    Item {
                        id: regPanel
                        y: logPanel.y - dash.pg - dash.regH
                        width: parent.width; height: dash.regH
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "REGISTRY"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        ScrambleText {
                            anchors.right: parent.right; y: card.px(10)
                            full: "G  OPEN STORE"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Repeater {
                            model: [
                                ["INSTALLED", String(root.apps.length)],
                                ["RUNNING", String(root.runningCount)],
                                ["APP UPDATES", root.noteApps > 0 ? String(root.noteApps) : "NONE"],
                                ["CORE UPDATE", root.noteCore !== "" ? root.noteCore : "-"]
                            ]
                            delegate: Item {
                                required property int index
                                required property var modelData
                                y: card.px(34) + index * card.px(24)
                                width: regPanel.width; height: card.px(24)
                                Text {
                                    x: card.px(2); anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[0]; color: th.soft
                                    font.family: root.fontLabel; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[1]; color: th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                                }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.5 }
                            }
                        }
                        MouseArea { anchors.fill: parent; z: -1; cursorShape: Qt.PointingHandCursor; onClicked: root.dashAct("G") }
                    }

                    // LOG
                    Item {
                        id: logPanel
                        y: parent.height - dash.logH
                        width: parent.width; height: dash.logH
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "LOG"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        Text {
                            anchors.right: parent.right; y: card.px(10)
                            text: "/TMP/SUMI.LOG"; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Column {
                            y: card.px(34); width: parent.width
                            Repeater {
                                model: root.logLines
                                delegate: Text {
                                    required property var modelData
                                    width: logPanel.width; height: card.px(20)
                                    elide: Text.ElideRight
                                    text: modelData; color: th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(12)
                                }
                            }
                        }
                        ScrambleText {
                            x: card.px(2); y: card.px(36)
                            visible: root.logLines.length === 0
                            full: "NO LOG ENTRIES"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                    }
                }

                // ===== cột B =====
                Item {
                    id: bCol
                    x: card.wA + card.gg; width: card.wB; height: dash.height
                    visible: root.cur !== null
                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    ScrambleText {
                        x: card.px(2); y: card.px(8)
                        width: bCol.width - card.px(230); height: card.px(104)
                        verticalAlignment: Text.AlignVCenter
                        full: root.cur ? root.titleOf(root.cur) : ""
                        active: root.cur !== null
                        color: th.ink
                        font.family: root.fontTitle; font.bold: true
                        font.pixelSize: card.fs(76); fontSizeMode: Text.Fit; minimumPixelSize: card.fs(30)
                    }
                    ScrambleText {
                        anchors.right: parent.right; y: card.px(2)
                        full: root.cur ? root.cur.kanji : ""
                        active: root.cur !== null
                        color: th.rule
                        font.family: root.fontKanji; font.pixelSize: card.fs(110)
                    }
                    Rectangle { y: card.px(122); width: parent.width; height: 1; color: th.ink }
                    Text {
                        y: card.px(134); width: parent.width; height: card.px(50)
                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        text: root.cur ? root.cur.description : ""
                        color: th.ink
                        font.family: root.fontLabel; font.pixelSize: card.fs(17)
                    }

                    // DETAILS: lưới 2 cột x 4 hàng
                    ScrambleText {
                        x: card.px(2); y: card.px(194)
                        full: "DETAILS"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                    }
                    Rectangle { y: card.px(216); width: parent.width; height: 1; color: th.rule }
                    Repeater {
                        model: root.curInfo
                        delegate: Item {
                            required property int index
                            required property var modelData
                            readonly property real cw: (bCol.width - card.px(40)) / 2
                            x: (index % 2) * (cw + card.px(40))
                            y: card.px(222) + Math.floor(index / 2) * card.px(34)
                            width: cw; height: card.px(34)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData[0]; color: th.soft
                                font.family: root.fontLabel; font.pixelSize: card.fs(14); font.letterSpacing: 1.5
                            }
                            Text {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - card.px(130); horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                                text: modelData[1]; color: th.ink
                                font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.6 }
                        }
                    }

                    // FUNCTIONS: thẻ chọn bằng A/D
                    Text {
                        x: card.px(2); y: card.px(374)
                        text: root.cur && root.cur.kind === "daemon" ? "FUNCTIONS" : "TEST RUN"; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                    }
                    ScrambleText {
                        anchors.right: parent.right; y: card.px(374)
                        visible: root.cur !== null && root.cur.kind === "daemon"
                        full: "A / D  SELECT"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                    }
                    Row {
                        y: card.px(398)
                        spacing: card.px(12)
                        visible: root.cur !== null && root.cur.kind === "daemon"
                        Repeater {
                            model: root.curFns
                            delegate: Rectangle {
                                id: fcard
                                required property int index
                                required property var modelData
                                readonly property bool on: index === root.fnSel
                                width: Math.min(card.px(260), (bCol.width - (root.curFns.length - 1) * card.px(12)) / Math.max(1, root.curFns.length))
                                height: card.px(92)
                                color: on ? th.ink : (fmouse.containsMouse ? th.wash : "transparent")
                                border.width: 1; border.color: th.ink
                                Text {
                                    x: card.px(14); y: card.px(10)
                                    width: parent.width - card.px(60); elide: Text.ElideRight
                                    text: fcard.modelData.label
                                    color: fcard.on ? th.paper : th.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(24); font.bold: true; font.letterSpacing: 1
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: card.px(12); y: card.px(14)
                                    text: (fcard.index < 9 ? "0" : "") + (fcard.index + 1)
                                    color: fcard.on ? th.paper : th.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(13)
                                }
                                Text {
                                    x: card.px(14); y: card.px(50)
                                    text: "OBJECT   " + root.fnObjId(root.cur, fcard.modelData).toUpperCase()
                                    color: fcard.on ? th.paper : th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1
                                }
                                Text {
                                    x: card.px(14); y: card.px(68)
                                    text: "IPC      " + fcard.modelData.ipc_name
                                    color: fcard.on ? th.paper : th.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1
                                }
                                MouseArea {
                                    id: fmouse
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.fnSel = fcard.index
                                }
                            }
                        }
                    }
                    Rectangle {
                        y: card.px(398); width: parent.width; height: card.px(92)
                        visible: root.cur !== null && root.cur.kind !== "daemon"
                        color: "transparent"; border.width: 1; border.color: th.ink
                        Text {
                            x: card.px(14); y: card.px(12)
                            text: "ONESHOT DIALOG"; color: th.ink
                            font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true; font.letterSpacing: 1
                        }
                        Text {
                            x: card.px(14); y: card.px(48); width: parent.width - card.px(28)
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            text: "Enter mở thử dialog với dữ liệu mẫu (thoát mã 0 = Yes, 1 = No)."
                            color: th.soft
                            font.family: root.fontLabel; font.pixelSize: card.fs(15)
                        }
                    }

                    // KEYBINDS của app (phím hiệu lực = mặc định + phần người dùng đổi)
                    ScrambleText {
                        x: card.px(2); y: card.px(508)
                        full: "KEYBINDS"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                    }
                    ScrambleText {
                        anchors.right: parent.right; y: card.px(508)
                        full: "K  EDIT"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                    }
                    Flow {
                        y: card.px(532); width: parent.width; height: card.px(84)
                        spacing: card.px(8)
                        clip: true
                        Repeater {
                            model: root.curKeys
                            delegate: Rectangle {
                                id: kcap
                                required property var modelData
                                height: card.px(36)
                                width: kcKey.width + kcLab.width + card.px(22)
                                color: "transparent"; border.width: 1; border.color: th.ink
                                Rectangle {
                                    id: kcKey
                                    height: parent.height; width: kcKeyT.width + card.px(18)
                                    color: th.ink
                                    Text {
                                        id: kcKeyT
                                        anchors.centerIn: parent
                                        text: kcap.modelData.key.toUpperCase(); color: th.paper
                                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                                    }
                                }
                                Text {
                                    id: kcLab
                                    x: kcKey.width + card.px(10); anchors.verticalCenter: parent.verticalCenter
                                    text: kcap.modelData.label; color: th.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(13); font.letterSpacing: 1
                                }
                            }
                        }
                    }

                    // RUN: thanh mực vát góc
                    Item {
                        id: runBar
                        y: parent.height - card.px(60); width: parent.width; height: card.px(60)
                        Shape {
                            anchors.fill: parent
                            ShapePath {
                                id: runSP
                                readonly property real c: card.px(20)
                                fillColor: runMouse.containsMouse ? th.soft : th.ink
                                strokeColor: th.ink
                                strokeWidth: 1
                                startX: 0; startY: 0
                                PathLine { x: runBar.width; y: 0 }
                                PathLine { x: runBar.width; y: runBar.height - runSP.c }
                                PathLine { x: runBar.width - runSP.c; y: runBar.height }
                                PathLine { x: 0; y: runBar.height }
                                PathLine { x: 0; y: 0 }
                            }
                        }
                        Text {
                            x: card.px(18); anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - card.px(150); elide: Text.ElideRight
                            text: root.runLabel
                            color: th.paper
                            font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true; font.letterSpacing: 2
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: card.px(40); anchors.verticalCenter: parent.verticalCenter
                            text: "ENTER"; color: th.paper
                            font.family: root.fontData; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 2
                        }
                        MouseArea {
                            id: runMouse
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.dashAct("RUN")
                        }
                    }
                }

                // trạng thái rỗng / lỗi (không có app)
                Text {
                    x: card.wA + card.gg; y: card.px(20); width: card.wB
                    visible: root.cur === null
                    wrapMode: Text.WordWrap
                    text: root.errorText !== "" ? root.errorText : "KHÔNG CÓ APP NÀO ĐÃ CÀI   (G: STORE)"
                    color: th.ink
                    font.family: root.fontLabel; font.pixelSize: card.fs(22); font.bold: true
                }
                Text {
                    x: card.wA + card.gg; y: card.px(120); width: card.wB
                    visible: root.cur !== null && root.errorText !== ""
                    wrapMode: Text.WordWrap
                    text: root.errorText; color: th.danger
                    font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                }

                // ===== cột C =====
                Item {
                    id: cCol
                    x: card.wA + card.wB + 2 * card.gg; width: card.wC; height: dash.height
                    Rectangle { width: parent.width; height: 1; color: th.ink }

                    // SYSTEM (số liệu thật, làm mới mỗi 2 giây khi đang ở trang APPS)
                    Item {
                        id: sysPanel
                        y: card.dashPvY + card.pvH + card.gg
                        width: parent.width; height: card.px(184)
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "SYSTEM"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        Text {
                            anchors.right: parent.right; y: card.px(10)
                            text: "EVERY 2 S"; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Repeater {
                            model: [
                                { k: "MEM", v: root.sysMem, t: root.sysMemText !== "" ? root.sysMemText : "-", bar: root.sysMem >= 0, alert: root.sysMem > 0.9 },
                                { k: "BAT", v: root.sysBat >= 0 ? root.sysBat / 100 : 0, t: root.sysBat >= 0 ? (root.sysBat + "%  " + root.sysBatState.toUpperCase()) : "NO BATTERY", bar: root.sysBat >= 0, alert: root.sysBat >= 0 && root.sysBat <= 15 },
                                { k: "TEMP", v: root.sysTemp >= 0 ? Math.min(1, root.sysTemp / 100) : 0, t: root.sysTemp >= 0 ? (root.sysTemp + " C  MAX SENSOR") : "-", bar: root.sysTemp >= 0, alert: root.sysTemp >= 85 },
                                { k: "LOAD", v: 0, t: root.sysLoad !== "" ? root.sysLoad : "-", bar: false, alert: false },
                                { k: "UPTIME", v: 0, t: root.fmtUp(root.sysUp), bar: false, alert: false }
                            ]
                            delegate: Item {
                                id: srow2
                                required property int index
                                required property var modelData
                                y: card.px(34) + index * card.px(30)
                                width: sysPanel.width; height: card.px(30)
                                Text {
                                    x: card.px(2); anchors.verticalCenter: parent.verticalCenter
                                    text: srow2.modelData.k; color: th.soft
                                    font.family: root.fontLabel; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                                }
                                PixelBar {
                                    x: card.px(76); anchors.verticalCenter: parent.verticalCenter
                                    width: srow2.width - card.px(76) - card.px(156); height: card.px(10)
                                    visible: srow2.modelData.bar
                                    value: srow2.modelData.v; cells: 20
                                    litColor: th.ink; dimColor: th.rule; alertColor: th.danger
                                    alert: srow2.modelData.alert
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: card.px(150); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                    text: srow2.modelData.t
                                    color: srow2.modelData.alert ? th.danger : th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.4 }
                            }
                        }
                    }

                    // KEYS: phím tắt của trang APPS (bấm chuột cũng được)
                    Item {
                        id: keyPanel
                        y: sysPanel.y + sysPanel.height + card.gg
                        width: parent.width; height: card.px(202)
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "SHORTCUTS"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        ScrambleText {
                            anchors.right: parent.right; y: card.px(10)
                            full: "W/S APP"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Repeater {
                            model: [["TAB", "SETTINGS"], ["G", "STORE"], ["T", "THEME"], ["F", "FONT"], ["K", "KEYS"], ["O", "OPTION"], ["ENTER", "RUN"], ["ESC", "CLOSE"]]
                            delegate: Rectangle {
                                id: skey
                                required property int index
                                required property var modelData
                                readonly property real cw: (keyPanel.width - card.px(8)) / 2
                                x: (index % 2) * (cw + card.px(8))
                                y: card.px(34) + Math.floor(index / 2) * card.px(42)
                                width: cw; height: card.px(36)
                                color: skm.containsMouse ? th.wash : "transparent"
                                border.width: 1; border.color: th.ink
                                Rectangle {
                                    id: skKey
                                    height: parent.height; width: card.px(52)
                                    color: th.ink
                                    Text {
                                        anchors.centerIn: parent
                                        text: skey.modelData[0]; color: th.paper
                                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                                    }
                                }
                                Text {
                                    x: skKey.width + card.px(12); anchors.verticalCenter: parent.verticalCenter
                                    text: skey.modelData[1]; color: th.ink
                                    font.family: root.fontLabel; font.pixelSize: card.fs(14); font.bold: true; font.letterSpacing: 1.5
                                }
                                MouseArea {
                                    id: skm
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dashAct(skey.modelData[0])
                                }
                            }
                        }
                    }
                }
            }

            // ---------- SETTINGS: một màn hình cho mỗi phạm vi (THEME / FONT / KEYS / OPTIONS gồm OBJECTS) ----------
            Item {
                id: tp
                visible: root.inSettings
                x: card.gx; y: card.gy; width: card.gw; height: card.gh
                readonly property real pg: card.px(22)
                readonly property real secH: card.px(34) + 4 * card.px(32)
                readonly property real stH: card.px(98)

                // ===== cột A: phạm vi, section, trạng thái =====
                Item {
                    id: sCol
                    width: card.wA; height: tp.height
                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    ScrambleText {
                        x: card.px(2); y: card.px(10)
                        full: "SCOPE"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                    }
                    ScrambleText {
                        anchors.right: parent.right; y: card.px(8)
                        full: "Q / E"; trigger: root.pageTok; color: th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                    }
                    ListView {
                        id: scopeList
                        y: card.px(38); width: parent.width
                        height: Math.max(card.px(52), secPanel.y - tp.pg - card.px(38))
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
                            width: scopeList.width
                            height: card.px(52)
                            Rectangle {
                                anchors.fill: parent; anchors.bottomMargin: 1
                                color: srow.on ? th.ink : (smouse.containsMouse ? th.wash : "transparent")
                            }
                            Text {
                                x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - card.px(110)
                                elide: Text.ElideRight
                                text: srow.modelData.name
                                color: srow.on ? th.paper : th.ink
                                font.family: root.fontLabel; font.pixelSize: card.fs(19); font.bold: true
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: card.px(14)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.scopeTag(srow.modelData.id)
                                color: srow.on ? th.paper : th.soft
                                font.family: root.fontData; font.pixelSize: card.fs(12)
                            }
                            MouseArea {
                                id: smouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.setScope(srow.index)
                            }
                        }
                    }

                    // SECTIONS: nhảy nhanh (1..4 hoặc Tab)
                    Item {
                        id: secPanel
                        y: stPanel.y - tp.pg - tp.secH
                        width: parent.width; height: tp.secH
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "SECTIONS"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        ScrambleText {
                            anchors.right: parent.right; y: card.px(10)
                            full: "TAB"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Repeater {
                            model: root.secIds
                            delegate: Item {
                                id: scr
                                required property int index
                                required property string modelData
                                readonly property bool avail: root.secCount(modelData) > 0
                                readonly property bool on: avail && modelData === root.page
                                y: card.px(34) + index * card.px(32)
                                width: secPanel.width; height: card.px(32)
                                Rectangle {
                                    anchors.fill: parent; anchors.bottomMargin: 1
                                    color: scr.on ? th.ink : (scm.containsMouse && scr.avail ? th.wash : "transparent")
                                }
                                Text {
                                    x: card.px(12); anchors.verticalCenter: parent.verticalCenter
                                    text: (scr.avail ? (root.secList.indexOf(scr.modelData) + 1) : "-") + "  " + root.secTitle(scr.modelData)
                                    color: scr.on ? th.paper : (scr.avail ? th.ink : th.rule)
                                    font.family: root.fontLabel; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 1
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: card.px(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: !scr.avail ? "N/A" : (root.tabDirty(scr.modelData) ? "DRAFT" : "")
                                    color: scr.on ? th.paper : th.soft
                                    font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1
                                }
                                MouseArea {
                                    id: scm
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: scr.avail ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (scr.avail) root.focusRow(scr.modelData, root.secSel(scr.modelData))
                                }
                            }
                        }
                    }

                    // STATUS
                    Item {
                        id: stPanel
                        y: parent.height - tp.stH
                        width: parent.width; height: tp.stH
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "STATUS"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        ScrambleText {
                            anchors.right: parent.right; y: card.px(10)
                            full: "SPACE  APPLY"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        Repeater {
                            model: [
                                ["DRAFT", root.dirtyList.length > 0 ? root.dirtyList.join(" + ").toUpperCase() : "NONE", root.dirtyList.length > 0],
                                ["LAST APPLY", root.applyMsg !== "" ? root.applyMsg : "-", root.applyMsg !== "" && !root.applyOk]
                            ]
                            delegate: Item {
                                required property int index
                                required property var modelData
                                y: card.px(34) + index * card.px(28)
                                width: stPanel.width; height: card.px(28)
                                Text {
                                    x: card.px(2); anchors.verticalCenter: parent.verticalCenter
                                    text: modelData[0]; color: th.soft
                                    font.family: root.fontLabel; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - card.px(110); horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                                    text: modelData[1]
                                    color: modelData[2] ? th.danger : th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.rule; opacity: 0.5 }
                            }
                        }
                    }
                }

                // ===== cột B: danh sách hàng theo section =====
                Item {
                    id: sMain
                    x: card.wA + card.gg; width: card.wB; height: tp.height
                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    ScrambleText {
                        x: card.px(2); y: card.px(6)
                        width: parent.width - card.px(140); elide: Text.ElideRight
                        full: "SETTINGS / " + root.scopeName; color: th.ink
                        font.family: root.fontTitle; font.pixelSize: card.fs(28); font.bold: true
                    }
                    Text {
                        anchors.right: parent.right; y: card.px(14)
                        text: root.anyDirty ? "DRAFT" : "SAVED"; color: root.anyDirty ? th.danger : th.soft
                        font.family: root.fontData; font.pixelSize: card.fs(14); font.letterSpacing: 2; font.bold: root.anyDirty
                    }
                    ListView {
                        id: setList
                        y: card.px(52); width: parent.width; height: parent.height - card.px(52)
                        clip: true
                        interactive: false
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.viewRows
                        currentIndex: root.viewSel
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        delegate: Item {
                            id: sr
                            required property int index
                            required property var modelData
                            readonly property string sec: modelData.sec
                            readonly property int idx: modelData.i
                            readonly property bool isHead: modelData.kind === "head"
                            readonly property bool on: !isHead && sec === root.page && idx === root.secSel(sec)
                            width: setList.width
                            height: isHead ? card.px(40) : (sec === "theme" ? (idx === 0 ? card.px(128) : card.px(44)) : (sec === "font" ? card.px(46) : card.px(38)))
                            Loader {
                                anchors.fill: parent
                                sourceComponent: sr.isHead ? headC : (sr.sec === "theme" ? (sr.idx === 0 ? presetC : sliderC) : (sr.sec === "font" ? fontC : (sr.sec === "keys" ? keyC : optC)))
                            }

                            // --- tiêu đề section ---
                            Component {
                                id: headC
                                Item {
                                    ScrambleText {
                                        x: card.px(2); anchors.bottom: parent.bottom; anchors.bottomMargin: card.px(6)
                                        full: root.secTitle(sr.sec); trigger: root.pageTok; color: th.ink
                                        font.family: root.fontLabel; font.pixelSize: card.fs(15); font.bold: true; font.letterSpacing: 3
                                    }
                                    Text {
                                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: card.px(7)
                                        text: root.tabDirty(sr.sec) ? "DRAFT" : "SAVED"
                                        color: root.tabDirty(sr.sec) ? th.danger : th.soft
                                        font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 2
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: th.ink }
                                }
                            }

                            // --- THEME: 6 thẻ preset ---
                            Component {
                                id: presetC
                                Item {
                                    Rectangle {
                                        visible: sr.on
                                        x: 0; y: card.px(6); width: card.px(5); height: parent.height - card.px(12); color: th.ink
                                    }
                                    Row {
                                        x: card.px(14); y: card.px(8)
                                        spacing: card.px(8)
                                        Repeater {
                                            model: ce.themes
                                            delegate: Item {
                                                id: pc
                                                required property int index
                                                required property string modelData
                                                readonly property var dv: th.derive(modelData, root.effTint, root.effInk)
                                                readonly property bool cur: modelData === root.effTheme
                                                readonly property bool bad: dv.contrast < th.minContrast
                                                readonly property bool weak: !bad && dv.contrast < th.goodContrast
                                                width: Math.floor((sr.width - card.px(14) - 5 * card.px(8)) / 6)
                                                height: card.px(112)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: pc.dv.paper
                                                    border.width: pc.cur ? 3 : 1
                                                    border.color: pc.cur ? th.ink : th.rule
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
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { root.focusRow("theme", 0); root.setPreset(pc.modelData) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // --- THEME: TINT và INK DARKEN ---
                            Component {
                                id: sliderC
                                Item {
                                    id: sl2
                                    readonly property var spec: sr.idx === 1 ? ({ key: "tint", label: "TINT", lo: 0, hi: 0.6, step: 0.02, nd: 2 }) : ({ key: "ink", label: "INK DARKEN", lo: 1, hi: 2.5, step: 0.1, nd: 1 })
                                    readonly property real v: sr.idx === 1 ? root.effTint : root.effInk
                                    readonly property bool isInh: sr.idx === 1 ? root.draft.tint === null : root.draft.inkDarken === null
                                    opacity: root.tintEditable ? 1 : 0.35
                                    Rectangle {
                                        anchors.fill: parent; anchors.bottomMargin: 1
                                        color: sr.on ? th.ink : (slm.containsMouse ? th.wash : "transparent")
                                    }
                                    Text {
                                        x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                        text: sl2.spec.label; color: sr.on ? th.paper : th.soft
                                        font.family: root.fontLabel; font.pixelSize: card.fs(14); font.letterSpacing: 1.5
                                    }
                                    Rectangle {
                                        x: card.px(150); anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - card.px(150) - card.px(190); height: card.px(8)
                                        color: sr.on ? th.paper : th.wash; border.width: 1; border.color: sr.on ? th.paper : th.rule
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(1, (sl2.v - sl2.spec.lo) / (sl2.spec.hi - sl2.spec.lo)))
                                            height: parent.height; color: sr.on ? th.ink : th.ink
                                        }
                                    }
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: card.px(14)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: card.px(150); horizontalAlignment: Text.AlignRight
                                        text: sl2.v.toFixed(sl2.spec.nd) + (sl2.isInh ? "  inh" : "")
                                        color: sr.on ? th.paper : th.ink
                                        font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: true
                                    }
                                    MouseArea {
                                        id: slm
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.focusRow("theme", sr.idx)
                                    }
                                }
                            }

                            // --- FONT ---
                            Component {
                                id: fontC
                                Item {
                                    id: fr2
                                    readonly property string role: root.fontRows[sr.idx] !== undefined ? root.fontRows[sr.idx] : ""
                                    readonly property bool own: role !== "" && root.fontDraft[role] !== null
                                    readonly property bool bad: role !== "" && (root.fontMissing(role) || root.fontNoJa(role))
                                    Rectangle {
                                        anchors.fill: parent; anchors.bottomMargin: 1
                                        color: sr.on ? th.ink : (frm.containsMouse ? th.wash : "transparent")
                                    }
                                    Text {
                                        x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                        text: fr2.role.toUpperCase()
                                        color: sr.on ? th.paper : th.soft
                                        font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
                                    }
                                    Text {
                                        x: card.px(124); anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - card.px(124) - card.px(100)
                                        elide: Text.ElideRight
                                        text: fr2.role !== "" ? root.fontShown(fr2.role) : ""
                                        color: sr.on ? th.paper : th.ink
                                        font.family: fr2.role !== "" ? root.fam(fr2.role) : root.fontLabel; font.pixelSize: card.fs(20)
                                    }
                                    Text {
                                        anchors.right: parent.right; anchors.rightMargin: card.px(14)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fr2.role === "" ? "" : (root.fontMissing(fr2.role) ? "MISSING" : (root.fontNoJa(fr2.role) ? "NO JA" : (fr2.own ? "OWN" : "inh")))
                                        color: fr2.bad ? th.danger : (sr.on ? th.paper : th.soft)
                                        font.family: root.fontData; font.pixelSize: card.fs(12); font.bold: fr2.bad
                                    }
                                    MouseArea {
                                        id: frm
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (sr.on) root.openPicker(); else root.focusRow("font", sr.idx) }
                                    }
                                }
                            }

                            // --- KEYS ---
                            Component {
                                id: keyC
                                Item {
                                    id: kr2
                                    readonly property var kb: root.kbList[sr.idx] !== undefined ? root.kbList[sr.idx] : ({ action: "", label: "", default: "", locked: false })
                                    readonly property bool locked: kb.locked === true
                                    readonly property bool changed: !locked && root.keyDraft[kb.action] !== undefined
                                    readonly property bool conf: root.keyConf[kb.action] !== undefined
                                    readonly property bool capHere: sr.on && root.capturing
                                    Rectangle {
                                        anchors.fill: parent; anchors.bottomMargin: 1
                                        color: sr.on ? th.ink : (krm.containsMouse ? th.wash : "transparent")
                                    }
                                    Text {
                                        x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                        width: card.px(180); elide: Text.ElideRight
                                        text: String(kr2.kb.label).toUpperCase()
                                        color: sr.on ? th.paper : th.ink
                                        font.family: root.fontLabel; font.pixelSize: card.fs(16); font.bold: true
                                    }
                                    Text {
                                        x: card.px(206); anchors.verticalCenter: parent.verticalCenter
                                        text: kr2.kb.action
                                        color: sr.on ? th.paper : th.soft
                                        font.family: root.fontData; font.pixelSize: card.fs(12)
                                    }
                                    Text {
                                        anchors.right: kcap2.left; anchors.rightMargin: card.px(10)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: kr2.locked ? "LOCK" : (kr2.changed ? ("def " + kr2.kb.default) : "")
                                        color: sr.on ? th.paper : th.soft
                                        font.family: root.fontData; font.pixelSize: card.fs(12)
                                    }
                                    Rectangle {
                                        id: kcap2
                                        anchors.right: parent.right; anchors.rightMargin: card.px(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: card.px(112); height: card.px(26)
                                        color: kr2.capHere ? th.paper : "transparent"
                                        border.width: kr2.conf ? 2 : 1
                                        border.color: kr2.conf ? th.danger : (sr.on ? th.paper : th.ink)
                                        Text {
                                            anchors.centerIn: parent
                                            text: kr2.capHere ? "PRESS KEY" : String(root.keyShown(kr2.kb)).toUpperCase()
                                            color: kr2.capHere ? th.ink : (sr.on ? th.paper : th.ink)
                                            font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        id: krm
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (sr.on) root.startCapture(); else root.focusRow("keys", sr.idx) }
                                    }
                                }
                            }

                            // --- OPTIONS (gồm OBJECTS của từng function) ---
                            Component {
                                id: optC
                                Item {
                                    id: or2
                                    readonly property var o: root.optList[sr.idx] !== undefined ? root.optList[sr.idx] : ({ key: "", label: "", type: "bool", default: false, locked: false })
                                    readonly property bool locked: o.locked === true
                                    readonly property bool changed: !locked && root.optDraft[o.key] !== undefined
                                    readonly property bool conf: root.optConf[o.key] !== undefined
                                    readonly property bool editHere: sr.on && root.optEditing
                                    Rectangle {
                                        anchors.fill: parent; anchors.bottomMargin: 1
                                        color: sr.on ? th.ink : (orm.containsMouse ? th.wash : "transparent")
                                    }
                                    Text {
                                        x: card.px(14); anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - card.px(14) - card.px(210) - card.px(150); elide: Text.ElideRight
                                        text: or2.o.label
                                        color: sr.on ? th.paper : th.ink
                                        font.family: root.fontLabel; font.pixelSize: card.fs(15); font.bold: true
                                    }
                                    Text {
                                        anchors.right: ocap2.left; anchors.rightMargin: card.px(10)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: card.px(140); horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                                        text: or2.locked ? "LOCK" : (or2.changed ? ("def " + ce.optFormat(or2.o, or2.o.default)) : "")
                                        color: sr.on ? th.paper : th.soft
                                        font.family: root.fontData; font.pixelSize: card.fs(12)
                                    }
                                    Rectangle {
                                        id: ocap2
                                        anchors.right: parent.right; anchors.rightMargin: card.px(12)
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: card.px(196); height: card.px(26)
                                        color: or2.editHere ? th.paper : "transparent"
                                        border.width: or2.conf ? 2 : 1
                                        border.color: or2.conf ? th.danger : (sr.on ? th.paper : th.ink)
                                        Text {
                                            anchors.fill: parent; anchors.leftMargin: card.px(6); anchors.rightMargin: card.px(6)
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: or2.editHere ? Text.AlignLeft : Text.AlignHCenter
                                            elide: or2.editHere ? Text.ElideLeft : Text.ElideRight
                                            text: or2.editHere ? (root.optBuf + "_") : ce.optFormat(or2.o, root.optShown(or2.o))
                                            color: or2.editHere ? th.ink : (sr.on ? th.paper : th.ink)
                                            font.family: root.fontData; font.pixelSize: card.fs(13); font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        id: orm
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (sr.on) { if (!root.optEditing) root.enterOpt() }
                                            else root.focusRow("options", sr.idx)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ----- bộ chọn font: gõ để lọc, mũi tên để chọn -----
                    Rectangle {
                        id: pk
                        visible: root.pickOpen
                        z: 5
                        y: card.px(52); width: parent.width; height: Math.min(parent.height - card.px(52), card.px(430))
                        color: th.paper; border.width: 2; border.color: th.ink
                        readonly property var curItem: root.pickItems.length > 0 ? root.pickItems[Math.max(0, Math.min(root.pickIdx, root.pickItems.length - 1))] : null
                        readonly property string inhFam: {
                            if (root.pickRole === "") return ""
                            const v = root.fontInh[root.pickRole]
                            if (v !== undefined && v !== "") return v
                            const d = root.pickRole === "kanji" ? Qt.application.font.family : ce.fontDefaults[root.pickRole]
                            return d === undefined ? "" : d
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
                            width: parent.width - card.px(16); height: pk.height - card.px(58) - card.px(64)
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
                        Rectangle { x: card.px(14); y: pk.height - card.px(58); width: parent.width - card.px(28); height: 1; color: th.rule }
                        Text {
                            x: card.px(14); y: pk.height - card.px(46); width: parent.width - card.px(28)
                            elide: Text.ElideRight
                            text: "Aa Đóng cửa sổ 0123 [Y] 墨紙 確認"; color: th.ink
                            font.family: pk.prevFam; font.pixelSize: card.fs(22)
                        }
                    }
                }

                // ===== cột C: preview (pvFrame vẽ đè đúng chỗ) + chi tiết hàng đang chọn =====
                Item {
                    id: sDet
                    x: card.wA + card.wB + 2 * card.gg; width: card.wC; height: tp.height
                    Rectangle { width: parent.width; height: 1; color: th.ink }
                    Item {
                        id: detPanel
                        y: card.dashPvY + card.pvH + card.gg
                        width: parent.width; height: parent.height - y
                        Rectangle { width: parent.width; height: 1; color: th.ink }
                        ScrambleText {
                            x: card.px(2); y: card.px(10)
                            full: "DETAIL"; trigger: root.pageTok; color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 2
                        }
                        Text {
                            anchors.right: parent.right; y: card.px(10)
                            text: root.secTitle(root.page); color: th.soft
                            font.family: root.fontData; font.pixelSize: card.fs(12); font.letterSpacing: 1.5
                        }
                        // bảng màu dẫn xuất của bản nháp theme (chỉ khi đang ở section THEME)
                        Row {
                            y: card.px(36)
                            visible: root.page === "theme"
                            spacing: card.px(6)
                            Repeater {
                                model: [root.curDerived.paper, root.curDerived.ink, root.curDerived.soft, root.curDerived.rule, root.curDerived.ghostB]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: Math.floor((detPanel.width - 4 * card.px(6)) / 5); height: card.px(30)
                                    color: modelData; border.width: 1; border.color: th.ink
                                }
                            }
                        }
                        Column {
                            y: root.page === "theme" ? card.px(80) : card.px(38)
                            width: parent.width
                            spacing: card.px(8)
                            Repeater {
                                model: root.detailLines
                                delegate: Text {
                                    required property var modelData
                                    width: detPanel.width
                                    wrapMode: Text.WordWrap
                                    text: modelData.t
                                    color: modelData.bad ? th.danger : th.ink
                                    font.family: root.fontData; font.pixelSize: card.fs(14); font.bold: modelData.bad
                                }
                            }
                        }
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

            // ---------- PREVIEW (luôn bật, đầu cột C) ----------
            Item {
                id: pvFrame
                visible: root.page !== "store"
                x: card.gx + card.wA + card.wB + 2 * card.gg
                y: card.gy + card.dashPvY
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
                            active: root.page !== "store" && root.pvApp !== null
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
            Text {
                anchors.right: parent.right; anchors.rightMargin: card.m; y: card.height - card.px(52)
                visible: root.page === "apps"
                text: root.hexText; color: th.soft
                font.family: root.fontData; font.pixelSize: card.fs(13); font.letterSpacing: 1.5
            }
        }
    }
}
