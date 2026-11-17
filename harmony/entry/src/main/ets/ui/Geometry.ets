/**
 * 键盘布局的纯数学层（对应 Android ime/Geometry.kt，与 iOS KeyboardGeometry.swift 同数值）。
 * 全部以 vp 为单位，不依赖 UI 组件，便于单元测试。
 */

export class Box {
  readonly left: number;
  readonly top: number;
  readonly width: number;
  readonly height: number;

  constructor(left: number, top: number, width: number, height: number) {
    this.left = left;
    this.top = top;
    this.width = width;
    this.height = height;
  }

  get bottom(): number { return this.top + this.height; }
}

export function boxRight(b: Box): number { return b.left + b.width; }
export function boxBottom(b: Box): number { return b.top + b.height; }
export function boxCenterX(b: Box): number { return b.left + b.width / 2; }
export function boxCenterY(b: Box): number { return b.top + b.height / 2; }
export function boxContains(b: Box, x: number, y: number): boolean {
  return x >= b.left && x < boxRight(b) && y >= b.top && y < boxBottom(b);
}
export function boxIntersects(a: Box, b: Box): boolean {
  return a.left < boxRight(b) && b.left < boxRight(a) && a.top < boxBottom(b) && b.top < boxBottom(a);
}
export function boxOffset(b: Box, dx: number, dy: number): Box {
  return new Box(b.left + dx, b.top + dy, b.width, b.height);
}
export function boxZero(): Box { return new Box(0, 0, 0, 0); }

export enum Idiom {
  PHONE, PHONE_LANDSCAPE, TABLET,
}

export function resolveIdiom(screenHeightDp: number, smallestWidthDp: number): Idiom {
  if (smallestWidthDp >= 600) return Idiom.TABLET;
  if (screenHeightDp < 500) return Idiom.PHONE_LANDSCAPE;
  return Idiom.PHONE;
}

class BarFrame {
  static readonly LEFT_ASPECT: number = 0.9135;
  static readonly RIGHT_ASPECT: number = 1.0543;
}

export class CandidateRegionLayout {
  readonly width: number;
  readonly scale: number;
  readonly height: number;
  readonly glass: Box;
  readonly row: Box;
  readonly chevron: Box;
  readonly fontSize: number;
  readonly statusFontSize: number;
  readonly pillHeight: number;
  readonly idiom: Idiom;
  readonly cats: boolean;
  readonly rim: number;

