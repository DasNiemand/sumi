const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const grab = n => { const i = src.indexOf('function ' + n + '('); let j = src.indexOf('{', i), d = 0, k = j; for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } } return src.slice(i, k + 1); };
const names = [...src.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
const body = `const themes = ["paper","ink","mono-white","mono-black","accent","follow"]; const defaults = {theme:"paper",tint:0.12,inkDarken:1.5};\n` + names.map(grab).join('\n') + `\nreturn {${names.join(',')}};`;
const ce = new Function(body)();
let f = 0; const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, JSON.stringify(a), '!=', JSON.stringify(b)); f++; } };
// cấu hình rỗng / hỏng
eq(ce.effective({}, 'global'), { theme: 'paper', tint: 0.12, inkDarken: 1.5 }, 'defaults');
eq(ce.effective(null, 'jigen'), { theme: 'paper', tint: 0.12, inkDarken: 1.5 }, 'null data');
// kế thừa
const base = { version: 1, global: { theme: 'ink', tint: 0.3 }, apps: { jigen: { theme: 'accent' } }, hub: { theme: 'mono-black' } };
eq(ce.effective(base, 'jigen'), { theme: 'accent', tint: 0.3, inkDarken: 1.5 }, 'jigen eff');
eq(ce.effective(base, 'kakunin'), { theme: 'ink', tint: 0.3, inkDarken: 1.5 }, 'kakunin kế thừa global');
eq(ce.lookOf(base, 'hub'), { theme: 'mono-black', tint: null, inkDarken: null }, 'hub look');
eq(ce.inherited(base, 'jigen'), { theme: 'ink', tint: 0.3, inkDarken: 1.5 }, 'inherited app');
eq(ce.inherited(base, 'global'), { theme: 'paper', tint: 0.12, inkDarken: 1.5 }, 'inherited global');
// giá trị rác bị bỏ qua / kẹp
eq(ce.lookOf({ global: { theme: 'banana', tint: 9, inkDarken: 'x' } }, 'global'), { theme: null, tint: 0.6, inkDarken: null }, 'rác');
// withLook: không sửa đầu vào, round, dọn
const snap = JSON.stringify(base);
const n1 = ce.withLook(base, 'kakunin', { theme: 'ink', tint: 0.1 + 0.2, inkDarken: 1.2000000001 });
eq(JSON.stringify(base), snap, 'bất biến đầu vào');
eq(n1.apps.kakunin, { theme: 'ink', tint: 0.3, inkDarken: 1.2 }, 'round');
const n2 = ce.withLook(n1, 'kakunin', { theme: null, tint: null, inkDarken: null });
eq(n2.apps.kakunin, undefined, 'kế thừa xóa app rỗng');
const n3 = ce.withLook({}, 'global', { theme: 'follow', tint: null, inkDarken: null });
eq(n3, { version: 1, global: { theme: 'follow' } }, 'từ rỗng');
const n4 = ce.withLook(base, 'hub', { theme: null, tint: 0.5, inkDarken: 2 });
eq(n4.hub, undefined, 'hub xóa -> bỏ key hub; tint/ink bị bỏ qua ở hub');
eq(ce.withLook(base, 'jigen', { theme: 'accent', tint: 5, inkDarken: 0 }).apps.jigen, { theme: 'accent', tint: 0.6, inkDarken: 1 }, 'kẹp');
// giữ nguyên phần không đụng tới
eq(ce.withLook({ version: 1, global: {}, apps: { jigen: { options: { 'timer.presets': [10, 20] }, keybinds: { 'nav.left': 'H' } } } }, 'jigen', { theme: 'ink', tint: null, inkDarken: null }).apps.jigen,
   { options: { 'timer.presets': [10, 20] }, keybinds: { 'nav.left': 'H' }, theme: 'ink' }, 'giữ options/keybinds');
// validate
eq(ce.validateLook({ theme: 'x', tint: null, inkDarken: null }, 'global').length, 1, 'theme sai');
eq(ce.validateLook({ theme: 'ink', tint: 0.7, inkDarken: 3 }, 'jigen').length, 2, 'range');
eq(ce.validateLook({ theme: 'ink', tint: null, inkDarken: null }, '../etc').length, 1, 'tên app xấu');
eq(ce.validateLook({ theme: 'ink', tint: 0.3, inkDarken: 1.5 }, 'global'), [], 'hợp lệ');
// sameLook
eq(ce.sameLook({ theme: null, tint: null, inkDarken: null }, { theme: null, tint: null, inkDarken: null }), true, 'same');
console.log(f ? 'FAILS ' + f : 'TAT CA OK');
process.exit(f ? 1 : 0);
