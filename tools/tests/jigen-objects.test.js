// Test object theo function của jigen: objectFor() trong View.qml, danh sách khớp manifest, wrapper đủ file.
const fs = require('fs'), path = require('path');
const dir = process.argv[2];                       // thư mục repo sumi-jigen
const view = fs.readFileSync(path.join(dir, 'View.qml'), 'utf8');
const man = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
const grab = (nm) => { const i = view.indexOf('function ' + nm + '('); if (i < 0) throw new Error('thiếu ' + nm); let j = view.indexOf('{', i), d = 0, k = j; for (; k < view.length; k++) { if (view[k] === '{') d++; else if (view[k] === '}') { d--; if (!d) break; } } return view.slice(i, k + 1); };
const lit = (nm) => { const m = view.match(new RegExp('readonly property var ' + nm + ': \\(\\{([\\s\\S]*?)\\}\\)')); if (!m) throw new Error('thiếu ' + nm); return new Function('return ({' + m[1] + '})')(); };
const allowed = lit('objectAllowed'), defaults = lit('objectDefaults');
const mk = (cfg) => new Function('objectCfg', 'objectAllowed', 'objectDefaults', grab('objectDefault') + '\n' + grab('objectFor') + '\nreturn {objectDefault, objectFor};')(cfg, allowed, defaults);

// khớp manifest
for (const fn of man.functions) {
  eq(allowed[fn.id], fn.objects, 'View.objectAllowed khớp manifest: ' + fn.id);
  eq(defaults[fn.id], fn.defaultObject, 'View.objectDefaults khớp manifest: ' + fn.id);
  eq(fn.objects.includes(fn.defaultObject), true, 'defaultObject nằm trong objects: ' + fn.id);
  for (const o of fn.objects) eq(fs.existsSync(path.join(dir, 'objects', o + '.qml')), true, 'có objects/' + o + '.qml');
}
// wrapper khai báo đủ thuộc tính Object API
for (const o of ['globe', 'torus', 'hourglass']) {
  const src = fs.readFileSync(path.join(dir, 'objects', o + '.qml'), 'utf8');
  for (const p of ['palette', 'running', 'size', 'speed', 'interactive', 'grid']) eq(new RegExp('property \\w+ ' + p + ':').test(src), true, o + ' có ' + p);
}
// Layout đều dùng ObjectSlot, không còn gọi thẳng object cũ
for (const [lay, fn] of [['LayoutShutdown', 'shutdown'], ['LayoutReboot', 'reboot'], ['LayoutTimer', 'timer']]) {
  const src = fs.readFileSync(path.join(dir, lay + '.qml'), 'utf8');
  eq([/ObjectSlot \{/.test(src), src.includes('fn: "' + fn + '"'), /\b(GlobeObject|PointObject) \{/.test(src)], [true, true, false], lay + ' dùng ObjectSlot');
}
// objectFor
let V = mk({});
eq(V.objectFor('shutdown'), { id: 'globe', speed: 1, grid: 0, interactive: true }, 'mặc định shutdown');
eq(V.objectFor('reboot').id, 'torus', 'mặc định reboot'); eq(V.objectFor('timer').id, 'hourglass', 'mặc định timer');
eq(V.objectFor('khong-co').id, 'globe', 'function lạ -> globe');
V = mk({ shutdown: { id: 'hourglass', speed: 2.5, grid: 50, interactive: false }, reboot: { id: 'nope', speed: 99, grid: 10 }, timer: { id: 5, speed: 'x', grid: 'y', interactive: 'z' } });
eq(V.objectFor('shutdown'), { id: 'hourglass', speed: 2.5, grid: 50, interactive: false }, 'giá trị hợp lệ giữ nguyên');
eq(V.objectFor('reboot'), { id: 'torus', speed: 5, grid: 0, interactive: true }, 'id lạ -> mặc định, speed kẹp, grid sai -> 0');
eq(V.objectFor('timer'), { id: 'hourglass', speed: 1, grid: 0, interactive: true }, 'sai kiểu -> mặc định hết');
eq([mk(null).objectFor('shutdown').id, mk('x').objectFor('shutdown').id, mk([]).objectFor('timer').id, mk({ shutdown: null }).objectFor('shutdown').id], ['globe', 'globe', 'hourglass', 'globe'], 'objectCfg rác không làm hỏng');
eq(mk({ shutdown: { speed: -3 } }).objectFor('shutdown').speed, 0, 'speed âm -> 0'); eq(mk({ shutdown: { grid: 44.4 } }).objectFor('shutdown').grid, 44, 'grid làm tròn');
eq(mk({ shutdown: { speed: NaN, grid: Infinity } }).objectFor('shutdown'), { id: 'globe', speed: 1, grid: 0, interactive: true }, 'NaN/Infinity bị loại');

console.log(f === 0 ? `TAT CA OK (${n} kiem tra, jigen-objects)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
