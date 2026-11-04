import QtQuick

// Hàm THUẦN cho tab STORE của hub (không Process, không file). Dữ liệu vào là JSON do `sumi store ... --json` in ra.
QtObject {
    function isObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

    // Phân tích stdout của `sumi store`. Trả { ok, data, msg }.
    //  - mảng (lệnh `removed`)            -> ok, data = mảng
    //  - đối tượng {ok:true,...}          -> ok, data = đối tượng
    //  - đối tượng {ok:false,code,...}    -> !ok, msg = "CODE: message" (+ errors)
    //  - rỗng / không phải JSON           -> !ok, msg báo không có phản hồi
    function parse(text) {
        let d = null
        try { d = JSON.parse(String(text).trim()) } catch (e) { d = null }
        if (Array.isArray(d)) return { ok: true, data: d, msg: "" }
        if (!isObj(d)) return { ok: false, data: null, msg: "KHÔNG CÓ PHẢN HỒI TỪ sumi store (chạy: sumi doctor)" }
        if (d.ok === true) return { ok: true, data: d, msg: "" }
        let m = (typeof d.code === "string" ? d.code.toUpperCase() : "ERROR") + ": " + (typeof d.message === "string" ? d.message : "")
        if (Array.isArray(d.errors) && d.errors.length > 0) m += " — " + d.errors.join("; ")
        return { ok: false, data: d, msg: m }
    }

    function short(sha) { return typeof sha === "string" ? sha.slice(0, 12) : "" }

    // Nhãn trạng thái ở danh sách bên trái.
    function badge(a) {
        if (!isObj(a)) return ""
        if (a.state === "update") return "UPDATE " + a.ref
        if (a.state === "installed") return "● " + a.ref
        if (a.state === "dev") return "DEV"
        return "NEW " + a.ref
    }

    // Việc Enter làm với app a: "install" | "update" | "" (không có việc).
    function opFor(a) {
        if (!isObj(a)) return ""
        if (a.state === "available" || a.state === "dev") return "install"
        if (a.state === "update") return "update"
        return ""
    }

    function stateText(a) {
        if (!isObj(a)) return ""
        if (a.state === "installed") return "INSTALLED"
        if (a.state === "update") return "UPDATE AVAILABLE"
        if (a.state === "dev") return "DEV COPY (NOT MANAGED BY STORE)"
        return "NOT INSTALLED"
    }

    // Gợi ý phím cho app đang chọn.
    function hint(a) {
        if (!isObj(a)) return ""
        if (a.state === "update") return "ENTER  UPDATE      X  REMOVE"
        if (a.state === "installed") return "UP TO DATE      X  REMOVE"
        if (a.state === "dev") return "ENTER  REPLACE DEV COPY WITH STORE VERSION (DEV COPY IS BACKED UP)"
        return "ENTER  INSTALL"
    }

    function canRemove(a) { return isObj(a) && (a.state === "installed" || a.state === "update") }

    // Lý do từ chối ở phía hub khi app đang chạy (CLI vẫn chặn thật bằng mã 3). "" = cho phép.
    function runningBlock(a, op) {
        if (!isObj(a) || a.running !== true) return ""
        if (op === "install" && a.state === "available") return ""
        let m = a.id.toUpperCase() + " ĐANG CHẠY. TẮT APP TRƯỚC RỒI THỬ LẠI."
        if (a.id === "jigen") m += " (TẮT JIGEN SẼ HUỶ HẸN GIỜ ĐANG ĐẾM)"
        return m
    }

    // Dòng thông báo sau khi lệnh ghi thành công.
    function opText(d) {
        if (!isObj(d)) return ""
        if (d.noop === true) return "ĐÃ Ở BẢN MỚI NHẤT"
        if (typeof d.restored === "string") return "ĐÃ KHÔI PHỤC " + d.id.toUpperCase() + " v" + d.version
        if (typeof d.mode === "string") return (d.mode === "update" ? "ĐÃ CẬP NHẬT " : "ĐÃ CÀI ") + d.id.toUpperCase() + " v" + d.version
        return "ĐÃ GỠ " + (typeof d.id === "string" ? d.id.toUpperCase() : "")
    }

    // Các dòng màn hình xác nhận: [nhãn, giá trị, nguy hiểm?]. Tối đa maxRows dòng (dòng cuối "+n").
    function confirmRows(op, ins, id, stamp, maxRows) {
        const rows = []
        if (op === "remove") {
            rows.push(["GỠ", id, false])
            rows.push(["SAO LƯU", "app được chuyển vào backups/removed/, khôi phục được bằng B", false])
            rows.push(["CẤU HÌNH", "giữ nguyên trong config.json", false])
            return rows
        }
        if (op === "restore") {
            rows.push(["KHÔI PHỤC", id, false])
            rows.push(["BẢN", stamp, false])
            rows.push(["BẢN ĐANG CÓ", "được sao lưu trước khi thay", false])
            return rows
        }
        if (!isObj(ins)) return rows
        const lib = isObj(ins.lib) ? ins.lib : ({})
        rows.push(["APP", String(ins.name || ins.id) + ((ins.kanji && String(ins.name || "").indexOf(ins.kanji) < 0) ? ("  " + ins.kanji) : "") + "  v" + ins.version + "  (" + ins.kind + ")", false])
        rows.push(["NGUỒN", String(ins.url || ""), false])
        rows.push(["TAG", String(ins.ref || ""), false])
        rows.push(["SHA", String(ins.sha || ""), false])
        if (lib.compatible === true) rows.push(["LIB", "cần " + lib.required + ", có " + lib.installed + "  OK", false])
        else rows.push(["LIB", "[INCOMPATIBLE] cần " + lib.required + ", có " + (lib.installed || "không có"), true])
        const req = Array.isArray(ins.requires) ? ins.requires : []
        if (req.length === 0) rows.push(["GÓI CẦN", "(không có)", false])
        for (let i = 0; i < req.length; i++) {
            const st = req[i].status
            rows.push([i === 0 ? "GÓI CẦN" : "", req[i].name + (st === "ok" ? "  ok" : (st === "missing" ? "  THIẾU (hub không tự cài)" : "  không kiểm được")), st === "missing"])
        }
        const cmds = Array.isArray(ins.shell_commands) ? ins.shell_commands : []
        if (cmds.length === 0) rows.push(["LỆNH SHELL", "(không có)", false])
        for (let j = 0; j < cmds.length; j++) rows.push([j === 0 ? "LỆNH SHELL" : "", String(cmds[j]), false])
        if (ins.conflict === "dev") rows.push(["BẢN DEV", "đang có bản dev; sẽ được sao lưu rồi thay bằng bản store", true])
        const w = Array.isArray(ins.warnings) ? ins.warnings : []
        for (let k = 0; k < w.length; k++) rows.push([k === 0 ? "CẢNH BÁO" : "", String(w[k]), true])
        const cap = (typeof maxRows === "number" && maxRows > 2) ? maxRows : 14
        if (rows.length > cap) {
            const extra = rows.length - (cap - 1)
            rows.length = cap - 1
            rows.push(["", "… +" + extra + " dòng nữa", false])
        }
        return rows
    }

    // Có cho xác nhận không? install/update cần lib tương thích.
    function canConfirm(op, ins) {
        if (op === "install" || op === "update") return isObj(ins) && isObj(ins.lib) && ins.lib.compatible === true
        return op === "remove" || op === "restore"
    }

    // Đối số `sumi store ...` cho thao tác đã xác nhận (SHA lấy từ bản đã inspect, không lấy từ nơi khác).
    function opArgs(op, ins, id, stamp) {
        if (op === "install" || op === "update") {
            const a = [op, id, "--sha", ins.sha]
            if (op === "install" && ins.conflict === "dev") a.push("--replace")
            return a
        }
        if (op === "remove") return ["remove", id]
        if (op === "restore") return ["restore", id, stamp]
        return []
    }
}