  constructor(rawWidth: number, idiom: Idiom, cats: boolean = true, rim: number = 0) {
    this.idiom = idiom;
    this.cats = cats;
    this.rim = rim;
    this.width = (Number.isFinite(rawWidth) && rawWidth > 1) ? rawWidth : 320;
    let s: number, regionHeight: number, glassHeight: number;
    let leftHeight: number, rightHeight: number, font: number;
    let statusFont: number;
    switch (idiom) {
      case Idiom.PHONE:
        s = Math.min(1.15, Math.max(0.9, this.width / 393));
        regionHeight = 82 * s; glassHeight = 46 * s;
        leftHeight = 62 * s; rightHeight = 54 * s;
        font = Math.min(21, Math.max(19, 20 * s));
        statusFont = Math.round(13 * s);
        break;
      case Idiom.PHONE_LANDSCAPE:
        s = 1;
        regionHeight = 63; glassHeight = 36;
        leftHeight = 46; rightHeight = 40;
        font = 18;
        statusFont = 12;
        break;
      case Idiom.TABLET:
      default:
        s = 1.15;
        regionHeight = 94; glassHeight = 53;
        leftHeight = 71; rightHeight = 62;
        font = 21;
        statusFont = 15;
        break;
    }
    this.scale = s;
    this.fontSize = Math.round(font);
    this.statusFontSize = statusFont;
    this.pillHeight = Math.round(glassHeight * 0.70);
    const rimY = Math.min(0.3, Math.max(0, rim)) * glassHeight;

    if (cats) {
      // 【鸿蒙额外留白】不做玻璃裁剪后猫是整只完整显示，需要额外头顶空间，
      // 否则放大后的猫头会超出候选栏 Canvas 被裁掉。
      // 全部按比例推导（不写绝对像素）：留白取自玻璃高度的一部分，
      // 因此候选栏在不同屏宽/字号/输入框缩放下一并等比变化，不会出现某档尺寸下猫被切头的硬编码失效。
      const catHeadroom = glassHeight * CandidateRegionLayout.CAT_HEADROOM_RATIO;
      this.height = Math.round(regionHeight + catHeadroom);
      // 玻璃只留容纳候选胶囊所需的高度：胶囊高 pillHeight，上下各留一点点余量。
      // 多余部分让给猫，使猫的爪子压得更低、直接搭在下方符号键区上沿，
      // 而不是隔着一整块玻璃和键区离得很远。
      const pill = Math.round(glassHeight * 0.70);
      const slimGlass = Math.max(pill + 4 * s, glassHeight * CandidateRegionLayout.GLASS_SLIM_RATIO);
      // 玻璃直接贴住候选栏底缘（不留间隙）：避免猫脚下露出一条浅色带。
      const glassBottom = this.height;
      const top = glassBottom - slimGlass;
      const leftStart = 2 * s;
      const leftWidth = leftHeight * BarFrame.LEFT_ASPECT;
      const rightStart = this.width - 4 * s - rightHeight * BarFrame.RIGHT_ASPECT;
      const glassLeft = leftStart + 0.24 * leftWidth;
      this.glass = new Box(glassLeft, top, Math.max(1, this.width - 6 * s - glassLeft), slimGlass);
      const chevronWidth = 34 * s;
      const chevronY = boxCenterY(this.glass) + rimY / 2 + 2 * s;
      const chevronHeight = Math.min(Math.min(44, slimGlass), 2 * (this.height - chevronY));
      this.chevron = new Box(rightStart - 6 * s - chevronWidth / 2, chevronY - chevronHeight / 2, chevronWidth, chevronHeight);
      const rowLeft = leftStart + leftWidth + 2 * s;
      this.row = new Box(rowLeft, this.glass.top, Math.max(1, this.chevron.left - rowLeft), slimGlass);
    } else {
      this.height = Math.round(glassHeight + 12 * s);
      this.glass = new Box(4 * s, (this.height - glassHeight) / 2, Math.max(1, this.width - 8 * s), glassHeight);
      const chevronWidth = 40 * s;
      const chevronHeight = Math.min(44, glassHeight);
      const chevronY = Math.min(boxCenterY(this.glass) + rimY / 2, this.height - chevronHeight / 2);
      this.chevron = new Box(boxRight(this.glass) - 6 * s - chevronWidth, chevronY - chevronHeight / 2, chevronWidth, chevronHeight);
      const rowLeft = this.glass.left + glassHeight * 0.3;
      this.row = new Box(rowLeft, this.glass.top, Math.max(1, this.chevron.left - rowLeft), glassHeight);
    }
  }

  get maximumCandidateWidth(): number { return Math.max(60, this.row.width * 0.70); }

  static readonly ARROW_WIDTH = 11;

  /**
   * 候选栏给猫头预留的额外高度，取玻璃高度的比例（不写死像素）。
   * 【0.9.1 对齐】安卓 0.9.1 真机实测：候选栏总高 ≈ regionHeight（无额外留白），
   * 玻璃贴栏底、猫头允许小幅探出玻璃上方（≈24dp），猫本身缩放由 FILL 控制。
   * 旧值 0.52 会把玻璃压扁、把猫顶到高处悬空（真机像素分析证实），随 0.9.1 废弃。
   */
  static readonly CAT_HEADROOM_RATIO = 0;

