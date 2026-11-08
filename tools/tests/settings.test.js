// Test màn hình CÀI ĐẶT gộp (THEME + FONT + KEYS + OPTIONS/OBJECTS theo phạm vi) trong hub/shell.qml.
// Trích hàm và property thật của root, chạy với root giả + SumiConfigEdit thật.
const fs = require('fs');
const [cePath, hubPath, jigenManifest, kakuninManifest] = process.argv.slice(2);
const hub = fs.readFileSync(hubPath, 'utf8');
const libSrc = fs.readFileSync(cePath, 'utf8');
const lib = libSrc.slice(libSrc.indexOf('QtObject {') + 10, libSrc.lastIndexOf('}')).replace(/^\s*readonly property var (\w+):\s*(.*)$/gm, 'const $1 = $2;');
const lnames = [...libSrc.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]), lconsts = [...libSrc.matchAll(/^    readonly property var (\w+):/gm)].map(m => m[1]);
const QTK = new Proxy({ application: { font: { family: 'SysFont' } } }, { get: (t, p) => p in t ? t[p] : (typeof p === 'string' && p.startsWith('Key_') ? 1000 + p.length : undefined) });
const ce = new Function('Qt', lib + `\nreturn {${lnames.concat(lconsts).join(',')}};`)(QTK);
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };

const head = hub.slice(0, hub.indexOf('    PanelWindow {'));
function balancedFrom(src, i) { let d = 0, q = null; for (let k = i; k < src.length; k++) { const c = src[k]; if (q) { if (c === '\\') k++; else if (c === q) q = null; continue; } if (c === '"' || c === "'") { q = c; continue; } if (c === '(' || c === '{' || c === '[') d++; else if (c === ')' || c === '}' || c === ']') d--; else if (c === '\n' && d === 0) return k; } return src.length; }
const props = {}, writable = {};
for (const m of head.matchAll(/^    readonly property \w+ (\w+):\s*/gm)) { const s = m.index + m[0].length; const t = head.slice(s, balancedFrom(head, s)).trim(); props[m[1]] = t.startsWith('{') ? `(function(){ ${t.slice(1, -1)} })()` : `(${t})`; }
for (const m of head.matchAll(/^    property (\w+) (\w+):\s*(.*)$/gm)) writable[m[2]] = m[3];
function fnSrc(name) { const i = head.indexOf('    function ' + name + '('); if (i < 0) throw new Error('thiếu hàm ' + name); let j = head.indexOf('{', i), d = 0, k = j; for (; k < head.length; k++) { if (head[k] === '{') d++; else if (head[k] === '}') { d--; if (!d) break; } } return head.slice(i, k + 1); }
const SKIP = new Set(['commitConfig', 'fail', 'ensureFonts', 'finish', 'dismiss', 'storeKey', 'runSelected', 'openStore', 'move', 'moveFn', 'pickerKey', 'captureEvent', 'optEditKey', 'applyDone', 'revertTick', 'keepConfig', 'doRevert', 'revertKey', 'sysLine', 'dashAct']);
const fnames = [...head.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]).filter(x => !SKIP.has(x));

const JM = JSON.parse(fs.readFileSync(jigenManifest, 'utf8')), KM = JSON.parse(fs.readFileSync(kakuninManifest, 'utf8'));
const asApp = (m, dir) => Object.assign({ dir, kanji: '', description: '', running: false, source: 'dev', ref: '', sha: '' }, m);
const JIGEN = asApp(JM, '/d/jigen'), KAK = asApp(KM, '/d/kakunin');

const mk = (o) => {
  const R = Object.assign({
    ce, Qt: QTK, apps: [JIGEN, KAK], cur: JIGEN, fnSel: 0,
    cfg: { data: { version: 1, global: {}, apps: {} } },
    th: { minContrast: 4.5, goodContrast: 7, derive: (name, t, i) => ({ contrast: name === 'bad' ? 3 : (name === 'weak' ? 5 : 9), paper: '#fff', ink: '#000', soft: '#444', rule: '#888', ghostB: '#00f' }) },
    committed: null, failed: [], applyProc: { running: false }
  }, o || {});
  for (const k in writable) if (!(k in R)) { try { R[k] = new Function('Qt', 'return (' + writable[k] + ')')(QTK); } catch (e) { R[k] = undefined; } }
  for (const k in props) if (!(k in R)) Object.defineProperty(R, k, { get() { return new Function('R', `with (R) { return ${props[k]}; }`)(R); }, configurable: true });
  R.commitConfig = (next) => { R.committed = next; };
  R.fail = (m, e) => { R.failed.push([m, e || '']); };
  R.ensureFonts = () => {};
  Object.assign(R, new Function('R', `with (R) {\n${fnames.map(fnSrc).join('\n')}\nreturn {${fnames.join(',')}};\n}`)(R));
  return R;
};
const enter = (R, p, id) => { R.enterPage(p, id); return R; };

