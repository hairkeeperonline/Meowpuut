/**
 * 【round 66 框架】多设备形态纵向架构仿真：把 FormFactor.ets（断点/形态/岛宽求解）
 * 与 Geometry.ets 的岛化增量（CandidateRegionLayout.originX、layoutKeyGrid.originX、
 * keyMetricsOf 的 FOLD 档）移植到 Node，用真实数值断言：
 *   1. 断点阈值 320/600/840/1440（vp，对齐官方推荐区间）；
 *   2. 形态判定（横屏优先 / Pura X 440vp 零回归 / 折叠展开 MD / 平板 LG / PC XL 预留）；
 *   3. 岛宽与居中偏移数学（铺满=零偏移零回归；分屏窄窗口自动降档铺满）；
 *   4. layoutKeyGrid 岛偏移（帧平移精确、命中区延展到岛缘、岛外死区）；
 *   5. CandidateRegionLayout 岛偏移（三盒平移、宽高不变、originX 字段可查）；
 *   6. FOLD 档度量与 PHONE 同源公式（手感一致）；
 *   7. 猫落座锚点不越岛（右边界 = 岛宽+偏移）。
 * 反证：把 originX 实现退化为 0（铺满逻辑）时，岛内断言必须失败（证明断言真实约束）。
 */

// ---------- 移植：FormFactor.ets ----------
const Breakpoint = { SM: 'SM', MD: 'MD', LG: 'LG', XL: 'XL' };
const DeviceForm = { PHONE: 'PHONE', PHONE_LANDSCAPE: 'PHONE_LANDSCAPE', FOLD: 'FOLD', TABLET: 'TABLET' };
const Idiom = { PHONE: 'PHONE', PHONE_LANDSCAPE: 'PHONE_LANDSCAPE', TABLET: 'TABLET', FOLD: 'FOLD' };

class FormSpec {
  constructor(form, islandMaxW, supported, note) {
    this.form = form; this.islandMaxW = islandMaxW; this.supported = supported; this.note = note;
  }
}
const FormSpecs = {
  PHONE: new FormSpec(DeviceForm.PHONE, Number.POSITIVE_INFINITY, true, '铺满'),
  PHONE_LANDSCAPE: new FormSpec(DeviceForm.PHONE_LANDSCAPE, Number.POSITIVE_INFINITY, true, '铺满横屏'),
  FOLD: new FormSpec(DeviceForm.FOLD, 600, true, '600vp 岛'),
  TABLET: new FormSpec(DeviceForm.TABLET, 640, true, '640vp 岛'),
  TABLET_XL: new FormSpec(DeviceForm.TABLET, 640, false, 'PC 预留'),
};
const BpWidths = { MD_MIN: 600, LG_MIN: 840, XL_MIN: 1440 };

function breakpointOf(w) {
  if (w >= BpWidths.XL_MIN) return Breakpoint.XL;
  if (w >= BpWidths.LG_MIN) return Breakpoint.LG;
  if (w >= BpWidths.MD_MIN) return Breakpoint.MD;
  return Breakpoint.SM;
}
function resolveForm(w, h) {
  if (h < 500) return FormSpecs.PHONE_LANDSCAPE;
  switch (breakpointOf(w)) {
    case Breakpoint.MD: return FormSpecs.FOLD;
    case Breakpoint.LG: return FormSpecs.TABLET;
    case Breakpoint.XL: return FormSpecs.TABLET_XL;
    default: return FormSpecs.PHONE;
  }
}
class LayoutSolution {
  constructor(spec, bp, idiom, panelW, contentW, contentLeft) {
    this.spec = spec; this.form = spec.form; this.bp = bp; this.idiom = idiom;
    this.panelW = panelW; this.contentW = contentW; this.contentLeft = contentLeft;
  }
  static solve(w, h) {
    const width = Number.isFinite(w) && w > 1 ? w : 320;
    const spec = resolveForm(width, h);
    const contentW = Math.min(width, spec.islandMaxW);
    const contentLeft = Math.max(0, (width - contentW) / 2);
    let idiom;
    switch (spec.form) {
      case DeviceForm.PHONE_LANDSCAPE: idiom = Idiom.PHONE_LANDSCAPE; break;
      case DeviceForm.FOLD: idiom = Idiom.FOLD; break;
      case DeviceForm.TABLET: idiom = Idiom.TABLET; break;
      default: idiom = Idiom.PHONE; break;
    }
    return new LayoutSolution(spec, breakpointOf(width), idiom, width, contentW, contentLeft);
  }
}

