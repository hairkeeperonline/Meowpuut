/**
 * 候选玻璃的轮廓数学（对应 Android ime/GlassOutline.kt，与 iOS GlassShapes.swift 逐点一致）。
 * ArkUI 侧用它生成 Path 的点串。
 */
import { Box } from './Geometry';

export enum GlassShape {
  CAPSULE = 'capsule',
  WAVE = 'wave',
  CLOUD = 'cloud',
}

export function glassShapeOf(key: string | undefined | null): GlassShape {
  if (key === GlassShape.CAPSULE) return GlassShape.CAPSULE;
  if (key === GlassShape.WAVE) return GlassShape.WAVE;
  if (key === GlassShape.CLOUD) return GlassShape.CLOUD;
  return GlassShape.CAPSULE;
}

const WAVE_AMPLITUDE = 0.065;
const CLOUD_BASE = 0.16;
const CLOUD_SMOOTHING = 0.10;
const CLOUD_BUMPS: number[][] = [
  [0.15, 0.58, 0],
  [0.47, 0.75, 0.05],
  [0.77, 0.56, 0.07],
];

export function smoothstep(edge0: number, edge1: number, x: number): number {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

export function smoothMin(a: number, b: number, k: number): number {
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k / 4;
}

/** 候选所在的垂直带（轮廓盒的相对值）。 */
export class ContentBand {
  low: number;
  high: number;
  constructor(low: number, high: number) {
    this.low = low;
    this.high = high;
  }
}

export function contentBand(shape: GlassShape, height: number): ContentBand {
  switch (shape) {
    case GlassShape.CAPSULE: return new ContentBand(0, height);
    case GlassShape.WAVE: return new ContentBand(WAVE_AMPLITUDE * height, height * (1 - WAVE_AMPLITUDE));
    case GlassShape.CLOUD: return new ContentBand(CLOUD_BASE * height, height);
    default: return new ContentBand(0, height);
  }
}

export function waveCount(width: number): number {
  return Math.max(2, Math.round(width / 170));
}

export function waveOffset(x: number, width: number, height: number, waves: number, amplitude: number): number {
  const radius = Math.max(1, height / 2 - amplitude);
  const straight = Math.max(1, width - 2 * radius);
  const u = (x - radius) / straight;
  const envelope = smoothstep(0, 0.12, u) * smoothstep(0, 0.12, 1 - u);
  return -amplitude * Math.sin(2 * Math.PI * waves * u) * envelope;
}

export class Circle {
  cx: number;
  r: number;
  cy: number;
  constructor(cx: number, r: number, cy: number) {
    this.cx = cx;
    this.r = r;
    this.cy = cy;
  }
}

function cloudCircles(width: number, height: number): Circle[] {
  const base = CLOUD_BASE * height;
  const radius = (height - base) / 2;
  const smoothing = CLOUD_SMOOTHING * height;
  const result: Circle[] = [];
  for (let i = 0; i < CLOUD_BUMPS.length; i++) {
    const bump = CLOUD_BUMPS[i];
    const r = bump[1] * height;
    const cy = bump[2] * height + r;
    const reach = Math.sqrt(Math.max(0, r * r - (cy - base) * (cy - base))) + smoothing + 2;
    const lower = radius + reach;
    const upper = width - radius - reach;
    const cx = upper > lower ? Math.min(Math.max(bump[0] * width, lower), upper) : width / 2;
    result.push(new Circle(cx, r, cy));
  }
  return result;
}

function cloudTopAt(x: number, circles: Circle[], height: number): number {
  let y = CLOUD_BASE * height;
  for (let i = 0; i < circles.length; i++) {
    const c = circles[i];
    const dx = x - c.cx;
    if (Math.abs(dx) >= c.r) continue;
    y = smoothMin(y, c.cy - Math.sqrt(c.r * c.r - dx * dx), CLOUD_SMOOTHING * height);
  }
  return y;
}

export function cloudTop(x: number, width: number, height: number): number {
  return cloudTopAt(x, cloudCircles(width, height), height);
}

export function endRadius(shape: GlassShape, height: number): number {
  switch (shape) {
    case GlassShape.CAPSULE: return height / 2;
    case GlassShape.WAVE: return Math.max(1, height / 2 - WAVE_AMPLITUDE * height);
    case GlassShape.CLOUD: return (height - CLOUD_BASE * height) / 2;
    default: return height / 2;
  }
}

/** 上缘在 [x]（相对盒）的 y。 */
export function glassTop(shape: GlassShape, x: number, width: number, height: number): number {
  const radius = endRadius(shape, height);
  const band = contentBand(shape, height);
  const rim = band.low;
  const fromEnd = Math.max(0, Math.min(x, width - x));
  if (fromEnd < radius) {
    return rim + radius - Math.sqrt(radius * radius - (radius - fromEnd) * (radius - fromEnd));
  }
  switch (shape) {
    case GlassShape.CAPSULE: return 0;
    case GlassShape.WAVE: return rim + waveOffset(x, width, height, waveCount(width), WAVE_AMPLITUDE * height);
    case GlassShape.CLOUD: return cloudTop(x, width, height);
    default: return 0;
  }
}

/** 一个二维点。 */
export class Point2D {
  x: number;
  y: number;
  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/** 轮廓点串（用于 ArkUI Path / canvas）。返回闭合多边形的顶点。 */
export function traceOutline(shape: GlassShape, box: Box, inset: number): Point2D[] {
  const left = box.left + inset;
  const top = box.top + inset;
  const width = box.width - 2 * inset;
  const height = box.height - 2 * inset;
  if (width <= 2 || height <= 2) return [];

  const pts: Point2D[] = [];
  switch (shape) {
    case GlassShape.CAPSULE: {
      const r = height / 2;
      pts.push(new Point2D(left + r, top));
      pts.push(new Point2D(left + width - r, top));
      arcTo(pts, left + width - r, top + r, r, -90, 180);
      pts.push(new Point2D(left + r, top + height));
      arcTo(pts, left + r, top + r, r, 90, 180);
      break;
    }
    case GlassShape.WAVE: {
      const waves = waveCount(box.width);
      const amplitude = WAVE_AMPLITUDE * box.height;
      const radius = Math.max(1, height / 2 - amplitude);
      const straight = Math.max(1, width - 2 * radius);
      const steps = 64;
      for (let i = 0; i <= steps; i++) {
        const x = radius + straight * i / steps;
        const y = top + amplitude + waveOffset(x, width, height, waves, amplitude);
        pts.push(new Point2D(left + x, y));
      }
      arcTo(pts, left + width - radius, top + height / 2, radius, -90, 180);
      for (let i = steps; i >= 0; i--) {
        const x = radius + straight * i / steps;
        pts.push(new Point2D(left + x, top + height - amplitude + waveOffset(x, width, height, waves, amplitude)));
      }
      arcTo(pts, left + radius, top + height / 2, radius, 90, 180);
      break;
    }
    case GlassShape.CLOUD: {
      const base = CLOUD_BASE * height;
      const radius = (height - base) / 2;
      const centerY = base + radius;
      const circles = cloudCircles(width, height);
      const straight = Math.max(1, width - 2 * radius);
      const steps = 96;
      for (let i = 0; i <= steps; i++) {
        const x = radius + straight * i / steps;
        const y = top + cloudTopAt(x, circles, height);
        pts.push(new Point2D(left + x, y));
      }
      arcTo(pts, left + width - radius, top + centerY, radius, -90, 180);
      pts.push(new Point2D(left + radius, top + height));
      arcTo(pts, left + radius, top + centerY, radius, 90, 180);
      break;
    }
  }
  return pts;
}

/** 圆弧采样（角度制，正方向顺时针）。 */
function arcTo(pts: Point2D[], cx: number, cy: number, r: number, startDeg: number, sweepDeg: number): void {
  const seg = Math.max(4, Math.ceil(Math.abs(sweepDeg) / 12));
  for (let i = 0; i <= seg; i++) {
    const deg = startDeg + sweepDeg * i / seg;
    const rad = deg * Math.PI / 180;
    pts.push(new Point2D(cx + r * Math.cos(rad), cy + r * Math.sin(rad)));
  }
}