// ---- phạm vi và section ----
let R = mk();
eq(R.scopes.map(s => s.id), ['global', 'hub', 'jigen', 'kakunin'], 'phạm vi: GLOBAL, HUB rồi mọi app');
enter(R, 'theme', 'global'); eq([R.scopeId, R.secList], ['global', ['theme', 'font']], 'GLOBAL: THEME + FONT');
enter(R, 'theme', 'hub'); eq([R.scopeId, R.secList, R.secCount('theme'), R.tintEditable], ['hub', ['theme', 'options'], 1, false], 'HUB: THEME (chỉ preset) + OPTIONS, không FONT/KEYS');
enter(R, 'theme', 'jigen'); eq([R.secList, R.secCount('theme'), R.secCount('font'), R.secCount('keys')], [['theme', 'font', 'keys', 'options'], 3, 5, JIGEN.keybinds.length], 'app: đủ 4 section');
eq(R.secCount('options'), R.objOptList.length + R.plainOptList.length, 'OPTIONS = OBJECTS + option manifest');
eq(R.objOptList.length > 0 && R.plainOptList.length === JIGEN.options.length, true, 'jigen có objects và option');
eq(R.secTitle('options'), 'OPTIONS / OBJECTS', 'tiêu đề section gộp');
enter(R, 'theme', 'kakunin'); eq([R.objOptList.length, R.plainOptList.map(o => o.key), R.secTitle('options')], [0, KAK.options.map(o => o.key), 'OPTIONS'], 'kakunin: không có objects');
eq(R.optsWithout([{ key: 'a' }, { key: 'b' }], [{ key: 'a' }]).map(o => o.key), ['b'], 'optsWithout bỏ khoá trùng');
eq(R.mergeOpts({ a: 1 }, { b: 2, a: 3 }), { a: 3, b: 2 }, 'mergeOpts');
enter(R, 'theme', 'nope'); eq(R.scopeId, 'global', 'id lạ -> phần tử đầu');

// ---- viewRows / viewSel / moveRow ----
enter(R, 'theme', 'jigen');
const heads = R.viewRows.filter(r => r.kind === 'head').map(r => r.sec);
eq(heads, ['theme', 'font', 'keys', 'options'], 'viewRows: tiêu đề từng section');
eq([R.viewRows[0].kind, R.viewRows[1].kind, R.viewRows.filter(r => r.kind === 'row').length === R.flatCount], ['head', 'row', true], 'viewRows: head rồi các hàng');
eq(R.viewRows[R.viewSel], { kind: 'row', sec: 'theme', i: 0 }, 'viewSel trỏ đúng hàng focus');
R.moveRow(1); eq([R.page, R.themeSel], ['theme', 1], 'S: hàng kế');
R.moveRow(1); R.moveRow(1); eq([R.page, R.fontSel], ['font', 0], 'hết THEME sang FONT');
for (let i = 0; i < 4; i++) R.moveRow(1); eq([R.page, R.fontSel], ['font', 4], 'đi hết FONT');
R.moveRow(1); eq([R.page, R.keySel], ['keys', 0], 'sang KEYS');
for (let i = 0; i < R.secCount('keys'); i++) R.moveRow(1); eq([R.page, R.optSel], ['options', 0], 'sang OPTIONS');
for (let i = 0; i < R.secCount('options'); i++) R.moveRow(1); eq([R.page, R.themeSel], ['theme', 0], 'vòng về đầu');
R.moveRow(-1); eq([R.page, R.optSel], ['options', R.secCount('options') - 1], 'W ở đầu -> hàng cuối');
eq(R.viewRows[R.viewSel], { kind: 'row', sec: 'options', i: R.secCount('options') - 1 }, 'viewSel theo');
enter(R, 'theme', 'hub'); R.moveRow(1); eq([R.page, R.optSel], ['options', 0], 'HUB: theme chỉ 1 hàng, S sang OPTIONS');
// focusRow: tắt các chế độ đang mở, bỏ qua section rỗng
enter(R, 'theme', 'jigen'); R.capturing = true; R.pickOpen = true; R.optEditing = true; R.capMsg = 'x'; R.optMsg = 'y';
R.focusRow('keys', 2); eq([R.page, R.keySel, R.capturing, R.pickOpen, R.optEditing, R.capMsg, R.optMsg], ['keys', 2, false, false, false, '', ''], 'focusRow đóng picker/capture/ô nhập');
enter(R, 'theme', 'global'); R.focusRow('keys', 0); eq(R.page, 'theme', 'section rỗng bị bỏ qua'); R.focusRow('font', 99); eq([R.page, R.fontSel], ['font', 4], 'chỉ số kẹp theo số hàng');
// Tab / số
enter(R, 'theme', 'jigen'); R.cycleSection(1); eq(R.page, 'font', 'Tab'); R.cycleSection(-1); R.cycleSection(-1); eq(R.page, 'options', 'Shift+Tab vòng ngược');
R.jumpSection(2); eq(R.page, 'keys', 'phím 3 = section thứ 3'); R.jumpSection(9); eq(R.page, 'keys', 'số quá lớn bị bỏ qua');
enter(R, 'theme', 'hub'); R.jumpSection(1); eq(R.page, 'options', 'HUB: phím 2 = OPTIONS (đánh số theo section đang có)');
R.focusRow('options', 3); R.cycleSection(1); eq([R.page, R.themeSel], ['theme', 0], 'Tab giữ vị trí hàng đã chọn của từng section');