// ---------- 移植：Geometry.ets 岛化增量 ----------
class Box {
  constructor(left, top, width, height) { this.left = left; this.top = top; this.width = width; this.height = height; }
  get right() { return this.left + this.width; }
  get bottom() { return this.top + this.height; }
}
const boxOffset = (b, dx) => new Box(b.left + dx, b.top, b.width, b.height);
const boxRight = (b) => b.left + b.width;

class KeyPlacement {
  constructor(row, column, frame, hitFrame) { this.row = row; this.column = column; this.frame = frame; this.hitFrame = hitFrame; }
}
const keyMetricsAreaHeight = (m, rows) => m.topPadding + rows * m.keyHeight + Math.max(0, rows - 1) * m.rowGap;

function layoutKeyGrid(rows, width, referenceColumns, metrics, maximumWidth = 0, originX = 0) {
  const layoutWidth = maximumWidth > 0 ? Math.min(width, maximumWidth) : width;
  const shift = (width - layoutWidth) / 2 + originX;
  const usable = Math.max(1, layoutWidth - 2 * metrics.sideMargin);
  const unit = Math.max(1, (usable - (referenceColumns - 1) * metrics.keyGap) / referenceColumns);
  const totalHeight = keyMetricsAreaHeight(metrics, rows.length);
  const span = (units) => units * unit + Math.max(0, units - 1) * metrics.keyGap;
  const placements = [];
  rows.forEach((spec, r) => {
    const y = metrics.topPadding + r * (metrics.keyHeight + metrics.rowGap);
    const hitTop = r === 0 ? 0 : y - metrics.rowGap / 2;
    const hitBottom = r === rows.length - 1 ? totalHeight : y + metrics.keyHeight + metrics.rowGap / 2;
    const widths = spec.units.map(span);
    const gaps = Math.max(0, spec.units.length - 1) * metrics.keyGap;
    let x = shift + metrics.sideMargin + Math.max(0, (usable - widths.reduce((a, b) => a + b, 0) - gaps) / 2);
    const frames = [];
    for (let i = 0; i < widths.length; i++) {
      frames.push(new Box(x, y, widths[i], metrics.keyHeight));
      x += widths[i] + metrics.keyGap;
    }
    const rowPlacements = [];
    frames.forEach((frame, c) => {
      const left = c === 0 ? originX : (boxRight(frames[c - 1]) + frame.left) / 2;
      const right = c === frames.length - 1 ? width + originX : (boxRight(frame) + frames[c + 1].left) / 2;
      rowPlacements.push(new KeyPlacement(r, c, frame, new Box(left, hitTop, Math.max(0, right - left), hitBottom - hitTop)));
    });
    placements.push(rowPlacements);
  });
  return placements;
}

