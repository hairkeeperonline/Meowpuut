/**
 * 【round 66】多设备形态纵向架构。
 *
 * 产品边界（用户拍板 2026-11-17）：
 *   - 手表 XS 场景明确排除（IME 不存在于穿戴，宽度 <600vp 一律按手机档兜底）；
 *   - 分屏按窗口适配——断点输入源是「窗口/面板宽 vp」而非显示宽，分屏收窄后
 *     自动降档（平板分到 500vp 窗口 → 手机版式铺满）；
 *   - PC/2in1（XL）预留：暂映射平板居中岛，形态位与 spec 表已留好，未来
 *     加 DeviceForm.PC 时只改 L1 表 + L3 映射，消费方零改动。
 *
 * 纵向四层（上层声明、下层消费，新增形态=加一行 spec）：
 *   L1 形态注册表 FORM_SPECS  ——「世界上有哪些形态」：声明式 spec；
 *   L2 断点解析 resolveForm   ——「当前窗口是什么形态」：窗口宽+屏高 → FormSpec；
 *   L3 布局求解 LayoutSolution ——「这个形态怎么摆」：岛宽/居中偏移/兼容 Idiom；
 *   L4 消费方                 —— MeowpuutAbility（面板高度）与
 *                                MeowpuutKeyboard（绘制/命中/a11y）从同一解取数，
 *                                两侧几何永不脱节（都调 LayoutSolution.solve）。
 *
 * 尺寸输入口径（不对称，刻意为之）：
 *   宽 = 窗口/面板宽 vp（分屏敏感；keyboard 侧来自 onAreaChange 的实际宽）；
 *   高 = 整块屏幕高 vp（横屏判定用；键盘自身高恒 <500vp，不可作判据）。
 *
 * 断点阈值对齐官方推荐区间（sm/md/lg/xl），交叉来源：SegmentFault 实战文
 * 《HarmonyOS 折叠屏与鸿蒙电脑适配》+ InfoQ《多端自适应实战》，华为官方文档
 * 站为 JS 渲染 SPA 无法抓取正文，但两篇独立来源数值一致。
 */
import { Idiom } from './Geometry';

/** 横向断点（XS(0,320)=手表已按产品决策排除，不设枚举位）。 */
export enum Breakpoint {
  /** [320, 600) 直板机；折叠屏窄展开（如 Pura X 440vp）也在此档。 */
  SM,
  /** [600, 840) 折叠展开/横屏手机。 */
  MD,
  /** [840, 1440) 平板/大折叠。 */
  LG,
  /** [1440, ∞) PC/2in1（预留：暂映射平板策略）。 */
  XL,
}

/** 断点宽度阈值（vp）。 */
export class BpWidths {
  static readonly MD_MIN: number = 600;
  static readonly LG_MIN: number = 840;
  static readonly XL_MIN: number = 1440;
}

/**
 * 设备形态。这是「渲染语义」的形态（横屏是独立形态，因为版式完全不同）；
 * 未来 PC 形态加入时在此追加 PC 成员，L1 表加一行即可。
 */
export enum DeviceForm {
  PHONE,
  PHONE_LANDSCAPE,
  FOLD,
  TABLET,
}

/** L1：形态声明。supported=false 表示预留位（当前走映射兜底）。 */
export class FormSpec {
  readonly form: DeviceForm;
  /** 内容岛最大宽（vp）；Infinity = 铺满窗口（手机/横屏）。 */
  readonly islandMaxW: number;
  readonly supported: boolean;
  readonly note: string;

  constructor(form: DeviceForm, islandMaxW: number, supported: boolean, note: string) {
    this.form = form;
    this.islandMaxW = islandMaxW;
    this.supported = supported;
    this.note = note;
  }
}

