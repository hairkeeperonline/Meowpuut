/**
 * 玻璃与矢量图形的绘制（对应 Android ime/Painting.kt，用 ArkUI CanvasRenderingContext2D）。
 */
import { Box } from './Geometry';
import { GlassShape, traceOutline, endRadius } from './GlassOutline';
import { Look, withAlpha, lighten, darken } from './Theme';

/**
 * 【round 65 ①】绘制目标统一放宽到 CanvasRenderer：CanvasRenderingContext2D 与
 * OffscreenCanvasRenderingContext2D 都是它的子类——玻璃静态层要画进离屏画布，
 * 共享同一套绘制代码（GlassPainter/roundRect/tracePath 等只用公共成员）。
 */
export type Canvas2D = CanvasRenderer;

/** 把玻璃轮廓画到 ctx（闭合路径）。 */
export function tracePath(ctx: Canvas2D, shape: GlassShape, box: Box, inset: number = 0): void {
  const pts = traceOutline(shape, box, inset);
  if (pts.length === 0) return;
  ctx.beginPath();
  const first = pts[0];
  ctx.moveTo(first.x, first.y);
  for (let i = 1; i < pts.length; i++) {
    const pt = pts[i];
    ctx.lineTo(pt.x, pt.y);
  }
  ctx.closePath();
}

/**
 * 玻璃体（Android 没有实时背景模糊，鸿蒙同样用「仿真」玻璃）：
 * 磨砂体、内釉、内缘亮带、下缘虹彩、内高光、镜面斑与抛光边。
 */
export class GlassPainter {
  static readonly REACH = 20;

  static shadow(ctx: Canvas2D, shape: GlassShape, glass: Box, dark: boolean): void {
    const pathBox: Box = new Box(glass.left + 6, glass.top + 5, glass.width - 12, glass.height);
    ctx.save();
    // 只画玻璃外围：先画整条，再用玻璃轮廓挖掉。
    ctx.beginPath();
    ctx.rect(0, 0, 10000, 10000);
    tracePath(ctx, shape, glass);
    ctx.clip('evenodd');
    ctx.beginPath();
    tracePath(ctx, shape, pathBox);
    if (dark) {
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.shadowBlur = 8;
      ctx.shadowColor = 'rgba(0,0,0,0.5)';
    } else {
      ctx.fillStyle = 'rgba(61,41,69,0.13)';
      ctx.shadowBlur = 7;
      ctx.shadowColor = 'rgba(61,41,69,0.13)';
    }
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.restore();
  }