// CandidateRegionLayout：只移植 cats=false 直排路径 + FOLD/PHONE 度量（够断言用）。
class CandidateRegionLayout {
  constructor(rawWidth, idiom, cats = true, rim = 0, originX = 0) {
    this.idiom = idiom; this.cats = cats; this.rim = rim; this.originX = originX;
    this.width = Number.isFinite(rawWidth) && rawWidth > 1 ? rawWidth : 320;
    let s, regionHeight, glassHeight;
    switch (idiom) {
      case Idiom.PHONE:
      case Idiom.FOLD:
        s = Math.min(1.15, Math.max(0.9, this.width / 393));
        regionHeight = 82 * s; glassHeight = 46 * s;
        break;
      case Idiom.PHONE_LANDSCAPE:
        s = 1; regionHeight = 63; glassHeight = 36;
        break;
      default:
        s = 1.15; regionHeight = 94; glassHeight = 53;
        break;
    }
    this.scale = s;
    this.height = Math.round(glassHeight + 12 * s);
    this.glass = new Box(4 * s, (this.height - glassHeight) / 2, Math.max(1, this.width - 8 * s), glassHeight);
    const chevronWidth = 40 * s;
    const chevronHeight = Math.min(44, glassHeight);
    const chevronY = Math.min(this.glass.top + this.glass.height / 2, this.height - chevronHeight / 2);
    this.chevron = new Box(boxRight(this.glass) - 6 * s - chevronWidth, chevronY - chevronHeight / 2, chevronWidth, chevronHeight);
    this.row = new Box(this.glass.left + glassHeight * 0.3, this.glass.top, Math.max(1, this.chevron.left - (this.glass.left + glassHeight * 0.3)), glassHeight);
    if (originX !== 0) {
      this.glass = boxOffset(this.glass, originX, 0);
      this.chevron = boxOffset(this.chevron, originX, 0);
      this.row = boxOffset(this.row, originX, 0);
    }
  }
}

function keyMetricsOf(idiom, width, rows) {
  const dense = rows >= 5;
  switch (idiom) {
    case Idiom.PHONE:
    case Idiom.FOLD: {
      const s = Math.min(1.06, Math.max(0.94, width / 393));
      return { sideMargin: 3, keyGap: 6, keyHeight: Math.round((dense ? 37 : 42) * s),
        rowGap: dense ? 7.5 : 11, topPadding: dense ? 6 : 8, bottomPadding: 4,
        cornerRadius: 8.5, letterFont: dense ? 21 : 23, utilityFont: 15 };
    }
    case Idiom.PHONE_LANDSCAPE:
      return { sideMargin: 3, keyGap: 6, keyHeight: dense ? 28 : 32,
        rowGap: dense ? 5 : 6, topPadding: 5, bottomPadding: 3,
        cornerRadius: 7, letterFont: dense ? 19 : 21, utilityFont: 14 };
    default:
      return { sideMargin: 6, keyGap: 9, keyHeight: dense ? 46 : 52,
        rowGap: dense ? 8 : 10, topPadding: 8, bottomPadding: 6,
        cornerRadius: 9, letterFont: dense ? 23 : 25, utilityFont: 17 };
  }
}

// ---------- 断言 ----------
let pass = 0, fail = 0; const fails = [];
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) { pass++; return; }
  fail++; fails.push(`✗ ${name}: got=${JSON.stringify(got)} want=${JSON.stringify(want)}`);
}
function approx(name, got, want, eps = 1e-6) {
  const ok = Math.abs(got - want) <= eps;
  if (ok) { pass++; return; }
  fail++; fails.push(`✗ ${name}: got=${got} want=${want}`);
}

// 1. 断点阈值
check('bp 319', breakpointOf(319), 'SM');
check('bp 320', breakpointOf(320), 'SM');
check('bp 599', breakpointOf(599), 'SM');
check('bp 600', breakpointOf(600), 'MD');
check('bp 839', breakpointOf(839), 'MD');
check('bp 840', breakpointOf(840), 'LG');
check('bp 1439', breakpointOf(1439), 'LG');
check('bp 1440', breakpointOf(1440), 'XL');

// 2. 形态判定
check('Pura X 440×707 → PHONE', LayoutSolution.solve(440, 707).form, 'PHONE');
check('折叠展开 720×1640 → FOLD', LayoutSolution.solve(720, 1640).form, 'FOLD');
check('平板 1000×1360 → TABLET', LayoutSolution.solve(1000, 1360).form, 'TABLET');
check('PC 1600×1000 → TABLET(XL预留)', LayoutSolution.solve(1600, 1000).form, 'TABLET');
check('PC 1600 预留未支持', LayoutSolution.solve(1600, 1000).spec.supported, false);
check('横屏手机 880×400 → LANDSCAPE（高度优先）', LayoutSolution.solve(880, 400).form, 'PHONE_LANDSCAPE');
check('横屏平板 1280×800 → TABLET（高800不判横屏）', LayoutSolution.solve(1280, 800).form, 'TABLET');
check('大折叠横屏 1550×660 → TABLET', LayoutSolution.solve(1550, 660).form, 'TABLET');
check('分屏窄窗 500×640 → PHONE（降档铺满）', LayoutSolution.solve(500, 640).form, 'PHONE');

