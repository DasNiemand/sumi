// Test máy trạng thái tab OPTIONS trong hub/shell.qml (trích hàm thật, giả lập root) + lib SumiConfigEdit.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const grab = n => { const i = src.indexOf('function ' + n + '('); let j = src.indexOf('{', i), d = 0, k = j; for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } } return src.slice(i, k + 1); };
const names = [...src.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
const cm = [...src.matchAll(/^    readonly property var (\w+): (.*)$/gm)];
const consts = cm.map(m => `const ${m[1]} = (${m[2]});`).join('\n');
const cnames = cm.map(m => m[1]);
const body = consts + '\n' + names.map(grab).join('\n') + `\nreturn {${names.concat(cnames).join(',')}};`;
// Qt giả: mã phím = số thứ tự ổn định cho từng tên
const Qt = new Proxy({}, { get: (t, p) => (typeof p === 'string' && p.startsWith('Key_')) ? (p === 'Key_Escape' ? 1 : p === 'Key_Tab' ? 2 : p === 'Key_Backtab' ? 3 : 1000 + [...p].reduce((a, c) => a * 31 + c.charCodeAt(0), 7) % 100000) : undefined });
const ce = new Function('Qt', body)(Qt);
const hubSrc = fs.readFileSync(process.argv[3], 'utf8');
const grabH = n => { const i = hubSrc.indexOf('function ' + n + '('); if (i < 0) throw new Error('thiếu hàm ' + n); let j = hubSrc.indexOf('{', i), d = 0, k = j; for (; k < hubSrc.length; k++) { if (hubSrc[k] === '{') d++; else if (hubSrc[k] === '}') { d--; if (!d) break; } } return hubSrc.slice(i, k + 1); };
const JO = JSON.parse(fs.readFileSync(process.argv[4], 'utf8')).options;
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
const QT = { Key_Escape: 1, Key_Return: 2, Key_Enter: 3, Key_Backspace: 4, ControlModifier: 16, AltModifier: 8, MetaModifier: 4096 };
const fnNames = ['setOpt', 'moveOptRow', 'nudgeOpt', 'enterOpt', 'optEditKey', 'resetOptRow', 'resetOptAll', 'applyOptions', 'optShown'];
const mk = (cfgData) => {
  const R = { ce, Qt: QT, page: 'options', optDraft: {}, optSel: 0, optEditing: false, optBuf: '', optMsg: '', applyMsg: '', applyErr: '', applyOk: false, hasScope: true, scopeId: 'jigen', optList: JO,
    cfg: { data: cfgData || { version: 1, global: {}, apps: {} } }, committed: null, failed: [] };
  Object.defineProperty(R, 'optStored', { get() { return R.page === 'objects' ? ce.objectsOf(R.cfg.data, R.scopeId, R.optList) : ce.optionsOf(R.cfg.data, R.scopeId, R.optList); } });
  Object.defineProperty(R, 'optDirty', { get() { return !ce.sameOptions(R.optDraft, R.optStored); } });
  Object.defineProperty(R, 'curOpt', { get() { return R.optList.length > 0 && R.optSel >= 0 && R.optSel < R.optList.length ? R.optList[R.optSel] : null; } });
  R.fail = (m, e) => { R.failed.push([m, e || '']); };
  R.commitConfig = (next) => { R.committed = next; };
  const src = fnNames.map(grabH).join('\n');
  Object.assign(R, new Function('R', `with (R) {\n${src}\nreturn {${fnNames.join(',')}};\n}`)(R));
  return R;
};
const sel = (R, key) => { R.optSel = R.optList.findIndex(o => o.key === key); };
const typ = (R, text) => { for (const ch of text) R.optEditKey({ key: 100, text: ch, modifiers: 0, isAutoRepeat: false }); };
const press = (R, key, extra) => R.optEditKey(Object.assign({ key, text: '', modifiers: 0, isAutoRepeat: false }, extra || {}));

let R = mk();
// nudge int: lên rồi về đúng mặc định thì bản nháp sạch
sel(R, 'timer.defaultMinutes'); R.nudgeOpt(1); eq(R.optDraft, { 'timer.defaultMinutes': 40 }, 'nudge lên'); eq(R.optDirty, true, 'dirty');
R.nudgeOpt(-1); eq(R.optDraft, {}, 'về mặc định thì xoá khỏi draft'); eq(R.optDirty, false, 'hết dirty');
// float
sel(R, 'dither.noise'); R.nudgeOpt(1); eq(R.optDraft['dither.noise'], 0.34, 'float +0.02');
// kiểu không nudge được
sel(R, 'timer.presets'); R.nudgeOpt(1); eq(R.optMsg, 'KIỂU NÀY SỬA BẰNG ENTER', 'intlist không nudge'); 
// ô nhập intlist
R.resetOptAll(); sel(R, 'timer.presets'); R.enterOpt();
eq([R.optEditing, R.optBuf], [true, '5, 15, 30, 60'], 'mở ô nhập với giá trị hiện tại');
press(R, QT.Key_Backspace); press(R, QT.Key_Backspace); typ(R, '90'); eq(R.optBuf, '5, 15, 30, 90', 'gõ');
press(R, QT.Key_Return); eq([R.optEditing, R.optDraft['timer.presets']], [false, [5, 15, 30, 90]], 'Enter lưu nháp');
// ô nhập lỗi: ở lại, báo lỗi; Esc huỷ không đổi gì
R.enterOpt(); typ(R, ', 500'); press(R, QT.Key_Return);
eq([R.optEditing, R.optMsg], [true, '500 NGOÀI KHOẢNG 1..240'], 'giá trị sai -> ở lại ô nhập'); 
press(R, QT.Key_Escape); eq([R.optEditing, R.optMsg, R.optDraft['timer.presets']], [false, '', [5, 15, 30, 90]], 'Esc huỷ, giữ nháp cũ');
// ký tự cấm bị từ chối + thông báo
R.enterOpt(); typ(R, 'x'); eq([R.optBuf.endsWith('x'), R.optMsg.startsWith('KÝ TỰ KHÔNG HỢP LỆ')], [false, true], 'ký tự cấm'); press(R, QT.Key_Escape);
// Ctrl+phím không gõ vào ô
R.enterOpt(); const before = R.optBuf; R.optEditKey({ key: 100, text: '5', modifiers: QT.ControlModifier, isAutoRepeat: false }); eq(R.optBuf, before, 'Ctrl bị bỏ qua'); press(R, QT.Key_Escape);
// auto-repeat Backspace được, ký tự thì không
R.enterOpt(); R.optEditKey({ key: 100, text: '7', modifiers: 0, isAutoRepeat: true }); eq(R.optBuf, before, 'auto-repeat ký tự bị bỏ'); R.optEditKey({ key: QT.Key_Backspace, text: '', modifiers: 0, isAutoRepeat: true }); eq(R.optBuf, before.slice(0, -1), 'auto-repeat Backspace xoá'); press(R, QT.Key_Escape);
// reset hàng / tất cả
R.resetOptRow(); eq('timer.presets' in R.optDraft, false, 'R xoá hàng'); R.nudgeOpt(1);
sel(R, 'crtBootMs'); R.enterOpt(); press(R, QT.Key_Backspace); press(R, QT.Key_Backspace); press(R, QT.Key_Backspace); typ(R, '1200'); press(R, QT.Key_Return);
eq(R.optDraft, { 'crtBootMs': 1200 }, 'sửa số bằng ô nhập (nudge presets không đổi gì)');
R.resetOptAll(); eq(R.optDraft, {}, 'X xoá hết');
// bool/enum: Enter đổi giá trị luôn
const BO = { key: 'b', type: 'bool', default: false, label: 'B' }, EO = { key: 'e', type: 'enum', default: 'a', values: ['a', 'b'], label: 'E' };
R = mk(); R.optList = [BO, EO]; R.enterOpt(); eq(R.optDraft, { b: true }, 'bool bật'); R.enterOpt(); eq(R.optDraft, {}, 'bool tắt về mặc định');
R.optSel = 1; R.enterOpt(); eq(R.optDraft, { e: 'b' }, 'enum đổi'); eq(R.optEditing, false, 'bool/enum không mở ô nhập');
// khoá
const LK = { key: 'l', type: 'int', default: 5, min: 1, max: 9, label: 'L', locked: true };
R = mk(); R.optList = [LK]; R.nudgeOpt(1); eq([R.optDraft, R.optMsg], [{}, 'LOCKED'], 'nudge khoá'); R.enterOpt(); eq([R.optEditing, R.optMsg.startsWith('LOCKED')], [false, true], 'enter khoá'); R.resetOptRow(); eq(R.optDraft, {}, 'reset khoá không làm gì');
// apply
R = mk(); R.applyOptions(); eq([R.failed, R.committed], [[['NO CHANGES', '']], null], 'apply không đổi gì');
sel(R, 'timer.defaultMinutes'); R.nudgeOpt(1); R.applyOptions();
eq([R.failed.length, R.committed.apps.jigen.options], [1, { 'timer.defaultMinutes': 40 }], 'apply ghi config');
R = mk(); R.hasScope = false; R.applyOptions(); eq(R.failed[0][0], 'REJECTED', 'không có scope');
R = mk(); R.optDraft = { bogus: 1 }; R.applyOptions(); eq([R.failed[0][0], R.failed[0][1], R.committed], ['REJECTED', 'option lạ: bogus', null], 'draft bẩn bị validate chặn');
// config đã lưu: optStored khớp thì không dirty
R = mk({ version: 1, global: {}, apps: { jigen: { options: { 'timer.defaultMinutes': 45 } } } });
R.optDraft = ce.optionsOf(R.cfg.data, 'jigen', JO); eq(R.optDirty, false, 'nạp từ config -> sạch'); sel(R, 'timer.defaultMinutes'); R.nudgeOpt(1); eq(R.optDirty, true, 'sửa -> dirty');
// apply giữ key khác trong config
R.applyOptions(); eq(R.committed.apps.jigen.options, { 'timer.defaultMinutes': 55 }, 'apply sửa đúng giá trị');


// ---- trang OBJECTS dùng chung máy trạng thái ----
{
  const jm = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
  const OO = ce.objectOptsOf(jm);
  const R2 = mk({ version: 1, global: {}, apps: { jigen: { objects: { shutdown: { grid: 50 } } } } });
  R2.optList = OO; R2.page = 'objects';
  R2.optDraft = ce.objectsOf(R2.cfg.data, 'jigen', OO);
  R2.optSel = 0; R2.enterOpt(); eq(R2.optDraft, { 'shutdown.id': 'torus' }, 'Enter trên hàng enum đổi object (globe -> torus)');
  R2.nudgeOpt(1); eq(R2.optDraft['shutdown.id'], 'hourglass', 'D tiếp'); R2.nudgeOpt(1); eq('shutdown.id' in R2.optDraft, false, 'vòng về mặc định thì xoá khỏi draft');
  R2.optSel = 1; R2.nudgeOpt(1); R2.nudgeOpt(1); eq(R2.optDraft['shutdown.speed'], 1.2, 'speed +0.1 mỗi nấc');
  R2.optSel = 2; R2.enterOpt(); eq(R2.optDraft['shutdown.interactive'], false, 'bool tắt');
  // apply gọi withObjects (giữ grid), không gọi withOptions
  const src = grabH('applyOptions');
  const ap = new Function('R', `with (R) {\n${src}\nreturn applyOptions;\n}`)(R2);
  ap();
  eq(R2.committed.apps.jigen.objects.shutdown, { grid: 50, speed: 1.2, interactive: false }, 'apply ghi objects và giữ grid');
  eq(R2.committed.apps.jigen.options, undefined, 'apply trang objects không ghi options');
}
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, options-ui)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
