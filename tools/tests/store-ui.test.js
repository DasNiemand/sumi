// Test logic tab STORE: hàm thuần trong lib/SumiStoreLogic.qml + máy trạng thái trong hub/shell.qml (trích hàm thật, giả lập root).
const fs = require('fs');
const libSrc = fs.readFileSync(process.argv[2], 'utf8');
const hubSrc = fs.readFileSync(process.argv[3], 'utf8');
const grab = (src, n) => { const i = src.indexOf('function ' + n + '('); if (i < 0) throw new Error('thiếu hàm ' + n); let j = src.indexOf('{', i), d = 0, k = j; for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } } return src.slice(i, k + 1); };
const names = [...libSrc.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
const sl = new Function(names.map(n => grab(libSrc, n)).join('\n') + `\nreturn {${names.join(',')}};`)();
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };

// ---- parse ----
eq(sl.parse('[{"id":"a"}]').ok, true, 'mảng ok');
eq(sl.parse('{"ok":true,"apps":[]}').data.apps, [], 'obj ok');
eq(sl.parse('{"ok":false,"code":"running","message":"x đang chạy"}'), { ok: false, data: { ok: false, code: 'running', message: 'x đang chạy' }, msg: 'RUNNING: x đang chạy' }, 'lỗi');
eq(sl.parse('{"ok":false,"code":"invalid","message":"m","errors":["a","b"]}').msg, 'INVALID: m — a; b', 'lỗi có errors');
eq(sl.parse('').ok, false, 'rỗng'); eq(sl.parse('not json').ok, false, 'rác'); eq(sl.parse('42').ok, false, 'số'); eq(sl.parse(undefined).ok, false, 'undefined');
// ---- badge/op ----
const A = (state, extra) => Object.assign({ id: 'jigen', state, ref: 'v1.1.0', running: false }, extra || {});
eq([sl.badge(A('available')), sl.badge(A('update')), sl.badge(A('installed')), sl.badge(A('dev'))], ['NEW v1.1.0', 'UPDATE v1.1.0', '● v1.1.0', 'DEV'], 'badge');
eq(['available', 'dev', 'update', 'installed'].map(s => sl.opFor(A(s))), ['install', 'install', 'update', ''], 'opFor');
eq(['available', 'dev', 'update', 'installed'].map(s => sl.canRemove(A(s))), [false, false, true, true], 'canRemove');
eq(sl.runningBlock(A('update', { running: true }), 'update').includes('JIGEN SẼ HUỶ HẸN GIỜ'), true, 'chặn khi chạy + cảnh báo jigen');
eq(sl.runningBlock(A('update', { id: 'kakunin', running: true }), 'update').includes('HUỶ'), false, 'kakunin không có cảnh báo hẹn giờ');
eq(sl.runningBlock(A('dev', { running: true }), 'install') !== '', true, 'bản dev đang chạy không được thay');
eq(sl.runningBlock(A('available'), 'install'), '', 'chưa cài -> cho');
eq(sl.runningBlock(A('installed'), 'remove'), '', 'không chạy -> cho');
eq(sl.runningBlock(null, 'restore'), '', 'null -> cho (CLI vẫn chặn)');
eq([sl.opText({ noop: true }), sl.opText({ mode: 'install', id: 'jigen', version: '1.1.0' }), sl.opText({ mode: 'update', id: 'jigen', version: '1.2.0' }),
    sl.opText({ restored: '2026', id: 'jigen', version: '1.0.0' }), sl.opText({ id: 'jigen', backup: 'x' })],
   ['ĐÃ Ở BẢN MỚI NHẤT', 'ĐÃ CÀI JIGEN v1.1.0', 'ĐÃ CẬP NHẬT JIGEN v1.2.0', 'ĐÃ KHÔI PHỤC JIGEN v1.0.0', 'ĐÃ GỠ JIGEN'], 'opText');
// ---- confirmRows ----
const ins = (o) => Object.assign({ ok: true, id: 'jigen', name: 'JIGEN', kanji: '時限', version: '1.1.0', kind: 'daemon', url: 'https://github.com/o/sumi-jigen', ref: 'v1.1.0',
    sha: 'ab'.repeat(20), lib: { required: '>=1.2 <2.0', installed: '1.3.0', compatible: true }, requires: [{ name: 'noto-fonts-cjk', status: 'ok' }],
    shell_commands: ['systemctl poweroff', 'systemctl reboot'], conflict: 'none', warnings: [] }, o || {});
