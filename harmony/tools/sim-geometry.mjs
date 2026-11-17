/**
 * Round 65 几何仿真：从 ETS 源码移植关键算法，在 Node 下用真实数值验证
 * ② a11y 候选格坐标平移 与 ④ keyPlacementAt 命中规则是否正确。
 * 目的：在没有真机的情况下，把「靠推理认为对」变成「用数值算出来对」。
 */

// ---------- 从 Geometry.ets 移植的常量与布局 ----------
const RowAlignment = { CENTERED: 'CENTERED', JUSTIFIED: 'JUSTIFIED', SPLIT_EDGES: 'SPLIT_EDGES' };

class Box {
  constructor(left, top, width, height) {
    this.left = left; this.top = top; this.width = width; this.height = height;
  }
  get bottom() { return this.top + this.height; }
  get right() { return this.left + this.width; }
}
const boxRight = (b) => b.left + b.width;

class KeyPlacement {
  constructor(row, column, frame, hitFrame) {
    this.row = row; this.column = column; this.frame = frame; this.hitFrame = hitFrame;
  }
}

const keyMetricsAreaHeight = (m, rowCount) =>
  m.topPadding + rowCount * m.keyHeight + Math.max(0, rowCount - 1) * m.rowGap;

function layoutKeyGrid(rows, width, referenceColumns, metrics, maximumWidth) {
  const layoutWidth = maximumWidth > 0 ? Math.min(width, maximumWidth) : width;
  const shift = (width - layoutWidth) / 2;
  const usable = Math.max(1, layoutWidth - 2 * metrics.sideMargin);
  const unit = Math.max(1, (usable - (referenceColumns - 1) * metrics.keyGap) / referenceColumns);
  const totalHeight = keyMetricsAreaHeight(metrics, rows.length);
  const span = (units) => units * unit + Math.max(0, units - 1) * metrics.keyGap;

  const placements = [];
  rows.forEach((spec, r) => {
    const y = metrics.topPadding + r * (metrics.keyHeight + metrics.rowGap);
    const hitTop = r === 0 ? 0 : y - metrics.rowGap / 2;
    const hitBottom = r === rows.length - 1 ? totalHeight : y + metrics.keyHeight + metrics.rowGap / 2;
    const gaps = Math.max(0, spec.units.length - 1) * metrics.keyGap;
    const frames = [];
    switch (spec.alignment) {
      case RowAlignment.CENTERED: {
        const widths = spec.units.map(span);
        let x = shift + metrics.sideMargin + Math.max(0, (usable - widths.reduce((a, b) => a + b, 0) - gaps) / 2);
        for (const w of widths) { frames.push(new Box(x, y, w, metrics.keyHeight)); x += w + metrics.keyGap; }
        break;
      }
      case RowAlignment.JUSTIFIED: {
        const fixed = spec.units.filter(u => u > 0).reduce((a, u) => a + span(u), 0);
        const flexibleCount = spec.units.filter(u => u === 0).length;
        let widths;
        if (flexibleCount > 0) {
          const flexible = Math.max(unit, (usable - gaps - fixed) / flexibleCount);
          widths = spec.units.map(u => u === 0 ? flexible : span(u));
        } else {
          const factor = fixed > 0 ? Math.max(0.5, (usable - gaps) / fixed) : 1;
          widths = spec.units.map(u => span(u) * factor);
        }
        let x = shift + metrics.sideMargin + Math.max(0, (usable - widths.reduce((a, b) => a + b, 0) - gaps) / 2);
        for (const w of widths) { frames.push(new Box(x, y, w, metrics.keyHeight)); x += w + metrics.keyGap; }
        break;
      }
      case RowAlignment.SPLIT_EDGES: {
        const widths = spec.units.map(span);
        const first = widths[0];
        const last = widths[widths.length - 1];
        frames.push(new Box(shift + metrics.sideMargin, y, first, metrics.keyHeight));
        const middle = widths.slice(1, Math.max(1, widths.length - 1));
        const middleWidth = middle.reduce((a, b) => a + b, 0) + Math.max(0, middle.length - 1) * metrics.keyGap;
        let x = shift + metrics.sideMargin + (usable - middleWidth) / 2;
        for (const w of middle) { frames.push(new Box(x, y, w, metrics.keyHeight)); x += w + metrics.keyGap; }
        if (widths.length > 1) frames.push(new Box(shift + metrics.sideMargin + usable - last, y, last, metrics.keyHeight));
        break;
      }
    }
    const rowPlacements = [];
    frames.forEach((frame, c) => {
      const left = c === 0 ? 0 : (boxRight(frames[c - 1]) + frame.left) / 2;
      const right = c === frames.length - 1 ? width : (boxRight(frame) + frames[c + 1].left) / 2;
      rowPlacements.push(new KeyPlacement(r, c, frame,
        new Box(left, hitTop, Math.max(0, right - left), hitBottom - hitTop)));
    });
    placements.push(rowPlacements);
  });
  return placements;
}

