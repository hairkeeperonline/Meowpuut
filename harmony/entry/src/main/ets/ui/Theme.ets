/**
 * 配色（对应 Android ime/Theme.kt，颜色来自 docs/DESIGN.md §3–§5 与 Sources/GlassShapes.swift）。
 * 颜色统一用 "#AARRGGBB" 字符串，ArkUI 直接可用。
 */
import { GlassShape } from './GlassOutline';

export enum Palette {
  ROSE = 'rose', OCEAN = 'ocean', SAGE = 'sage', LAVENDER = 'lavender', AMBER = 'amber', GRAPHITE = 'graphite',
}

export function paletteOf(key: string | undefined | null): Palette {
  switch (key) {
    case Palette.OCEAN: return Palette.OCEAN;
    case Palette.SAGE: return Palette.SAGE;
    case Palette.LAVENDER: return Palette.LAVENDER;
    case Palette.AMBER: return Palette.AMBER;
    case Palette.GRAPHITE: return Palette.GRAPHITE;
    default: return Palette.ROSE;
  }
}

export enum Tone {
  SYSTEM = 'system', LIGHT = 'light', DARK = 'dark',
}

export function toneOf(key: string | undefined | null): Tone {
  if (key === Tone.LIGHT) return Tone.LIGHT;
  if (key === Tone.DARK) return Tone.DARK;
  return Tone.SYSTEM;
}

export enum GlassStrength {
  SOFT = 'soft', BALANCED = 'balanced', VIVID = 'vivid',
}

export function glassStrengthOf(key: string | undefined | null): GlassStrength {
  if (key === GlassStrength.SOFT) return GlassStrength.SOFT;
  if (key === GlassStrength.VIVID) return GlassStrength.VIVID;
  return GlassStrength.BALANCED;
}

/** 决定键盘如何被绘制的全部信息。 */
export class Look {
  readonly dark: boolean;
  readonly shape: GlassShape;
  readonly palette: Palette;
  readonly strength: GlassStrength;
  readonly cats: boolean;
  readonly pillOverride: string | null;
  readonly opaque: boolean;
  /** 按键气泡开关（对应 Android keyPopups，默认开）。 */
  readonly keyPopups: boolean;
  /** 键盘高度档位（对应 Android keyboardHeight：short/standard/tall）。 */
  readonly keyboardHeight: string;
  /** 视觉特效档位（对应 Android effects：lightweight/standard/extreme）。 */
  readonly effects: string;

  constructor(dark: boolean, shape: GlassShape, palette: Palette, strength: GlassStrength, cats: boolean,
    pillOverride: string | null = null, opaque: boolean = false, keyPopups: boolean = true,
    keyboardHeight: string = 'standard', effects: string = 'standard') {
    this.dark = dark;
    this.shape = shape;
    this.palette = palette;
    this.strength = strength;
    this.cats = cats;
    this.pillOverride = pillOverride;
    this.opaque = opaque;
    this.keyPopups = keyPopups;
    this.keyboardHeight = keyboardHeight;
    this.effects = effects;
  }

  /** 键盘高度缩放系数（short=0.88 / standard=1.0 / tall=1.12）。 */
  get heightScale(): number {
    return this.keyboardHeight === 'short' ? 0.88 : this.keyboardHeight === 'tall' ? 1.12 : 1.0;
  }

  /**
   * 玻璃通透度附加系数（对应 Android effects：极致让候选栏、键帽和底板更通透）。
   * extreme 额外把 alpha 乘 0.82；lightweight/standard 保持 1.0。
   */
  get effectAlphaScale(): number {
    return this.effects === 'extreme' ? 0.82 : 1.0;
  }

  /** lean 动效时长（毫秒），轻量减少动效→140ms，其余 320ms。 */
  get leanDuration(): number {
    return this.effects === 'lightweight' ? 140 : 320;
  }

  get keyboardTop(): string { return this.dark ? '#FF252428' : '#FFE9E8EF'; }
  get keyboardBottom(): string { return this.dark ? '#FF1A191C' : '#FFD9D8E0'; }
  get keyFaceTop(): string { return this.dark ? '#FF636268' : '#FFFFFFFF'; }
  get keyFaceBottom(): string { return this.dark ? '#FF5A595F' : '#FFFAFAFC'; }
  get keyUtility(): string { return this.dark ? '#FF3C3B40' : '#FFCFCED8'; }
  get keyPressed(): string { return this.dark ? '#FF77767D' : '#FFFFFFFF'; }
  get keyCharacterPressed(): string { return this.dark ? '#FF4A494F' : '#FFE2E1E8'; }
  get keyShadow(): string { return this.dark ? '#73000000' : '#33000000'; }
  get keyText(): string { return this.dark ? '#FFFFFFFF' : '#FF18181B'; }
  get keyTextDisabled(): string { return this.dark ? '#66FFFFFF' : '#5518181B'; }
  get candidateText(): string { return this.dark ? '#FFF5EFE9' : '#FF3A3334'; }
  get candidateSecondary(): string { return this.dark ? '#FFCCC2BA' : '#FF7A7072'; }
  get balloonFace(): string { return this.dark ? '#FF6B6A70' : '#FFFFFFFF'; }

  get pill(): [string, string] {
    if (this.pillOverride !== null) return [lighten(this.pillOverride, 0.14), this.pillOverride];
    return palettePill(this.palette, this.dark);
  }

  get accent(): string { return this.pill[1]; }

