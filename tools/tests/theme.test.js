// Trích hàm JS thật từ SumiTheme.qml, giả lập Qt.* (darker/lighter/tint/rgba) theo ngữ nghĩa Qt6.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
function grab(name) {
  const i = src.indexOf('function ' + name + '(');
  let j = src.indexOf('{', i), depth = 0, k = j;
  for (; k < src.length; k++) { if (src[k] === '{') depth++; else if (src[k] === '}') { depth--; if (depth === 0) break; } }
  return src.slice(i, k + 1);
}
const hex = h => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255, a: 1 });
function rgb2hsv(c) { const mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b), d = mx - mn; let h = 0;
  if (d) { if (mx === c.r) h = ((c.g - c.b) / d) % 6; else if (mx === c.g) h = (c.b - c.r) / d + 2; else h = (c.r - c.g) / d + 4; h /= 6; if (h < 0) h += 1; }
  return { h, s: mx ? d / mx : 0, v: mx }; }
function hsv2rgb(h, s, v) { const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  const m = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]; return { r: m[0], g: m[1], b: m[2], a: 1 }; }
const Qt = {
  rgba: (r, g, b, a) => ({ r, g, b, a: a === undefined ? 1 : a }),
  darker: (c, f) => { const x = rgb2hsv(c); return hsv2rgb(x.h, x.s, x.v * 1 / f); },
  lighter: (c, f) => { const x = rgb2hsv(c); let v = x.v * f, s = x.s; if (v > 1) { s = Math.max(0, s - (v - 1)); v = 1; } return hsv2rgb(x.h, s, v); },
  tint: (b, t) => ({ r: t.r * t.a + b.r * (1 - t.a), g: t.g * t.a + b.g * (1 - t.a), b: t.b * t.a + b.b * (1 - t.a), a: 1 }),
};
const fnSrc = ['mix', 'lum', 'lin', 'relLum', 'contrastOf', 'gray', 'derive'].map(grab).join('\n');
function make(bg, fg, acc, tint = 0.12, inkDarken = 1.5) {
  const cBg = hex(bg), cFg = hex(fg), cAcc = hex(acc);
  const ctx = { Qt, Math, tint, inkDarken, cAcc };
  const f = new Function('Qt', 'Math', 'tint', 'inkDarken', 'cAcc', 'cBg', 'cFg', `
    const lum0 = c => 0.2126*c.r+0.7152*c.g+0.0722*c.b;
    const bgIsLighter = lum0(cBg) > lum0(cFg);
    const lightC = bgIsLighter ? cBg : cFg, darkC = bgIsLighter ? cFg : cBg;
    ${fnSrc}
    return derive;`);
  return f(Qt, Math, tint, inkDarken, cAcc, cBg, cFg);
}
const pals = {
  'noctalia-dark-blue': ['#14161a', '#e3e1e6', '#a9b8f0'],
  'noctalia-light': ['#f7f5fa', '#1c1b1f', '#4a5ab8'],
  'grey (nhu mac dinh jigen)': ['#101213', '#c3c3c4', '#717878'],
  'neon-green-dark': ['#0d140d', '#d8f5d0', '#39ff14'],
  'warm-orange-dark': ['#1a1410', '#efe0d0', '#ff9a3c'],
  'low-contrast-dark': ['#2a2b30', '#8a8b92', '#9aa0c0'],
};
const names = ['paper', 'ink', 'mono-white', 'mono-black', 'accent', 'follow'];
let fails = 0;
for (const [pn, [bg, fg, ac]] of Object.entries(pals)) {
  const d = make(bg, fg, ac);
  console.log('\n' + pn);
  for (const n of names) { const r = d(n); const flag = r.contrast < 4.5 ? 'BLOCK' : r.contrast < 7 ? 'warn' : 'ok'; console.log('  ' + n.padEnd(11) + '-> ' + r.name.padEnd(10) + r.contrast.toFixed(2).padStart(6) + ' ' + flag); }
}
// kiểm tra bất biến
const d = make('#14161a', '#e3e1e6', '#a9b8f0');
const paper = d('paper'), unk = d('banana');
if (JSON.stringify(paper) !== JSON.stringify(unk)) { console.log('FAIL: ten la phai = paper'); fails++; }
// paper phải đúng công thức gốc
const lightC = hex('#e3e1e6'), darkC = hex('#14161a'), acc = hex('#a9b8f0');
const want = Qt.tint(Qt.darker(lightC, 1.16), Qt.rgba(acc.r, acc.g, acc.b, 0.12));
if (Math.abs(want.r - paper.paper.r) > 1e-9) { console.log('FAIL: paper != cong thuc goc'); fails++; }
const wantInk = Qt.darker(darkC, 1.5);
if (Math.abs(wantInk.g - paper.ink.g) > 1e-9) { console.log('FAIL: ink != cong thuc goc'); fails++; }
// follow: palette tối -> ink, sáng -> paper
if (make('#14161a', '#e3e1e6', '#a9b8f0')('follow').name !== 'paper') { /* bgIsLighter=false => ink */ }
console.log('\nfollow(dark)=' + make('#14161a', '#e3e1e6', '#a9b8f0')('follow').name + '  follow(light)=' + make('#f7f5fa', '#1c1b1f', '#4a5ab8')('follow').name);
// quét tint/inkDarken: contrast không NaN
for (const t of [0, 0.3, 0.6]) for (const k of [1, 1.5, 2.5]) for (const n of names) { const c = make('#14161a', '#e3e1e6', '#a9b8f0', t, k)(n).contrast; if (!isFinite(c)) { console.log('FAIL NaN', t, k, n); fails++; } }
console.log(fails ? '\nFAILS: ' + fails : '\nTAT CA OK');
process.exit(fails ? 1 : 0);
