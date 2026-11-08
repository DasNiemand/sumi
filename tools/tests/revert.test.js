// Test AUTO-REVERT trong hub/shell.qml (hàm thật, root giả) + lib SumiConfigEdit.
const fs = require('fs');
const libSrc = fs.readFileSync(process.argv[2], 'utf8'), hub = fs.readFileSync(process.argv[3], 'utf8');
const body = libSrc.slice(libSrc.indexOf('QtObject {') + 10, libSrc.lastIndexOf('}')).replace(/^\s*readonly property var (\w+):\s*(.*)$/gm, 'const $1 = $2;');
const names = [...libSrc.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
const consts = [...libSrc.matchAll(/^    readonly property var (\w+):/gm)].map(m => m[1]);
const ce = new Function('Qt', body + `\nreturn {${names.concat(consts).join(',')}};`)({});
const grab = n => { const i = hub.indexOf('function ' + n + '('); if (i < 0) throw new Error('thiếu hàm ' + n); let j = hub.indexOf('{', i), d = 0, k = j; for (; k < hub.length; k++) { if (hub[k] === '{') d++; else if (hub[k] === '}') { d--; if (!d) break; } } return hub.slice(i, k + 1); };
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
const QT = { Key_Return: 2, Key_Enter: 3, Key_Space: 4, Key_Escape: 1, Key_Backspace: 5, Key_Delete: 6, Key_A: 7 };
const FN = ['revertArmed', 'applyDone', 'revertTick', 'keepConfig', 'doRevert', 'revertKey', 'dismiss', 'commitConfig', 'fail', 'finish'];
const mk = (data, o) => {
  const R = Object.assign({ ce, Qt: QT, page: 'theme', scopeId: 'jigen', optDirty: false, storeBusy: false, sumiBin: '/b/sumi',
    cfg: { data, text() { return JSON.stringify(data); } },
    applyProc: { running: false, command: [] }, applyMsg: '', applyErr: '', applyOk: false,
    applyKind: 'apply', revertPrev: '', revertArm: false, revertActive: false, revertLeft: 0, revertTotal: 0,
    quit: 0, detached: [], Quickshell: null, closing: false, outP: 0, crtOutroMs: 0, outAnim: { start() {} } }, o || {});
  R.Quickshell = { execDetached(c) { R.detached.push(c); } };
  R.Qt = Object.assign({}, QT, { quit() { R.quit++; } });
  Object.assign(R, new Function('R', `with (R) {\n${FN.map(grab).join('\n')}\nreturn {${FN.join(',')}};\n}`)(R));
  return R;
};
const run = (R) => { R.applyProc.running = true; };          // lệnh đã khởi chạy
const done = (R, code) => { R.applyProc.running = false; R.applyDone(code); };
const cfgOn = (sec) => ({ version: 1, global: { theme: 'ink' }, hub: { autoRevert: true, autoRevertSec: sec }, apps: {} });

// a) tắt: không đếm ngược
let R = mk({ version: 1, global: {} });
R.commitConfig({ version: 1, global: { theme: 'paper' } }); run(R); eq(R.applyProc.command.slice(0, 3), ['/b/sumi', 'config', 'apply'], 'apply chạy'); done(R, 0);
eq([R.applyMsg, R.revertActive], ['APPLIED', false], 'tắt auto-revert: không đếm');
// b) bật: đếm ngược, hết giờ thì hoàn tác đúng bản trước đó
const before = cfgOn(10);
R = mk(before);
R.commitConfig({ version: 1, global: { theme: 'paper' }, hub: { autoRevert: true, autoRevertSec: 10 } }); run(R);
eq(JSON.parse(R.revertPrev), before, 'revertPrev = config trước apply'); done(R, 0);
eq([R.applyMsg, R.revertActive, R.revertLeft, R.revertTotal], ['APPLIED', true, 10, 10], 'bắt đầu đếm 10 s');
for (let i = 0; i < 9; i++) R.revertTick(); eq([R.revertActive, R.revertLeft], [true, 1], 'còn 1 s');
R.revertTick();
eq([R.revertActive, R.applyKind, R.applyMsg, R.applyProc.command], [false, 'revert', 'REVERTING...', ['/b/sumi', 'config', 'apply', JSON.stringify(before)]], 'hết giờ -> áp lại bản trước');
run(R); done(R, 0); eq([R.applyMsg, R.applyOk, R.applyKind, R.revertActive], ['REVERTED', true, 'apply', false], 'hoàn tác xong, không đếm lại');
R.revertTick(); eq(R.applyMsg, 'REVERTED', 'tick sau khi xong không làm gì');
// c) giữ
R = mk(cfgOn(15)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); eq(R.revertTotal, 15, 'sec 15');
R.revertKey({ key: QT.Key_Return, isAutoRepeat: false }); eq([R.revertActive, R.applyMsg, R.applyOk], [false, 'KEPT', true], 'Enter giữ');
R.revertTick(); R.revertTick(); eq(R.applyProc.command[3] === undefined || R.applyKind === 'apply', true, 'sau khi giữ không hoàn tác');
// d) Esc / Backspace hoàn tác ngay; phím khác bị bỏ qua; auto-repeat bỏ qua
R = mk(cfgOn(30)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0);
R.revertKey({ key: QT.Key_A, isAutoRepeat: false }); eq(R.revertActive, true, 'phím khác không làm gì');
R.revertKey({ key: QT.Key_Return, isAutoRepeat: true }); eq(R.revertActive, true, 'auto-repeat Enter bỏ qua');
R.revertKey({ key: QT.Key_Escape, isAutoRepeat: false }); eq([R.revertActive, R.applyKind], [false, 'revert'], 'Esc hoàn tác ngay');
R = mk(cfgOn(10)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); R.revertKey({ key: QT.Key_Backspace, isAutoRepeat: false }); eq(R.applyKind, 'revert', 'Backspace hoàn tác');
// e) apply lỗi: không đếm
R = mk(cfgOn(10)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 3); eq([R.applyMsg, R.applyOk, R.revertActive, R.revertArm], ['FAILED (3)', false, false, false], 'apply lỗi -> không đếm ngược');
// f) đổi chính cài đặt auto-revert (OPTIONS > HUB) thì không đếm
R = mk(cfgOn(10), { page: 'options', scopeId: 'hub', optDirty: true }); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); eq(R.revertActive, false, 'scope HUB đang sửa OPTIONS (kể cả đang focus section khác) không đếm');
R = mk(cfgOn(10), { page: 'theme', scopeId: 'hub', optDirty: false }); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); eq(R.revertActive, true, 'scope HUB chỉ đổi theme vẫn đếm');
R = mk(cfgOn(10), { page: 'options', scopeId: 'jigen' }); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); eq(R.revertActive, true, 'OPTIONS của app vẫn đếm');
// g) config chưa có: hoàn tác về bản hợp lệ tối thiểu
R = mk({}); R.cfg.data = { hub: { autoRevert: true } }; R.commitConfig({ version: 1, global: {}, hub: { autoRevert: true } }); run(R); done(R, 0); R.revertKey({ key: QT.Key_Escape, isAutoRepeat: false });
eq(JSON.parse(R.applyProc.command[3]), { hub: { autoRevert: true }, version: 1, global: {} }, 'snapshot luôn có version và global');
// h) đóng hub
R = mk(cfgOn(10)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); R.dismiss();
eq([R.quit, R.detached.length, R.detached[0].slice(0, 3), R.revertActive], [1, 1, ['/b/sumi', 'config', 'apply'], false], 'đóng hub khi đang đếm -> hoàn tác rồi thoát');
R = mk(cfgOn(10)); R.dismiss(); eq([R.quit, R.detached.length], [1, 0], 'đóng hub bình thường');
R = mk(cfgOn(10), { storeBusy: true }); R.dismiss(); eq(R.quit, 0, 'store đang bận thì không đóng');
// i) đang bận ghi thì hoàn tác báo lỗi, không chạy lệnh
R = mk(cfgOn(10)); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); R.applyProc.running = true; R.applyProc.command = ['x']; R.revertKey({ key: QT.Key_Escape, isAutoRepeat: false });
eq([R.applyMsg, R.applyProc.command], ['REVERT FAILED', ['x']], 'applyProc bận: không chạy lệnh thứ hai');
// j) apply thứ hai trong lúc applyProc bận bị bỏ qua (không đè revertPrev)
R = mk(cfgOn(10)); R.commitConfig({ version: 1, global: { a: 1 } }); run(R); const prev1 = R.revertPrev; R.cfg.data = { version: 1, global: { changed: 1 } }; R.commitConfig({ version: 1, global: { b: 1 } }); eq(R.revertPrev, prev1, 'commit khi đang bận không ghi đè revertPrev');
// k) sec lạ -> 15
R = mk({ version: 1, global: {}, hub: { autoRevert: true, autoRevertSec: 7 } }); R.commitConfig({ version: 1, global: {} }); run(R); done(R, 0); eq(R.revertTotal, 15, 'sec lạ -> 15');
// l) giao diện: footer + thanh đếm ngược tồn tại và chặn phím trước mọi trang
eq([/if \(revertActive\) return "ENTER KEEP/.test(hub), /id: revBar\s+visible: root\.revertActive/.test(hub), /if \(root\.revertActive\) \{ root\.revertKey\(event\); event\.accepted = true; return \}/.test(hub)], [true, true, true], 'footer, thanh đếm, chặn phím');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, revert)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
