/**
 * 节日皮肤（对应 Android ime/Festivals.kt，与 iOS Festivals.swift 同规则）。
 * 清单来自 assets/festivals/festivals.json（manifest v2）。
 */
import { CatSprite } from './CatSpriteData';
import { Box } from './Geometry';

export class FestivalInsets {
  top: number;
  left: number;
  bottom: number;
  right: number;
  constructor(top: number, left: number, bottom: number, right: number) {
    this.top = top;
    this.left = left;
    this.bottom = bottom;
    this.right = right;
  }
}

export class FestivalBust {
  bounds: number[];
  row: number;
  cutLeft: number;
  cutRight: number;
  constructor(bounds: number[], row: number, cutLeft: number, cutRight: number) {
    this.bounds = bounds;
    this.row = row;
    this.cutLeft = cutLeft;
    this.cutRight = cutRight;
  }
}

export class FestivalSprite {
  image: string;
  width: number;
  height: number;
  anchorX: number;
  anchorY: number;
  bust: FestivalBust | null;
  constructor(image: string, width: number, height: number, anchorX: number, anchorY: number,
    bust: FestivalBust | null = null) {
    this.image = image;
    this.width = width;
    this.height = height;
    this.anchorX = anchorX;
    this.anchorY = anchorY;
    this.bust = bust;
  }

  catSprite(): CatSprite | null {
    const b = this.bust;
    if (b === null) return null;
    return new CatSprite(this.image, this.width, this.height, (b.cutLeft + b.cutRight) / 2, b.row,
      b.bounds[0], b.bounds[1], b.bounds[0] + b.bounds[2], b.bounds[1] + b.bounds[3],
      b.cutLeft, b.cutRight, []);
  }
}

export class FestivalPiece {
  image: string; width: number; height: number;
  constructor(image: string, width: number, height: number) { this.image = image; this.width = width; this.height = height; }
}

export class FestivalTrim {
  image: string; width: number; height: number;
  caps: FestivalInsets; safeText: FestivalInsets; rim: FestivalInsets;
  constructor(image: string, width: number, height: number, caps: FestivalInsets,
    safeText: FestivalInsets, rim: FestivalInsets) {
    this.image = image; this.width = width; this.height = height;
    this.caps = caps; this.safeText = safeText; this.rim = rim;
  }
}

export class FestivalColors {
  accent: string; light: string[]; dark: string[]; contrast: string;
  constructor(accent: string, light: string[], dark: string[], contrast: string) {
    this.accent = accent; this.light = light; this.dark = dark; this.contrast = contrast;
  }
}

export class FestivalDays {
  first: string; main: string; last: string;
  constructor(first: string, main: string, last: string) { this.first = first; this.main = main; this.last = last; }
}

export class FestivalTheme {
  id: string; hant: string; hans: string; ja: string; en: string;
  mimimo: FestivalSprite; momo: FestivalSprite; trim: FestivalTrim;
  right: FestivalPiece | null; colors: FestivalColors; days: FestivalDays[];
  constructor(id: string, hant: string, hans: string, ja: string, en: string,
    mimimo: FestivalSprite, momo: FestivalSprite, trim: FestivalTrim, right: FestivalPiece | null,
    colors: FestivalColors, days: FestivalDays[]) {
    this.id = id; this.hant = hant; this.hans = hans; this.ja = ja; this.en = en;
    this.mimimo = mimimo; this.momo = momo; this.trim = trim; this.right = right;
    this.colors = colors; this.days = days;
  }
  name(simplified: boolean): string { return simplified ? this.hans : this.hant; }
}

export class FestivalWardrobe {
  on: boolean;
  skipped: Set<string>;
  constructor(on: boolean = true, skipped: Set<string> = new Set()) { this.on = on; this.skipped = skipped; }
}

export class FestivalLoaded {
  leadDays: number;
  themes: FestivalTheme[];
  constructor(leadDays: number, themes: FestivalTheme[]) { this.leadDays = leadDays; this.themes = themes; }
}

