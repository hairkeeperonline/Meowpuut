/**
 * 猫在候选栏上的落座（对应 Android ime/CatStage.kt，与 iOS CatSprites.swift 同规则）。
 */
import { Box, boxRight, boxIntersects, boxCenterX } from './Geometry';
import { GlassShape, glassTop, endRadius } from './GlassOutline';
import { CatSprite, PawPoint } from './CatSpriteData';

export enum Cat { MIMIMO = 'mimimo', MOMO = 'momo' }

export class CatStage {
  readonly width: number;
  readonly height: number;
  readonly glass: Box;
  readonly shape: GlassShape;
  readonly unit: number;
  readonly room: number;
  readonly row: Box;
  readonly arrow: Box;

  constructor(width: number, height: number, glass: Box, shape: GlassShape, unit: number,
    room: number, row: Box, arrow: Box) {
    this.width = width;
    this.height = height;
    this.glass = glass;
    this.shape = shape;
    this.unit = unit;
    this.room = room;
    this.row = row;
    this.arrow = arrow;
  }
}

export class CatPlacement {
  readonly cat: Cat;
  readonly sprite: CatSprite;
  readonly frame: Box;
  readonly anchorX: number;
  readonly anchorY: number;

  constructor(cat: Cat, sprite: CatSprite, frame: Box, anchorX: number, anchorY: number) {
    this.cat = cat;
    this.sprite = sprite;
    this.frame = frame;
    this.anchorX = anchorX;
    this.anchorY = anchorY;
  }

  get scale(): number { return this.frame.width / this.sprite.width; }

  get visible(): Box {
    return new Box(
      this.frame.left + this.sprite.left * this.frame.width,
      this.frame.top + this.sprite.top * this.frame.height,
      (this.sprite.right - this.sprite.left) * this.frame.width,
      (this.sprite.bottom - this.sprite.top) * this.frame.height,
    );
  }

  get paws(): Box[] {
    const result: Box[] = [];
    for (let i = 0; i < this.sprite.paws.length; i++) {
      const paw = this.sprite.paws[i];
      result.push(new Box(
        this.frame.left + (paw.x - paw.halfWidth) * this.frame.width - 0.5,
        this.anchorY,
        2 * paw.halfWidth * this.frame.width + 1,
        paw.depth * this.frame.height + 0.5,
      ));
    }
    return result;
  }

  get reach(): number {
    return Math.max(this.sprite.anchorX - this.sprite.cutLeft, this.sprite.cutRight - this.sprite.anchorX) * this.frame.width;
  }

  covers(stage: CatStage): boolean {
    return this.paws.some((p: Box) => boxIntersects(p, stage.row) || boxIntersects(p, stage.arrow));
  }

  touch(stage: CatStage): Box {
    const width = Math.max(44, this.visible.width);
    const x = Math.min(Math.max(0, boxCenterX(this.visible) - width / 2), Math.max(0, stage.width - width));
    return new Box(x, 0, width, Math.max(1, this.anchorY));
  }
}

export class Rise {
  readonly low: number;
  readonly most: number;
  readonly middle: number;
  constructor(low: number, most: number, middle: number) { this.low = low; this.most = most; this.middle = middle; }
}

export class CatSeats {
  static readonly SMALLEST = 0.45;

