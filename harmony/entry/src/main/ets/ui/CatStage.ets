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
    const left = CatSeats.seat(stage, Cat.MIMIMO, mimimo, true);
    const right = CatSeats.seat(stage, Cat.MOMO, momo, false);
    if (left === null || right === null) return null;
    for (const box of [left.visible, right.visible]) {
      if (box.left < -0.01 || box.top < -0.01 || boxRight(box) > stage.width + 0.01 ||
        box.top + box.height > stage.height + 0.01) return null;
    }
    if (boxRight(left.visible) + 4 * stage.unit > right.visible.left) return null;
    return [left, right];
  }

  private static seat(stage: CatStage, cat: Cat, art: CatSprite, fromLeft: boolean): CatPlacement | null {
    const unit = stage.unit;
    const glass = stage.glass;
    const scale = Math.min(1, stage.room / ((art.anchorY - art.top) * art.height));
    if (scale < CatSeats.SMALLEST) return null;
    const width = art.width * scale;
    const height = art.height * scale;
    const span = (art.cutRight - art.cutLeft) * width;
    const radius = endRadius(stage.shape, glass.height);
    let slide = 0;
    while (slide <= glass.width * 0.3) {
      const start = fromLeft ? radius - 4 * unit + slide : glass.width - radius + 4 * unit - slide - span;
      const edge = CatSeats.rise(stage.shape, glass, start, start + span);
      const x = glass.left + start - art.cutLeft * width;
      let pawsLevel = true;
      for (let pi = 0; pi < art.paws.length; pi++) {
        const paw = art.paws[pi];
        const centre = x - glass.left + paw.x * width;
        const under = CatSeats.rise(stage.shape, glass, centre - paw.halfWidth * width, centre + paw.halfWidth * width);
        if (edge.low - (under.low - under.most) > 1.5 * unit) { pawsLevel = false; break; }
      }
      if (edge.most <= 4 * unit && edge.middle <= 1.5 * unit && pawsLevel) {
        const anchorY = glass.top + edge.low;
        const place = new CatPlacement(cat, art,
          new Box(x, anchorY - art.anchorY * height, width, height),
          x + art.anchorX * width, anchorY);
        if (!place.covers(stage)) return place;
      }
      slide += 2 * unit;
    }
    return null;
  }

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