/** L1：形态注册表。新增/调整形态只改这里。 */
export class FormSpecs {
  /** 直板机：铺满窗口（Pura X 440vp 折叠展开也走此档，零回归）。 */
  static readonly PHONE: FormSpec =
    new FormSpec(DeviceForm.PHONE, Number.POSITIVE_INFINITY, true, '铺满窗口');
  /** 横屏紧凑：高度放不下竖排版式（候选栏+4~5 行键），铺满窗口。 */
  static readonly PHONE_LANDSCAPE: FormSpec =
    new FormSpec(DeviceForm.PHONE_LANDSCAPE, Number.POSITIVE_INFINITY, true, '铺满窗口（紧凑高度）');
  /** 折叠展开（MD 600–840vp）：600vp 居中岛，两侧只铺底色渐变。 */
  static readonly FOLD: FormSpec =
    new FormSpec(DeviceForm.FOLD, 600, true, '折叠展开：600vp 居中岛');
  /** 平板/大折叠（LG 840–1440vp）：640vp 居中岛。 */
  static readonly TABLET: FormSpec =
    new FormSpec(DeviceForm.TABLET, 640, true, '平板/大折叠：640vp 居中岛');
  /** PC/2in1（XL ≥1440vp）预留位：暂映射平板岛（用户决策「PC 暂不支持」）。 */
  static readonly TABLET_XL: FormSpec =
    new FormSpec(DeviceForm.TABLET, 640, false, 'PC/2in1 预留：暂映射平板岛');
}

/** L2：窗口宽 → 断点。 */
export function breakpointOf(windowWidthVp: number): Breakpoint {
  if (windowWidthVp >= BpWidths.XL_MIN) return Breakpoint.XL;
  if (windowWidthVp >= BpWidths.LG_MIN) return Breakpoint.LG;
  if (windowWidthVp >= BpWidths.MD_MIN) return Breakpoint.MD;
  return Breakpoint.SM;
}

/**
 * L2：窗口宽 + 屏高 → 形态。
 * 高度优先：屏高 <500vp 放不下竖排版式 → 横屏紧凑档，不受断点影响
 * （横屏平板 1280×800 屏高 800 仍走 TABLET 岛；横屏手机 880×400 走 LANDSCAPE）。
 */
export function resolveForm(windowWidthVp: number, screenHeightVp: number): FormSpec {
  if (screenHeightVp < 500) return FormSpecs.PHONE_LANDSCAPE;
  switch (breakpointOf(windowWidthVp)) {
    case Breakpoint.MD:
      return FormSpecs.FOLD;
    case Breakpoint.LG:
      return FormSpecs.TABLET;
    case Breakpoint.XL:
      return FormSpecs.TABLET_XL;
    default:
      return FormSpecs.PHONE;
  }
}

/**
 * L3：布局解。一次求解，L4 两侧（ability 面板高度 / keyboard 绘制命中）共用。
 * 纯函数（仅算术），rebuild 每帧调用无压力。
 */
export class LayoutSolution {
  readonly spec: FormSpec;
  readonly form: DeviceForm;
  readonly bp: Breakpoint;
  /** 兼容映射：存量渲染分支按 Idiom 走，框架不推翻存量（FOLD 是新增档）。 */
  readonly idiom: Idiom;
  /** 窗口/面板宽 vp（断点输入源）。 */
  readonly panelW: number;
  /** 岛宽 = min(panelW, spec.islandMaxW)；铺满形态下 === panelW。 */
  readonly contentW: number;
  /** 岛在窗口内的居中偏移；铺满 = 0。 */
  readonly contentLeft: number;

  private constructor(spec: FormSpec, bp: Breakpoint, idiom: Idiom, panelW: number,
    contentW: number, contentLeft: number) {
    this.spec = spec;
    this.form = spec.form;
    this.bp = bp;
    this.idiom = idiom;
    this.panelW = panelW;
    this.contentW = contentW;
    this.contentLeft = contentLeft;
  }

  /** 求解入口。windowWidthVp=窗口宽（分屏敏感），screenHeightVp=整屏高（横屏判定）。 */
  static solve(windowWidthVp: number, screenHeightVp: number): LayoutSolution {
    const w = Number.isFinite(windowWidthVp) && windowWidthVp > 1 ? windowWidthVp : 320;
    const spec = resolveForm(w, screenHeightVp);
    // 岛宽不能超过窗口本身（分屏窄窗口时自动收窄到窗口宽=铺满）。
    const contentW = Math.min(w, spec.islandMaxW);
    const contentLeft = Math.max(0, (w - contentW) / 2);
    let idiom: Idiom;
    switch (spec.form) {
      case DeviceForm.PHONE_LANDSCAPE:
        idiom = Idiom.PHONE_LANDSCAPE;
        break;
      case DeviceForm.FOLD:
        idiom = Idiom.FOLD;
        break;
      case DeviceForm.TABLET:
        idiom = Idiom.TABLET;
        break;
      default:
        idiom = Idiom.PHONE;
        break;
    }
    return new LayoutSolution(spec, breakpointOf(w), idiom, w, contentW, contentLeft);
  }
}