let r = sl.confirmRows('install', ins(), 'jigen', '', 14);
eq(r[0][1].startsWith('JIGEN  時限  v1.1.0  (daemon)'), true, 'dòng APP');
eq(sl.confirmRows('install', ins({ name: 'JIGEN 時限' }), 'jigen', '', 14)[0][1], 'JIGEN 時限  v1.1.0  (daemon)', 'kanji đã nằm trong tên thì không lặp');
eq(sl.confirmRows('install', ins({ name: 'Jigen' }), 'jigen', '', 14)[0][1], 'Jigen  時限  v1.1.0  (daemon)', 'tên không có kanji thì thêm kanji');
eq(r.find(x => x[0] === 'SHA')[1], 'ab'.repeat(20), 'SHA đầy đủ');
eq(r.filter(x => x[0] === '' || x[0] === 'LỆNH SHELL').map(x => x[1]), ['systemctl poweroff', 'systemctl reboot'], 'liệt kê lệnh shell');
eq(r.some(x => x[2]), false, 'không có dòng nguy hiểm khi sạch');
r = sl.confirmRows('install', ins({ lib: { required: '>=9.0', installed: '1.3.0', compatible: false } }), 'jigen', '', 14);
eq(r.find(x => x[0] === 'LIB'), ['LIB', '[INCOMPATIBLE] cần >=9.0, có 1.3.0', true], 'INCOMPATIBLE nổi bật');
eq(sl.canConfirm('install', ins({ lib: { compatible: false } })), false, 'không xác nhận khi INCOMPATIBLE');
r = sl.confirmRows('install', ins({ requires: [{ name: 'a', status: 'missing' }, { name: 'b', status: 'unknown' }] }), 'jigen', '', 14);
eq(r.filter(x => x[0] === 'GÓI CẦN' || (x[0] === '' && /^(a|b)/.test(x[1]))).map(x => [x[1].split(' ')[0], x[2]]), [['a', true], ['b', false]], 'gói thiếu = nguy hiểm');
eq(sl.confirmRows('install', ins({ conflict: 'dev' }), 'jigen', '', 14).some(x => x[0] === 'BẢN DEV' && x[2]), true, 'bản dev có cảnh báo');
r = sl.confirmRows('install', ins({ shell_commands: Array.from({ length: 30 }, (_, i) => 'cmd' + i) }), 'jigen', '', 14);
eq([r.length, r[r.length - 1][1].startsWith('… +')], [14, true], 'cắt còn 14 dòng, dòng cuối báo phần dư');
eq(sl.confirmRows('install', ins({ warnings: ['repo có file script'] }), 'jigen', '', 30).some(x => x[0] === 'CẢNH BÁO' && x[2]), true, 'warnings');
eq(sl.confirmRows('install', null, 'jigen', '', 14), [], 'ins null');
eq(sl.confirmRows('remove', null, 'jigen', '', 14).length, 3, 'remove'); eq(sl.confirmRows('restore', null, 'jigen', '2026', 14)[1][1], '2026', 'restore stamp');
// ---- opArgs: SHA lấy từ bản đã inspect ----
eq(sl.opArgs('install', ins(), 'jigen', ''), ['install', 'jigen', '--sha', 'ab'.repeat(20)], 'install');
eq(sl.opArgs('install', ins({ conflict: 'dev' }), 'jigen', ''), ['install', 'jigen', '--sha', 'ab'.repeat(20), '--replace'], 'install --replace khi bản dev');
eq(sl.opArgs('update', ins({ conflict: 'installed' }), 'jigen', ''), ['update', 'jigen', '--sha', 'ab'.repeat(20)], 'update không --replace');
eq(sl.opArgs('remove', null, 'jigen', ''), ['remove', 'jigen'], 'remove'); eq(sl.opArgs('restore', null, 'jigen', '20261104-112401'), ['restore', 'jigen', '20261104-112401'], 'restore');
eq(sl.opArgs('???', null, 'x', ''), [], 'op lạ -> rỗng');