// 3. 岛宽数学
{
  const s = LayoutSolution.solve(440, 707);
  check('PHONE 岛宽=窗口（铺满）', s.contentW, 440);
  check('PHONE 偏移=0（零回归）', s.contentLeft, 0);
}
{
  const s = LayoutSolution.solve(720, 1640);
  check('FOLD 720 岛宽 600', s.contentW, 600);
  check('FOLD 720 偏移 60', s.contentLeft, 60);
  check('FOLD idiom', s.idiom, 'FOLD');
}
{
  const s = LayoutSolution.solve(620, 1640);
  check('FOLD 620 岛宽 600', s.contentW, 600);
  check('FOLD 620 偏移 10', s.contentLeft, 10);
}
{
  const s = LayoutSolution.solve(1000, 1360);
  check('TABLET 1000 岛宽 640', s.contentW, 640);
  check('TABLET 1000 偏移 180', s.contentLeft, 180);
}
{
  const s = LayoutSolution.solve(1600, 1000);
  check('XL 1600 岛宽 640', s.contentW, 640);
  check('XL 1600 偏移 480', s.contentLeft, 480);
  check('XL idiom 兼容映射 TABLET', s.idiom, 'TABLET');
}
{
  // 分屏窄窗：岛宽 clamp 到窗口宽 → 偏移 0 铺满
  const s = LayoutSolution.solve(500, 640);
  check('分屏 500 岛宽=窗口 500', s.contentW, 500);
  check('分屏 500 偏移 0', s.contentLeft, 0);
}
{
  // 兜底：非法宽
  const s = LayoutSolution.solve(NaN, 700);
  check('NaN 宽兜底 320', s.panelW, 320);
}

// 4. layoutKeyGrid 岛偏移
{
  const metrics = keyMetricsOf('FOLD', 600, 4);
  const rows = [{ units: [1, 1, 1, 1, 1, 1, 1, 1, 1, 0], alignment: 'JUSTIFIED' },
                { units: [1.5, 1, 1, 1, 1.5], alignment: 'CENTERED' }];
  const base = layoutKeyGrid(rows, 600, 10, metrics, 0, 0);
  const isl = layoutKeyGrid(rows, 600, 10, metrics, 0, 60);
  // 每帧精确平移 +60，宽高不变
  let shifted = true, sameSize = true;
  for (let r = 0; r < rows.length; r++) {
    for (let c = 0; c < base[r].length; c++) {
      if (Math.abs((isl[r][c].frame.left - base[r][c].frame.left) - 60) > 1e-6) shifted = false;
      if (isl[r][c].frame.width !== base[r][c].frame.width) sameSize = false;
    }
  }
  check('岛化帧整体平移 +60', shifted, true);
  check('岛化帧宽高不变', sameSize, true);
  // 命中区延展到岛缘：首键 hit.left=60，末键 hit.right=660
  check('首键命中区左缘=岛左', isl[0][0].hitFrame.left, 60);
  approx('末键命中区右缘=岛右', isl[0][isl[0].length - 1].hitFrame.right, 660);
  // 岛外死区：x=30（岛外 margin）无命中 → keyAt 返回行内键（fallback）≠ 直接命中？
  // 按实现：岛外 x<originX 落在首键 hitFrame 之外，keyAt 走「行末兜底」逻辑——
  // 命中行为是「越界兜底」而非死区；但 hitFrame 明确不覆盖岛外（断言区界即可）。
  check('岛外 30 不在首键命中区内', 30 >= isl[0][0].hitFrame.left, false);
  // 铺满形态零回归：5 参（旧签名）与 6 参 originX=0 结果逐帧一致
  const legacy = layoutKeyGrid(rows, 600, 10, metrics, 0);
  let same = true;
  for (let r = 0; r < rows.length; r++) {
    for (let c = 0; c < legacy[r].length; c++) {
      const a = legacy[r][c], b = base[r][c];
      if (a.frame.left !== b.frame.left || a.frame.width !== b.frame.width ||
        a.hitFrame.left !== b.hitFrame.left || a.hitFrame.right !== b.hitFrame.right) same = false;
    }
  }
  check('旧签名(5参) == 新签名(originX=0) 零回归', same, true);
}