  static body(ctx: Canvas2D, shape: GlassShape, glass: Box, look: Look): void {
    const dark = look.dark;
    tracePath(ctx, shape, glass);
    if (!look.opaque) {
      // 透过玻璃的虹彩，落在下半部。
      const spill: Box = new Box(glass.left + 14, glass.top + 6, glass.width - 28, glass.height);
      const grad = ctx.createLinearGradient(spill.left, 0, spill.left + spill.width, 0);
      const caustic = look.causticColors;
      for (let i = 0; i < caustic.length; i++) grad.addColorStop(i / (caustic.length - 1), caustic[i]);
      ctx.save();
      tracePath(ctx, shape, spill);
      ctx.globalAlpha = dark ? 0.20 : 0.30;
      // 横向彩虹渐变（对应 Android Painting.kt:72-79 的 causticColors）。
      ctx.fillStyle = grad;
      ctx.shadowBlur = 7;
      ctx.shadowColor = caustic.length > 0 ? caustic[0] : '#40FFFFFF';
      ctx.fill();
      ctx.restore();
    }
    ctx.save();
    tracePath(ctx, shape, glass);
    ctx.fillStyle = look.glassFill;
    ctx.fill();

    if (look.opaque) {
      GlassPainter.edge(ctx, shape, glass, look);
      ctx.restore();
      return;
    }

    ctx.fillStyle = withAlpha(look.tint, 0.07);
    ctx.fill();

    // 内釉，顶部更亮。
    const glaze = ctx.createLinearGradient(0, glass.top, 0, glass.top + glass.height);
    glaze.addColorStop(0, withAlpha('#FFFFFFFF', dark ? 0.09 : 0.22));
    glaze.addColorStop(1, withAlpha('#FFFFFFFF', dark ? 0 : 0.04));
    ctx.fillStyle = glaze;
    ctx.fill();

    // 内缘亮带。
    ctx.clip();
    tracePath(ctx, shape, glass, 3);
    ctx.lineWidth = 3.5;
    ctx.strokeStyle = withAlpha('#FFFFFFFF', dark ? 0.07 : 0.38);
    ctx.shadowBlur = 1.8;
    ctx.shadowColor = withAlpha('#FFFFFFFF', dark ? 0.07 : 0.38);
    ctx.stroke();
    ctx.shadowBlur = 0;

    // 下缘虹彩。
    tracePath(ctx, shape, glass, 2);
    const causticLine = ctx.createLinearGradient(glass.left, 0, glass.left + glass.width, 0);
    const cs = look.causticColors;
    for (let i = 0; i < cs.length; i++) causticLine.addColorStop(i / (cs.length - 1), cs[i]);
    ctx.lineWidth = 2.4;
    ctx.strokeStyle = causticLine;
    ctx.globalAlpha = dark ? 0.6 : 0.8;
    ctx.stroke();
    ctx.globalAlpha = 1;

    // 顶部内缘的厚度高光。
    tracePath(ctx, shape, glass, 1.2);
    const topLight = ctx.createLinearGradient(0, glass.top, 0, glass.top + glass.height);
    topLight.addColorStop(0, withAlpha('#FFFFFFFF', dark ? 0.24 : 0.9));
    topLight.addColorStop(0.45, withAlpha('#FFFFFFFF', 0));
    ctx.lineWidth = 1.4;
    ctx.strokeStyle = topLight;
    ctx.stroke();

    // 左上镜面斑。
    tracePath(ctx, shape, glass, 1.5);
    ctx.lineWidth = 2;
    ctx.strokeStyle = withAlpha('#FFFFFFFF', dark ? 0.4 : 0.9);
    ctx.stroke();

    GlassPainter.edge(ctx, shape, glass, look);

    // 下缘内侧的柔和阴影（仅浅色）与细深线。
    tracePath(ctx, shape, glass, 3);
    if (!dark) {
      ctx.lineWidth = 5;
      ctx.strokeStyle = 'rgba(77,56,87,0.07)';
      ctx.shadowBlur = 2.5;
      ctx.shadowColor = 'rgba(77,56,87,0.07)';
      ctx.stroke();
      ctx.shadowBlur = 0;
    }
    tracePath(ctx, shape, glass);
    ctx.lineWidth = 0.5;
    ctx.strokeStyle = withAlpha('#FF000000', dark ? 0.35 : 0.08);
    ctx.stroke();
    ctx.restore();
  }

  private static edge(ctx: Canvas2D, shape: GlassShape, glass: Box, look: Look): void {
    const dark = look.dark;
    tracePath(ctx, shape, glass);
    ctx.lineWidth = 1.5;
    const edge = ctx.createLinearGradient(glass.left, glass.top, glass.left + glass.width, glass.top + glass.height);
    edge.addColorStop(0, withAlpha(look.rim, dark ? 0.95 : 1));
    edge.addColorStop(0.55, withAlpha(look.rim, dark ? 0.16 : 0.4));
    edge.addColorStop(1, withAlpha(look.rim, dark ? 0.5 : 0.8));
    ctx.strokeStyle = edge;
    ctx.stroke();
  }
}

/** 选中候选的胶囊：一颗彩色玻璃珠。 */
export class PillPainter {
  static draw(ctx: Canvas2D, left: number, top: number, width: number, height: number,
    colors: [string, string], dark: boolean, shadow: boolean): void {
    const radius = height / 2;
    const middle = top + height / 2;
    const fill = ctx.createLinearGradient(0, top, 0, top + height);
    fill.addColorStop(0, colors[0]);
    fill.addColorStop(1, colors[1]);
    ctx.save();
    if (shadow) {
      ctx.shadowBlur = 3.5;
      ctx.shadowOffsetY = 1.5;
      ctx.shadowColor = withAlpha(colors[1], dark ? 0.30 : 0.38);
    }
    ctx.fillStyle = fill;
    roundRect(ctx, left, top, width, height, radius);
    ctx.fill();
    ctx.restore();

    ctx.save();
    roundRect(ctx, left, top, width, height, radius);
    ctx.clip();
    // 上缘高光。
    const line = ctx.createLinearGradient(0, top, 0, middle);
    line.addColorStop(0, withAlpha('#FFFFFFFF', dark ? 0.34 : 0.55));
    line.addColorStop(1, withAlpha('#FFFFFFFF', 0));
    ctx.strokeStyle = line;
    ctx.lineWidth = 0.8;
    roundRect(ctx, left + 0.5, top + 0.5, width - 1, height - 1, radius - 0.5);
    ctx.stroke();
    // 下缘聚光：从中心往下渐强（对应 Android Painting.kt:212-213）。
    const glow = ctx.createLinearGradient(0, middle, 0, top + height);
    glow.addColorStop(0, withAlpha('#FFFFFFFF', 0));
    glow.addColorStop(1, withAlpha('#FFFFFFFF', dark ? 0.16 : 0.26));
    ctx.strokeStyle = glow;
    ctx.lineWidth = 1.6;
    ctx.shadowBlur = 0.8;
    ctx.shadowColor = withAlpha('#FFFFFFFF', dark ? 0.16 : 0.26);
    roundRect(ctx, left + 0.7, top + 0.7, width - 1.4, height - 1.4, radius - 1.2);
    ctx.stroke();
    ctx.restore();
  }
}

