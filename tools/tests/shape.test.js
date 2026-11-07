// Kiểm tra tĩnh lỗi phạm vi (scope) hay gặp trong QML: bên trong ShapePath, các PathLine/PathArc/... KHÔNG thấy property tự khai báo
// trên ShapePath nếu dùng trơn tên (phải viết <id>.<tên>) -> toạ độ thành NaN và hình bị vẽ sai (đường cheo cắt thẻ).
// Dùng: node shape.test.js <thư mục hoặc file .qml> ...
const fs = require('fs'), path = require('path');
let f = 0, n = 0;
const files = [];
const walk = (p) => { if (!fs.existsSync(p)) return; const st = fs.statSync(p); if (st.isDirectory()) { for (const e of fs.readdirSync(p)) if (e !== '.git' && e !== 'lib' && e !== 'node_modules') walk(path.join(p, e)); } else if (p.endsWith('.qml')) files.push(p); };
process.argv.slice(2).forEach(walk);
const block = (src, i) => { let j = src.indexOf('{', i), d = 0, k = j; for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (!d) break; } } return [j, k]; };
for (const file of files) {
  const src = fs.readFileSync(file, 'utf8');
  const re = /\bShapePath\s*\{/g; let m;
  while ((m = re.exec(src)) !== null) {
    const [a, b] = block(src, m.index);
    const body = src.slice(a + 1, b);
    const names = [...body.matchAll(/\bproperty\s+\w+\s+(\w+)\s*:/g)].map(x => x[1]);
    const idm = body.match(/\bid\s*:\s*(\w+)/);
    const line = src.slice(0, m.index).split('\n').length;
    for (const name of names) {
      n++;
      const bad = [];
      for (const l of body.split('\n')) {
        if (!/\bPath\w+\s*\{/.test(l)) continue;
        if (new RegExp('(^|[^.\\w])' + name + '(?![\\w])').test(l.replace(/\bPath\w+\s*\{/, ''))) bad.push(l.trim());
      }
      if (bad.length > 0) { f++; console.log(`FAIL ${file}:${line}: ShapePath${idm ? ' ' + idm[1] : ''} khai báo '${name}' nhưng PathLine dùng trơn tên (phải viết ${idm ? idm[1] : '<id>'}.${name}):\n   ${bad.join('\n   ')}`); }
    }
  }
}
console.log(f === 0 ? `TAT CA OK (${n} property trong ShapePath, ${files.length} file, shape)` : `${f} LOI`);
process.exit(f ? 1 : 0);
