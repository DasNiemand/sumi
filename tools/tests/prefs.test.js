// Test logic thuần 2b-2 (font + keybind) của SumiConfigEdit.qml. Trích hằng "readonly property var" một dòng và các hàm.
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
let f = 0; const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); f++; } };
const N = { title: null, label: null, data: null, numeral: null, kanji: null };

// ---- fonts ----
eq(ce.fontsOf({}, 'global'), N, 'fonts rỗng');
eq(ce.fontsOf(null, 'jigen'), N, 'fonts null');
const base = { version: 1, global: { fonts: { data: 'JetBrains Mono', kanji: 'Noto Sans CJK JP' } }, apps: { jigen: { fonts: { title: 'Inter' }, options: { 'timer.presets': [5] } } } };
eq(ce.fontsOf(base, 'global'), { title: null, label: null, data: 'JetBrains Mono', numeral: null, kanji: 'Noto Sans CJK JP' }, 'global fonts');
eq(ce.fontsOf(base, 'hub'), N, 'hub không có font riêng');
eq(ce.fontsInherited(base, 'jigen'), { title: 'sans-serif', label: 'sans-serif', data: 'JetBrains Mono', numeral: 'monospace', kanji: 'Noto Sans CJK JP' }, 'app kế thừa global');
eq(ce.fontsInherited({}, 'global'), { title: 'sans-serif', label: 'sans-serif', data: 'monospace', numeral: 'monospace', kanji: '' }, 'mặc định, kanji = hệ thống');
eq(ce.fontsOf({ global: { fonts: { title: 5, label: '', data: 'a"b', numeral: 'x'.repeat(81) } } }, 'global'), N, 'rác bị bỏ');
eq(ce.fontsOf({ global: { fonts: 'x' } }, 'global'), N, 'fonts sai kiểu');
const snap = JSON.stringify(base);
const w1 = ce.withFonts(base, 'jigen', { title: null, label: 'Inter', data: null, numeral: null, kanji: null });
eq(JSON.stringify(base), snap, 'bất biến');
eq(w1.apps.jigen, { fonts: { label: 'Inter' }, options: { 'timer.presets': [5] } }, 'đặt label, xoá title, giữ options');
eq(ce.withFonts(w1, 'jigen', N).apps.jigen, { options: { 'timer.presets': [5] } }, 'xoá hết fonts, giữ options');
eq(ce.withFonts({ version: 1, global: {}, apps: { kakunin: { fonts: { data: 'X' } } } }, 'kakunin', N), { version: 1, global: {} }, 'dọn app rỗng và apps rỗng');
eq(ce.withFonts({}, 'global', { title: 'Inter', label: null, data: null, numeral: null, kanji: null }), { version: 1, global: { fonts: { title: 'Inter' } } }, 'từ rỗng');
eq(ce.withFonts({ version: 1, global: { fonts: { title: 'A', extra: 'keep' } } }, 'global', N).global, { fonts: { extra: 'keep' } }, 'giữ key lạ trong fonts');
eq(ce.withFonts(base, 'hub', { title: 'Inter' }), base, 'hub bị bỏ qua');
eq(ce.validateFonts(N, 'global'), [], 'hợp lệ');
eq(ce.validateFonts(N, 'hub').length, 1, 'hub bị từ chối');
eq(ce.validateFonts(N, '../x').length, 1, 'tên app xấu');
eq(ce.validateFonts({ title: 'a"b', zzz: 'x' }, 'jigen').length, 2, 'font xấu + vai trò lạ');
eq(ce.sameFonts(N, N), true, 'same'); eq(ce.sameFonts(N, { ...N, data: 'x' }), false, 'khác');
eq(ce.fontRolesOf(null), ce.roles, 'không rõ -> cả 5');
eq(ce.fontRolesOf({ fonts: [] }), ce.roles, 'rỗng -> cả 5');
eq(ce.fontRolesOf({ fonts: ['kanji', 'title', 'bogus'] }), ['title', 'kanji'], 'giữ thứ tự vai trò, bỏ lạ');
eq(ce.fontRolesOf({ fonts: [{ role: 'data' }, { id: 'label' }, 7] }), ['label', 'data'], 'dạng object');
eq(ce.fontRolesOf({ fonts: ['zzz'] }), ce.roles, 'toàn lạ -> cả 5');
// danh sách font
const txt = 'A|DejaVu Sans|\nA|DejaVu Sans Mono|100\nA|noto sans cjk jp|\nA|JetBrains Mono|100\nA|Charcell|110\nJ|noto sans cjk jp\nJ|Ghost\n\nbad line\nA||100\n';
const L = ce.parseFontList(txt);
eq(L.map(x => x.name), ['Charcell', 'DejaVu Sans', 'DejaVu Sans Mono', 'Ghost', 'JetBrains Mono', 'noto sans cjk jp'], 'sắp xếp không phân biệt hoa thường, bỏ dòng hỏng');
eq(L.filter(x => x.mono).map(x => x.name), ['Charcell', 'DejaVu Sans Mono', 'JetBrains Mono'], 'mono 100/110');
eq(L.filter(x => x.ja).map(x => x.name), ['Ghost', 'noto sans cjk jp'], 'ja');
eq(ce.parseFontList('').length, 0, 'rỗng');
eq(ce.filterKind('kanji') + ce.filterKind('data') + ce.filterKind('numeral') + '|' + ce.filterKind('title'), 'jamonomono|', 'filterKind');
eq(ce.filterFonts(L, '', 'ja').map(x => x.name), ['Ghost', 'noto sans cjk jp'], 'lọc ja');
eq(ce.filterFonts(L, 'MONO', 'mono').map(x => x.name), ['DejaVu Sans Mono', 'JetBrains Mono'], 'lọc mono + chuỗi');
eq(ce.filterFonts(L, '  dejavu ', '').length, 2, 'lọc chuỗi, trim');