// ---- thông báo bản mới ----
eq([sl.coreNote('{"ok":true,"available":true,"latest":"1.1.0"}'), sl.coreNote('{"ok":true,"available":false,"latest":"1.0.0"}'), sl.coreNote('{"ok":false,"code":"dev_install","message":"x"}'), sl.coreNote(''), sl.coreNote('rác')], ['v1.1.0', '', '', '', ''], 'coreNote');
eq([sl.updatesIn([{ state: 'update' }, { state: 'installed' }, { state: 'update' }, null]), sl.updatesIn(null), sl.updatesIn([])], [2, 0, 0], 'updatesIn');
eq([sl.appsNote('{"ok":true,"apps":[{"state":"update"},{"state":"available"}]}'), sl.appsNote('{"ok":false,"code":"offline","message":"x"}'), sl.appsNote('')], [1, 0, 0], 'appsNote');
eq([sl.noteLine('v1.1.0', 2), sl.noteLine('v1.1.0', 0), sl.noteLine('', 1), sl.noteLine('', 0), sl.noteLine('', 3)], ['UPDATE   SUMI v1.1.0  ·  2 APPS', 'UPDATE   SUMI v1.1.0', 'UPDATE   1 APP', '', 'UPDATE   3 APPS'], 'noteLine');

// ---- máy trạng thái trong hub (hàm thật, giả lập root) ----
const fnNames = ['storeRun', 'storeRefresh', 'storeDone', 'openStore', 'closeStore', 'storeMove', 'storeAction', 'storeRemoveAsk', 'storeBackupsOpen', 'storeRestoreAsk', 'storeConfirm', 'storeKey'];
const mk = () => {
  const R = { page: 'apps', sumiBin: '/bin/sumi', storeApps: [], storeSel: 0, storeView: 'list', storeBusy: false, storeBusyText: '', storeKind: '', storeStale: false, storeLoaded: false,
    storeMsg: '', storeOk: true, insData: null, confirmOp: '', confirmFrom: 'list', pendingId: '', pendingStamp: '', backups: [], bkSel: 0,
    storeProc: { running: false, command: [] }, storeRetry: { force: false, fired: 0, restart() { this.fired++; } },
    sl, Qt: { Key_Escape: 1, Key_Q: 2, Key_W: 3, Key_Up: 4, Key_S: 5, Key_Down: 6, Key_Return: 7, Key_Enter: 8, Key_Space: 9, Key_R: 10, Key_X: 11, Key_B: 12 } };
  Object.defineProperty(R, 'storeCur', { get() { return (R.storeApps.length > 0 && R.storeSel >= 0 && R.storeSel < R.storeApps.length) ? R.storeApps[R.storeSel] : null; } });
  Object.defineProperty(R, 'confirmRows', { get() { return sl.confirmRows(R.confirmOp, R.insData, R.pendingId, R.pendingStamp, 14); } });
  Object.defineProperty(R, 'confirmOk', { get() { return sl.canConfirm(R.confirmOp, R.insData); } });
  const src = fnNames.map(n => grab(hubSrc, n)).join('\n');
  const fns = new Function('R', `with (R) {\n${src}\nreturn {${fnNames.join(',')}};\n}`)(R);
  Object.assign(R, fns);
  // `with` + hàm khai báo: gọi chéo giữa các hàm đi qua R
  return R;
};
const key = (R, k, ar) => { const ev = { key: k, isAutoRepeat: !!ar, accepted: false }; R.storeKey(ev); return ev.accepted; };
const finish = (R, json) => { R.storeProc.running = false; R.storeDone(typeof json === 'string' ? json : JSON.stringify(json)); };
const reg = (apps, stale) => ({ ok: true, stale: !!stale, fetched_at: 1, apps: apps.map(a => Object.assign({ repo: 'github.com/o/sumi-' + a.id, ref: 'v1.1.0', sha: 'c'.repeat(40), installed_version: '', installed_ref: '', installed_sha: '', running: false }, a)) });