export function roundRect(ctx: Canvas2D, x: number, y: number, w: number, h: number, r: number): void {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.lineTo(x + w - rr, y);
  ctx.arcTo(x + w, y, x + w, y + rr, rr);
  ctx.lineTo(x + w, y + h - rr);
  ctx.arcTo(x + w, y + h, x + w - rr, y + h, rr);
  ctx.lineTo(x + rr, y + h);
  ctx.arcTo(x, y + h, x, y + h - rr, rr);
  ctx.lineTo(x, y + rr);
  ctx.arcTo(x, y, x + rr, y, rr);
  ctx.closePath();
}

/** 小矢量图形。 */
export class Glyphs {
  static paw(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(-20 * Math.PI / 180);
    ctx.translate(-cx, -cy);
    const s = size / 10;
    ctx.fillStyle = color;
    ellipse(ctx, cx - 3.1 * s, cy - 0.2 * s, cx + 3.1 * s, cy + 4.6 * s);
    const toes = [-3.9, -1.3, -1.5, -3.6, 1.5, -3.6, 3.9, -1.3];
    for (let i = 0; i < toes.length; i += 2) {
      ellipse(ctx, cx + (toes[i] - 1.25) * s, cy + (toes[i + 1] - 1.6) * s, cx + (toes[i] + 1.25) * s, cy + (toes[i + 1] + 1.6) * s);
    }
    ctx.restore();
  }

  /** 【剪贴板芯片 round 61】小剪贴板图标：圆角板身 + 顶部压夹，细线描边。 */
  static clipboard(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const w = size * 0.78;
    const h = size;
    const left = cx - w / 2;
    const top = cy - h / 2 + size * 0.06;
    ctx.save();
    ctx.lineWidth = Math.max(1.2, size * 0.09);
    ctx.lineJoin = 'round';
    ctx.strokeStyle = color;
    // 板身。
    roundRect(ctx, left, top, w, h, size * 0.12);
    ctx.stroke();
    // 压夹：板顶小圆角矩形（横跨上沿）。
    const cw = w * 0.52;
    roundRect(ctx, cx - cw / 2, top - size * 0.12, cw, size * 0.24, size * 0.08);
    ctx.fillStyle = color;
    ctx.fill();
    // 板面两条短横线示意内容。
    ctx.beginPath();
    ctx.moveTo(left + w * 0.26, cy + size * 0.08);
    ctx.lineTo(left + w * 0.74, cy + size * 0.08);
    ctx.moveTo(left + w * 0.26, cy + size * 0.3);
    ctx.lineTo(left + w * 0.58, cy + size * 0.3);
    ctx.lineWidth = Math.max(1, size * 0.07);
    ctx.stroke();
    ctx.restore();
  }

  static chevron(ctx: Canvas2D, cx: number, cy: number, width: number, up: boolean, color: string): void {
    const h = width * 0.5;
    const dir = up ? -1 : 1;
    ctx.beginPath();
    ctx.moveTo(cx - width / 2, cy - dir * h / 2);
    ctx.lineTo(cx, cy + dir * h / 2);
    ctx.lineTo(cx + width / 2, cy - dir * h / 2);
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  static delete(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const w = size * 1.18;
    const h = size * 0.82;
    const left = cx - w / 2;
    const point = left + h * 0.42;
    ctx.beginPath();
    ctx.moveTo(left, cy);
    ctx.lineTo(point, cy - h / 2);
    ctx.lineTo(cx + w / 2, cy - h / 2);
    ctx.lineTo(cx + w / 2, cy + h / 2);
    ctx.lineTo(point, cy + h / 2);
    ctx.closePath();
    ctx.lineWidth = size * 0.085;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
    const xc = (point + cx + w / 2) / 2 + size * 0.02;
    const d = h * 0.2;
    ctx.beginPath();
    ctx.moveTo(xc - d, cy - d);
    ctx.lineTo(xc + d, cy + d);
    ctx.moveTo(xc - d, cy + d);
    ctx.lineTo(xc + d, cy - d);
    ctx.stroke();
  }

  static globe(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const r = size * 0.5;
    ctx.lineWidth = size * 0.075;
    ctx.strokeStyle = color;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.ellipse(cx, cy, r * 0.45, r, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy);
    ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r);
    ctx.stroke();
  }