  /**
   * 玻璃最小高度相对原玻璃高度的比例（鸿蒙专用）。
   * 玻璃只需容纳候选胶囊（pillHeight = glassHeight × 0.70），其余高度让给猫，
   * 使猫爪压得更低、直接搭在下方符号键区上沿。随 glassHeight 等比缩放，不写死像素。
   */
  static readonly GLASS_SLIM_RATIO = 0.92;
}

export class KeyMetrics {
  readonly sideMargin: number;
  readonly keyGap: number;
  readonly keyHeight: number;
  readonly rowGap: number;
  readonly topPadding: number;
  readonly bottomPadding: number;
  readonly cornerRadius: number;
  readonly letterFont: number;
  readonly utilityFont: number;

  constructor(sideMargin: number, keyGap: number, keyHeight: number, rowGap: number,
    topPadding: number, bottomPadding: number, cornerRadius: number, letterFont: number, utilityFont: number) {
    this.sideMargin = sideMargin;
    this.keyGap = keyGap;
    this.keyHeight = keyHeight;
    this.rowGap = rowGap;
    this.topPadding = topPadding;
    this.bottomPadding = bottomPadding;
    this.cornerRadius = cornerRadius;
    this.letterFont = letterFont;
    this.utilityFont = utilityFont;
  }
}

export function keyMetricsAreaHeight(m: KeyMetrics, rows: number): number {
  return m.topPadding + rows * m.keyHeight + Math.max(0, rows - 1) * m.rowGap + m.bottomPadding;
}

export function keyMetricsOf(idiom: Idiom, width: number, rows: number): KeyMetrics {
  const dense = rows >= 5;
  switch (idiom) {
    case Idiom.PHONE: {
      const s = Math.min(1.06, Math.max(0.94, width / 393));
      return new KeyMetrics(
        3, 6,
        Math.round((dense ? 37 : 42) * s),
        dense ? 7.5 : 11,
        dense ? 6 : 8, 4,
        8.5, dense ? 21 : 23, 15,
      );
    }
    case Idiom.PHONE_LANDSCAPE:
      return new KeyMetrics(
        3, 6,
        dense ? 28 : 32,
        dense ? 5 : 6,
        5, 3,
        7, dense ? 19 : 21, 14,
      );
    case Idiom.TABLET:
    default:
      return new KeyMetrics(
        6, 9,
        dense ? 46 : 52,
        dense ? 8 : 10,
        8, 6,
        9, dense ? 23 : 25, 17,
      );
  }
}

export function keyMetricsFitted(idiom: Idiom, width: number, rows: number, baseRows: number): KeyMetrics {
  const own = keyMetricsOf(idiom, width, rows);
  if (rows === baseRows) return own;
  const area = keyMetricsAreaHeight(keyMetricsOf(idiom, width, baseRows), baseRows);
  const gaps = Math.max(0, rows - 1) * own.rowGap;
  const keyHeight = Math.floor(Math.max(1, (area - own.topPadding - own.bottomPadding - gaps) / rows));
  const used = own.topPadding + rows * keyHeight + gaps;
  return new KeyMetrics(
    own.sideMargin, own.keyGap, keyHeight, own.rowGap,
    own.topPadding, Math.max(own.bottomPadding, area - used),
    own.cornerRadius, own.letterFont, own.utilityFont,
  );
}

export enum RowAlignment {
  CENTERED, JUSTIFIED, SPLIT_EDGES,
}

export class RowSpec {
  readonly units: number[];
  readonly alignment: RowAlignment;

  constructor(units: number[], alignment: RowAlignment) {
    this.units = units;
    this.alignment = alignment;
  }
}

export class KeyPlacement {
  readonly row: number;
  readonly column: number;
  readonly frame: Box;
  readonly hitFrame: Box;

  constructor(row: number, column: number, frame: Box, hitFrame: Box) {
    this.row = row;
    this.column = column;
    this.frame = frame;
    this.hitFrame = hitFrame;
  }
}

