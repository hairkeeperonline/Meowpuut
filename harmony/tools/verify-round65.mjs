/**
 * Round 65 离线验证总入口：顺序跑全部仿真，任一失败即整体失败。
 * 用法： node tools/verify-round65.mjs
 * 退出码： 0 = 全部通过；1 = 有失败
 */
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

const SUITES = [
  { file: 'sim-geometry.mjs',    item: '④②共用', desc: '命中测试几何 + 候选格坐标' },
  { file: 'sim-glass-cache.mjs', item: '①',     desc: '玻璃静态层离屏缓存' },
  { file: 'sim-a11y.mjs',        item: '②',     desc: '逐键无障碍虚拟节点' },
  { file: 'sim-shift.mjs',       item: '③',     desc: '物理 Shift/CapsLock 状态机' },
  { file: 'sim-mouse.mjs',       item: '④',     desc: '鼠标 hover/滚轮/右键路由' },
];

const results = [];
let anyFail = false;

for (const s of SUITES) {
  const path = join(here, s.file);
  process.stdout.write(`\n──────── ${s.item} ${s.desc} ────────\n`);
  const r = spawnSync(process.execPath, [path], { encoding: 'utf8' });
  const text = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  // 只回显结果行与失败行，避免刷屏
  for (const line of text.split(/\r?\n/)) {
    if (/=== 结果|✗/.test(line)) console.log(line);
  }
  const ok = r.status === 0;
  if (!ok) anyFail = true;
  const summary = (text.split(/\r?\n/).find(l => l.includes('=== 结果')) ?? '(无结果行)').trim();
  results.push({ item: s.item, file: s.file, desc: s.desc, ok, status: r.status, summary });
}

console.log('\n════════════ Round 65 离线验证汇总 ════════════');
for (const r of results) {
  console.log(`${r.ok ? '✓' : '✗'} ${r.item.padEnd(8)} ${r.file.padEnd(22)} exit=${r.status}  ${r.summary}`);
}
const passed = results.filter(r => r.ok).length;
console.log(`\n${passed}/${results.length} 套通过 → ${anyFail ? '存在失败' : '全部通过'}`);
console.log('注意：以上为离线逻辑验证，不替代真机验收（像素/性能/a11y 树/事件投递均需上机）。');
process.exit(anyFail ? 1 : 0);
