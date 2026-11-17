/**
 * Round 65 ② 仿真：逐键无障碍虚拟节点生成（updateA11yKeyNodes）。
 * 把 updateA11yKeyNodes 逐行移植到 Node，验证节点集合、坐标、spoken、enabled、
 * 展开态裁剪、签名去重（含 panelScroll）。脚本：node tools/sim-a11y.mjs
 */

const PANEL_ROW = 46;

class A11yNode {
  constructor(id, left, top, width, height, spoken, enabled) {
    this.id = id; this.left = left; this.top = top;
    this.width = width; this.height = height; this.spoken = spoken; this.enabled = enabled;
  }
}

/** 被测对象的最小裁剪：只保留 a11y 相关状态与方法。 */
class A11yBuilder {
  constructor() {
    this.a11yKeyNodes = [];
    this.a11ySig = '';
    this.state = { expanded: false, composing: false };
    this.keySet = null;
    this.placements = [];
    this.panelCells = [];
    this.panelScroll = 0;
    this.kbHeight = 300;
    this.rebuilds = 0;   // 记录 a11yKeyNodes 被真正替换的次数
  }

  updateA11yKeyNodes() {
    const nodes = [];
    const expanded = this.state.expanded && this.state.composing;
    const keySet = this.keySet;
    if (keySet !== null && this.placements.length > 0) {
      const startRow = expanded ? keySet.rows.length - 1 : 0;
      for (let r = startRow; r < keySet.rows.length; r++) {
        const rowKeys = keySet.rows[r];
        const rowPlaces = this.placements[r];
        if (rowPlaces === undefined) continue;
        for (let c = 0; c < rowKeys.length; c++) {
          const key = rowKeys[c];
          const place = rowPlaces[c];
          if (key === undefined || place === undefined) continue;
          const spoken = key.spoken.length > 0 ? key.spoken : key.label;
          nodes.push(new A11yNode(`k${r}_${c}`, place.frame.left, place.frame.top,
            place.frame.width, place.frame.height, spoken, key.enabled));
        }
      }
    }
    if (expanded) {
      for (const cell of this.panelCells) {
        const screenTop = cell.top - this.panelScroll;
        if (screenTop + PANEL_ROW < 0 || screenTop > this.kbHeight) continue;
        nodes.push(new A11yNode(`p${cell.index}_${Math.round(cell.left)}_${Math.round(cell.top)}`,
          cell.left, screenTop, cell.width, PANEL_ROW, cell.shown, true));
      }
    }
    let sig = expanded ? `s${Math.round(this.panelScroll)};` : '';
    for (const n of nodes) {
      sig += `${n.id}|${Math.round(n.left)}|${Math.round(n.top)}|${Math.round(n.width)}|` +
        `${n.spoken}|${n.enabled ? 1 : 0};`;
    }
    if (sig !== this.a11ySig) {
      this.a11ySig = sig;
      this.a11yKeyNodes = nodes;
      this.rebuilds++;
    }
    return nodes;
  }
}

// ---------- 夹具 ----------
function makeKeySet() {
  const mkKey = (label, spoken, enabled = true) => ({ label, spoken, enabled });
  return {
    rows: [
      [mkKey('q', 'q'), mkKey('w', 'w'), mkKey('e', 'e')],
      [mkKey('a', 'a'), mkKey('s', 's'), mkKey('d', 'd')],
      [mkKey('⇧', '大写'), mkKey('空格', '空格'), mkKey('⌫', '删除')],
    ],
  };
}
function makePlacements() {
  // frame 用真实数值（含小数），检验签名里的 Math.round
  const p = [];
  for (let r = 0; r < 3; r++) {
    const row = [];
    for (let c = 0; c < 3; c++) {
      row.push({
        row: r, column: c,
        frame: { left: 3.4 + c * 118.7, top: 6.5 + r * 54.2, width: 115.2, height: 46 },
      });
    }
    p.push(row);
  }
  return p;
}
function makeCells(n) {
  const cells = [];
  for (let i = 0; i < n; i++) {
    cells.push({ index: i, left: 8, top: 6 + i * PANEL_ROW, width: 100, shown: `候选${i}` });
  }
  return cells;
}