// ---- keys ----
const kb = [
    { action: 'cancel', default: 'Escape', label: 'Cancel', locked: true },
    { action: 'yes', default: 'Y', label: 'Yes' }, { action: 'no', default: 'N', label: 'No' },
    { action: 'nav.left', default: 'A', label: 'Left' }, { action: 'nav.right', default: 'D', label: 'Right' },
    { action: 'confirm', default: 'Return', label: 'Confirm' }];
eq(ce.keyNames.indexOf('Tab'), -1, 'Tab không bắt được'); eq(ce.keyNames.indexOf('Escape'), -1, 'Esc không bắt được');
eq(new Set(ce.keyNames).size, ce.keyNames.length, 'keyNames không trùng');
eq(ce.keyNameOf(Qt.Key_Y), 'Y', 'keyNameOf Y'); eq(ce.keyNameOf(Qt.Key_Return), 'Return', 'Return'); eq(ce.keyNameOf(Qt.Key_Comma), 'Comma', 'Comma');
eq(ce.keyNameOf(5), '', 'mã lạ');
eq(ce.captureResult(Qt.Key_Escape).ok, false, 'Esc'); eq(ce.captureResult(Qt.Key_Tab).ok, false, 'Tab'); eq(ce.captureResult(Qt.Key_Backtab).ok, false, 'Backtab');
eq(ce.captureResult(Qt.Key_Q), { ok: true, key: 'Q', msg: '' }, 'Q'); eq(ce.captureResult(7).ok, false, 'không hỗ trợ');
eq(ce.keysOf({}, 'kakunin'), {}, 'keys rỗng'); eq(ce.keysOf(null, 'kakunin'), {}, 'keys null');
eq(ce.keysOf({ apps: { kakunin: { keybinds: { yes: 'J', no: 'zzz', x: 3 } } } }, 'kakunin'), { yes: 'J' }, 'bỏ phím rác');
const kd = { version: 1, global: {}, apps: { kakunin: { theme: 'ink', keybinds: { yes: 'J', old: 'K' } } } };
const ks = JSON.stringify(kd);
const k1 = ce.withKeys(kd, 'kakunin', { yes: 'H', no: 'N', cancel: 'Q', confirm: 'Space' }, kb);
eq(JSON.stringify(kd), ks, 'bất biến');
eq(k1.apps.kakunin, { theme: 'ink', keybinds: { yes: 'H', old: 'K', confirm: 'Space' } }, 'đặt yes/confirm; no = mặc định bị bỏ; cancel khoá bị bỏ; giữ action lạ cũ');
eq(ce.withKeys(k1, 'kakunin', {}, kb).apps.kakunin, { theme: 'ink', keybinds: { old: 'K' } }, 'reset hết, giữ action lạ');
eq(ce.withKeys({ version: 1, global: {}, apps: { kakunin: { keybinds: { yes: 'J' } } } }, 'kakunin', {}, kb), { version: 1, global: {} }, 'dọn app/apps rỗng');
eq(ce.withKeys({}, 'jigen', { yes: 'H' }, kb), { version: 1, global: {}, apps: { jigen: { keybinds: { yes: 'H' } } } }, 'từ rỗng');
eq(ce.validateKeys({ yes: 'H' }, kb, 'kakunin'), [], 'hợp lệ');
eq(ce.validateKeys({ cancel: 'Q', zz: 'A', no: 'bad' }, kb, 'kakunin').length, 3, 'khoá + lạ + sai tên');
eq(ce.validateKeys({}, kb, '../x').length, 1, 'tên app xấu');
eq(ce.sameKeys({ a: 'A', b: 'B' }, { b: 'B', a: 'A' }), true, 'same keys'); eq(ce.sameKeys({ a: 'A' }, { a: 'B' }), false, 'khác phím'); eq(ce.sameKeys({ a: 'A' }, {}), false, 'khác số lượng');
eq(ce.keyConflicts(kb, {}, false), {}, 'mặc định không cảnh báo');
eq(ce.keyConflicts(kb, { yes: 'N' }, false), { yes: ['trùng với no'], no: ['trùng với yes'] }, 'trùng yes/no');
eq(ce.keyConflicts(kb, { yes: 'Space' }, false), { yes: ['Space là phím cố định của app'] }, 'phím cố định');
eq(ce.keyConflicts(kb, { nav_ignored: 'X', yes: 'Left' }, false), { yes: ['Left là phím cố định của app'] }, 'Left thuộc nav.left, yes bị cảnh báo');
eq(ce.keyConflicts(kb, { nav_left: 'x', 'nav.left': 'Left' }, false), {}, 'nav.left dùng Left là hợp lệ');
eq(Object.keys(ce.keyConflicts(kb, { yes: '2' }, true)), ['yes'], '1-3 cảnh báo khi nhiều function');
eq(ce.keyConflicts(kb, { yes: '2' }, false), {}, '1-3 không cảnh báo khi một function');
eq(ce.keyConflicts(kb, { cancel: 'Q', yes: 'Escape' }, false), { }, 'phím khoá bị bỏ qua; Escape không phải tên hợp lệ nên rơi về mặc định');
eq(ce.keyConflicts([{ action: 'a', default: 'X' }, { action: 'b', default: 'X' }], {}, false), { a: ['trùng với b'], b: ['trùng với a'] }, 'mặc định trùng vẫn báo');
console.log(f ? 'FAILS ' + f : 'TAT CA OK (2b-2)');
process.exit(f ? 1 : 0);