// ---- đổi phạm vi: nạp lại nháp, chỉnh focus nếu section biến mất ----
enter(R, 'keys', 'jigen'); R.draft = { theme: 'ink', tint: null, inkDarken: null }; R.keySel = 3; R.applyMsg = 'APPLIED';
R.moveScope(-1); eq([R.scopeId, R.page, R.keySel, R.draft.theme, R.applyMsg], ['hub', 'theme', 0, null, ''], 'sang HUB (không có KEYS): về THEME, nháp và trạng thái được xoá');
R.setScope(2); eq([R.scopeId, R.keepScope], ['jigen', 'jigen'], 'setScope nhớ phạm vi');
R.moveScope(1); R.moveScope(1); eq(R.scopeId, 'global', 'vòng tròn');
// openSettings
R.cur = KAK; R.openSettings('keys'); eq([R.page, R.scopeId], ['keys', 'kakunin'], 'mở từ dashboard: app đang chọn, đúng section');
R.openSettings('objects'); eq([R.page, R.scopeId], ['options', 'jigen'.length ? 'kakunin' : ''], 'phím J cũ = section OPTIONS');
R.cur = null; R.keepScope = 'hub'; R.openSettings('font'); eq([R.page, R.scopeId], ['theme', 'hub'], 'không có app: dùng phạm vi gần nhất; section không có thì về THEME');
R.closeSettings(); eq(R.page, 'apps', 'Esc về dashboard');

// ---- chỉnh hàng ----
R = mk(); enter(R, 'theme', 'jigen');
R.rowAdjust(1); eq(R.draft.theme, 'ink', 'preset +1'); R.rowAdjust(-1); eq(R.draft.theme, 'paper', 'preset -1');
R.themeSel = 1; R.rowAdjust(1); eq(R.draft.tint, 0.14, 'tint +0.02'); R.themeSel = 2; R.rowAdjust(-1); eq(R.draft.inkDarken, 1.4, 'ink -0.1');
R.themeSel = 1; R.rowReset(); eq([R.draft.tint, R.draft.inkDarken], [null, 1.4], 'R trên hàng TINT chỉ xoá tint');
R.sectionReset(); eq(R.draft, { theme: null, tint: null, inkDarken: null }, 'X trong THEME = inherit hết');
R.themeSel = 0; R.rowEnter(); eq(R.draft.theme, 'ink', 'Enter trên PRESET = preset kế'); R.themeSel = 1; R.draft = { theme: null, tint: null, inkDarken: null }; R.rowEnter(); eq(R.draft.tint, null, 'Enter trên thanh không làm gì');
enter(R, 'theme', 'hub'); R.rowAdjust(1); R.themeSel = 0; R.nudge('tint', 0.02); eq(R.draft.tint, null, 'HUB không chỉnh tint');
enter(R, 'theme', 'jigen'); R.focusRow('options', 0); R.rowAdjust(1); eq(R.optDraft['shutdown.id'], 'torus', 'A/D trên hàng OPTIONS = nudge');
R.sectionReset(); eq(R.optDraft, {}, 'X trong OPTIONS xoá nháp'); R.focusRow('font', 1); R.fontDraft = { title: 'A', label: 'B', data: null, numeral: null, kanji: null }; R.rowReset(); eq(R.fontDraft.label, null, 'R trên font xoá hàng'); R.sectionReset(); eq(R.fontDraft.title, null, 'X trong FONT');
const kfree = JIGEN.keybinds.findIndex(k => k.locked !== true); R.focusRow('keys', kfree); R.keyDraft = { [JIGEN.keybinds[kfree].action]: 'Q', zzz: 'W' }; R.rowReset(); eq(R.keyDraft, { zzz: 'W' }, 'R trên phím xoá đúng hàng');
R.keyDraft = { a: 'Q' }; R.sectionReset(); eq(R.keyDraft, {}, 'X trong KEYS');