let R = mk();
R.openStore();
eq([R.page, R.storeBusy, R.storeProc.command.join(' ')], ['store', true, '/bin/sumi store registry --json'], 'openStore chạy registry');
eq(key(R, R.Qt.Key_Return), true, 'phím bị nuốt khi busy'); eq(R.storeView, 'list', 'busy: phím không làm gì');
finish(R, reg([{ id: 'jigen', state: 'update', installed_version: '1.0.0', ref: 'v1.1.0' }, { id: 'kakunin', state: 'available' }, { id: 'old', state: 'installed', installed_version: '1.0.0' }, { id: 'dv', state: 'dev' }]));
eq([R.storeBusy, R.storeLoaded, R.storeApps.length], [false, true, 4], 'registry nạp xong');
// di chuyển
key(R, R.Qt.Key_S); eq(R.storeSel, 1, 'S xuống'); key(R, R.Qt.Key_W); key(R, R.Qt.Key_W); eq(R.storeSel, 3, 'W vòng lên cuối'); R.storeSel = 0;
// Enter trên 'update' -> inspect
key(R, R.Qt.Key_Return);
eq([R.storeBusy, R.storeKind, R.storeProc.command.join(' '), R.confirmOp], [true, 'inspect', '/bin/sumi store inspect jigen --json', 'update'], 'Enter -> inspect');
finish(R, ins({ conflict: 'installed', sha: 'd'.repeat(40) }));
eq([R.storeView, R.confirmOk, R.insData.sha], ['confirm', true, 'd'.repeat(40)], 'sang màn xác nhận');
// Esc huỷ
key(R, R.Qt.Key_Escape); eq(R.storeView, 'list', 'Esc huỷ xác nhận');
// Enter lại, xác nhận
key(R, R.Qt.Key_Return); finish(R, ins({ conflict: 'installed', sha: 'd'.repeat(40) }));
key(R, R.Qt.Key_Return, true); eq(R.storeBusy, false, 'auto-repeat không xác nhận');
key(R, R.Qt.Key_Return);
eq([R.storeBusy, R.storeKind, R.storeProc.command.join(' ')], [true, 'op', '/bin/sumi store update jigen --sha ' + 'd'.repeat(40) + ' --json'], 'xác nhận -> update với SHA đã inspect');
finish(R, { ok: true, mode: 'update', id: 'jigen', version: '1.1.0' });
eq([R.storeView, R.storeOk, R.storeMsg, R.storeRetry.fired], ['list', true, 'ĐÃ CẬP NHẬT JIGEN v1.1.0', 1], 'op ok -> báo + hẹn làm mới');
R.storeRetry.force = false; R.storeRefresh(false); eq(R.storeKind, 'registry', 'làm mới sau op');
finish(R, reg([{ id: 'jigen', state: 'installed', installed_version: '1.1.0' }, { id: 'kakunin', state: 'available' }, { id: 'old', state: 'installed' }, { id: 'dv', state: 'dev' }]));
eq(R.storeCur.id, 'jigen', 'giữ nguyên app đang chọn sau làm mới');
// installed: Enter không làm gì, báo mới nhất
key(R, R.Qt.Key_Return); eq([R.storeBusy, R.storeMsg], [false, 'ĐÃ Ở BẢN MỚI NHẤT'], 'installed: Enter -> thông báo');
// X gỡ
key(R, R.Qt.Key_X); eq([R.storeView, R.confirmOp, R.confirmOk], ['confirm', 'remove', true], 'X -> xác nhận gỡ');
key(R, R.Qt.Key_Return); eq(R.storeProc.command.join(' '), '/bin/sumi store remove jigen --json', 'gỡ');
finish(R, { ok: false, code: 'running', message: 'jigen đang chạy' });
eq([R.storeView, R.storeOk, R.storeMsg], ['list', false, 'RUNNING: jigen đang chạy'], 'CLI từ chối (mã 3) -> hiện lỗi, về list');
// app đang chạy: hub chặn trước
R.storeApps = reg([{ id: 'jigen', state: 'installed', running: true }]).apps; R.storeSel = 0;
key(R, R.Qt.Key_X); eq([R.storeView, R.storeOk, R.storeMsg.includes('ĐANG CHẠY')], ['list', false, true], 'đang chạy -> chặn ngay ở hub');
// dev: không gỡ được; Enter -> install --replace
R.storeApps = reg([{ id: 'dv', state: 'dev' }]).apps; R.storeSel = 0; R.storeMsg = '';
key(R, R.Qt.Key_X); eq([R.storeView, R.storeMsg.includes('DEV')], ['list', true], 'bản dev không gỡ ở hub');
key(R, R.Qt.Key_Return); finish(R, ins({ id: 'dv', conflict: 'dev', sha: 'e'.repeat(40) })); key(R, R.Qt.Key_Return);
eq(R.storeProc.command.join(' '), '/bin/sumi store install dv --sha ' + 'e'.repeat(40) + ' --replace --json', 'dev -> install --replace');
finish(R, { ok: true, mode: 'install', id: 'dv', version: '1.1.0' });
// INCOMPATIBLE: không xác nhận được
R.storeApps = reg([{ id: 'kakunin', state: 'available' }]).apps; R.storeSel = 0;
key(R, R.Qt.Key_Return); finish(R, ins({ id: 'kakunin', lib: { required: '>=9.0', installed: '1.3.0', compatible: false } }));
const before = R.storeProc.command.join(' ');
key(R, R.Qt.Key_Return); eq([R.storeView, R.storeBusy, R.storeProc.command.join(' ')], ['confirm', false, before], 'INCOMPATIBLE: Enter không chạy gì');
key(R, R.Qt.Key_Escape);
// inspect lỗi -> về list có thông báo
key(R, R.Qt.Key_Return); finish(R, { ok: false, code: 'tag_moved', message: 'tag bị dời' });
eq([R.storeView, R.storeOk, R.storeMsg], ['list', false, 'TAG_MOVED: tag bị dời'], 'inspect lỗi');
// phản hồi rỗng (sumi-store crash / thiếu file)
key(R, R.Qt.Key_Return); finish(R, '');
eq([R.storeView, R.storeOk, R.storeMsg.startsWith('KHÔNG CÓ PHẢN HỒI')], ['list', false, true], 'rỗng -> báo lỗi, không kẹt busy');
eq(R.storeBusy, false, 'không kẹt busy');
// backups + restore
R.storeApps = reg([{ id: 'jigen', state: 'installed' }]).apps; R.storeSel = 0; R.storeMsg = '';
key(R, R.Qt.Key_B); eq(R.storeProc.command.join(' '), '/bin/sumi store removed jigen --json', 'B -> removed');
finish(R, [{ id: 'jigen', stamp: '20261104-112401', version: '1.1.0', path: '/p' }, { id: 'jigen', stamp: '20261103-090000', version: '1.0.0', path: '/q' }]);
eq([R.storeView, R.backups.length, R.bkSel], ['backups', 2, 0], 'danh sách sao lưu');
key(R, R.Qt.Key_S); eq(R.bkSel, 1, 'S chọn bản cũ hơn'); key(R, R.Qt.Key_S); eq(R.bkSel, 0, 'vòng');
key(R, R.Qt.Key_S); key(R, R.Qt.Key_Return); eq([R.storeView, R.confirmOp, R.pendingStamp], ['confirm', 'restore', '20261103-090000'], 'Enter -> xác nhận khôi phục');
key(R, R.Qt.Key_Escape); eq(R.storeView, 'backups', 'Esc từ xác nhận khôi phục quay lại danh sách sao lưu');
key(R, R.Qt.Key_Return); key(R, R.Qt.Key_Return); eq(R.storeProc.command.join(' '), '/bin/sumi store restore jigen 20261103-090000 --json', 'restore đúng stamp');
finish(R, { ok: true, id: 'jigen', version: '1.0.0', restored: '20261103-090000', backup: '/b' });
eq([R.storeView, R.storeMsg], ['list', 'ĐÃ KHÔI PHỤC JIGEN v1.0.0'], 'restore xong');
key(R, R.Qt.Key_B); finish(R, []); eq([R.storeView, R.backups.length], ['backups', 0], 'không có sao lưu vẫn vào được màn hình');
key(R, R.Qt.Key_Return); eq(R.storeView, 'backups', 'Enter khi rỗng không làm gì');
key(R, R.Qt.Key_Escape); eq(R.storeView, 'list', 'Esc về list');
// thoát
key(R, R.Qt.Key_Escape); eq(R.page, 'apps', 'Esc ở list -> về trang apps');
// registry lỗi lần đầu (offline không cache)
R = mk(); R.openStore(); finish(R, { ok: false, code: 'offline', message: 'không tải được registry' });
eq([R.storeLoaded, R.storeOk, R.storeMsg, R.storeCur], [false, false, 'OFFLINE: không tải được registry', null], 'offline lần đầu: không có app, có thông báo');
// refresh khi tiến trình cũ chưa thoát -> hẹn thử lại, không mất
R = mk(); R.page = 'store'; R.storeProc.running = true; R.storeRefresh(true);
eq([R.storeBusy, R.storeRetry.force, R.storeRetry.fired], [false, true, 1], 'tiến trình còn chạy -> hẹn thử lại');
// R làm mới có --refresh
R = mk(); R.page = 'store'; key(R, R.Qt.Key_R); eq(R.storeProc.command.join(' '), '/bin/sumi store registry --refresh --json', 'R -> --refresh');

const hubVis = hubSrc.match(/id: storeList\s+visible: ([^\n]+)/)[1];
eq(/storeView !== "confirm"/.test(hubVis), true, 'danh sách trái ẩn ở màn xác nhận (tránh đè chữ)');
eq(/noteApps = sl\.updatesIn\(r\.data\.apps\)/.test(hubSrc), true, 'tab Store làm mới số app có bản mới');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, store-ui)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