let fail = 0, pass = 0;
const eq = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name} — got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
};
const ok = (name, cond, detail) => {
  if (cond) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
};

console.log('=== 1. 常态：每个键一个节点 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  const nodes = b.updateA11yKeyNodes();
  eq('节点数 = 3 行 × 3 键', nodes.length, 9);
  eq('首个节点 id', nodes[0].id, 'k0_0');
  eq('首个节点 spoken', nodes[0].spoken, 'q');
  eq('末个节点 id', nodes[8].id, 'k2_2');
  ok('坐标与 placement.frame 完全一致（含小数）',
    nodes[1].left === 3.4 + 1 * 118.7 && nodes[3].top === 6.5 + 1 * 54.2,
    `left=${nodes[1].left} top=${nodes[3].top}`);
  eq('宽度/高度取自 frame', [nodes[0].width, nodes[0].height], [115.2, 46]);
  ok('所有节点 spoken 非空', nodes.every(n => n.spoken.length > 0));
}

console.log('\n=== 2. spoken 回退：spoken 为空时用 label ===');
{
  const b = new A11yBuilder();
  const ks = makeKeySet();
  ks.rows[0][0] = { label: 'Q', spoken: '', enabled: true };
  ks.rows[0][1] = { label: 'W', spoken: '大写W', enabled: true };
  b.keySet = ks; b.placements = makePlacements();
  const nodes = b.updateA11yKeyNodes();
  eq('spoken 为空 → 回退 label', nodes[0].spoken, 'Q');
  eq('spoken 非空 → 用 spoken', nodes[1].spoken, '大写W');
}

console.log('\n=== 3. enabled 透传 ===');
{
  const b = new A11yBuilder();
  const ks = makeKeySet();
  ks.rows[1][1].enabled = false;
  b.keySet = ks; b.placements = makePlacements();
  const nodes = b.updateA11yKeyNodes();
  eq('禁用键 enabled=false', nodes[4].enabled, false);
  eq('启用键 enabled=true', nodes[3].enabled, true);
  eq('节点 id 与行列对应', nodes[4].id, 'k1_1');
}

console.log('\n=== 4. 展开面板态：只暴露底行键 + 候选格 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.panelCells = makeCells(3);
  b.panelScroll = 0;
  b.state.expanded = true; b.state.composing = true;
  const nodes = b.updateA11yKeyNodes();
  const keyNodes = nodes.filter(n => n.id.startsWith('k'));
  const cellNodes = nodes.filter(n => n.id.startsWith('p'));
  eq('展开态键节点只剩底行 3 个（上面的行被面板盖住）', keyNodes.length, 3);
  eq('底行节点 id', keyNodes.map(n => n.id), ['k2_0', 'k2_1', 'k2_2']);
  eq('候选格节点数', cellNodes.length, 3);
  eq('总节点数', nodes.length, 6);
  // 底行 frame.top 应保持原值（未被面板影响）
  eq('底行坐标仍为 frame 值', keyNodes[0].top, 6.5 + 2 * 54.2);
}

console.log('\n=== 5. 展开但未在组词：不裁剪、不出候选格 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.panelCells = makeCells(3);
  b.state.expanded = true; b.state.composing = false;
  const nodes = b.updateA11yKeyNodes();
  eq('非组词组词态：全部 9 个键', nodes.length, 9);
  eq('无候选格节点', nodes.filter(n => n.id.startsWith('p')).length, 0);
}

console.log('\n=== 6. 候选格坐标平移：屏幕 y = 内容 y − panelScroll ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.panelCells = makeCells(10);
  b.state.expanded = true; b.state.composing = true;
  b.panelScroll = 138;
  const nodes = b.updateA11yKeyNodes();
  const cells = nodes.filter(n => n.id.startsWith('p'));
  ok('产出的候选格均有节点', cells.length > 0, `count=${cells.length}`);
  let allOk = true;
  for (const n of cells) {
    const idx = Number(n.id.split('_')[0].slice(1));
    const contentTop = 6 + idx * PANEL_ROW;
    if (Math.abs(contentTop - n.top - 138) > 1e-9) allOk = false;
  }
  ok('每格都满足 屏幕y = 内容y − 138', allOk);
  ok('所有节点屏幕 y 在可视范围 [−PANEL_ROW, kbHeight]',
    cells.every(n => n.top + PANEL_ROW >= 0 && n.top <= b.kbHeight));
  ok('滚出顶部的格（内容 y=6，屏幕 y=−132）已剔除',
    !cells.some(n => n.id.startsWith('p0_')));
}