// ---- Apply gộp ----
R = mk(); enter(R, 'theme', 'jigen');
R.applyCurrent(); eq([R.failed, R.committed], [[['NO CHANGES', '']], null], 'không đổi gì');
R.setPreset('ink'); R.applyCurrent(); eq([R.committed.apps.jigen.theme, R.failed.length], ['ink', 1], 'chỉ theme đổi');
R = mk(); enter(R, 'theme', 'jigen');
R.setPreset('mono-black'); R.setFont('title', 'My Sans');
R.focusRow('keys', 0); const kb = JIGEN.keybinds.find(k => k.locked !== true); const ki = JIGEN.keybinds.indexOf(kb); R.setKey(kb.action, 'Q');
R.focusRow('options', 0); R.rowAdjust(1);
eq(R.dirtyList, ['theme', 'font', 'keys', 'options'], 'dirtyList đủ 4 section');
R.applyCurrent();
const A = R.committed && R.committed.apps.jigen;
eq(!!A && [A.theme, A.fonts.title, A.keybinds[kb.action], A.objects.shutdown.id], ['mono-black', 'My Sans', 'Q', 'torus'], 'MỘT lần commit chứa theme + font + phím + object');
eq(R.failed, [], 'không lỗi');
// theme bị chặn thì không ghi gì (kể cả section khác)
R = mk(); enter(R, 'theme', 'jigen'); R.setPreset('bad'); R.setFont('title', 'X'); R.applyCurrent();
eq([R.failed[0][0], R.committed], ['BLOCKED', null], 'theme tương phản thấp chặn cả lần apply');
// section khác sai -> REJECTED, không commit
R = mk(); enter(R, 'theme', 'jigen'); R.setPreset('ink'); R.optDraft = { bogus: 1 }; R.applyCurrent();
eq([R.failed[0][0], R.failed[0][1], R.committed], ['REJECTED', 'option lạ: bogus', null], 'option lạ chặn cả lần apply');
// đang ghi dở thì bỏ qua
R = mk(); enter(R, 'theme', 'jigen'); R.setPreset('ink'); R.applyProc.running = true; R.applyCurrent(); eq([R.failed, R.committed], [[], null], 'đang ghi: bỏ qua');
// HUB: theme + option hub
R = mk(); enter(R, 'theme', 'hub'); R.setPreset('ink'); R.focusRow('options', 0); R.rowAdjust(1);
R.applyCurrent(); eq([R.committed.hub.theme, R.committed.hub.autoRevert, R.committed.global.theme], ['ink', true, undefined], 'HUB ghi theme và option vào config.hub');
// GLOBAL: font global
R = mk(); enter(R, 'font', 'global'); R.setFont('data', 'Mono X'); R.applyCurrent(); eq(R.committed.global.fonts.data, 'Mono X', 'GLOBAL ghi font');

// ---- scopeTag / detailLines ----
R = mk({ cfg: { data: { version: 1, global: { theme: 'ink' }, hub: { crtBootMs: 0 }, apps: { jigen: { theme: 'ink', fonts: { title: 'S' }, keybinds: { confirm: 'Q' }, objects: { shutdown: { id: 'torus' } }, options: { 'timer.defaultMinutes': 40 } } } } } });
eq([R.scopeTag('global'), R.scopeTag('hub'), R.scopeTag('jigen'), R.scopeTag('kakunin')], ['1 SET', '1 SET', '5 SET', 'DEFAULT'], 'scopeTag đếm mục đã tuỳ chỉnh');
enter(R, 'theme', 'jigen'); R.cfg.data.apps.jigen.keybinds = {};
R.page = 'theme'; eq(R.detailLines[0].t.startsWith('CONTRAST  9.00 : 1   OK'), true, 'detail THEME: tương phản'); eq(R.detailLines.length, 2, 'THEME: tương phản + gợi ý hàng');
R.setPreset('bad'); eq([R.detailLines[0].bad, /BLOCKED/.test(R.detailLines[0].t)], [true, true], 'BLOCKED báo đỏ');
enter(R, 'theme', 'hub'); eq(R.detailLines[1].t, 'HUB dùng tint và độ đậm của GLOBAL', 'HUB: ghi chú tint');
enter(R, 'keys', 'jigen'); eq(R.detailLines[0], { t: 'KHÔNG TRÙNG PHÍM', bad: false }, 'detail KEYS');
R.capMsg = 'LOCKED'; eq(R.detailLines[0], { t: 'LOCKED', bad: true }, 'capMsg ưu tiên');
enter(R, 'options', 'jigen'); R.optMsg = 'KIỂU NÀY SỬA BẰNG ENTER'; eq(R.detailLines[0].bad, true, 'optMsg báo đỏ');
R.applyMsg = 'APPLIED'; R.applyOk = true; eq(R.detailLines[R.detailLines.length - 1], { t: 'APPLIED', bad: false }, 'kết quả apply ở cuối');
R.applyOk = false; R.applyErr = 'boom'; eq(R.detailLines[R.detailLines.length - 1], { t: 'APPLIED  boom', bad: true }, 'lỗi apply');

