// Test logic PREVIEW trong hub/shell.qml: trích các property/hàm pv* thật và chạy với dữ liệu giả (không cần Quickshell).
const fs = require('fs');
const [libPath, hubPath] = [process.argv[2], process.argv[3]];
const libSrc = fs.readFileSync(libPath, 'utf8'), hub = fs.readFileSync(hubPath, 'utf8');
const body = libSrc.slice(libSrc.indexOf('QtObject {') + 10, libSrc.lastIndexOf('}'))
  .replace(/^\s*readonly property var (\w+):\s*(.*)$/gm, 'const $1 = $2;').replace(/^\s*function (\w+)\(/gm, 'function $1(');
const names = [...libSrc.matchAll(/^    function (\w+)\(/gm)].map(m => m[1]);
const consts = [...libSrc.matchAll(/^    readonly property (?:var|string|int|real) (\w+):/gm)].map(m => m[1]);
const ce = new Function('Qt', body + `\nreturn {${names.concat(consts).join(',')}};`)({});
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };

// ---- trích khối property / hàm ----
function balancedFrom(src, i) {         // i = vị trí bắt đầu biểu thức; trả về chỉ số kết thúc (không gồm)
  let d = 0, q = null;
  for (let k = i; k < src.length; k++) {
    const c = src[k];
    if (q) { if (c === '\\') k++; else if (c === q) q = null; continue; }
    if (c === '"' || c === "'") { q = c; continue; }
    if (c === '(' || c === '{' || c === '[') d++;
    else if (c === ')' || c === '}' || c === ']') d--;
    else if (c === '\n' && d === 0) return k;
  }
  return src.length;
}
function propExpr(name) {
  const m = new RegExp('readonly property \\w+ ' + name + ':\\s*').exec(hub);
  if (!m) throw new Error('thiếu property ' + name);
  const s = m.index + m[0].length, e = balancedFrom(hub, s);
  const t = hub.slice(s, e).trim();
  return t.startsWith('{') ? `(function(){ ${t.slice(1, -1)} })()` : `(${t})`;
}
function fnSrc(name) {
  const i = hub.indexOf('function ' + name + '('); if (i < 0) throw new Error('thiếu hàm ' + name);
  let j = hub.indexOf('{', i), d = 0, k = j; for (; k < hub.length; k++) { if (hub[k] === '{') d++; else if (hub[k] === '}') { d--; if (!d) break; } }
  return hub.slice(i, k + 1);
}
const PROPS = ['pvApp', 'pvFns', 'pvFnObj', 'pvFn', 'pvMode', 'pvLookS', 'pvInh', 'pvObjectCfg', 'pvProps'];
const FNS = ['pvPick', 'pvFam', 'pvLook', 'pvApply'];

function mk(o) {
  const R = Object.assign({
    ce, page: 'apps', scopeId: 'global', scopeApp: null, apps: [], cur: null, fnSel: 0, curOpt: null, optDraft: {}, optList: [],
    effTheme: 'paper', effTint: 0.12, effInk: 1.5, fontDraft: { title: null, label: null, data: null, numeral: null, kanji: null },
    fontInh: { title: '', label: '', data: '', numeral: '', kanji: '' },
    cfg: { data: { version: 1, global: {}, apps: {} } },
    colors: { adapter: { surface: '#101213', on_surface: '#c3c3c4', outline: '#59636e', primary: '#717878' } },
    Qt: { application: { font: { family: 'SysFont' } } }, pvLoader: { item: null }
  }, o || {});
  R.fontEff = (role) => R.fontDraft[role] !== null ? R.fontDraft[role] : R.fontInh[role];
  for (const p of PROPS) Object.defineProperty(R, p, { get() { return new Function('R', `with (R) { return ${propExpr(p)}; }`)(R); }, configurable: true });
  const src = FNS.map(fnSrc).join('\n');
  Object.assign(R, new Function('R', `with (R) {\n${src}\nreturn {${FNS.join(',')}};\n}`)(R));
  return R;
}
const JIGEN = { id: 'jigen', name: 'JIGEN', dir: '/d/jigen', functions: [{ id: 'shutdown', ipc_name: 'shutdown' }, { id: 'reboot', ipc_name: 'reboot' }, { id: 'timer', ipc_name: 'shutdown30' }] };
const KAK = { id: 'kakunin', name: 'KAKUNIN', dir: '/d/kakunin', functions: [{ id: 'confirm', ipc_name: 'confirm' }] };
const OO = ce.objectOptsOf(JIGEN.functions.length ? { functions: JIGEN.functions.map(x => Object.assign({ label: x.id.toUpperCase(), objects: ['globe', 'torus', 'hourglass'], defaultObject: x.id === 'shutdown' ? 'globe' : (x.id === 'reboot' ? 'torus' : 'hourglass') }, x)) } : null);

// ---- chọn app / function / mode ----
let R = mk({ page: 'apps', cur: JIGEN, apps: [JIGEN, KAK], fnSel: 2 });
eq([R.pvApp.id, R.pvFn, R.pvMode], ['jigen', 'timer', 'shutdown30'], 'trang APPS: theo function A/D, mode = ipc_name');
R.fnSel = 99; eq(R.pvFn, 'timer', 'fnSel quá lớn được kẹp');
R = mk({ page: 'apps', cur: KAK, apps: [JIGEN, KAK] }); eq([R.pvApp.id, R.pvMode], ['kakunin', 'confirm'], 'kakunin');
R = mk({ page: 'apps', cur: null, apps: [] }); eq([R.pvApp, R.pvFn, R.pvMode], [null, '', ''], 'không có app');
R = mk({ page: 'store', cur: JIGEN, apps: [JIGEN] }); eq(R.pvApp, null, 'Store không có preview');
R = mk({ page: 'theme', scopeId: 'hub', cur: JIGEN, apps: [JIGEN] }); eq(R.pvApp, null, 'scope HUB không có preview');
R = mk({ page: 'options', scopeId: 'hub', cur: JIGEN, apps: [JIGEN] }); eq(R.pvApp, null, 'OPTIONS > HUB không có preview');
R = mk({ page: 'theme', scopeId: 'global', cur: KAK, apps: [JIGEN, KAK] }); eq(R.pvApp.id, 'kakunin', 'scope GLOBAL: app đang chọn');
R = mk({ page: 'theme', scopeId: 'global', cur: null, apps: [JIGEN, KAK] }); eq(R.pvApp.id, 'jigen', 'scope GLOBAL không có app chọn: app đầu');
R = mk({ page: 'font', scopeId: 'jigen', scopeApp: JIGEN, cur: KAK, apps: [JIGEN, KAK], fnSel: 2 }); eq([R.pvApp.id, R.pvFn], ['jigen', 'shutdown'], 'scope app: app của scope, function đầu (fnSel chỉ áp dụng ở trang APPS)');
R = mk({ page: 'objects', scopeId: 'jigen', scopeApp: JIGEN, cur: JIGEN, apps: [JIGEN], optList: OO, curOpt: OO[4] });
eq([R.pvFn, R.pvMode], ['reboot', 'reboot'], 'tab OBJECTS: function của hàng đang chọn');
R.curOpt = OO[8]; eq([R.pvFn, R.pvMode], ['timer', 'shutdown30'], 'hàng timer.*');

// ---- object cfg: bản nháp ở tab OBJECTS, bản lưu ở nơi khác ----
const saved = { version: 1, global: {}, apps: { jigen: { objects: { shutdown: { id: 'torus' } } } } };
R = mk({ page: 'apps', scopeId: 'jigen', scopeApp: JIGEN, cur: JIGEN, apps: [JIGEN], optList: OO, optDraft: { 'reboot.speed': 3 }, cfg: { data: saved } });
eq(R.pvObjectCfg, { shutdown: { id: 'torus' } }, 'ngoài tab OBJECTS dùng config đã lưu (bỏ qua bản nháp)');
R = mk({ page: 'objects', scopeId: 'jigen', scopeApp: JIGEN, cur: JIGEN, apps: [JIGEN], optList: OO, curOpt: OO[0], optDraft: { 'reboot.speed': 3 }, cfg: { data: saved } });
eq(R.pvObjectCfg, { reboot: { speed: 3 } }, 'tab OBJECTS: dùng bản nháp (nháp thay thế phần đã lưu của function nằm trong danh sách)');
R = mk({ page: 'apps', cur: KAK, apps: [KAK] }); eq(R.pvObjectCfg, {}, 'app không có objects -> {}');

// ---- theme: bản nháp áp dụng đúng phạm vi ----
const cfgT = { version: 1, global: { theme: 'ink' }, apps: { jigen: { theme: 'mono-white' } } };
const base = { cur: JIGEN, apps: [JIGEN, KAK], cfg: { data: cfgT }, effTheme: 'DRAFT', effTint: 0.3, effInk: 2 };
R = mk(Object.assign({}, base, { page: 'theme', scopeId: 'jigen', scopeApp: JIGEN }));
eq(R.pvProps.preset, 'DRAFT', 'sửa chính app: lấy nháp');
R = mk(Object.assign({}, base, { page: 'theme', scopeId: 'global' }));
eq(R.pvProps.preset, 'mono-white', 'sửa GLOBAL nhưng app có theme riêng: giữ theme riêng');
R = mk(Object.assign({}, base, { page: 'theme', scopeId: 'global', cur: KAK }));
eq([R.pvProps.preset, R.pvProps.tint, R.pvProps.inkDarken], ['DRAFT', 0.3, 2], 'sửa GLOBAL, app không ghi đè: lấy nháp global');
R = mk(Object.assign({}, base, { page: 'keys', scopeId: 'jigen', scopeApp: JIGEN }));
eq(R.pvProps.preset, 'mono-white', 'tab khác: theme đã lưu của app');
R = mk(Object.assign({}, base, { page: 'apps', cur: KAK }));
eq(R.pvProps.preset, 'ink', 'trang APPS: kế thừa global');

// ---- font ----
const cfgF = { version: 1, global: { fonts: { title: 'GlobalSans' } }, apps: { jigen: { fonts: { data: 'JigenMono' } } } };
const fb = { cur: JIGEN, apps: [JIGEN], cfg: { data: cfgF }, fontInh: { title: 'GlobalSans', label: '', data: '', numeral: '', kanji: '' } };
R = mk(Object.assign({}, fb, { page: 'font', scopeId: 'jigen', scopeApp: JIGEN, fontDraft: { title: null, label: 'DraftLabel', data: 'JigenMono', numeral: null, kanji: null } }));
eq([R.pvFam('label'), R.pvFam('data')], ['DraftLabel', 'JigenMono'], 'sửa font của app: lấy nháp');
R = mk(Object.assign({}, fb, { page: 'font', scopeId: 'global', fontDraft: { title: 'DraftTitle', label: null, data: 'DraftData', numeral: null, kanji: null }, fontInh: { title: '', label: '', data: '', numeral: '', kanji: '' } }));
eq([R.pvFam('title'), R.pvFam('data')], ['DraftTitle', 'JigenMono'], 'sửa font GLOBAL: app có font riêng thì giữ');
R = mk(Object.assign({}, fb, { page: 'apps' }));
eq([R.pvFam('title'), R.pvFam('data'), R.pvFam('label'), R.pvFam('kanji')], ['GlobalSans', 'JigenMono', 'sans-serif', 'SysFont'], 'ngoài tab FONT: font đã lưu, rơi về mặc định vai trò');

// ---- pvProps: thứ tự, kiểu, mặc định ----
R = mk({ cur: KAK, apps: [KAK] });
const keys = Object.keys(R.pvProps);
eq([keys[0], keys[1], keys[keys.length - 1]], ['bootMs', 'outroMs', 'active'], 'bootMs đầu, active cuối (View đọc bootMs lúc active bật)');
eq([R.pvProps.previewMode, R.pvProps.closing, R.pvProps.scanlinesEnabled, R.pvProps.glitchEnabled, R.pvProps.scaleBoost], [true, false, true, true, 1], 'cờ preview');
eq([R.pvProps.bgColor, R.pvProps.mutedColor], ['#101213', '#59636e'], 'màu lấy từ palette');
R = mk({ cur: KAK, apps: [KAK], cfg: { data: { version: 1, global: { scanlines: false, glitch: false, scanlineOpacity: 0.1 }, apps: {} } } });
eq([R.pvProps.scanlinesEnabled, R.pvProps.glitchEnabled, R.pvProps.scanOpacity], [false, false, 0.1], 'scanlines/glitch theo config');

// ---- pvApply: chỉ gán thuộc tính View có, và chỉ khi khác ----
R = mk({ cur: KAK, apps: [KAK] });
const sets = []; const item = new Proxy({ bgColor: '', active: false, previewMode: false, appName: 'x' }, { set(t, k, v) { sets.push(k); t[k] = v; return true; } });
R.pvLoader = { item }; R.pvApply();
eq(sets.sort(), ['active', 'appName', 'bgColor', 'previewMode'], 'chỉ gán các thuộc tính tồn tại (mode/objectCfg bị bỏ qua)');
sets.length = 0; R.pvApply(); eq(sets, [], 'không gán lại khi không đổi');
R.pvLoader = { item: null }; R.pvApply(); eq(true, true, 'item null không lỗi');

// ---- giao diện: sân khấu 1920x1080 và preview không bắt chuột ----
eq([/id: pvStage\s+width: 1920; height: 1080/.test(hub), /scale: \(card\.pvW - 2\) \/ 1920/.test(hub), /MouseArea \{ anchors\.fill: parent; z: 3 \}/.test(hub)], [true, true, true], 'sân khấu + chặn chuột');
eq(/pvReserve/.test(hub.slice(hub.indexOf('id: scopeList'), hub.indexOf('id: scopeList') + 400)) && /pvReserve/.test(hub.slice(hub.indexOf('id: list\n'), hub.indexOf('id: list\n') + 400)), true, 'danh sách co lại khi bật preview');

console.log(f === 0 ? `TAT CA OK (${n} kiem tra, preview)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