function parseDate(s: string): number {
  // yyyy-MM-dd -> epoch day。格式必须精确（对照 Android Festivals.day：length==10 + LocalDate.parse）。
  if (typeof s !== 'string' || s.length !== 10) return NaN;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m === null) return NaN;
  const y = parseInt(m[1], 10);
  const mo = parseInt(m[2], 10);
  const d = parseInt(m[3], 10);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return NaN;
  const t = Date.UTC(y, mo - 1, d);
  // 反查：JS Date 会溢出（如 2 月 31 日 → 3 月 3 日），溢出即非法日期。
  const back = new Date(t);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return NaN;
  return Math.floor(t / 86400000);
}

class Standing {
  step: number;
  theme: FestivalTheme;
  days: FestivalDays;
  constructor(step: number, theme: FestivalTheme, days: FestivalDays) {
    this.step = step;
    this.theme = theme;
    this.days = days;
  }
}

export class Festivals {
  static readonly MANIFEST = 'festivals/festivals.json';
  static readonly EMPTY = new FestivalLoaded(7, []);

  static parse(json: string): FestivalLoaded {
    let root: Record<string, Object>;
    try { root = JSON.parse(json) as Record<string, Object>; } catch (e) { return Festivals.EMPTY; }
    if (root.version !== 2 || root.leadDays === undefined) return Festivals.EMPTY;
    const leadDays = root.leadDays as number;
    const list = root.themes as Array<Record<string, Object>>;
    if (list === undefined) return Festivals.EMPTY;
    const themes: FestivalTheme[] = [];
    for (const o of list) {
      try {
        const t = Festivals.parseTheme(o);
        if (t !== null) themes.push(t);
      } catch (e) { /* skip */ }
    }
    return new FestivalLoaded(leadDays, themes);
  }

  private static parseTheme(o: Record<string, Object>): FestivalTheme | null {
    const names = o.names as Record<string, Object>;
    const colors = o.colors as Record<string, Object>;
    const t = o.trim as Record<string, Object>;
    const trimSize = Festivals.pair(t.size as number[]);
    const daysArr = o.days as string[][];
    const days: FestivalDays[] = [];
    for (let di = 0; di < daysArr.length; di++) {
      const d = daysArr[di];
      // 校验（对照 Android Festivals.days）：长度==3，first <= main <= last，日期合法。
      if (d === undefined || d.length !== 3) throw new Error('bad days length');
      const f = parseDate(d[0]);
      const main = parseDate(d[1]);
      const l = parseDate(d[2]);
      if (Number.isNaN(f) || Number.isNaN(main) || Number.isNaN(l)) throw new Error('bad day');
      if (main < f || l < main) throw new Error('bad days order');
      days.push(new FestivalDays(d[0], d[1], d[2]));
    }
    const theme = new FestivalTheme(
      o.id as string,
      names.hant as string, names.hans as string, names.ja as string, names.en as string,
      Festivals.sprite(o.mimimo as Record<string, Object>), Festivals.sprite(o.momo as Record<string, Object>),
      new FestivalTrim(t.image as string, trimSize[0], trimSize[1],
        Festivals.insets(t.caps as number[]), Festivals.insets(t.safeText as number[]), Festivals.insets(t.rim as number[])),
      Festivals.rightPiece(o),
      new FestivalColors(colors.accent as string,
        (colors.light as string[]), (colors.dark as string[]), colors.contrast as string),
      days,
    );
    const names2 = [theme.id, theme.mimimo.image, theme.momo.image, theme.trim.image, theme.right?.image ?? 'x'];
    if (!names2.every(n => Festivals.isName(n))) return null;
    return theme;
  }

  private static rightPiece(o: Record<string, Object>): FestivalPiece | null {
    const ends = o.ends as Record<string, Object> | undefined;
    const right = ends?.right as Record<string, Object> | undefined;
    if (right === undefined) return null;
    const size = Festivals.pair(right.size as number[]);
    return new FestivalPiece(right.image as string, size[0], size[1]);
  }

