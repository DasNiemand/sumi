// Test logic thuần 2b-3 (OPTION theo manifest) của SumiConfigEdit.qml, dùng manifest thật của jigen/kakunin.
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
const man = id => JSON.parse(fs.readFileSync(process.argv[3] + '/sumi-' + id + '/manifest.json', 'utf8'));
const JO = man('jigen').options, KO = man('kakunin').options;
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
const O = k => JO.find(o => o.key === k);

// ---- optOk theo kiểu/khoảng ----
eq([ce.optOk(O('timer.defaultMinutes'), 30), ce.optOk(O('timer.defaultMinutes'), 0), ce.optOk(O('timer.defaultMinutes'), 241), ce.optOk(O('timer.defaultMinutes'), 3.5), ce.optOk(O('timer.defaultMinutes'), '30')], [true, false, false, false, false], 'int');
eq([ce.optOk(O('dither.noise'), 0.5), ce.optOk(O('dither.noise'), 1.01), ce.optOk(O('dither.noise'), NaN), ce.optOk(O('dither.noise'), Infinity)], [true, false, false, false], 'float');
eq([ce.optOk(O('timer.presets'), [5, 15]), ce.optOk(O('timer.presets'), []), ce.optOk(O('timer.presets'), [0]), ce.optOk(O('timer.presets'), [5, 'x']), ce.optOk(O('timer.presets'), Array(17).fill(5))], [true, false, false, false, false], 'intlist');
const B = { key: 'b', type: 'bool', default: false, label: 'B' }, E = { key: 'e', type: 'enum', default: 'a', values: ['a', 'b', 'c'], label: 'E' };
const SL = { key: 'protectedClasses', type: 'stringlist', default: ['zen*', 'Minecraft*'], label: 'P' }, S = { key: 's', type: 'string', default: 'x', label: 'S' };
eq([ce.optOk(B, true), ce.optOk(B, 1), ce.optOk(E, 'b'), ce.optOk(E, 'z')], [true, false, true, false], 'bool/enum');
eq([ce.optOk(SL, []), ce.optOk(SL, ['zen*', 'org.kde.dolphin']), ce.optOk(SL, ['a b']), ce.optOk(SL, ['$(x)']), ce.optOk(SL, ['']), ce.optOk(SL, 'zen*'), ce.optOk(SL, Array(33).fill('a'))], [true, true, false, false, false, false, false], 'stringlist');
eq([ce.optOk(S, 'ok'), ce.optOk(S, 'a\nb'), ce.optOk(S, 'x'.repeat(65))], [true, false, false], 'string');