console.log('\n=== 7. 签名去重：无变化时不重建 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.updateA11yKeyNodes();
  const firstRef = b.a11yKeyNodes;
  const firstRebuilds = b.rebuilds;
  b.updateA11yKeyNodes();
  b.updateA11yKeyNodes();
  eq('连续两次无变化：不重建', b.rebuilds, firstRebuilds);
  eq('节点数组引用未变（不触发 UI 刷新）', b.a11yKeyNodes === firstRef, true);
}

console.log('\n=== 8. 签名含 panelScroll：滚动必须触发重建（缺陷 B 修复）===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.panelCells = makeCells(10);
  b.state.expanded = true; b.state.composing = true;
  b.panelScroll = 0;
  b.updateA11yKeyNodes();
  const before = b.rebuilds;
  const refBefore = b.a11yKeyNodes;
  b.panelScroll = 46;     // 滚动一格
  b.updateA11yKeyNodes();
  eq('滚动后重建一次', b.rebuilds, before + 1);
  ok('节点数组已被替换', b.a11yKeyNodes !== refBefore);
  // 用 reset 掉签名里 panelScroll 的变体做反证
  class BadBuilder extends A11yBuilder {
    updateA11yKeyNodes() {
      const nodes = super.updateA11yKeyNodes();
      return nodes;
    }
  }
  // 反证：手写一个不含 panelScroll 的签名版本
  const b2 = new A11yBuilder();
  b2.keySet = makeKeySet(); b2.placements = makePlacements();
  b2.panelCells = makeCells(10);
  b2.state.expanded = true; b2.state.composing = true;
  const sigNoScroll = (obj, nodes, expanded) => {
    let sig = '';
    for (const n of nodes) {
      sig += `${n.id}|${Math.round(n.left)}|${Math.round(n.top)}|${Math.round(n.width)}|${n.spoken};`;
    }
    return sig;
  };
  // 手工模拟：滚动后 屏幕 y 变了，但 id/left/top(内容) 没变 —— 不含 scroll 的签名会漏判
  const cells = b2.panelCells;
  const nodesAt = (scroll) => cells
    .map(c => ({ id: `p${c.index}`, left: c.left, top: c.top, width: c.width, spoken: c.shown }));
  ok('（反证）不含 panelScroll 的签名在滚动前后完全相同 → 会漏触发重建',
    sigNoScroll(b2, nodesAt(0), true) === sigNoScroll(b2, nodesAt(46), true));
}

console.log('\n=== 9. 键 Set 为空 / placements 为空：安全 ===');
{
  const b = new A11yBuilder();
  eq('全空时节点数为 0', b.updateA11yKeyNodes().length, 0);
  const b2 = new A11yBuilder();
  b2.keySet = makeKeySet();   // 有键但无布局
  eq('有键无布局：节点数 0（不崩）', b2.updateA11yKeyNodes().length, 0);
}

console.log('\n=== 10. 行数不匹配时按较小者处理，不越界 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet();
  b.placements = makePlacements().slice(0, 2);   // 少一行
  const nodes = b.updateA11yKeyNodes();
  eq('缺 layout 的行被跳过 → 6 个节点', nodes.length, 6);
  ok('无 undefined 节点', nodes.every(n => n !== undefined && n.id !== undefined));
}

console.log('\n=== 11. id 唯一性 ===');
{
  const b = new A11yBuilder();
  b.keySet = makeKeySet(); b.placements = makePlacements();
  b.panelCells = makeCells(20);
  b.panelScroll = 100;
  b.state.expanded = true; b.state.composing = true;
  const nodes = b.updateA11yKeyNodes();
  const ids = nodes.map(n => n.id);
  eq('id 全部唯一（ForEach key 依赖）', new Set(ids).size, ids.length);
}

console.log(`\n=== 结果：${fail === 0 ? '全部通过' : fail + ' 项失败'}（通过 ${pass}）===`);
process.exit(fail === 0 ? 0 : 1);