  private static sprite(o: Record<string, Object>): FestivalSprite {
    const size = Festivals.pair(o.size as number[]);
    const anchor = Festivals.pair(o.anchor as number[]);
    let bust: FestivalBust | null = null;
    const b = o.bust as Record<string, Object> | undefined;
    if (b !== undefined) {
      const cut = b.cut as number[];
      bust = new FestivalBust(b.bounds as number[], b.row as number, cut[0], cut[1]);
    }
    return new FestivalSprite(o.image as string, size[0], size[1], anchor[0], anchor[1], bust);
  }

  private static pair(a: number[]): [number, number] { return [a[0], a[1]]; }

  private static insets(a: number[]): FestivalInsets {
    return new FestivalInsets(a[0], a[1], a[2], a[3]);
  }

  static isName(text: string): boolean {
    return text.length >= 1 && text.length <= 64 &&
      /^[a-zA-Z0-9_\-]+$/.test(text);
  }

  /**
   * 今天（epoch day）。按设备本地日历日计算，与 Android `LocalDate.now()` 对齐。
   * 用 UTC 取值会让东八区在 00:00–08:00 之间仍算作昨天，节日主题最多滞后 8 小时。
   */
  static today(): number {
    const now = new Date();
    return Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000);
  }

  static theme(today: number, loaded: FestivalLoaded, wardrobe: FestivalWardrobe): FestivalTheme | null {
    if (!wardrobe.on) return null;
    const pool: Standing[] = [];
    for (const theme of loaded.themes) {
      if (wardrobe.skipped.has(theme.id)) continue;
      for (const days of theme.days) {
        const first = parseDate(days.first);
        const main = parseDate(days.main);
        const last = parseDate(days.last);
        if (today < first - loaded.leadDays || today > last) continue;
        const step = today === main ? 1 : (today >= first ? 2 : 3);
        pool.push(new Standing(step, theme, days));
      }
    }
    if (pool.length === 0) return null;
    let step = pool[0].step;
    for (const s of pool) if (s.step < step) step = s.step;
    const standing = pool.filter(s => s.step === step);
    let leader: Standing;
    if (step === 2) {
      leader = standing[0];
      for (const s of standing) {
        const f = parseDate(s.days.first);
        const lf = parseDate(leader.days.first);
        const l = parseDate(s.days.last);
        const ll = parseDate(leader.days.last);
        if (f > lf || (f === lf && l < ll)) leader = s;
      }
    } else if (step === 3) {
      leader = standing[0];
      for (const s of standing) {
        if (parseDate(s.days.first) < parseDate(leader.days.first)) leader = s;
      }
    } else {
      leader = standing[0];
    }
    const turns = standing.filter(s => parseDate(s.days.main) === parseDate(leader.days.main));
    const idx = ((today % turns.length) + turns.length) % turns.length;
    return turns[idx].theme;
  }

  /**
   * 在 [since, today] 范围内，穿戴区间（first - leadDays 到 last）曾开始过
   * 至少一次的主题，按 manifest 顺序返回（对照 Android Festivals.met）。
   */
  static met(since: number, today: number, loaded: FestivalLoaded): FestivalTheme[] {
    const result: FestivalTheme[] = [];
    for (const theme of loaded.themes) {
      for (const days of theme.days) {
        const first = parseDate(days.first);
        const last = parseDate(days.last);
        if (Number.isNaN(first) || Number.isNaN(last)) continue;
        if (first - loaded.leadDays <= today && last >= since) {
          result.push(theme);
          break;
        }
      }
    }
    return result;
  }

  /** 右端装饰簇的落位。 */
  static placeRight(piece: FestivalPiece, glass: Box, band: [number, number], width: number, arrowRight: number): Box | null {
    const tallest = band[1] - band[0];
    const bottom = glass.top + band[1] + 1;
    const end = Math.min(width - 1, glass.left + glass.width + 4);
    const k = Math.min(tallest / piece.height, (end - arrowRight - 2) / piece.width);
    if (piece.height * k < 0.6 * tallest) return null;
    return new Box(end - piece.width * k, bottom - piece.height * k, piece.width * k, piece.height * k);
  }
}