// ---- optionsOf / withOptions: chỉ lưu phần khác mặc định, giữ nguyên key khác ----
const data0 = { version: 1, global: { theme: 'ink' }, apps: { jigen: { theme: 'paper', keybinds: { x: 'Q' }, options: { 'timer.defaultMinutes': 45, 'legacy.old': 7, 'dither.noise': 0.32 } } } };
eq(ce.optionsOf(data0, 'jigen', JO), { 'timer.defaultMinutes': 45 }, 'optionsOf bỏ key lạ + giá trị bằng mặc định');
eq(ce.optionsOf(data0, 'nope', JO), {}, 'app chưa có');
eq(ce.optionsOf(null, 'jigen', JO), {}, 'data null');
let nx = ce.withOptions(data0, 'jigen', { 'timer.defaultMinutes': 15, 'timer.presets': [10, 20] }, JO);
eq(Object.keys(nx.apps.jigen.options).sort(), ['legacy.old', 'timer.defaultMinutes', 'timer.presets'], 'ghi + giữ key lạ'); eq([nx.apps.jigen.options['legacy.old'], nx.apps.jigen.options['timer.defaultMinutes'], nx.apps.jigen.options['timer.presets']], [7, 15, [10, 20]], 'giá trị đúng');
eq([nx.apps.jigen.theme, nx.apps.jigen.keybinds, nx.global.theme], ['paper', { x: 'Q' }, 'ink'], 'không đụng key khác');
eq(JSON.stringify(data0).includes('"timer.presets"'), false, 'không sửa bản gốc');
nx = ce.withOptions(data0, 'jigen', { 'timer.defaultMinutes': 30 }, JO);   // 30 = mặc định
eq(nx.apps.jigen.options, { 'legacy.old': 7 }, 'bằng mặc định thì xoá');
nx = ce.withOptions({ version: 1, global: {}, apps: { kakunin: { options: { crtBootMs: 100 } } } }, 'kakunin', {}, KO);
eq(nx.apps, undefined, 'hết option và hết key khác thì app (và apps) bị dọn (tidyApp)');
nx = ce.withOptions({ version: 1, global: {}, apps: {} }, 'kakunin', { protectedClasses: ['firefox'] }, KO);
eq(nx.apps.kakunin.options, { protectedClasses: ['firefox'] }, 'protectedClasses lưu được');
nx = ce.withOptions({ version: 1, global: {}, apps: {} }, 'kakunin', { protectedClasses: ['zen*', 'Minecraft*'] }, KO);
eq(nx.apps, undefined, 'protectedClasses = mặc định thì không lưu');
nx = ce.withOptions({ version: 1, global: {}, apps: {} }, 'kakunin', { protectedClasses: [] }, KO);
eq(nx.apps.kakunin.options, { protectedClasses: [] }, 'danh sách rỗng khác mặc định -> lưu (nghĩa là không bảo vệ app nào)');
const LK = [{ key: 'l', type: 'int', default: 5, min: 1, max: 9, label: 'L', locked: true }];
eq(ce.withOptions({ version: 1, global: {}, apps: {} }, 'x1', { l: 7 }, LK).apps, undefined, 'option khoá không ghi');
eq(ce.validateOptions({ l: 7 }, LK, 'jigen'), ['option bị khoá: l'], 'validate: khoá');
eq(ce.validateOptions({ a: 1 }, JO, 'jigen'), ['option lạ: a'], 'validate: lạ');
eq(ce.validateOptions({ 'timer.defaultMinutes': 999 }, JO, 'jigen'), ['giá trị không hợp lệ cho timer.defaultMinutes'], 'validate: ngoài khoảng');
eq(ce.validateOptions({}, JO, 'Bad Name').length, 1, 'validate: tên app');
eq(ce.validateOptions({ 'timer.defaultMinutes': 20, protectedClasses: ['a'] }, JO.concat(KO.filter(o => o.key === 'protectedClasses')), 'jigen'), [], 'validate: hợp lệ');
eq([ce.sameOptions({}, {}), ce.sameOptions({ a: [1, 2] }, { a: [1, 2] }), ce.sameOptions({ a: [1, 2] }, { a: [2, 1] }), ce.sameOptions({ a: 1 }, {})], [true, true, false, false], 'sameOptions');
eq([ce.optEff(O('timer.defaultMinutes'), {}), ce.optEff(O('timer.defaultMinutes'), { 'timer.defaultMinutes': 99 }), ce.optEff(O('timer.defaultMinutes'), { 'timer.defaultMinutes': 9999 }), ce.optEff(LK[0], { l: 7 })], [30, 99, 30, 5], 'optEff');