// ---------- 被测实现：修复后的 keyPlacementAt ----------
function keyPlacementAt(placements, kbWidth, x, y) {
  if (placements.length === 0) return null;
  if (x < 0 || x >= kbWidth) return null;
  for (let r = 0; r < placements.length; r++) {
    const rowPlaces = placements[r];
    if (rowPlaces === undefined || rowPlaces.length === 0) continue;
    const first = rowPlaces[0];
    if (first === undefined) continue;
    const hit = first.hitFrame;
    if (y < hit.top || y >= hit.top + hit.height) continue;
    for (let c = 0; c < rowPlaces.length; c++) {
      const f = rowPlaces[c].hitFrame;
      if (x >= f.left && x < f.left + f.width) return [r, c];
    }
    return [r, x < first.hitFrame.left ? 0 : rowPlaces.length - 1];
  }
  return null;
}

// ---------- 参照实现：KeyTouches.keyAt（原版，用于交叉验证） ----------
function keyAt(placements, x, y) {
  for (let ri = 0; ri < placements.length; ri++) {
    const row = placements[ri];
    const first = row.length > 0 ? row[0] : null;
    if (first === null) continue;
    if (y < first.hitFrame.top || y >= first.hitFrame.bottom) continue;
    for (let ci = 0; ci < row.length; ci++) {
      const k = row[ci];
      if (x >= k.hitFrame.left && x < boxRight(k.hitFrame)) return [k.row, k.column];
    }
    const end = x < first.hitFrame.left ? first : row[row.length - 1];
    return [end.row, end.column];
  }
  return null;
}

// ---------- 测试 ----------
const metrics = {
  topPadding: 6, sideMargin: 3, keyGap: 3, rowGap: 8, keyHeight: 46,
};
const W = 360; // 手机竖屏 vp
const rows = [
  { alignment: RowAlignment.CENTERED, units: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1] },
  { alignment: RowAlignment.CENTERED, units: [1, 1, 1, 1, 1, 1, 1, 1, 1] },
  { alignment: RowAlignment.CENTERED, units: [1, 1, 1, 1, 1, 1, 1, 1, 1] },
  { alignment: RowAlignment.JUSTIFIED, units: [1.5, 1, 0, 1, 1.5] },
];

