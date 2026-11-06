// Test CRT của hub: công thức bật/tắt máy (trích property thật trong hub/shell.qml), finish(), và các ràng buộc trong giao diện.
const fs = require('fs');
const hub = fs.readFileSync(process.argv[2], 'utf8');
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
function balancedFrom(src, i) { let d = 0, q = null; for (let k = i; k < src.length; k++) { const c = src[k]; if (q) { if (c === '\\') k++; else if (c === q) q = null; continue; } if (c === '"' || c === "'") { q = c; continue; } if (c === '(' || c === '{' || c === '[') d++; else if (c === ')' || c === '}' || c === ']') d--; else if (c === '\n' && d === 0) return k; } return src.length; }
function propExpr(name) { const m = new RegExp('readonly property \\w+ ' + name + ':\\s*').exec(hub); if (!m) throw new Error('thiếu ' + name); const s = m.index + m[0].length; return '(' + hub.slice(s, balancedFrom(hub, s)).trim() + ')'; }
function fnSrc(name) { const i = hub.indexOf('function ' + name + '('); if (i < 0) throw new Error('thiếu hàm ' + name); let j = hub.indexOf('{', i), d = 0, k = j; for (; k < hub.length; k++) { if (hub[k] === '{') d++; else if (hub[k] === '}') { d--; if (!d) break; } } return hub.slice(i, k + 1); }
const PROPS = ['crtLineW', 'crtOpenH', 'crtContentP', 'crtVCollapse', 'crtHCollapse', 'crtXs', 'crtYs', 'crtFlicker', 'glitchNow'];
const mk = (o) => {
  const R = Object.assign({ crtBootMs: 600, crtOutroMs: 360, bp: 0, outP: 0, closing: false, glitchOn: false, quit: 0, started: 0, Math }, o || {});
  R.Qt = { quit() { R.quit++; } }; R.outAnim = { start() { R.started++; } };
  for (const p of PROPS) Object.defineProperty(R, p, { get() { return new Function('R', `with (R) { return ${propExpr(p)}; }`)(R); }, configurable: true });
  Object.assign(R, new Function('R', `with (R) {\n${fnSrc('clamp01')}\n${fnSrc('finish')}\nreturn {clamp01, finish};\n}`)(R));
  return R;
};
const at = (R, bp) => { R.bp = bp; return [R.crtXs, R.crtYs, R.crtContentP, R.crtFlicker].map(v => Math.round(v * 1000) / 1000); };
let R = mk();
eq(at(R, 0), [0.002, 0.004, 0, 0], 'bp=0: gần như tắt, flicker 0');
eq(at(R, 0.14), [0.5, 0.004, 0, 0.5], 'bp=0.14: đường kẻ mới dài một nửa (0.14*70=9.8 -> 9, lẻ nên nhấp nháy 0.5)');
R.bp = 0.1; eq(R.crtFlicker, 0.5, 'giai đoạn nhấp nháy (chẵn/lẻ theo bp*70)'); R.bp = 0.12; eq(R.crtFlicker, 1, 'nhấp nháy: nhịp chẵn');
eq(at(R, 0.28).slice(0, 2), [1, 0.004], 'bp=0.28: đường kẻ đầy, chưa mở dọc');
eq(at(R, 0.49).slice(0, 2), [1, 0.5], 'bp=0.49: mở nửa chiều dọc');
eq(at(R, 0.70).slice(0, 2), [1, 1], 'bp=0.7: mở hết');
eq(at(R, 1), [1, 1, 1, 1], 'bp=1: hiện đủ, không nhấp nháy');
R.bp = 0.55; eq(R.crtContentP, 0, 'nội dung bắt đầu hiện từ bp=0.55'); R.bp = 0.775; eq(Math.round(R.crtContentP * 100) / 100, 0.5, 'nội dung hiện một nửa');
// crtBootMs = 0 -> tắt hiệu ứng bật máy
R = mk({ crtBootMs: 0, bp: 0 }); eq([R.crtXs, R.crtYs, R.crtFlicker, R.crtContentP], [1, 1, 1, 1], 'CRT BOOT = 0: hiện ngay');
// tắt máy
R = mk({ bp: 1, closing: true });
const out = (p) => { R.outP = p; return [R.crtXs, R.crtYs].map(v => Math.round(v * 1000) / 1000); };
eq(out(0), [1, 1], 'outP=0: nguyên'); eq(out(0.34), [1, 1], 'outP=0.34: chưa co'); eq(out(0.54), [1, 0.5], 'outP=0.54: co dọc một nửa');
eq(out(0.74), [1, 0.004], 'outP=0.74: co dọc xong'); eq(out(0.87), [0.5, 0.004], 'outP=0.87: co ngang một nửa'); eq(out(1), [0.002, 0.004], 'outP=1: tắt hẳn');
// glitch
R = mk({ bp: 1 }); eq(R.glitchNow, false, 'không glitch bình thường'); R.glitchOn = true; eq(R.glitchNow, true, 'glitchOn'); R.glitchOn = false; R.closing = true; R.outP = 0.2; eq(R.glitchNow, true, 'glitch lúc bắt đầu tắt máy'); R.outP = 0.5; eq(R.glitchNow, false, 'hết glitch khi co dọc');
// finish()
R = mk({ crtOutroMs: 0 }); R.finish(); eq([R.quit, R.closing, R.started], [1, false, 0], 'outro = 0: thoát ngay');
R = mk({ crtOutroMs: 360 }); R.finish(); eq([R.quit, R.closing, R.started, R.outP], [0, true, 1, 0], 'có outro: chưa thoát, bắt đầu hoạt cảnh');
R.finish(); eq([R.quit, R.started], [0, 1], 'gọi lần hai không làm gì');
// ràng buộc trong giao diện
const code = hub.split('\n').map(l => l.replace(/\/\/.*$/, '')).join('\n');
eq((code.match(/Qt\.quit\(\)/g) || []).length, 2, 'chỉ finish() và outAnim.onFinished được gọi Qt.quit()');
eq(/NumberAnimation \{ id: outAnim[^\n]*onFinished: Qt\.quit\(\)/.test(hub), true, 'hết hoạt cảnh tắt máy thì thoát');
eq(/function dismiss\(\) \{[\s\S]*?finish\(\)\s*\}/.test(hub) && /id: quitTimer[^\n]*root\.finish\(\)/.test(hub), true, 'dismiss và quitTimer đều qua finish()');
eq(/WlrLayershell\.keyboardFocus: root\.closing \? WlrKeyboardFocus\.None : WlrKeyboardFocus\.Exclusive/.test(hub), true, 'đang tắt máy thì nhả focus bàn phím cho app vừa chạy');
eq(/if \(root\.closing\) \{ event\.accepted = true; return \}/.test(hub), true, 'đang tắt máy thì nuốt phím');
eq(/opacity: 0\.5 \* root\.bdIn \* \(1 - root\.outP\)/.test(hub), true, 'nền tối mờ dần khi tắt máy');
eq(/transform: Scale \{[^}]*xScale: root\.crtXs; yScale: root\.crtYs/.test(hub), true, 'card dùng Scale transform');
eq(/model: root\.crtScan \?/.test(hub) && /color: th\.ink; opacity: root\.crtScanOpacity; z: 40/.test(hub), true, 'scanline theo look');
eq(/visible: root\.glitchNow; text: "SUMI 墨"/.test(hub), true, 'glitch ở tiêu đề');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, crt)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
