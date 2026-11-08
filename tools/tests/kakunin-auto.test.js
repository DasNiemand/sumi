// Test logic tự động của kakunin/shell.qml: trích protectedList / globToRe / isProtected / onWindow / onMonitors thật, chạy với dữ liệu giả.
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
let f = 0, n = 0;
const eq = (a, b, m) => { n++; if (JSON.stringify(a) !== JSON.stringify(b)) { console.log('FAIL', m, '\n   got ', JSON.stringify(a), '\n   want', JSON.stringify(b)); f++; } };
function fn(name) {
  const i = src.indexOf('    function ' + name + '(');
  if (i < 0) throw new Error('thiếu ' + name);
  let d = 0, k = src.indexOf('{', i), st = k;
  for (; k < src.length; k++) { if (src[k] === '{') d++; else if (src[k] === '}') { d--; if (d === 0) break; } }
  return src.slice(i, k + 1).replace(/^\s*function/, 'function');
}
const dflt = JSON.parse(/readonly property var defaultProtected: (\[.*\])/.exec(src)[1]);
function make(optVal, env) {
  const log = { exit: null, mon: 0, close: 0 };
  const R = {
    defaultProtected: dflt, cfg: { option: (k, d) => optVal === undefined ? d : optVal },
    appName: '', appTitle: '', appWs: '', monId: -1, monName: '', gotWindow: false, showDialog: false, winAddr: '', wantAsk: false, monDone: false, monJson: '',
    monProc: { set running(v) { log.mon++; } }, closeProc: { command: null, set running(v) { log.close++; log.cmd = this.command; } },
  };
  const code = ['protectedList', 'globToRe', 'isProtected', 'onWindow', 'onMonitors', 'resolveMon', 'closeWindow'].map(fn).join('\n');
  const run = new Function('R', 'Qt', 'with(R){' + code + '\nR.f={protectedList,isProtected,onWindow,onMonitors,globToRe,closeWindow}}\nreturn R;');
  return [run(R, { exit: c => { log.exit = c; } }), log];
}
const win = (cls, extra) => JSON.stringify(Object.assign({ address: '0xabc123', class: cls, title: 'T', workspace: { name: '3' }, monitor: 1 }, extra || {}));

let [R] = make(undefined);
eq(R.f.protectedList(), ['zen*', 'Minecraft*'], 'chưa đặt -> mặc định');
eq(R.f.isProtected('zen-browser', R.f.protectedList()), true, 'zen khớp');
eq(R.f.isProtected('Minecraft* 1.20', R.f.protectedList()), true, 'Minecraft khớp');
eq(R.f.isProtected('firefox', R.f.protectedList()), false, 'firefox không khớp');
eq(R.f.isProtected('xzen', R.f.protectedList()), false, 'glob neo đầu');
[R] = make([]);
eq(R.f.protectedList(), [], '[] = không bảo vệ');
eq(R.f.isProtected('zen', []), false, '[] không khớp gì');
[R] = make(['org.kde.*', 'a;rm -rf x', '$(id)', 5, 'fire?ox']);
eq(R.f.protectedList(), ['org.kde.*', 'fire?ox'], 'mục sai định dạng bị bỏ');
eq(R.f.isProtected('org.kde.dolphin', R.f.protectedList()), true, '. là ký tự thật + *');
eq(R.f.isProtected('orgXkdeXdolphin', R.f.protectedList()), false, '. không phải wildcard');
eq(R.f.isProtected('firefox', R.f.protectedList()), true, '? khớp 1 ký tự');
[R] = make('zen*');
eq(R.f.protectedList(), ['zen*', 'Minecraft*'], 'không phải mảng -> mặc định');