export function layoutKeyGrid(rows: RowSpec[], width: number, referenceColumns: number, metrics: KeyMetrics,
  maximumWidth: number = 0): KeyPlacement[][] {
  // 【round 64】maximumWidth（对照安卓 KeySet.layoutWidth + KeyboardView.onLayout）：
  // 可用宽度收窄到上限后，整个键区网格水平居中（keyLeft=(width-layoutWidth)/2）。
  const layoutWidth = maximumWidth > 0 ? Math.min(width, maximumWidth) : width;
  const shift = (width - layoutWidth) / 2;
  const usable = Math.max(1, layoutWidth - 2 * metrics.sideMargin);
  const unit = Math.max(1, (usable - (referenceColumns - 1) * metrics.keyGap) / referenceColumns);
  const totalHeight = keyMetricsAreaHeight(metrics, rows.length);
  const span = (units: number) => units * unit + Math.max(0, units - 1) * metrics.keyGap;

  const placements: KeyPlacement[][] = [];
  rows.forEach((spec, r) => {
    const y = metrics.topPadding + r * (metrics.keyHeight + metrics.rowGap);
    const hitTop = r === 0 ? 0 : y - metrics.rowGap / 2;
    const hitBottom = r === rows.length - 1 ? totalHeight : y + metrics.keyHeight + metrics.rowGap / 2;
    const gaps = Math.max(0, spec.units.length - 1) * metrics.keyGap;
    const frames: Box[] = [];
    switch (spec.alignment) {
      case RowAlignment.CENTERED: {
        const widths = spec.units.map(span);
        let x = shift + metrics.sideMargin + Math.max(0, (usable - widths.reduce((a, b) => a + b, 0) - gaps) / 2);
        for (let i = 0; i < widths.length; i++) {
          const w = widths[i];
          frames.push(new Box(x, y, w, metrics.keyHeight));
          x += w + metrics.keyGap;
        }
        break;
      }
      case RowAlignment.JUSTIFIED: {
        const fixed = spec.units.filter(u => u > 0).reduce((a, u) => a + span(u), 0);
        const flexibleCount = spec.units.filter(u => u === 0).length;
        let widths: number[];
        if (flexibleCount > 0) {
          const flexible = Math.max(unit, (usable - gaps - fixed) / flexibleCount);
          widths = spec.units.map(u => u === 0 ? flexible : span(u));
        } else {
          const factor = fixed > 0 ? Math.max(0.5, (usable - gaps) / fixed) : 1;
          widths = spec.units.map(u => span(u) * factor);
        }
        let x = shift + metrics.sideMargin + Math.max(0, (usable - widths.reduce((a, b) => a + b, 0) - gaps) / 2);
        for (let i = 0; i < widths.length; i++) {
          const w = widths[i];
          frames.push(new Box(x, y, w, metrics.keyHeight));
          x += w + metrics.keyGap;
        }
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
        for (let i = 0; i < middle.length; i++) {
          const w = middle[i];
          frames.push(new Box(x, y, w, metrics.keyHeight));
          x += w + metrics.keyGap;
        }
        if (widths.length > 1) frames.push(new Box(shift + metrics.sideMargin + usable - last, y, last, metrics.keyHeight));
        break;
      }
    }
    const rowPlacements: KeyPlacement[] = [];
    frames.forEach((frame, c) => {
      const left = c === 0 ? 0 : (boxRight(frames[c - 1]) + frame.left) / 2;
      const right = c === frames.length - 1 ? width : (boxRight(frame) + frames[c + 1].left) / 2;
      rowPlacements.push(new KeyPlacement(
        r, c, frame,
        new Box(left, hitTop, Math.max(0, right - left), hitBottom - hitTop),
      ));
    });
    placements.push(rowPlacements);
  });
  return placements;
}