  get glassFill(): string {
    if (this.opaque) return this.dark ? '#FF2B2729' : '#FFF4F2F6';
    let alpha: number;
    switch (this.strength) {
      case GlassStrength.SOFT: alpha = this.dark ? 0.74 : 0.60; break;
      case GlassStrength.VIVID: alpha = this.dark ? 0.50 : 0.32; break;
      default: alpha = this.dark ? 0.62 : 0.46; break;
    }
    // effects=extreme 更通透：额外降低 alpha。
    alpha = Math.min(1, Math.max(0, alpha * this.effectAlphaScale));
    const rgb = this.dark ? 0x3A302C : 0xFFFFFF;
    return `#${toHex2(Math.round(alpha * 255))}${toHex6(rgb)}`;
  }

  get tint(): string { return paletteColor(this.palette, this.dark); }

  get rim(): string { return this.dark ? lighten(this.tint, 0.25) : '#FFFFFFFF'; }

  get causticColors(): string[] {
    return this.dark
      ? [this.tint, lighten(this.tint, 0.45), darken(this.tint, 0.12), lighten(this.tint, 0.45)]
      : ['#FFFFB8D2', '#FFFFD9B0', '#FFFFF4B8', '#FFC9F2DD', '#FFBFD9FF', '#FFDCC8FF'];
  }
}

function palettePill(p: Palette, dark: boolean): [string, string] {
  switch (p) {
    case Palette.ROSE: return dark ? ['#FFA88D8C', '#FF8C716F'] : ['#FFAB8689', '#FF946D71'];
    case Palette.OCEAN: return dark ? ['#FF6F8FAE', '#FF587894'] : ['#FF7892AD', '#FF5C7A9B'];
    case Palette.SAGE: return dark ? ['#FF7F9984', '#FF66806B'] : ['#FF7F9583', '#FF647D69'];
    case Palette.LAVENDER: return dark ? ['#FF8F7FA8', '#FF75668D'] : ['#FF9A88B3', '#FF816EA0'];
    case Palette.AMBER: return dark ? ['#FFA88B63', '#FF8C714D'] : ['#FFA78B60', '#FF927242'];
    case Palette.GRAPHITE: return dark ? ['#FF7E848D', '#FF666C75'] : ['#FF8B9099', '#FF717781'];
    default: return dark ? ['#FFA88D8C', '#FF8C716F'] : ['#FFAB8689', '#FF946D71'];
  }
}

function paletteColor(p: Palette, dark: boolean): string {
  switch (p) {
    case Palette.ROSE: return dark ? '#FFE69687' : '#FF91453D';
    case Palette.OCEAN: return dark ? '#FF70BAF0' : '#FF2966A6';
    case Palette.SAGE: return dark ? '#FF9CC7A1' : '#FF477554';
    case Palette.LAVENDER: return dark ? '#FFC2A8F0' : '#FF7554A6';
    case Palette.AMBER: return dark ? '#FFF0BF6B' : '#FF96611F';
    case Palette.GRAPHITE: return dark ? '#FFC2CCD9' : '#FF525E6E';
    default: return dark ? '#FFE69687' : '#FF91453D';
  }
}

export function lighten(color: string, amount: number): string {
  const c = parseInt(color.substring(1), 16);
  const a = (c >> 24) & 0xFF;
  const r = clamp(Math.round(((c >> 16) & 0xFF) + (255 - ((c >> 16) & 0xFF)) * amount));
  const g = clamp(Math.round(((c >> 8) & 0xFF) + (255 - ((c >> 8) & 0xFF)) * amount));
  const b = clamp(Math.round((c & 0xFF) + (255 - (c & 0xFF)) * amount));
  return `#${toHex2(a)}${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
}

export function darken(color: string, amount: number): string {
  const c = parseInt(color.substring(1), 16);
  const a = (c >> 24) & 0xFF;
  const r = clamp(Math.round(((c >> 16) & 0xFF) * (1 - amount)));
  const g = clamp(Math.round(((c >> 8) & 0xFF) * (1 - amount)));
  const b = clamp(Math.round((c & 0xFF) * (1 - amount)));
  return `#${toHex2(a)}${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
}

export function withAlpha(color: string, alpha: number): string {
  const c = parseInt(color.substring(1), 16) & 0x00FFFFFF;
  const a = clamp(Math.round(Math.min(1, Math.max(0, alpha)) * 255));
  return `#${toHex2(a)}${toHex6(c)}`;
}

export function parseColor(text: string | undefined | null): string | null {
  if (text === undefined || text === null || !text.startsWith('#')) return null;
  const hex = text.substring(1);
  if (!/^[0-9a-fA-F]+$/.test(hex)) return null;
  if (hex.length === 6) return '#FF' + hex.toUpperCase();
  if (hex.length === 8) return '#' + hex.toUpperCase();
  return null;
}

function clamp(v: number): number { return v < 0 ? 0 : (v > 255 ? 255 : v); }
function toHex2(v: number): string { return v.toString(16).padStart(2, '0').toUpperCase(); }
function toHex6(v: number): string { return v.toString(16).padStart(6, '0').toUpperCase(); }

/** 单个 ASCII 字母是否小写（对照 Android Char.isLowerCase）。 */
export function isLowercase(c: string): boolean {
  return c.length === 1 && c >= 'a' && c <= 'z';
}

/** 界面文案（简体/繁体双脚本）。 */
export class Words {
  readonly simplified: boolean;
  constructor(simplified: boolean) { this.simplified = simplified; }
  pick(traditional: string, simplifiedText: string): string {
    return this.simplified ? simplifiedText : traditional;
  }
}