  static ends(stage: CatStage, mimimo: CatSprite, momo: CatSprite): CatPlacement[] | null {
    // 【0.9.1 双猫聚拢右端】真机像素基准（安卓 0.9.1, 1080px 宽）：
    // 两只猫挨在一起坐在玻璃右端——米米莫（黑猫）在左、莫莫（暹罗）在右；
    // 两猫可见高度一致（≈玻璃高度的 0.72），爪基线贴玻璃上沿（edge.low 内）。
    // 旧版「黑猫贴左端 + 暹罗贴右端」的布局随 0.9.1 一并废弃。
    //
    // 实现说明：0.9.1 的双猫本来就压在候选行右端尾部（安卓上猫与候选文字可以共存，
    // 猫是前景层）。所以这里不再要求「不遮候选」——精确落座允许 covers()，
    // 只保留出界/贴地校验；这与安卓 0.9.1「猫趴在候选栏右端、挡住部分候选尾巴」
    // 的实际视觉一致。
    const place = (cat: Cat, art: CatSprite, anchorX: number): CatPlacement | null => {
      const unit = stage.unit;
      const glass = stage.glass;
      const available = stage.room;
      const visibleSpan = Math.max(0.01, art.bottom - art.top);
      const scale = (available * CatSeats.FILL) / (visibleSpan * art.height);
      if (scale < CatSeats.SMALLEST) return null;
      const width = art.width * scale;
      const height = art.height * scale;
      // anchorX 传「贴图锚点在玻璃坐标系中的绝对 x」；frame 由锚点反推。
      const x = anchorX - art.anchorX * width;
      // 玻璃在该锚点处的上沿（含圆弧抬升）作为爪基线。
      const edge = CatSeats.rise(stage.shape, glass,
        Math.max(0, anchorX - glass.left - width / 2),
        Math.min(glass.width, anchorX - glass.left + width / 2));
      const anchorY = glass.top + edge.low;
      return new CatPlacement(cat, art,
        new Box(x, anchorY - art.anchorY * height, width, height),
        anchorX, anchorY);
    };
    // 暹罗（右）：中心≈全宽 90%（安卓 0.9.1 基准：972px/1080px=90.0%），从玻璃右端内收 8.8% 屏宽
    // （实测校准：0.065 时暹罗中心 92.5%，左移后贴 90%）。
    const momoAnchor = stage.glass.left + stage.glass.width - 0.088 * stage.width;
    const momoPlace = place(Cat.MOMO, momo, momoAnchor);
    // 黑猫（左）：可见中心≈全宽 76.9%（安卓基准：830px/1080px），距暹罗 14.1% 屏宽
    // （实测两点标定：锚距 0.130→中心 79.1%、0.153→74.4%，线性拟合 0.141→≈76.9%）。
    const mimimoAnchor = momoAnchor - 0.141 * stage.width;
    const mimimoPlace = place(Cat.MIMIMO, mimimo, mimimoAnchor);
    if (momoPlace !== null && mimimoPlace !== null) {
      let ok = true;
      for (const box of [momoPlace.visible, mimimoPlace.visible]) {
        if (box.left < -0.01 || boxRight(box) > stage.width + 0.01 ||
          box.top + box.height > stage.height + 0.01) { ok = false; break; }
      }
      if (ok) return [mimimoPlace, momoPlace];
    }
    // 【兜底】任何一猫失败时，退化为「双猫聚拢右端」的简单落座（允许遮候选，不校验 covers）。
    return CatSeats.fallback(stage, mimimo, momo);
  }

  /** 精确落座失败时的兜底落座：双猫聚拢玻璃右端、底部贴玻璃顶线、尺寸仍按可用空间算。
   *  允许遮挡候选行（0.9.1 双猫本就趴在候选栏右端之上，与安卓视觉一致）。 */
  private static fallback(stage: CatStage, mimimo: CatSprite, momo: CatSprite): CatPlacement[] {
    const glass = stage.glass;
    const available = Math.max(1, stage.room);
    // 双猫等可见高：按「可见高 = 可用空间 × FILL」缩放（对照 0.9.1 实测两猫可见高一致）。
    const scaleOf = (art: CatSprite): number =>
      (available * CatSeats.FILL) / (Math.max(0.01, art.bottom - art.top) * art.height);
    const momoScale = scaleOf(momo);
    const place = (cat: Cat, art: CatSprite, x: number): CatPlacement => {
      const scale = scaleOf(art);
      const width = art.width * scale;
      const height = art.height * scale;
      const anchorY = glass.top;
      return new CatPlacement(cat, art,
        new Box(x, anchorY - art.anchorY * height, width, height),
        x + art.anchorX * width, anchorY);
    };
    // 右猫（暹罗）中心≈90% 屏宽；左猫（黑猫）中心距其 13% 屏宽（与 ends() 同基准）。
    const momoCentre = stage.width * 0.90;
    const momoX = momoCentre - momo.width * momoScale * momo.anchorX;
    const mimimoScale = scaleOf(mimimo);
    const mimimoX = momoCentre - 0.13 * stage.width - mimimo.width * mimimoScale * mimimo.anchorX;
    return [place(Cat.MIMIMO, mimimo, mimimoX), place(Cat.MOMO, momo, momoX)];
  }

  /**
   * 猫贴图相对「玻璃上方可用空间」的填充率。
   *
   * 不写死放大倍数，而是让猫的可见高度恰好占满玻璃上方的可用空间乘以该填充率。
   * 【0.9.1 对齐】实测安卓 0.9.1 两猫可见高 ≈ 0.72 × 玻璃高；按当前几何换算
   * （glassTop≈0.94×regionHeight−slimGlass）落在此值，同时留余量给倾斜/弹跳位移。
   */
  static readonly FILL = 0.80;

  static rise(shape: GlassShape, glass: Box, from: number, to: number): Rise {
    const quarter = (to - from) / 4;
    let low = -Number.MAX_VALUE;
    let high = Number.MAX_VALUE;
    let middle = Number.MAX_VALUE;
    let x = from;
    while (true) {
      const at = Math.min(x, to);
      const y = glassTop(shape, at, glass.width, glass.height);
      low = Math.max(low, y);
      high = Math.min(high, y);
      if (at >= from + quarter && at <= to - quarter) middle = Math.min(middle, y);
      if (x >= to) break;
      x += 1;
    }
    return new Rise(low, low - high, Math.max(0, low - middle));
  }
}