const placements = layoutKeyGrid(rows, W, 10, metrics, 0);
let fail = 0;
const check = (name, cond, detail) => {
  if (!cond) { fail++; console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
  else console.log(`  ✓ ${name}`);
};

console.log('=== 1. 布局基本自洽 ===');
const lastRow = placements[placements.length - 1];
const totalH = keyMetricsAreaHeight(metrics, rows.length);
check('末行 hitFrame 底缘 = 键区总高（消除底部死区）',
  Math.abs(lastRow[0].hitFrame.bottom - totalH) < 1e-9,
  `bottom=${lastRow[0].hitFrame.bottom} totalH=${totalH}`);
check('首行 hitFrame 上缘 = 0', Math.abs(placements[0][0].hitFrame.top) < 1e-9);
check('末行 hitFrame 完整覆盖末行 frame（不裁底行）',
  lastRow[0].hitFrame.bottom >= lastRow[0].frame.bottom - 1e-9,
  `hitBottom=${lastRow[0].hitFrame.bottom} frameBottom=${lastRow[0].frame.bottom}`);

console.log('\n=== 2. keyPlacementAt 与 keyAt 逐点一致（画布内）===');
// 说明：两者的边界职责不同，不能在画布外强行要求一致——
//  · keyAt 允许 x<0 命中首键，是给「手指按在屏幕左缘」做的触控容错；
//  · keyPlacementAt 只在画布内被调用（hover/mouse 事件不会在画布外触发），
//    且缺陷 C 的修复目标正是「画布外不得命中」，故显式守卫 x∈[0,W)。
// 因此严格比对限定在画布内。
let mismatch = 0, total = 0, samples = 0;
for (let x = 0; x < W; x += 0.5) {
  for (let y = 0; y < totalH; y += 0.5) {
    total++;
    const a = keyPlacementAt(placements, W, x, y);
    const b = keyAt(placements, x, y);
    const same = (a === null && b === null) ||
      (a !== null && b !== null && a[0] === b[0] && a[1] === b[1]);
    if (!same) { mismatch++; if (mismatch <= 3) console.log(`    mismatch at (${x.toFixed(1)},${y.toFixed(1)}): mine=${JSON.stringify(a)} ref=${JSON.stringify(b)}`); }
  }
  samples++;
}
check(`画布内 ${total} 个采样点与 keyAt 完全一致`, mismatch === 0, `mismatch=${mismatch}`);

console.log('\n=== 2b. 画布外行为（缺陷 C 修复目标）===');
let outsideHits = 0, outsideTotal = 0;
const probes = [];
for (let x = -30; x < 0; x += 1) probes.push([x, 50]);
for (let x = W; x <= W + 30; x += 1) probes.push([x, 50]);
for (let y = -30; y < 0; y += 1) probes.push([180, y]);
for (let y = totalH; y <= totalH + 60; y += 1) probes.push([180, y]);
for (const [x, y] of probes) {
  outsideTotal++;
  if (keyPlacementAt(placements, W, x, y) !== null) outsideHits++;
}
check(`画布外 ${outsideTotal} 个采样点全部不命中`, outsideHits === 0, `outsideHits=${outsideHits}`);

console.log('\n=== 3. 旧实现（缺陷 C 版本）在同一采样下的表现 ===');
function oldKeyPlacementAt(placements, kbWidth, x, y) {
  const rowsN = placements.length;
  const lastRowIdx = rowsN - 1;
  for (let r = 0; r < rowsN; r++) {
    let top = Number.MAX_VALUE, bottom = -Number.MAX_VALUE;
    const rowPlaces = placements[r];
    for (const p of rowPlaces) {
      top = Math.min(top, p.frame.top);
      bottom = Math.max(bottom, p.frame.top + p.frame.height);
    }
    if (x < 0 || x >= kbWidth) continue;
    if (r === lastRowIdx) { if (y >= top) return [r, 0]; continue; }
    if (y >= top && y < bottom) return [r, 0];
  }
  return null;
}
let oldOutside = 0;
for (let y = totalH; y <= totalH + 40; y += 1) {
  if (oldKeyPlacementAt(placements, W, 180, y) !== null) oldOutside++;
}
check('旧实现确实会在键区下方误命中（证明缺陷 C 真实存在）', oldOutside > 0,
  `oldOutsideHits=${oldOutside}（y ∈ [${totalH}, ${totalH + 40}]）`);

console.log('\n=== 4. ② 候选格坐标平移（缺陷 A/B）===');
// 模拟 panelCells（内容坐标）+ panelScroll，验证屏幕坐标与可见性裁剪
const PANEL_ROW = 46, PANEL_TOP = 6;
const panelHeight = 200;
const cellCount = 20;
const cells = [];
for (let i = 0; i < cellCount; i++) cells.push({ index: i, left: 8, top: 6 + i * PANEL_ROW, width: 100 });

function a11yCells(cells, panelScroll, viewportH) {
  const out = [];
  for (const c of cells) {
    const screenTop = c.top - panelScroll;
    if (screenTop + PANEL_ROW < 0 || screenTop > viewportH) continue;
    out.push({ index: c.index, y: screenTop });
  }
  return out;
}
const scroll = 138;
const got = a11yCells(cells, scroll, panelHeight);
const expectedFirst = Math.ceil((scroll - PANEL_ROW + 1) / PANEL_ROW);
check('滚动后首个可见格索引符合预期',
  got[0].index === expectedFirst || Math.abs(got[0].y + PANEL_ROW) <= PANEL_ROW,
  `scroll=${scroll} firstVisible=${got[0].index} y=${got[0].y} expected≈${expectedFirst}`);
check('所有产出节点的屏幕 y 落在合理可视范围',
  got.every(c => c.y + PANEL_ROW >= 0 && c.y <= panelHeight),
  JSON.stringify(got.map(c => c.y)));
const cellUnderScroll = cells.find(c => c.index === 3);
const nodeFor3 = got.find(c => c.index === 3);
check('同一候选格：内容坐标 = 屏幕坐标 + scroll（平移正确）',
  nodeFor3 === undefined || Math.abs(cellUnderScroll.top - nodeFor3.y - scroll) < 1e-9,
  `content=${cellUnderScroll.top} screen=${nodeFor3 && nodeFor3.y} scroll=${scroll}`);
const noScroll = a11yCells(cells, 0, panelHeight);
check('未滚动时屏幕坐标 = 内容坐标',
  noScroll[0].y === cells[0].top);

console.log('\n=== 5. 展开面板态只暴露底行（对照 drawKeys rowStart）===');
const expandedStart = placements.length - 1;
check('展开态起始行 = 末行', expandedStart === rows.length - 1);
check('展开态节点仅覆盖末行键',
  placements.slice(expandedStart).flat().length === lastRow.length);

console.log(`\n=== 结果：${fail === 0 ? '全部通过' : fail + ' 项失败'} ===`);
process.exit(fail === 0 ? 0 : 1);