/** 键盘上一个按键位置：画出的框，以及更大的命中区。 */
export function keyAt(x: number, y: number, placements: KeyPlacement[][]): number[] | null {
  for (let ri = 0; ri < placements.length; ri++) {
    const row = placements[ri];
    if (row.length === 0) continue;
    const first = row[0];
    if (y < first.hitFrame.top || y >= first.hitFrame.bottom) continue;
    for (let ki = 0; ki < row.length; ki++) {
      const key = row[ki];
      if (x >= key.hitFrame.left && x < boxRight(key.hitFrame)) {
        const result: number[] = [];
        result.push(key.row);
        result.push(key.column);
        return result;
      }
    }
    const end = x < first.hitFrame.left ? first : row[row.length - 1];
    const result: number[] = [];
    result.push(end.row);
    result.push(end.column);
    return result;
  }
  return null;
}

/** 长按候选条（替换字符预览的备选串）。 */
export class AlternatesStrip {
  readonly box: Box;
  readonly cell: number;
  readonly count: number;
  readonly mirrored: boolean;

  constructor(box: Box, cell: number, count: number, mirrored: boolean) {
    this.box = box; this.cell = cell; this.count = count; this.mirrored = mirrored;
  }

  static readonly PADDING = 4;

  /** [x] 下的候选序号。 */
  indexAt(x: number): number {
    const slot = Math.min(this.count - 1, Math.max(0, Math.floor((x - this.box.left - AlternatesStrip.PADDING) / this.cell)));
    return this.mirrored ? this.count - 1 - slot : slot;
  }

  /** 候选 [index] 所在格的左缘。 */
  cellLeft(index: number): number {
    return this.box.left + AlternatesStrip.PADDING + (this.mirrored ? this.count - 1 - index : index) * this.cell;
  }

  offset(dx: number, dy: number): AlternatesStrip {
    return new AlternatesStrip(boxOffset(this.box, dx, dy), this.cell, this.count, this.mirrored);
  }

  static fromKey(key: Box, count: number, keyboardWidth: number): AlternatesStrip {
    const options = Math.max(1, count);
    const cell = Math.max(30, Math.min(key.width, (keyboardWidth - 8) / options));
    const width = cell * options + 2 * AlternatesStrip.PADDING;
    const leftHalf = boxCenterX(key) < keyboardWidth / 2;
    const x = Math.min(Math.max(2, leftHalf ? key.left - 4 : boxRight(key) + 4 - width), keyboardWidth - 2 - width);
    // 【真机反馈 ③】长按弹框方向不再「有时向上有时向下」：一律画在按键上方。
    // 顶行（row 0）按键上方没有 50vp 空间时，strip 落到 y=2、盖住按键本体本身
    // （对照 Gboard：顶行长按弹出物覆盖在键帽上，不会跑到下方打乱布局）。
    // 原 round 60-2 的做法是顶行翻到下方，真机反馈方向不一致观感混乱。
    const STRIP_H = 50;
    const y = Math.max(2, key.top - STRIP_H - 4);
    return new AlternatesStrip(new Box(x, y, width, STRIP_H), cell, options, !leftHalf);
  }
}

/** 手机按下字符键时上方弹出的气泡。 */
export class KeyBalloon {
  static bubble(key: Box, keyboardWidth: number, idiom: Idiom): Box {
    const flare = idiom === Idiom.PHONE_LANDSCAPE ? 8 : 12;
    const height = idiom === Idiom.PHONE_LANDSCAPE ? 40 : 54;
    const width = Math.min(keyboardWidth - 4, key.width + 2 * flare);
    const x = Math.min(Math.max(2, boxCenterX(key) - width / 2), keyboardWidth - 2 - width);
    // 【真机反馈 ③】与 AlternatesStrip 同步统一方向：一律在按键上方，
    // 顶行 clamp 到 y=0 盖住按键本体，不再翻到下方。
    const y = Math.max(0, key.top - height + 2);
    return new Box(x, y, width, height);
  }
}