  /**
   * Shift 上箭头（对应 Android Painting.kt:273-297）。
   * `filled` 区分空心（SHIFT）与实心（SHIFT_ON / CAPS_LOCK），`lock` 追加底部锁定横条。
   */
  static shift(ctx: Canvas2D, cx: number, cy: number, size: number, filled: boolean, lock: boolean, color: string): void {
    const w = size * 0.92;
    const head = size * 0.5;
    const stem = w * 0.42;
    const top = cy - size * 0.55;
    const bottom = cy + size * (lock ? 0.18 : 0.42);
    ctx.beginPath();
    ctx.moveTo(cx, top);
    ctx.lineTo(cx + w / 2, top + head);
    ctx.lineTo(cx + stem / 2, top + head);
    ctx.lineTo(cx + stem / 2, bottom);
    ctx.lineTo(cx - stem / 2, bottom);
    ctx.lineTo(cx - stem / 2, top + head);
    ctx.lineTo(cx - w / 2, top + head);
    ctx.closePath();
    ctx.lineJoin = 'round';
    ctx.lineWidth = size * 0.085;
    ctx.strokeStyle = color;
    if (filled) {
      ctx.fillStyle = color;
      ctx.fill();
    }
    ctx.stroke();
    if (lock) {
      ctx.fillStyle = color;
      ctx.strokeStyle = color;
      const left = cx - stem / 2;
      const right = cx + stem / 2;
      const ltop = cy + size * 0.32;
      const lbottom = cy + size * 0.46;
      ctx.beginPath();
      ctx.rect(left, ltop, right - left, lbottom - ltop);
      ctx.fill();
      ctx.stroke();
    }
  }

  /** 心形（对应 Android Painting.kt:333-342）。 */
  static heart(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const s = size / 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy + s * 0.85);
    ctx.bezierCurveTo(cx - s * 1.25, cy - s * 0.05, cx - s * 0.75, cy - s * 1.05, cx, cy - s * 0.42);
    ctx.bezierCurveTo(cx + s * 0.75, cy - s * 1.05, cx + s * 1.25, cy - s * 0.05, cx, cy + s * 0.85);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  /** 四角星（对应 Android Painting.kt:344-355）。 */
  static sparkle(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const s = size / 2;
    const k = s * 0.22;
    ctx.beginPath();
    ctx.moveTo(cx, cy - s);
    ctx.quadraticCurveTo(cx + k, cy - k, cx + s, cy);
    ctx.quadraticCurveTo(cx + k, cy + k, cx, cy + s);
    ctx.quadraticCurveTo(cx - k, cy + k, cx - s, cy);
    ctx.quadraticCurveTo(cx - k, cy - k, cx, cy - s);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  /** 音符（对应 Android Painting.kt:357-366）。 */
  static note(ctx: Canvas2D, cx: number, cy: number, size: number, color: string): void {
    const s = size / 2;
    ctx.fillStyle = color;
    ellipse(ctx, cx - s * 0.9, cy + s * 0.25, cx - s * 0.05, cy + s * 0.9);
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(1, s * 0.22);
    ctx.beginPath();
    ctx.moveTo(cx - s * 0.1, cy + s * 0.55);
    ctx.lineTo(cx - s * 0.1, cy - s * 0.9);
    ctx.lineTo(cx + s * 0.7, cy - s * Math.min(0.5, 0.6));
    ctx.stroke();
  }
}

function ellipse(ctx: Canvas2D, x0: number, y0: number, x1: number, y1: number): void {
  const cx = (x0 + x1) / 2;
  const cy = (y0 + y1) / 2;
  const rx = Math.abs(x1 - x0) / 2;
  const ry = Math.abs(y1 - y0) / 2;
  ctx.beginPath();
  ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
  ctx.fill();
}