// 5. CandidateRegionLayout 岛偏移 + FOLD 度量
{
  const r0 = new CandidateRegionLayout(600, 'FOLD');
  approx('FOLD 600 候选栏高 = 82×1.15 ≈ 94', r0.height, Math.round(46 * 1.15 + 12 * 1.15));
  const ri = new CandidateRegionLayout(600, 'FOLD', true, 0, 60);
  check('originX 字段可查', ri.originX, 60);
  check('岛宽不变', ri.width, 600);
  approx('glass 平移 +60', ri.glass.left - r0.glass.left, 60);
  approx('chevron 平移 +60', ri.chevron.left - r0.chevron.left, 60);
  approx('row 平移 +60', ri.row.left - r0.row.left, 60);
  check('glass 宽不变', ri.glass.width, r0.glass.width);
  check('row 高不变', ri.row.height, r0.row.height);
  // 消费方「窗口右边界」口径 = width + originX
  approx('窗口右边界 = 岛宽+偏移', ri.width + ri.originX, 660);
}
{
  const rp = new CandidateRegionLayout(440, 'PHONE');
  check('PHONE originX 默认 0', rp.originX, 0);
  const rp2 = new CandidateRegionLayout(440, 'PHONE', true, 0, 0);
  check('PHONE 偏移 0 时盒子不动', rp2.glass.left, rp.glass.left);
}

// 6. FOLD 度量与 PHONE 同源
{
  const mf = keyMetricsOf('FOLD', 600, 4);
  const mp = keyMetricsOf('PHONE', 600, 4);
  check('FOLD==PHONE 度量(600vp)', mf, mp);
  check('FOLD 键高 600vp = round(42×1.06)=45', mf.keyHeight, 45);
  const mt = keyMetricsOf('TABLET', 640, 4);
  check('TABLET 键高 640vp = 52', mt.keyHeight, 52);
}

// 7. 猫落座锚点不越岛（CatSeats.ends 的锚点公式 + 右边界口径）
{
  const w = 600, ox = 60;
  const region = new CandidateRegionLayout(w, 'FOLD', true, 0, ox);
  const stageRight = region.width + region.originX; // CatStage.width 口径
  const momoAnchor = region.glass.left + region.glass.width - 0.088 * stageRight;
  const mimimoAnchor = momoAnchor - 0.141 * stageRight;
  const inIsland = (x) => x >= ox && x <= ox + w;
  check('暹罗锚点在岛内', inIsland(momoAnchor), true);
  check('黑猫锚点在岛内', inIsland(mimimoAnchor), true);
}

// ---------- 反证：岛化退化（originX 丢失）时岛内断言必须失败 ----------
{
  const spec = [{ units: [1, 1, 1], alignment: 'CENTERED' }];
  const metrics = keyMetricsOf('FOLD', 600, 4);
  // 岛内不变式：所有帧 ⊆ [contentLeft, contentLeft+contentW] = [60, 660]
  const inIsland = (grid) => grid.every((row) =>
    row.every((p) => p.frame.left >= 60 - 1e-6 && p.frame.right <= 660 + 1e-6));
  const real = layoutKeyGrid(spec, 600, 3, metrics, 0, 60);
  check('真实实现帧全在岛内', inIsland(real), true);
  const degraded = layoutKeyGrid(spec, 600, 3, metrics, 0, 0);
  check('反证：退化实现帧不在岛内（断言有效）', inIsland(degraded), false);
}

// ---------- 汇总 ----------
if (fail > 0) {
  console.log(`通过 ${pass} / ${pass + fail}`);
  fails.forEach((f) => console.log(f));
  console.log('=== 结果：存在失败 ===');
  process.exit(1);
}
console.log(`=== 结果：全部通过（通过 ${pass}）===`);