// ---- ràng buộc giao diện / phím ----
const kh = hub.slice(hub.indexOf('// ----- trang cài đặt -----'), hub.indexOf('// nền giấy toàn màn hình'));
eq([/Key_Tab\) \{ if \(!ar\) root\.cycleSection\(1\)/.test(kh), /Key_Backtab\) \{ if \(!ar\) root\.cycleSection\(-1\)/.test(kh), /Key_1 && k <= Qt\.Key_4\) \{ if \(!ar\) root\.jumpSection\(k - Qt\.Key_1\)/.test(kh)], [true, true, true], 'Tab / Shift+Tab / 1..4');
eq([/Key_W \|\| k === Qt\.Key_Up\) \{ if \(!ar\) root\.moveRow\(-1\)/.test(kh), /Key_S \|\| k === Qt\.Key_Down\) \{ if \(!ar\) root\.moveRow\(1\)/.test(kh), /Key_A \|\| k === Qt\.Key_Left\) \{ root\.rowAdjust\(-1\)/.test(kh), /Key_Return \|\| k === Qt\.Key_Enter\) \{ if \(!ar\) root\.rowEnter\(\)/.test(kh), /Key_Space\) \{ if \(!ar\) root\.applyCurrent\(\)/.test(kh)], [true, true, true, true, true], 'W/S xuyên section, A/D, Enter, Space = apply gộp');
eq(/Key_V/.test(hub), false, 'không còn phím V (preview luôn bật)');
eq([/id: setList[\s\S]*?model: root\.viewRows[\s\S]*?currentIndex: root\.viewSel/.test(hub), /model: root\.secList/.test(hub), /model: root\.scopes/.test(hub)], [true, true, true], 'danh sách chính theo viewRows, thanh trên theo secList');
const tpSrc = hub.slice(hub.indexOf('id: tp\n'), hub.indexOf('// ---------- trang STORE'));
eq(['sCol', 'sMain', 'sDet', 'scopeList', 'setList', 'secPanel', 'stPanel', 'detPanel', 'pk'].every(id => new RegExp('id: ' + id + '\\b').test(tpSrc)), true, 'đủ 3 cột và các panel');
eq(['headC', 'presetC', 'sliderC', 'fontC', 'keyC', 'optC'].every(id => new RegExp('Component \\{\\s+id: ' + id + '\\b').test(tpSrc)), true, 'đủ component hàng');
eq(/sourceComponent: sr\.isHead \? headC/.test(tpSrc), true, 'Loader chọn component theo loại hàng');
eq(!/\.\.\.tabIds|root\.tabIds|\bcycleTab\b|scopeListFor/.test(hub), true, 'không còn tabIds / cycleTab / scopeListFor');
// ---- transition scramble giữa các trang ----
eq(/onPageChanged: pageTok\+\+/.test(hub), true, 'đổi page tăng pageTok');
eq((hub.match(/trigger: root\.pageTok/g) || []).length >= 15, true, 'tiêu đề panel giải mã lại theo pageTok');
eq(/full: root\.secTitle\(sr\.sec\); trigger: root\.pageTok/.test(hub), true, 'tiêu đề section có trigger');
eq(/onTriggerChanged: \{ if \(active\) scramble\(\) \}/.test(fs.readFileSync(hubPath.replace(/hub\/shell\.qml$/, 'lib/ScrambleText.qml'), 'utf8')), true, 'ScrambleText có trigger');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, settings)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
