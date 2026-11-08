// Test DASHBOARD của hub (trang APPS): hàm/property thật trích từ hub/shell.qml chạy với root giả, script số liệu hệ thống chạy thật bằng sh,
// và các ràng buộc tĩnh của giao diện (không có Quickshell nên không dựng được hình).
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');
const [cePath, slPath, hubPath] = process.argv.slice(2);
const hub = fs.readFileSync(hubPath, 'utf8');
const loadLib = (p, cfgNames) => {
  const src = fs.readFileSync(p, 'utf8');
  const body = src.slice(src.indexOf('QtObject {') + 10, src.lastIndexOf('}'))
    .replace(/^\s*readonly property var (\w+):\s*(.*)$/gm, 'const $1 = $2;').replace(/^\s*function (\w+)\(/gm, 'function $1(');
  const names = [...src.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
  const consts = [...src.matchAll(/^    readonly property (?:var|string|int|real) (\w+):/gm)].map(m => m[1]);
  return new Function('Qt', body + `\nreturn {${names.concat(consts).join(',')}};`)({});
};
const ce = loadLib(cePath), sl = loadLib(slPath);
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
function balancedFrom(src, i) { let d = 0, q = null; for (let k = i; k < src.length; k++) { const c = src[k]; if (q) { if (c === '\\') k++; else if (c === q) q = null; continue; } if (c === '"' || c === "'") { q = c; continue; } if (c === '(' || c === '{' || c === '[') d++; else if (c === ')' || c === '}' || c === ']') d--; else if (c === '\n' && d === 0) return k; } return src.length; }
function propExpr(name) { const m = new RegExp('readonly property \\w+ ' + name + ':\\s*').exec(hub); if (!m) throw new Error('thiếu property ' + name); const s = m.index + m[0].length, t = hub.slice(s, balancedFrom(hub, s)).trim(); return t.startsWith('{') ? `(function(){ ${t.slice(1, -1)} })()` : `(${t})`; }
function fnSrc(name) { const i = hub.indexOf('function ' + name + '('); if (i < 0) throw new Error('thiếu hàm ' + name); let j = hub.indexOf('{', i), d = 0, k = j; for (; k < hub.length; k++) { if (hub[k] === '{') d++; else if (hub[k] === '}') { d--; if (!d) break; } } return hub.slice(i, k + 1); }
const PROPS = ['runningCount', 'curInfo', 'curKeys', 'runLabel'];
const FNS = ['titleOf', 'fnObjId', 'dashAct', 'sysLine', 'fmtUp', 'hex4'];
function mk(o) {
  const R = Object.assign({
    ce, sl, Math, JSON, parseInt, isNaN, String, Array, Object, apps: [], cur: null, curFns: [], fnSel: 0, page: 'apps', closing: false, revertActive: false,
    cfg: { data: { version: 1, global: {}, apps: {} } }, calls: [], previewOn: false,
    sysUp: -1, sysMem: -1, sysMemText: '', sysLoad: '', sysBat: -1, sysBatState: '', sysTemp: -1, logLines: [], logBuf: []
  }, o || {});
  R.openSettings = (p) => R.calls.push('settings:' + p); R.openStore = () => R.calls.push('store'); R.dismiss = () => R.calls.push('dismiss'); R.runSelected = () => R.calls.push('run');
  for (const p of PROPS) Object.defineProperty(R, p, { get() { return new Function('R', `with (R) { return ${propExpr(p)}; }`)(R); }, configurable: true });
  Object.assign(R, new Function('R', `with (R) {\n${FNS.map(fnSrc).join('\n')}\nreturn {${FNS.join(',')}};\n}`)(R));
  return R;
}
const JIGEN = { id: 'jigen', name: 'JIGEN 時限', kanji: '時限', kind: 'daemon', version: '1.2.1', running: true, source: 'github.com/DasNiemand/sumi-jigen', ref: 'v1.2.1', sha: 'c467a6f'.padEnd(40, '0'),
  functions: [{ id: 'shutdown', label: 'SHUTDOWN', ipc_name: 'shutdown', objects: ['globe', 'torus', 'hourglass'], defaultObject: 'globe' }, { id: 'timer', label: 'TIMER', ipc_name: 'shutdown30', objects: ['globe', 'torus', 'hourglass'], defaultObject: 'hourglass' }],
  options: [{ key: 'a' }, { key: 'b' }, { key: 'c' }], keybinds: [{ action: 'confirm', default: 'Return', label: 'confirm', locked: false }, { action: 'cancel', default: 'Escape', label: 'cancel', locked: true }] };
const KAK = { id: 'kakunin', name: 'KAKUNIN 確認', kanji: '確認', kind: 'oneshot', version: '1.2.1', running: false, source: 'dev', ref: '', sha: '', functions: [{ id: 'confirm', label: 'CONFIRM', ipc_name: 'confirm', objects: [], defaultObject: '' }], options: [], keybinds: [] };

// ---- titleOf ----
let R = mk();
eq([R.titleOf(JIGEN), R.titleOf(KAK), R.titleOf({ name: 'Foo', kanji: '' }), R.titleOf({ name: '墨', kanji: '墨' }), R.titleOf(null)], ['JIGEN', 'KAKUNIN', 'FOO', '墨', ''], 'titleOf bỏ kanji khỏi tiêu đề, giữ nếu chỉ có kanji');

// ---- fnObjId ----
R = mk();
eq([R.fnObjId(JIGEN, JIGEN.functions[0]), R.fnObjId(JIGEN, JIGEN.functions[1])], ['globe', 'hourglass'], 'mặc định = defaultObject');
R = mk({ cfg: { data: { apps: { jigen: { objects: { shutdown: { id: 'torus' }, timer: { id: 'bogus' } } } } } } });
eq([R.fnObjId(JIGEN, JIGEN.functions[0]), R.fnObjId(JIGEN, JIGEN.functions[1])], ['torus', 'hourglass'], 'config hợp lệ được dùng; giá trị lạ bị bỏ');
R = mk({ cfg: { data: null } }); eq(R.fnObjId(JIGEN, JIGEN.functions[0]), 'globe', 'config null không lỗi');
eq(R.fnObjId(KAK, KAK.functions[0]), '-', 'function không có object -> "-"');
eq(R.fnObjId(JIGEN, { id: 'x', objects: ['a', 'b'], defaultObject: '' }), 'a', 'không có defaultObject -> object đầu');

// ---- runningCount / curInfo / curKeys / runLabel ----
R = mk({ apps: [JIGEN, KAK, Object.assign({}, KAK, { running: true })] }); eq(R.runningCount, 2, 'đếm app đang chạy');
R = mk({ cur: null }); eq([R.curInfo, R.curKeys, R.runLabel], [[], [], ''], 'không có app: rỗng');
R = mk({ cur: JIGEN, curFns: JIGEN.functions });
eq(R.curInfo.map(r => r[0]), ['VERSION', 'SOURCE', 'KIND', 'REF', 'STATUS', 'SHA', 'FUNCTIONS', 'OPTIONS / KEYS'], 'lưới DETAILS: 8 mục, đúng thứ tự cặp cột');
eq(R.curInfo.map(r => r[1]), ['v1.2.1', 'github.com/DasNiemand/sumi-jigen', 'DAEMON', 'v1.2.1', 'RUNNING', 'c467a6f00000', '2', '3 / 2'], 'giá trị DETAILS');
R = mk({ cur: KAK, curFns: KAK.functions }); eq([R.curInfo[1][1], R.curInfo[3][1], R.curInfo[5][1], R.curInfo[4][1]], ['DEV (LOCAL)', '-', '-', 'IDLE'], 'bản dev: SOURCE/REF/SHA');
R = mk({ cur: JIGEN, curFns: JIGEN.functions });
eq(R.curKeys, [{ label: 'CONFIRM', key: 'Return' }, { label: 'CANCEL', key: 'Escape' }], 'phím mặc định');
R = mk({ cur: JIGEN, curFns: JIGEN.functions, cfg: { data: { apps: { jigen: { keybinds: { confirm: 'Space', cancel: 'Q' } } } } } });
eq(R.curKeys, [{ label: 'CONFIRM', key: 'Space' }, { label: 'CANCEL', key: 'Escape' }], 'phím người dùng đổi được hiện; phím khóa (cancel) giữ nguyên');
R = mk({ cur: JIGEN, curFns: JIGEN.functions, fnSel: 1 }); eq(R.runLabel, 'RUN   JIGEN  /  TIMER', 'RUN ghi function đang chọn');
R = mk({ cur: JIGEN, curFns: JIGEN.functions, fnSel: 9 }); eq(R.runLabel, 'RUN   JIGEN  /  TIMER', 'fnSel vượt biên được kẹp');
R = mk({ cur: KAK, curFns: KAK.functions }); eq(R.runLabel, 'RUN   KAKUNIN', 'oneshot không ghi function');

// ---- dashAct ----
R = mk(); for (const k of ['T', 'TAB', 'F', 'K', 'O', 'G', 'ESC', 'RUN', 'X', 'V', 'J']) R.dashAct(k);
eq(R.calls, ['settings:theme', 'settings:theme', 'settings:font', 'settings:keys', 'settings:options', 'store', 'dismiss', 'run'], 'dashAct gọi đúng hành động; phím lạ (kể cả V, J cũ) bị bỏ qua');
for (const o of [{ closing: true }, { revertActive: true }, { page: 'theme' }]) { R = mk(o); R.dashAct('T'); R.dashAct('RUN'); eq(R.calls, [], 'dashAct bị chặn: ' + JSON.stringify(o)); }

// ---- sysLine / fmtUp ----
R = mk();
for (const l of ['begin=1', 'up=93784', 'mem=16000000 4000000', 'load=0.12 0.20 0.18', 'bat=82 Charging', 'temp=54000', 'log=2026-11-07 20:30:00 hub start', 'log=a=b', 'end=1']) R.sysLine(l);
eq([R.sysUp, Math.round(R.sysMem * 1000) / 1000, R.sysMemText, R.sysLoad, R.sysBat, R.sysBatState, R.sysTemp, R.logLines], [93784, 0.75, '11.4 / 15.3 GB', '0.12 0.20 0.18', 82, 'Charging', 54, ['2026-11-07 20:30:00 hub start', 'a=b']], 'sysLine: parse đủ khóa, log giữ dấu "="');
R.sysLine('begin=1'); R.sysLine('log=mới'); eq(R.logLines.length, 2, 'log chưa đổi cho tới khi `end`'); R.sysLine('end=1'); eq(R.logLines, ['mới'], 'end chốt log mới');
R = mk(); for (const l of ['up=abc', 'mem=0 0', 'mem=100 200', 'bat=x', 'temp=0', 'temp=-5', 'garbage', '=1', 'bat=250 Full']) R.sysLine(l);
eq([R.sysUp, R.sysMem, R.sysBat, R.sysTemp], [-1, -1, 100, -1], 'dữ liệu hỏng bị bỏ, pin kẹp 0..100');
eq([R.fmtUp(-1), R.fmtUp(0), R.fmtUp(3600 * 5 + 60 * 7), R.fmtUp(86400 * 2 + 3600 * 3 + 60 * 4)], ['-', '00h 00m', '05h 07m', '2d 03h 04m'], 'fmtUp');
eq(/^[0-9A-F]{4}$/.test(R.hex4()), true, 'hex4');

// ---- script số liệu thật chạy bằng sh ----
const cmdM = /command: \["sh", "-c", (\[[\s\S]*?\])\.join\("\\n"\)\]/.exec(hub);
eq(!!cmdM, true, 'tìm thấy script sysProc');
const lines = new Function('return ' + cmdM[1])();
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dashtest-'));
const logf = path.join(tmp, 'sumi.log');
fs.writeFileSync(logf, Array.from({ length: 9 }, (_, i) => `2026-11-07 20:0${i} dòng ${i}`).join('\n') + '\n');
const script = lines.join('\n').split('/tmp/sumi.log').join(logf);
const out = cp.spawnSync('sh', ['-c', script], { encoding: 'utf8' });
eq(out.status, 0, 'script thoát mã 0');
R = mk(); for (const l of out.stdout.split('\n')) if (l !== '') R.sysLine(l);
eq(out.stdout.split('\n')[0] === 'begin=1' && out.stdout.trim().endsWith('end=1'), true, 'script mở bằng begin, đóng bằng end');
eq([R.sysUp > 0, R.sysMem > 0 && R.sysMem < 1, /GB$/.test(R.sysMemText), /^[0-9.]+ [0-9.]+ [0-9.]+$/.test(R.sysLoad)], [true, true, true, true], 'số liệu thật từ /proc parse được');
eq([R.logLines.length, R.logLines[0], R.logLines[5]], [6, '2026-11-07 20:03 dòng 3', '2026-11-07 20:08 dòng 8'], 'log lấy 6 dòng cuối');
fs.rmSync(tmp, { recursive: true });
eq(cp.spawnSync('sh', ['-c', lines.join('\n').split('/tmp/sumi.log').join(path.join(tmp, 'khong-co'))], { encoding: 'utf8' }).status, 0, 'không có log vẫn thoát mã 0');

// ---- ràng buộc giao diện ----
const code = hub.split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n');
const dashSrc = hub.slice(hub.indexOf('id: dash\n'), hub.indexOf('// ---------- SETTINGS'));
eq(/id: dash\s+visible: root\.page === "apps"/.test(hub), true, 'dashboard chỉ hiện ở trang APPS');
eq(/Timer \{\s+interval: 2000; repeat: true; triggeredOnStart: true\s+running: root\.page === "apps" && !root\.closing/.test(hub), true, 'số liệu hệ thống chỉ chạy khi ở APPS và chưa tắt máy');
eq(/Timer \{\s+interval: 130; repeat: true\s+running: root\.page === "apps" && root\.crtContentP >= 1 && !root\.closing/.test(hub), true, 'ticker hex chỉ chạy khi cần');
eq(/stdout: SplitParser \{ onRead: \(line\) => root\.sysLine\(line\) \}/.test(hub), true, 'sysProc đọc từng dòng qua sysLine');
eq(/anchors\.fill: parent\s+\/\/ Toàn màn hình|id: card\s+anchors\.fill: parent/.test(hub), true, 'card toàn màn hình');
eq(/anchors \{ top: true; bottom: true; left: true; right: true \}/.test(hub), true, 'PanelWindow phủ 4 cạnh');
eq(/property color (litColor|dimColor|alertColor)/.test(hub) && !/property \w+ on[A-Z]/.test(hub), true, 'PixelBar không đặt tên property on+Hoa (bị hiểu là signal handler)');
eq(/ShapePath \{\s+id: runSP[\s\S]*?PathLine \{ x: runBar\.width - runSP\.c; y: runBar\.height \}/.test(dashSrc), true, 'RUN bar: ShapePath có id và PathLine dùng runSP.c');
eq(/ShapePath \{\s+id: bodySP[\s\S]*?PathLine \{ x: card\.width - bodySP\.ins - bodySP\.c;/.test(hub), true, 'khung: PathLine dùng bodySP.ins/bodySP.c');
eq(['aCol', 'bCol', 'cCol', 'regPanel', 'logPanel', 'sysPanel', 'keyPanel', 'runBar'].every(id => new RegExp('id: ' + id + '\\b').test(dashSrc)), true, 'đủ 3 cột và các panel');
eq(['SYSTEM', 'SHORTCUTS', 'REGISTRY', 'LOG', 'KEYBINDS', 'FUNCTIONS', 'DETAILS'].every(t => dashSrc.includes('text: "' + t + '"') || dashSrc.includes('"' + t + '"')), true, 'đủ tiêu đề panel');
eq((dashSrc.match(/\broot\.dashAct\("(\w+)"\)/g) || []).length >= 2 && /root\.dashAct\(skey\.modelData\[0\]\)/.test(dashSrc), true, 'chuột: RUN, STORE và lưới phím tắt đều qua dashAct');
eq(/model: root\.apps\s+currentIndex: root\.sel/.test(dashSrc) && /onClicked: \{ root\.sel = row\.index; root\.fnSel = 0 \}/.test(dashSrc) && /onClicked: root\.fnSel = fcard\.index/.test(dashSrc), true, 'chuột chọn app / function');
eq(/Qt\.quit\(\)/.test(dashSrc) || /Quickshell\.exec/.test(dashSrc), false, 'dashboard không tự thoát/chạy lệnh (chỉ qua hàm root)');
// không số liệu bịa: mọi giá trị hệ thống lấy từ root.sys*
eq(/root\.sysMem/.test(dashSrc) && /root\.sysBat/.test(dashSrc) && /root\.sysTemp/.test(dashSrc) && /root\.sysLoad/.test(dashSrc) && /root\.fmtUp\(root\.sysUp\)/.test(dashSrc), true, 'SYSTEM dùng số liệu thật');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, dashboard)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