// luồng quyết định
let L;
const MONS = JSON.stringify([{ id: 0, name: 'DP-1' }, { id: 1, name: 'HDMI-A-1' }]);
[R, L] = make(undefined); R.f.onWindow(win('zen-browser'));
eq([L.close, L.exit, R.appName, R.appTitle, R.appWs, R.monId, R.winAddr, R.showDialog], [0, null, 'zen-browser', 'T', '3', 1, '0xabc123', false], 'cửa sổ bảo vệ, chưa có danh sách màn -> chờ');
R.f.onMonitors(MONS);
eq([R.monName, R.showDialog], ['HDMI-A-1', true], 'màn về sau: chọn đúng màn rồi hiện dialog');
[R, L] = make(undefined); R.f.onMonitors(MONS); R.f.onWindow(win('zen-browser'));
eq([R.monName, R.showDialog, L.close], ['HDMI-A-1', true, 0], 'màn về trước: hiện dialog ngay khi biết cửa sổ');
[R, L] = make(undefined); R.f.onMonitors(MONS); R.f.onWindow(win('firefox'));
eq([R.showDialog, L.close], [false, 1], 'cửa sổ thường: không hiện dialog dù màn đã về');
[R, L] = make(undefined); R.f.onWindow(win('firefox'));
eq([L.close, L.exit, R.showDialog], [1, null, false], 'cửa sổ thường -> đóng luôn, không hiện dialog');
[R, L] = make(undefined); R.f.onWindow('{}');
eq([L.close, L.exit], [0, 1], 'không có cửa sổ -> thoát mã 1');
[R, L] = make(undefined); R.f.onWindow('không phải json');
eq([L.close, L.exit], [0, 1], 'JSON hỏng -> thoát mã 1, không đóng gì');
[R, L] = make([]); R.f.onWindow(win('zen-browser'));
eq([R.wantAsk, L.close], [false, 1], '[] -> zen cũng đóng luôn');
[R, L] = make(undefined); R.f.onWindow(win('zen', { monitor: undefined }));
eq(R.monId, -1, 'thiếu monitor -> -1');
[R, L] = make(undefined); R.f.onMonitors('hỏng'); R.f.onWindow(win('zen'));
eq(R.showDialog, true, 'hyprctl monitors hỏng vẫn hiện dialog');

// Đóng theo địa chỉ, không theo focus
[R, L] = make(undefined); R.f.onWindow(win('zen')); R.f.closeWindow();
const cmd = L.cmd[2];
eq([L.close, /hl\.dsp\.window\.close\(\{ window = "address:0xabc123" \}\)/.test(cmd)], [1, true], 'Yes: đóng đúng địa chỉ bằng Lua dispatcher');
eq(/closewindow/.test(cmd), false, 'không dùng cú pháp cũ (hyprctl chỉ nhận Lua)');
eq(/killactive|activewindow/.test(cmd), false, 'không dựa vào cửa sổ đang focus');
[R, L] = make(undefined); R.f.onWindow(win('zen', { address: '0x1;rm -rf' })); R.f.closeWindow();
eq([R.winAddr, L.close, L.exit], ['', 0, 1], 'địa chỉ lạ: không chèn vào lệnh, không đóng gì');
[R, L] = make(undefined); R.f.onWindow(win('firefox'));
eq(/address:0xabc123/.test(L.cmd[2]), true, 'cửa sổ thường cũng đóng theo địa chỉ');

// cấu trúc QML
eq(/model: root\.showDialog \? Quickshell\.screens : \[\]/.test(src), true, 'Variants theo showDialog');
eq(/onTriggered: \{\s*if \(root\.auto && root\.exitCode === 0\)/.test(src), true, 'Yes ở chế độ tự động đóng cửa sổ');
eq(/readonly property bool auto: !Quickshell\.env\("CONFIRM_APP"\)/.test(src), true, 'CONFIRM_APP = chế độ tương thích');
eq(/Timer \{ interval: 3000; running: root\.auto/.test(src), true, 'timeout khi hyprctl không trả lời');
console.log(f === 0 ? `TAT CA OK (${n} kiem tra, kakunin-auto)` : `${f}/${n} LOI`);
process.exit(f ? 1 : 0);