// ---- format / parse / nudge ----
eq([ce.optFormat(B, true), ce.optFormat(B, false), ce.optFormat(O('dither.noise'), 0.32), ce.optFormat(O('timer.presets'), [5, 15]), ce.optFormat(SL, []), ce.optFormat(SL, ['a', 'b'])], ['ON', 'OFF', '0.32', '5, 15', '(NONE)', 'a, b'], 'format');
eq([ce.optEditText(SL, []), ce.optEditText(O('timer.presets'), [5, 15]), ce.optEditText(O('crtBootMs'), 900)], ['', '5, 15', '900'], 'editText');
eq(ce.optParse(O('crtBootMs'), ' 1200 '), { ok: true, value: 1200, msg: '' }, 'parse int');
eq([ce.optParse(O('crtBootMs'), '99999').msg, ce.optParse(O('crtBootMs'), '12a').msg, ce.optParse(O('crtBootMs'), '').ok], ['NGOÀI KHOẢNG 0..3000', 'CẦN SỐ NGUYÊN', false], 'parse int lỗi');
eq(ce.optParse(O('dither.noise'), '.5').value, 0.5, 'parse float .5'); eq(ce.optParse(O('dither.noise'), '0.3249').value, 0.325, 'làm tròn 3 số');
eq([ce.optParse(O('dither.noise'), '2').ok, ce.optParse(O('dither.noise'), 'abc').ok, ce.optParse(O('dither.noise'), '1.2.3').ok], [false, false, false], 'parse float lỗi');
eq(ce.optParse(O('timer.presets'), '10, 20 45').value, [10, 20, 45], 'parse intlist');
eq([ce.optParse(O('timer.presets'), '').ok, ce.optParse(O('timer.presets'), '5, x').msg, ce.optParse(O('timer.presets'), '5, 500').msg], [false, 'KHÔNG PHẢI SỐ NGUYÊN: x', '500 NGOÀI KHOẢNG 1..240'], 'parse intlist lỗi');
eq(ce.optParse(SL, 'zen*, firefox  firefox').value, ['zen*', 'firefox'], 'parse stringlist + dedupe');
eq(ce.optParse(SL, '').value, [], 'stringlist rỗng hợp lệ');
eq(ce.optParse(SL, 'a;rm').ok, false, 'stringlist ký tự cấm');
eq(ce.optParse(B, 'x').ok, false, 'bool không nhập tay');
eq([ce.optStep(O('timer.defaultMinutes')), ce.optStep(O('crtBootMs')), ce.optStep(O('dither.pixelSize')), ce.optStep(O('acceptHoldMs')), ce.optStep(O('dither.noise'))], [10, 100, 1, 100, 0.02], 'bước');
eq([ce.optNudge(O('timer.defaultMinutes'), 30, 1), ce.optNudge(O('timer.defaultMinutes'), 235, 1), ce.optNudge(O('timer.defaultMinutes'), 3, -1), ce.optNudge(O('dither.pixelSize'), 20, 1)], [40, 240, 1, 21], 'nudge int + kẹp');
eq([ce.optNudge(O('dither.noise'), 0.32, 1), ce.optNudge(O('dither.noise'), 0.99, 1), ce.optNudge(O('dither.noise'), 0.01, -1)], [0.34, 1, 0], 'nudge float');
eq([ce.optNudge(B, false, 1), ce.optNudge(B, true, -1), ce.optNudge(E, 'a', 1), ce.optNudge(E, 'a', -1), ce.optNudge(E, 'c', 1)], [true, false, 'b', 'c', 'a'], 'nudge bool/enum');
eq(ce.optNudge(O('timer.presets'), [5], 1), [5], 'intlist không nudge');
eq([ce.optInputOk(O('crtBootMs'), '7'), ce.optInputOk(O('crtBootMs'), 'a'), ce.optInputOk(O('dither.noise'), '.'), ce.optInputOk(O('timer.presets'), ','), ce.optInputOk(SL, '*'), ce.optInputOk(SL, ';'), ce.optInputOk(S, '$'), ce.optInputOk(S, '\n'), ce.optInputOk(S, 'ab')], [true, false, true, true, true, false, true, false, false], 'ký tự nhập');
eq(ce.isTextOpt(B) || ce.isTextOpt(E), false, 'bool/enum không phải text'); eq(ce.isTextOpt(SL) && ce.isTextOpt(O('crtBootMs')), true, 'text opts');
// ---- cảnh báo chéo ----
eq(ce.optConflicts(JO, {}), {}, 'mặc định không cảnh báo');
eq(ce.optConflicts(JO, { 'timer.presets': [10, 20] }), { 'timer.defaultMinutes': ['30 không nằm trong timer.presets'] }, 'defaultMinutes ngoài presets');
eq(ce.optConflicts(JO, { 'timer.presets': [10, 20], 'timer.defaultMinutes': 20 }), {}, 'sửa cả hai thì hết cảnh báo');
eq(ce.optConflicts(KO, {}), {}, 'kakunin không có timer');

console.log(f === 0 ? `TAT CA OK (${n} kiem tra, options)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
