/**
 * 键盘 ArkUI 组件（对应 Android ime/KeyboardView.kt + KeysView.kt + CandidateBarView.kt 的合并）。
 * 用 Canvas 绘制候选栏玻璃、键盘按键与猫咪；触控交给 KeyTouches 状态机。
 */
import { Box, keyMetricsOf, keyMetricsFitted, layoutKeyGrid, Idiom, resolveIdiom,
  CandidateRegionLayout, KeyPlacement, KeyBalloon, AlternatesStrip, KeyMetrics } from './Geometry';
import { Key, KeySet, KeyIcon, KeyStyle, KeyBuilder, KeyContext, ShiftState } from './Keys';
import { KeyTouches, KeyListener, TouchHost } from './KeyTouches';
import { GlassPainter, PillPainter, roundRect, Glyphs, tracePath } from './Painting';
import { Look, withAlpha, lighten, isLowercase, Palette, GlassStrength } from './Theme';
import { GlassShape, contentBand , glassTop } from './GlassOutline';
import { CatSeats, CatStage, Cat, CatPlacement } from './CatStage';
import { CatSpriteData, CatSprite } from './CatSpriteData';
import { CatMotion, CatPose, CatAffection } from './Cats';
import { FestivalTheme, Festivals } from './Festivals';
import { Candidate, InputMode, isJapanese } from '../engine/Types';
import { KeyboardHost } from './KeyboardHost';
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class KeyboardState {
  keyboard: Look;
  keyCtx: KeyContext;
  candidates: Candidate[];
  visibleIndices: number[];
  highlighted: number;
  predictions: string[];
  punctuation: string[];
  status: string;
  expanded: boolean;
  canExpand: boolean;
  composing: boolean;
  japaneseMarks: boolean;
  /** 今日节日主题（无则 null），用于换装猫与右端饰簇。 */
  festival: FestivalTheme | null;
  constructor(keyboard: Look, keyCtx: KeyContext, candidates: Candidate[], visibleIndices: number[],
    highlighted: number, predictions: string[], punctuation: string[], status: string,
    expanded: boolean, canExpand: boolean, composing: boolean, japaneseMarks: boolean,
    festival: FestivalTheme | null = null) {
    this.keyboard = keyboard;
    this.keyCtx = keyCtx;
    this.candidates = candidates;
    this.visibleIndices = visibleIndices;
    this.highlighted = highlighted;
    this.predictions = predictions;
    this.punctuation = punctuation;
    this.status = status;
    this.expanded = expanded;
    this.canExpand = canExpand;
    this.composing = composing;
    this.japaneseMarks = japaneseMarks;
    this.festival = festival;
  }
}

/** 手机竖屏单字符键的气泡字号（对照 Android KeysView.BALLOON_FONT = 34f）。 */
const BALLOON_FONT = 34;

class BalloonEntry {
  key: Key;
  frame: Box;
  fontSize: number;
  constructor(key: Key, frame: Box, fontSize: number) {
    this.key = key;
    this.frame = frame;
    this.fontSize = fontSize;
  }
}

/**
 * 摸猫时喷发的粒子（对照 Android CandidateBarView.Particle）。
 * kind: 0=heart 1=paw 2=note 3=sparkle。
 */
class Particle {
  cat: Cat;
  kind: number;
  start: number;
  span: number;
  size: number;
  drift: number;
  color: string;
  constructor(cat: Cat, kind: number, start: number, span: number,
    size: number, drift: number, color: string) {
    this.cat = cat;
    this.kind = kind;
    this.start = start;
    this.span = span;
    this.size = size;
    this.drift = drift;
    this.color = color;
  }
}

class AlternatesState {
  strip: AlternatesStrip;
  options: string[];
  selected: number;
  constructor(strip: AlternatesStrip, options: string[], selected: number) {
    this.strip = strip;
    this.options = options;
    this.selected = selected;
  }
}

/** 【剪贴板芯片 round 61】预测行首位「粘贴」芯片的文案。 */
const CLIPBOARD_PASTE_LABEL: string = '粘贴';

class KeyboardTouchHost implements TouchHost {
  private kb: MeowpuutKeyboard;
  constructor(kb: MeowpuutKeyboard) { this.kb = kb; }
  post(delayMs: number, action: () => void): number {
    const id = ++this.kb.timerCounter;
    this.kb.timers.set(id, setTimeout(() => { this.kb.timers.delete(id); action(); }, delayMs));
    return id;
  }
  cancel(id: number): void {
    const t = this.kb.timers.get(id);
    if (t !== undefined) { clearTimeout(t); this.kb.timers.delete(id); }
  }
  showBalloon(id: number, key: Key, frame: Box): void {
    // 按键气泡开关（对应 Android keyPopups）：关闭时不弹预览气泡。
    if (!this.kb.keyPopupsEnabled()) return;
    // 字号分支在 struct 的 balloonFont 里算（平板返回 null 不弹气泡），
    // 对照 Android KeysView.showBalloon L222-228。
    const size = this.kb.balloonFont(key);
    if (size === null) return;
    this.kb.balloons.set(id, new BalloonEntry(key, frame, size));
  }
  hideBalloon(id: number): void {
    this.kb.balloons.delete(id);
  }
  showAlternates(strip: AlternatesStrip, options: string[], selected: number): void {
    this.kb.alternates = new AlternatesState(strip, options, selected);
  }
  selectAlternate(index: number): void {
    if (this.kb.alternates !== null) this.kb.alternates.selected = index;
  }
  hideAlternates(): void {
    this.kb.alternates = null;
  }
  clearVisuals(): void {
    this.kb.balloons.clear();
    this.kb.alternates = null;
  }
  redraw(): void {
    this.kb.drawTick++;
    if (this.kb.canvasReady) {
      this.kb.drawCandidateBar();
      this.kb.drawKeys();
    }
  }
}

class KeyboardListener implements KeyListener {
  private kb: MeowpuutKeyboard;
  constructor(kb: MeowpuutKeyboard) { this.kb = kb; }
  onKeyDown(key: Key): void { this.kb.onKeyDownEvt?.(key); }
  onKey(key: Key, text: string | null): void { this.kb.onKeyEvt?.(key, text); }
  onDelete(word: boolean): void { this.kb.onDeleteEvt?.(word); }
  onShiftDown(): void { this.kb.onShiftDownEvt?.(); }
  onShiftUp(typed: boolean): void { this.kb.onShiftUpEvt?.(typed); }
  onPage(page: number): void { this.kb.onPageEvt?.(page); }
  onCursorStart(): void { this.kb.onCursorStartEvt?.(); }
  onCursorMove(steps: number): void { this.kb.onCursorMoveEvt?.(steps); }
  onCursorEnd(): void { this.kb.onCursorEndEvt?.(); }
  onTick(): void { this.kb.onTickEvt?.(); }
}

class CandidateItem {
  index: number;
  kind: number;
  text: string;
  width: number;
  japanese: boolean;
  constructor(index: number, kind: number, text: string, width: number, japanese: boolean) {
    this.index = index;
    this.kind = kind;
    this.text = text;
    this.width = width;
    this.japanese = japanese;
  }
}

/** 展开面板里的一个候选格（对应 Android ExpandedPanelView.Cell）。 */
class PanelCell {
  index: number;
  left: number;
  top: number;
  width: number;
  shown: string;
  japanese: boolean;
  constructor(index: number, left: number, top: number, width: number, shown: string, japanese: boolean) {
    this.index = index;
    this.left = left;
    this.top = top;
    this.width = width;
    this.shown = shown;
    this.japanese = japanese;
  }
}

@Component
export struct MeowpuutKeyboard {
  /** 键盘向外发送动作的回调。 */
  onKeyDownEvt?: (key: Key) => void;
  onKeyEvt?: (key: Key, text: string | null) => void;
  onDeleteEvt?: (word: boolean) => void;
  onShiftDownEvt?: () => void;
  onShiftUpEvt?: (typed: boolean) => void;
  onPageEvt?: (page: number) => void;
  onCursorStartEvt?: () => void;
  onCursorMoveEvt?: (steps: number) => void;
  onCursorEndEvt?: () => void;
  onTickEvt?: () => void;
  onCandidateEvt?: (index: number) => void;
  onPredictionEvt?: (text: string) => void;
  /** 【剪贴板 round 61】点击「粘贴」芯片：让编辑框执行系统粘贴。 */
  onPasteEvt?: () => void;
  onPunctuationEvt?: (mark: string) => void;
  onToggleExpandedEvt?: () => void;
  onPetEvt?: (cat: string) => void;
  /** 候选栏下拉收起键盘。 */
  onHideEvt?: () => void;

  private state: KeyboardState = makeEmptyState();
  private touches: KeyTouches | null = null;
  private keySet: KeySet | null = null;
  private placements: KeyPlacement[][] = [];
  private idiom: Idiom = Idiom.PHONE;
  private metrics = keyMetricsOf(Idiom.PHONE, 393, 4);
  @State private kbWidth: number = 393;
  @State private kbHeight: number = 720;
  timerCounter: number = 0;
  timers: Map<number, number> = new Map();
  private motions: Map<string, CatMotion> = new Map();
  /** 组字时猫向候选方向倾斜的进度 0~1（对照 Android animateLean，米米莫 +2.5°/莫莫 −2.5°）。 */
  private lean: number = 0;
  private leanStart: number = 0;
  private leanFrom: number = 0;
  private leanTo: number = 0;
  private lastComposing: boolean = false;
  /** 正被按着的猫（按压 squash，wide 1.06 / tall 0.93）。 */
  private pressedCats: Set<string> = new Set();
  /** 当前按下命中的猫（抬手时清除按压态）。 */
  private pressedCat: string | null = null;
  /** 摸猫喷发的粒子（对照 Android CandidateBarView.particles，上限 8）。 */
  private particles: Particle[] = [];
  canvasReady: boolean = false;
  private barSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private barCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.barSettings);
  private keySettings: RenderingContextSettings = new RenderingContextSettings(true);
  private keyCtx2d: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.keySettings);
  /** 重绘信号：@Watch 主动重画两块 Canvas（Canvas 内容不会随 @State 自动刷新）。 */
  @State @Watch('onDrawTick') drawTick: number = 0;
  private toastText: string = '';
  private toastExpires: number = 0;
  /** toast 出现时刻（对照 Android Toast.start，用于淡入/弹跳动画的 age）。 */
  private toastStart: number = 0;
  /** 摸猫进度爱心数（-1 = 无进度爱心，画单颗大爱心/不画）。 */
  private toastHearts: number = -1;
  /** 【iOS 风格增强】候选选中胶囊的滑动动画（segmented-control 式平滑过渡）。 */
  private pillFromX: number = -1;   // 动画起点（选中项内容坐标 x），-1 = 无动画
  private pillFromW: number = 0;
  private pillToX: number = -1;     // 目标（同上）
  private pillToW: number = 0;
  private pillAnimStart: number = 0;
  /** 上一帧实画的胶囊位置（内容坐标）；-1 = 还没画过。 */
  private pillDrawnX: number = -1;
  private pillDrawnW: number = 0;
  private static readonly PILL_SLIDE_MS = 150;

  /** 摸猫提示是否 emphasis（简繁切换成功的醒目强调）。 */
  private toastEmphasis: boolean = false;
  /**
   * 候选行横向滚动（对应 Android CandidateBarView 的 scroll / OverScroller）。
   * 候选往往有几十个，可视宽度只放得下两三个，必须能横向拖。
   */
  private barScroll: number = 0;
  private barMaxScroll: number = 0;
  private barContentWidth: number = 0;
  private barDragId: number = -1;
  private barDownX: number = 0;
  private barDownY: number = 0;
  /** 【全键盘下拉收起】本手势周期内是否已触发收起（去抖，一次手势只收一次）。 */
  private pullDownFired: boolean = false;
  private barDownScroll: number = 0;
  private barDragging: boolean = false;
  private barVel: number = 0;
  private barLastX: number = 0;
  private barLastT: number = 0;
  private barFlingId: number = 0;
  /** 抬手时若没拖动过，就用按下点当作点击位置。 */
  private barTapX: number = 0;
  private barTapValid: boolean = false;
  balloons: Map<number, BalloonEntry> = new Map();
  alternates: AlternatesState | null = null;
  private catPixels: Map<string, image.PixelMap> = new Map();
  private catsLoading = false;
  /** 节日换装猫与右端饰簇的贴图（festivals/*.png），按文件名缓存。 */
  private festivalPixels: Map<string, image.PixelMap> = new Map();
  /** 已加载贴图对应的节日 id（去重，对照 Android festivalArt 按 theme.id 缓存）。 */
  private festivalLoadedId: string = '';
  private festivalLoading = false;
  /**
   * 候选行里刚被按下的项（-1 表示没有）。安卓在按下时会给该项叠一层浅色底
   * 并把内容缩到 0.95，抬手才提交；鸿蒙侧原先点下即提交、没有任何按下反馈。
   * 这里记录项序号，绘制时按它加反馈。
   */
  private pressedCandidate: number = -1;
  /** 按下反馈的清除定时器，避免抬手后一直停在按下态。 */
  private pressedTimer: number = -1;
  /**
   * 展开候选面板（对应 Android ExpandedPanelView）。多行网格覆盖键区，纵向滚动浏览全部候选。
   */
  private panelCells: PanelCell[] = [];
  private panelContentHeight: number = 0;
  private panelScroll: number = 0;
  private panelDragId: number = -1;
  private panelDownY: number = 0;
  private panelDownScroll: number = 0;
  private panelDragging: boolean = false;
  private panelPressed: number = -1;
  private panelVel: number = 0;
  private panelLastY: number = 0;
  private panelLastT: number = 0;

  aboutToAppear(): void {
    this.touches = new KeyTouches(this.host());
    this.touches.listener = this.listener();
    // 从 KeyboardHost 拉取状态与互动（面板生命周期内轮询）。
    // 不启动这个轮询，界面会一直停在首帧快照：打键不出候选、点候选也拿不到列表。
    this.pollHost();
    this.loadCatSprites();
  }

  /**
   * 把 8 张猫贴图从 rawfile 解码成 PixelMap，供 drawCats 直接 drawImage。
   *
   * 重做要点（此前猫完全画不出来，真机像素分析证实候选栏两端无任何猫像素）：
   *  1. 逐张加载，用 await 串行等待每个 decode 完成，不再依赖「remaining 计数 + 静默 catch」；
   *  2. 每一张都打 hilog（成功/失败 + 失败原因），杜绝「没图也查不出原因」；
   *  3. resourceManager 兜底：KeyboardHost 未注入时回退到 Ability 上下文；
   *  4. 失败后允许重试（catsLoading 不会永久卡 true），并有一次性延迟重试。
   */
  private loadCatSprites(): void {
    if (this.catsLoading) return;
    if (this.catPixels.size > 0) return; // 已加载过
    this.catsLoading = true;
    const names = [
      'mimimo_edge_rest', 'mimimo_edge_peek', 'mimimo_edge_lounge', 'mimimo_side_hold',
      'momo_edge_rest', 'momo_edge_peek', 'momo_edge_lounge', 'momo_side_hold',
    ];
    const rm = KeyboardHost.get().resourceManager;
    if (rm === null) {
      hilog.error(0x0000, 'MeowpuutCat', 'loadCatSprites: resourceManager is null, defer retry');
      this.catsLoading = false;
      // 面板刚创建时 host 可能尚未注入 resourceManager，延迟重试一次。
      setTimeout(() => { this.loadCatSprites(); }, 300);
      return;
    }
    this.decodeCats(rm, names).then((ok: number) => {
      this.catsLoading = false;
      hilog.info(0x0000, 'MeowpuutCat', `loadCatSprites done: ${ok}/${names.length} decoded`);
      if (ok > 0) this.drawTick++;
    }).catch((e: BusinessError) => {
      this.catsLoading = false;
      hilog.error(0x0000, 'MeowpuutCat', `loadCatSprites failed: ${e.code} ${e.message}`);
    });
  }

  /** 串行解码全部猫贴图，返回成功张数。失败逐张记录原因。 */
  private async decodeCats(rm: resourceManager.ResourceManager, names: string[]): Promise<number> {
    let ok = 0;
    for (const name of names) {
      try {
        const bytes = rm.getRawFileContentSync(`cats/${name}.png`);
        hilog.info(0x0000, 'MeowpuutCat', `${name}: raw ${bytes.length} bytes`);
        const source = image.createImageSource(bytes.buffer as ArrayBuffer);
        if (source === undefined) {
          hilog.error(0x0000, 'MeowpuutCat', `${name}: createImageSource returned undefined`);
          continue;
        }
        const pm = await source.createPixelMap();
        if (pm !== undefined) {
          this.catPixels.set(name, pm);
          ok++;
          const info = source.getImageInfoSync();
          hilog.info(0x0000, 'MeowpuutCat', `${name}: ok ${info.size.width}x${info.size.height}`);
        } else {
          hilog.error(0x0000, 'MeowpuutCat', `${name}: createPixelMap returned undefined`);
        }
        source.release();
      } catch (e) {
        const be = e as BusinessError;
        hilog.error(0x0000, 'MeowpuutCat', `${name}: ${be.code} ${be.message}`);
      }
    }
    return ok;
  }

  /** 按名取猫/节日贴图：先日常猫，再节日换装猫。 */
  private pixelFor(name: string): image.PixelMap | undefined {
    return this.catPixels.get(name) ?? this.festivalPixels.get(name);
  }

  /**
   * 节日换装猫 + 右端饰簇贴图（对照 Android FestivalArt.load）。
   * 已按 theme.id 去重；加载完成触发重绘。
   */
  private loadFestivalArt(theme: FestivalTheme): void {
    if (this.festivalLoading || this.festivalLoadedId === theme.id) return;
    this.festivalLoading = true;
    const names: string[] = [theme.mimimo.image, theme.momo.image];
    if (theme.right !== null) names.push(theme.right.image);
    const rm = KeyboardHost.get().resourceManager;
    if (rm === null) { this.festivalLoading = false; return; }
    let remaining = names.length;
    for (const name of names) {
      try {
        const bytes = rm.getRawFileContentSync(`festivals/${name}.png`);
        const source = image.createImageSource(bytes.buffer as ArrayBuffer);
        source.createPixelMap((err: BusinessError, pm: image.PixelMap) => {
          remaining--;
          if (err === undefined && pm !== undefined) {
            this.festivalPixels.set(name, pm);
          }
          if (remaining <= 0) {
            this.festivalLoading = false;
            this.festivalLoadedId = theme.id;
            this.drawTick++;
          }
        });
      } catch (e) {
        remaining--;
        if (remaining <= 0) {
          this.festivalLoading = false;
          this.festivalLoadedId = theme.id;
        }
      }
    }
  }

  private lastStateToken = -1;
  private lastCommitToken = -1;
  private lastPetToken = -1;
  private lastAnnounceToken = -1;

  private pollHost(): void {
    setInterval(() => {
      const host = KeyboardHost.get();
      const t = host.take();
      if (t.state !== null && t.token !== this.lastStateToken) {
        this.lastStateToken = t.token;
        this.state = t.state;
        this.rebuild();
        // state 是普通成员，改了不会自己触发重绘；drawTick 是 @State，靠它刷新。
        this.drawTick++;
      }
      const c = host.takeCommitted();
      if (c !== this.lastCommitToken) {
        this.lastCommitToken = c;
        this.committed();
      }
      const p = host.takePet();
      if (p.token !== this.lastPetToken) {
        this.lastPetToken = p.token;
        this.pet(p.cat, p.toast, p.hearts);
      }
      const a = host.takeAnnounce();
      if (a.token !== this.lastAnnounceToken) {
        this.lastAnnounceToken = a.token;
        this.announce(a.text);
      }
      // 持续推进 lean 动画与粒子，并让活跃中的短动画持续重绘。
      this.stepLean();
      this.stepParticles();
      if (this.lean !== this.leanTo || this.particles.length > 0 || Date.now() < this.toastExpires ||
        Date.now() < this.pillAnimStart + MeowpuutKeyboard.PILL_SLIDE_MS) {
        this.drawTick++;
      }
    }, 16);
  }

  private host(): TouchHost {
    return new KeyboardTouchHost(this);
  }

  private listener(): KeyListener {
    return new KeyboardListener(this);
  }

  /** 由宿主（ability）调用刷新。 */
  refresh(next: KeyboardState, resetPanel: boolean = false): void {
    // 候选行内容变化时归零横向滚动（对照 Android CandidateBarView.update 的
    // newRow → scroll=0）：否则打字加长后第一个候选被滚出屏，高亮药丸看起来
    // 不以第一个候选为中心（用户反馈第 9 条）。
    let rowChanged = false;
    if (next.visibleIndices.length !== this.state.visibleIndices.length) {
      rowChanged = true;
    } else {
      for (let i = 0; i < next.visibleIndices.length; i++) {
        const a = next.candidates[next.visibleIndices[i]];
        const b = this.state.candidates[this.state.visibleIndices[i]];
        if (a === undefined || b === undefined || a.text !== b.text) { rowChanged = true; break; }
      }
    }
    // 预测行同理（非组字态显示预测）。
    if (!rowChanged) {
      if (next.predictions.length !== this.state.predictions.length) {
        rowChanged = true;
      } else {
        for (let i = 0; i < next.predictions.length; i++) {
          if (next.predictions[i] !== this.state.predictions[i]) { rowChanged = true; break; }
        }
      }
    }
    if (rowChanged) this.barScroll = 0;
    this.state = next;
    this.rebuild();
  }

  /** 启动 lean 动画（0~1），用 320ms easeInOut，进度由 onDrawTick 的定时器推进。 */
  private animateLean(to: number): void {
    this.leanFrom = this.lean;
    this.leanTo = to;
    this.leanStart = Date.now();
    // 确保有持续重绘（下方 pollHost 每 16ms 推进一次）。
    this.drawTick++;
  }

  /** 每帧推进 lean（在重绘循环里调用）。 */
  private stepLean(): void {
    if (this.lean === this.leanTo) return;
    const t = (Date.now() - this.leanStart) / this.state.keyboard.leanDuration;
    if (t >= 1) {
      this.lean = this.leanTo;
    } else {
      const u = t * t * (3 - 2 * t);
      this.lean = this.leanFrom + (this.leanTo - this.leanFrom) * u;
    }
  }

  /**
   * 【iOS 风格】选中胶囊滑动插值。toX 是本次的目标（内容坐标），
   * 返回 [插值x, 插值w]；动画未激活返回 null。
   * 触发时机：上次绘制的胶囊位置有效、且与本次目标都来自「候选列表态」
   * （同为 kind=0 的选中项）时，从上次实画位置滑到新位置。
   */
  private pillSlideX(toX: number, toW: number): [number, number] | null {
    const now = Date.now();
    let animating = now < this.pillAnimStart + MeowpuutKeyboard.PILL_SLIDE_MS;
    let fromX = this.pillDrawnX;   // 上一次实画的 x（可能本身就是插值帧）
    let fromW = this.pillDrawnW;
    // 动画进行中目标变了（快速连续打字候选重排）：立刻把动画「接」到新目标上，
    // 从当前插值位置重启 —— 否则旧动画继续跑、胶囊短暂停在旧目标，观感是
    // 高亮底色偶尔不在第一个候选上（用户反馈「快打时底色不以第一个字符为中心」）。
    if (animating && (Math.abs(toX - this.pillToX) > 0.5 || Math.abs(toW - this.pillToW) > 0.5)) {
      this.pillFromX = fromX;
      this.pillFromW = fromW;
      this.pillToX = toX;
      this.pillToW = toW;
      this.pillAnimStart = now;
    }
    if (!animating) {
      if (fromX < 0 || Math.abs(toX - fromX) > this.kbWidth) {
        // 首次出现 / 列表大变（新组字）：不滑，直接就位。
        this.pillDrawnX = toX; this.pillDrawnW = toW;
        this.pillToX = toX; this.pillToW = toW;
        this.pillAnimStart = 0;
        return null;
      }
      if (Math.abs(toX - fromX) < 0.5 && Math.abs(toW - fromW) < 0.5) {
        this.pillDrawnX = toX; this.pillDrawnW = toW;
        return null;
      }
      // 启动新滑动
      this.pillFromX = fromX; this.pillFromW = fromW;
      this.pillToX = toX; this.pillToW = toW;
      this.pillAnimStart = now;
    }
    const t = Math.min(1, (now - this.pillAnimStart) / MeowpuutKeyboard.PILL_SLIDE_MS);
    const ease = 1 - Math.pow(1 - t, 3);   // easeOutCubic
    const x = this.pillFromX + (this.pillToX - this.pillFromX) * ease;
    const w = this.pillFromW + (this.pillToW - this.pillFromW) * ease;
    this.pillDrawnX = x; this.pillDrawnW = w;
    return [x, w];
  }

  committed(): void {
    this.motions.set('mimimo', new CatMotion(Cat.MIMIMO, Date.now(), this.motionTimeScale()));
  }

  /** drawTick 变了就重画。Canvas 的绘制指令不会因为 @State 变化自己重放。 */
  private onDrawTick(): void {
    if (this.canvasReady) this.drawCandidateBar();
    this.drawKeys();
  }

  /**
   * 动效时长时间缩放（对照 Android CandidateBarView.kt:760-764 的 timeScale()）：
   * Android 读系统 Settings.Global.ANIMATOR_DURATION_SCALE，鸿蒙该常量 API21 已废弃且无现代等价，
   * 改用应用内 effects 档位代理——lightweight（轻量/减少动效）→ 0（瞬时完成），其余 → 1。
   */
  private motionTimeScale(): number {
    return this.state.keyboard.effects === 'lightweight' ? 0 : 1;
  }

  /** 播放摸猫动作并显示提示；简繁切换的计数与状态由 ability 负责。 */
  pet(catName: string, toast: string, hearts: number = -1): void {
    // 猫名与 Cat 枚举严格对应：'mimimo'（黑猫 米米莫）/ 'momo'（橘猫 莫莫）。
    // 注意不能用 'mimo' 之类近似匹配——onPet 派发用的就是 'mimimo'（见 pointer 命中处）。
    const cat = catName === 'momo' ? Cat.MOMO : Cat.MIMIMO;
    const timeScale = this.motionTimeScale();
    this.motions.set(catName, new CatMotion(cat, Date.now(), timeScale));
    // 【真机反馈 round 63】空文案且无爱心进度时不弹 toast：米米莫每次、莫莫第 1 下
    // 都走到这里（对照 Android CandidateBarView.kt:722 拍第 1 下不出提示），此前
    // 照样启动计时器，drawToast 会画出 48×30 的空深色胶囊——候选栏中央的「黑点」。
    // 空内容时也不动正在显示的进度 toast：先摸莫莫再立刻摸米米莫，进度提示不被打断。
    if (toast.length > 0 || hearts >= 0) {
      this.toastText = toast;
      this.toastHearts = hearts;
      this.toastEmphasis = hearts < 0 && toast.length > 0;
      // 时长对照 Android Toast.duration：emphasis 2400ms，否则 1400ms。
      this.toastStart = Date.now();
      this.toastExpires = this.toastStart + (this.toastEmphasis ? 2400 : 1400);
    }
    // 简繁切换/提示的语音播报（对应 Android onPet 里的 bar.announce）。
    if (toast.length > 0) this.announceAccessibility(toast);
    // 摸猫喷粒子（对照 Android CandidateBarView.pet）：
    // 米米莫喷爪/音符/星（金黄，向右），莫莫喷心（粉，向左）。
    // 轻量动效档位下不喷粒子（对照 Android motionEnabled 守卫）。
    if (timeScale > 0) {
      if (cat === Cat.MIMIMO) {
        const kind = 1 + Math.floor(Math.random() * 3); // 1=paw 2=note 3=sparkle
        this.emit(cat, kind, 10, (4 + Math.random() * 6), '#FFDBA83D');
      } else {
        this.emit(cat, 0, 9, -(4 + Math.random() * 6), '#FFF2738C');
      }
    }
    this.drawTick++;
  }

  /** 追加粒子，上限 8（对照 Android emit）。 */
  private emit(cat: Cat, kind: number, size: number, drift: number, color: string): void {
    this.particles.push(new Particle(cat, kind, Date.now(), 900, size, drift, color));
    while (this.particles.length > 8) this.particles.shift();
  }

  /** 每帧清理过期粒子（在重绘循环里调用）。 */
  private stepParticles(): void {
    if (this.particles.length === 0) return;
    const now = Date.now();
    this.particles = this.particles.filter((p) => now - p.start < p.span);
  }

  announce(text: string): void {
    this.toastText = text;
    // announce 是简繁切换/提示，emphasis=true、无进度爱心（对照 Android CandidateBarView L740）。
    this.toastHearts = -1;
    this.toastEmphasis = true;
    this.toastStart = Date.now();
    this.toastExpires = this.toastStart + 2400;
    this.announceAccessibility(text);
    this.drawTick++;
  }

  /**
   * 无障碍语音播报（对应 Android CandidateBarView.announce → announceForAccessibility）。
   * 视力障碍用户听不到视觉 toast，这里补上 TalkBack 朗读。屏幕阅读器未开启时事件静默无效。
   */
  private announceAccessibility(text: string): void {
    if (text.length === 0) return;
    try {
      if (!accessibility.isScreenReaderOpenSync()) return;
      const event: accessibility.EventInfo = {
        type: 'announceForAccessibility',
        bundleName: 'com.krysta1ll.meowpuut.ohos',
        triggerAction: 'click',
        textAnnouncedForAccessibility: text,
      };
      accessibility.sendAccessibilityEvent(event).catch(() => {});
    } catch (e) {
      // 无障碍服务不可用（未授权/未开启）时忽略，不影响主流程。
    }
  }

  private rebuild(): void {
    const ctx = this.state.keyCtx;
    // 组字状态变化时，猫向候选方向倾斜（对照 Android animateLean，320ms 缓动）。
    if (this.state.composing !== this.lastComposing) {
      this.lastComposing = this.state.composing;
      this.animateLean(this.state.composing ? 1 : 0);
    }
    // resolveIdiom 的签名是 (屏幕高度, 最小宽度)。这里键盘宽度就是最小宽度，
    // 屏幕高度必须取整块屏幕，否则键盘自身高度 370 < 500 会被误判成横屏。
    this.idiom = resolveIdiom(this.screenHeightDp(), this.kbWidth);
    // 键盘行数：注音 5 行，其余 4 行。切换页高不跳（用 5 行定高）。
    const baseRows = ctx.mode === InputMode.ZHUYIN && !ctx.english ? 5 : 4;
    const keySet = KeyBuilder.build(ctx);
    const rows = keySet.rows.length;
    this.keySet = keySet;
    this.metrics = keyMetricsFitted(this.idiom, this.kbWidth, rows, baseRows);
    // 键盘高度（对应 Android keyboardHeight）：对 natural 键高应用缩放，
    // 使 short/tall 档位在 panel 高度之外也真实改变键帽大小。
    const scale = this.state.keyboard.heightScale;
    if (scale !== 1.0) {
      const m = this.metrics;
      this.metrics = new KeyMetrics(m.sideMargin, m.keyGap, Math.max(1, Math.round(m.keyHeight * scale)),
        m.rowGap, m.topPadding, m.bottomPadding, m.cornerRadius, m.letterFont, m.utilityFont);
    }
    this.placements = layoutKeyGrid(keySet.specs, this.kbWidth, keySet.referenceColumns, this.metrics);
    this.touches?.layout(keySet, this.placements, this.kbWidth, true);
    // rebuild 会把 metrics 重置成固定键高，这里立刻补一次撑满，否则轮询刷新后面板底部又出现死区。
    this.drawTick++;
  }

  /** 整块屏幕的高度（vp），用于判定手机/平板/横屏形态。 */
  private screenHeightDp(): number {
    try {
      const disp = display.getDefaultDisplaySync();
      const density = disp.densityDPI / 160;
      return disp.height / density;
    } catch (e) {
      // 取不到显示信息时按手机竖屏处理。
      return 800;
    }
  }

  /**
   * 屏幕像素密度（vp→px 倍数）。CanvasRenderingContext2D.drawImage 对 PixelMap 的
   * 目标矩形按物理像素解释（真机实测：64vp 猫帧画出来只有 64px，恰为 1/density），
   * 而路径/文字仍按 vp。所有 drawImage(PixelMap) 的目标坐标须乘该倍数折算。
   */
  private pxRatio(): number {
    try {
      const disp = display.getDefaultDisplaySync();
      return disp.densityDPI / 160;
    } catch (e) {
      return 3;
    }
  }

  /**
   * 按面板剩余空间分配键高。
   * 面板高度是系统给的固定值，键高若不跟着撑开，键盘底部会留一条点不到的死区。
   */
  private fitKeysToPanel(): void {
    if (this.keySet === null) return;
    const remain = this.kbHeight - this.keyboardRegionHeight();
    const natural = this.keysAreaHeight();
    if (!Number.isFinite(remain) || remain <= natural + 1) return;
    const rows = this.keySet.rows.length;
    const m = this.metrics;
    const gaps = Math.max(0, rows - 1) * m.rowGap;
    const usable = remain - m.topPadding - m.bottomPadding - gaps;
    if (usable <= rows) return;
    const keyHeight = Math.floor(usable / rows);
    if (keyHeight <= m.keyHeight) return;
    this.metrics = new KeyMetrics(m.sideMargin, m.keyGap, keyHeight, m.rowGap,
      m.topPadding, m.bottomPadding, m.cornerRadius, m.letterFont, m.utilityFont);
    this.placements = layoutKeyGrid(this.keySet.specs, this.kbWidth, this.keySet.referenceColumns, this.metrics);
    this.touches?.layout(this.keySet, this.placements, this.kbWidth, true);
  }

  private keysAreaHeight(): number {
    const m = this.metrics;
    // 首帧 rebuild() 尚未执行时 keySet 仍是 null。这里必须回退到按模式推算的
    // 行数，否则 this.keySet!.rows 会抛 TypeError，导致输入法进程反复崩溃。
    const ctx = this.state.keyCtx;
    const baseRows = ctx.mode === InputMode.ZHUYIN && !ctx.english ? 5 : 4;
    const rows = this.keySet !== null ? this.keySet.rows.length : baseRows;
    return m.topPadding + rows * m.keyHeight +
      Math.max(0, rows - 1) * m.rowGap + m.bottomPadding;
  }

  private keyboardRegionHeight(): number {
    const region = new CandidateRegionLayout(this.kbWidth, this.idiom, this.state.keyboard.cats);
    return region.height;
  }

  build(): void {
    Column() {
      // 候选栏（玻璃 + 猫咪 + 候选行）。
      Canvas(this.barCtx)
        .width('100%')
        .height(this.keyboardRegionHeight())
        .onReady(() => {
          this.canvasReady = true;
          this.drawCandidateBar();
        })
        .onTouch((event: TouchEvent) => {
          this.handleBarTouch(event);
        })

      // 键盘按键：用 layoutWeight 撑满候选栏之外的剩余空间，
      // 否则固定键高会在面板底部留一条点不到的死区。
      Canvas(this.keyCtx2d)
        .width('100%')
        .layoutWeight(1)
        .onReady(() => {
          this.drawKeys();
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
    }
    .width('100%')
    // 无障碍基础落地：整块键盘对屏幕阅读器可识别。逐键虚拟节点
    // （对应 Android VirtualAccessibility）需叠加透明语义层 + 真机 TalkBack
    // 验证，见 PARITY.md。
    .accessibilityGroup(true)
    .accessibilityText('喵扑输入键盘')
    // 【全键盘下拉收起】（真机反馈 round 60-5）：手指没按在按键上时，竖向
    // 下拉超过 56vp 即收起键盘 —— 不再局限于候选栏（原来区域小很难选中）。
    // 起点在按键上（含字符键、删除、空格等）不触发；展开面板滚动态不触发。
    .gesture(
      PanGesture({ fingers: 1, distance: 8, direction: PanDirection.Vertical })
        .onActionStart(() => {
          this.pullDownFired = false;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.pullDownFired || this.state.expanded) return;
          if (this.touches !== null && this.touches.anyPointerOnKey()) return;
          if (event.offsetY > 56) {
            this.pullDownFired = true;
            this.onHideEvt?.();
          }
        })
    )
    // 底色取渐变终点，避免和 Canvas 的键盘背景渐变叠成一层平色。
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w = newArea.width as number;
      const h = newArea.height as number;
      if (Math.abs(w - this.kbWidth) > 1 || Math.abs(h - this.kbHeight) > 1) {
        this.kbWidth = w;
        this.kbHeight = h;
        this.rebuild();
        // 面板尺寸确定后，把键高撑满剩余空间，消除底部死区。
        this.drawTick++;
      }
    })
  }

  // ---------------------------------------------------------------- 触控

  private handleTouch(event: TouchEvent): void {
    if (this.touches === null) return;
    // 展开面板覆盖键区时，键区触控全部交给面板（点候选 + 纵向滚动）。
    if (this.state.expanded && this.state.composing) {
      this.handlePanelTouch(event);
      return;
    }
    for (const change of event.changedTouches) {
      const x = change.x;
      const y = change.y;
      if (change.type === TouchType.Down) {
        this.touches.down(change.id, x, y);
      } else if (change.type === TouchType.Move) {
        this.touches.move(change.id, x, y);
      } else if (change.type === TouchType.Up || change.type === TouchType.Cancel) {
        this.touches.up(change.id, x, y);
      }
    }
  }

  /** 候选栏触控：优先命中箭头与候选词，其次才是摸猫。 */
  private handleBarTouch(event: TouchEvent): void {
    for (const change of event.changedTouches) {
      if (change.type === TouchType.Move) { this.barMove(change.id, change.x, change.y); continue; }
      if (change.type === TouchType.Up || change.type === TouchType.Cancel) {
        this.barRelease(change.id);
        // 抬手清除猫的按压态（squash 只按着时生效）。
        if (this.pressedCat !== null) {
          this.pressedCats.delete(this.pressedCat);
          this.pressedCat = null;
          this.drawTick++;
        }
        continue;
      }
      if (change.type !== TouchType.Down) continue;
      const look = this.state.keyboard;
      const region = new CandidateRegionLayout(this.kbWidth, this.idiom, look.cats);
      const x = change.x;
      const y = change.y;

      // 1.【对齐 Android CandidateBarView.onTouchEvent 命中顺序】猫优先于箭头/候选行：
      //   「A cat answers on its picture above the glass; the expand key and the
      //    candidates keep what is theirs.」——先按座位 touch 框找猫，但点在箭头区
      //   （y 在箭头上沿以下）或候选胶囊区（x 在行内且 y 在胶囊顶以下）时让位。
      const chevron = region.chevron;
      const onArrow = chevron !== null &&
        x >= chevron.left - 6 && x <= chevron.left + chevron.width + 6;
      const onRow = x >= region.row.left && x <= region.row.left + region.row.width;
      const rowCenterY = region.row.top + region.row.height / 2;
      const candidatesTop = rowCenterY - region.pillHeight / 2;
      const seats = this.seats(region, look);
      const stage = this.stage(region, look.shape);
      let pet: CatPlacement | null = null;
      for (const seat of seats) {
        const t = seat.touch(stage);
        if (x >= t.left && x < t.left + t.width && y >= t.top && y < t.top + t.height) {
          const yields = (onArrow && chevron !== null && y >= chevron.top) ||
            (onRow && y >= candidatesTop);
          if (!yields) { pet = seat; break; }
        }
      }
      if (pet !== null) {
        const catName = pet.cat === Cat.MIMIMO ? 'mimimo' : 'momo';
        this.pressedCat = catName;
        this.pressedCats.add(catName);
        this.drawTick++;
        this.onPetEvt?.(catName);
        return;
      }

      // 2. 展开箭头（对应 Android CandidateBarView.kt:626-634 的排他判定）。
      if (chevron !== null) {
        const c = chevron;
        if (x >= c.left && x < c.left + c.width && y >= c.top && y < c.top + c.height) {
          this.onToggleExpandedEvt?.();
          return;
        }
      }

      // 3. 候选行。按下只是开始，抬手时才决定是点击还是拖动
      //    （候选多的时候要能横向拖，见 barPress/barMove/barRelease）。
      if (y >= region.row.top && y < region.row.top + region.row.height) {
        this.barPress(change.id, x, y);
        return;
      }
    }
  }

  /**
   * 候选行按下。候选往往有几十个，可视宽度只放得下两三个，
   * 所以要能横向拖：按下先记位置，抬手时再决定是点击还是拖动
   * （对应 Android CandidateBarView 的 downX / downScroll / scroll 状态机）。
   */
  private barPress(id: number, x: number, y: number): void {
    this.barFlingStop();
    this.barDragId = id;
    this.barDownX = x;
    this.barDownY = y;
    this.barDownScroll = this.barScroll;
    this.barDragging = false;
    this.barLastX = x;
    this.barLastT = Date.now();
    this.barVel = 0;
    this.barTapX = x;
    this.barTapValid = true;
  }

  /** 候选行拖动中。 */
  private barMove(id: number, x: number, y: number = 0): void {
    if (this.barDragId !== id) return;
    const dx = x - this.barDownX;
    // 【候选栏下拉收起】纵向下拉超过 64px 且纵向位移大于横向（横向是滚动候选），
    // 收起键盘（对照 iOS 键盘候选栏下拉 hide；鸿蒙增强）。
    const dy = y - this.barDownY;
    if (dy > 64 && dy > Math.abs(dx) * 1.5) {
      this.barDragId = -1;
      this.barTapValid = false;
      this.onHideEvt?.();
      return;
    }
    if (!this.barDragging && Math.abs(dx) > 8) this.barDragging = true;
    if (!this.barDragging) return;
    this.barTapValid = false;
    const now = Date.now();
    const dt = now - this.barLastT;
    if (dt > 0) {
      // 手指左滑 -> 内容左移 -> 滚动量增大，所以取负号。
      const v = -(x - this.barLastX) / dt;
      this.barVel = this.barVel * 0.6 + v * 0.4;
    }
    this.barLastX = x;
    this.barLastT = now;
    this.barScroll = Math.min(this.barMaxScroll, Math.max(0, this.barDownScroll - dx));
    this.drawTick++;
  }

  /** 候选行抬手：没拖动就当点击，拖过就交给惯性。 */
  private barRelease(id: number): void {
    if (this.barDragId !== id) return;
    this.barDragId = -1;
    if (this.barDragging) {
      this.barFlingStart();
      this.barTapValid = false;
      return;
    }
    if (this.barTapValid) {
      this.barTapValid = false;
      const region = new CandidateRegionLayout(this.kbWidth, this.idiom, this.state.keyboard.cats);
      this.hitCandidate(region, this.barTapX);
    }
  }

  /** 惯性滑动：按速度衰减推进滚动量，直到停下（对应 OverScroller.fling）。 */
  private barFlingStart(): void {
    if (Math.abs(this.barVel) < 0.05 || this.barMaxScroll <= 0) return;
    this.barFlingId++;
    const token = this.barFlingId;
    const step = (): void => {
      if (token !== this.barFlingId) return;
      this.barVel *= 0.92;
      this.barScroll = Math.min(this.barMaxScroll, Math.max(0, this.barScroll + this.barVel * 16));
      this.drawTick++;
      if (Math.abs(this.barVel) > 0.01 && this.barScroll > 0 && this.barScroll < this.barMaxScroll) {
        setTimeout(step, 16);
      }
    };
    setTimeout(step, 16);
  }

  private barFlingStop(): void {
    this.barFlingId++;
  }

  /** 记一次按下反馈：先亮出按下态，约一帧后再提交，这样用户能看到形变。 */
  private flashPress(n: number, commit: () => void): void {    this.pressedCandidate = n;
    if (this.pressedTimer >= 0) { clearTimeout(this.pressedTimer); this.pressedTimer = -1; }
    this.drawTick++;
    this.pressedTimer = setTimeout(() => {
      this.pressedCandidate = -1;
      this.pressedTimer = -1;
      this.drawTick++;
      commit();
    }, 70) as number;
  }

  /** 命中候选/预测/标点，返回是否已消费。逐项复刻 drawRow 的排布，避免点错。 */
  private hitCandidate(region: CandidateRegionLayout, x: number): boolean {
    const st = this.state;
    const row = region.row;
    const font = region.fontSize;
    const gap = 6;
    const maxText = region.maximumCandidateWidth - 24;
    const ctx = this.barCtx;
    // 与 drawRow 一致：宽度依赖实测文本尺寸（显式设定字体，不依赖上一帧残留）。
    ctx.font = `${font}vp sans-serif`;

    let cx = row.left + 4 - this.barScroll;
    // items0 是候选行的项序号（与 drawRow 里 items 的下标一致，预测/标点接着排）。
    let items0 = 0;
    const hit = (w: number): boolean => x >= cx && x < cx + w;

    if (st.candidates.length > 0) {
      for (const i of st.visibleIndices) {
        const c = st.candidates[i];
        if (c === undefined) continue;
        const japanese = c.kind === 'JAPANESE_WORD' || c.kind === 'MIXED' ||
          c.kind === 'MIXED_PREFIX' || c.kind === 'KANA';
        const mark = japanese && st.japaneseMarks ? font * 0.45 + 3 : 0;
        const measured = ctx.measureText(c.text).width;
        const shown = measured > maxText - mark ? truncateMiddle(c.text, ctx, maxText - mark) : c.text;
        const width = Math.max(region.pillHeight, ctx.measureText(shown).width + 24 + mark);
        if (hit(width)) {
          const index = i;
          this.flashPress(items0, () => this.onCandidateEvt?.(index));
          return true;
        }
        items0++;
        cx += width + gap;
      }
    } else if (st.predictions.length > 0) {
      // 粘贴芯片（宽度公式与 drawRow 完全一致）。
      const pasteIcon = font * 0.66;
      const pasteW = Math.max(region.pillHeight,
        ctx.measureText(CLIPBOARD_PASTE_LABEL).width + pasteIcon + 4 + 26);
      if (hit(pasteW)) {
        const index = items0;
        this.flashPress(index, () => this.onPasteEvt?.());
        return true;
      }
      items0++;
      cx += pasteW + gap;
      for (let i = 0; i < st.predictions.length; i++) {
        const text = st.predictions[i];
        const width = Math.max(region.pillHeight, ctx.measureText(text).width + 22);
        if (hit(width)) {
          const index = items0;
          this.flashPress(index, () => this.onPredictionEvt?.(text));
          return true;
        }
        items0++;
        cx += width + gap;
      }
    } else if (st.punctuation.length > 0) {
      for (let i = 0; i < st.punctuation.length; i++) {
        if (hit(34)) {
          const mark = st.punctuation[i];
          const index = items0;
          this.flashPress(index, () => this.onPunctuationEvt?.(mark));
          return true;
        }
        items0++;
        cx += 34 + 2;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- 绘制

  drawCandidateBar(): void {
    const ctx = this.barCtx;
    const w = this.kbWidth;
    const look = this.state.keyboard;
    const region = new CandidateRegionLayout(w, this.idiom, look.cats);
    const h = region.height;
    ctx.clearRect(0, 0, w, h);
    // 【真机反馈 round 60-4】字母/候选/猫咪区域背景透明：候选栏不再铺键盘底色，
    // 玻璃带与猫直接浮在输入法面板上、透出底层应用（不随深浅色变化）。
    // 键区地板渐变仍在 drawKeys 里绘制（造型轮廓在那边）。

    // 玻璃。
    GlassPainter.shadow(ctx, look.shape, region.glass, look.dark);
    GlassPainter.body(ctx, look.shape, region.glass, look);
    // 爪子在玻璃上的软阴影（对照 Android pawShadows，画进玻璃体之后）。
    if (region.cats && look.cats) {
      this.pawShadows(ctx, region, look);
    }

    // 节日：加载换装猫/饰簇贴图，然后画右端饰簇（玻璃上、猫与候选下）。
    const festival = this.state.festival;
    if (festival !== null) {
      this.loadFestivalArt(festival);
      this.drawFestivalEnd(ctx, region, look);
    }

    // 【纯净版】柔光带暂时停用：真机反馈它在候选栏上形成一块白斑观感。
    // 先确认两只猫能完整、清晰地显示出来，之后再决定是否以更淡的方式恢复。
    // this.drawLightBand(ctx, region, look);

    // 候选行。
    this.drawRow(ctx, region, look);

    // 猫咪（最上层，完整绘制不被任何东西遮挡）。
    if (region.cats && look.cats) {
      this.drawCats(ctx, region, look);
    }

    // 摸猫喷发的粒子（对照 Android drawParticles）。
    this.drawParticles(ctx, region, look);

    // 展开箭头。
    this.drawChevron(ctx, region, look);

    // Toast（摸猫提示）。
    if (Date.now() < this.toastExpires) {
      this.drawToast(ctx, region, look);
    }
  }

  /**
   * 统一的 CatStage 构造（对照 Android CandidateRegionLayout.stage）：
   * row 传 pill 带（非整行），arrow 传箭头中心小框（非整个 chevron）。
   */
  private stage(region: CandidateRegionLayout, shape: GlassShape): CatStage {
    const band = contentBand(shape, region.glass.height);
    const middle = region.glass.top + (band.low + band.high) / 2;
    const arrowWidth = CandidateRegionLayout.ARROW_WIDTH + 2;
    const arrowHeight = CandidateRegionLayout.ARROW_WIDTH / 2 + 2;
    const chevronCx = region.chevron.left + region.chevron.width / 2;
    return new CatStage(
      region.width, region.height, region.glass, shape, region.scale,
      Math.max(0, region.glass.top - 1.5),
      new Box(region.row.left, middle - region.pillHeight / 2, region.row.width, region.pillHeight),
      new Box(chevronCx - arrowWidth / 2, middle - arrowHeight / 2, arrowWidth, arrowHeight));
  }

  private seats(region: CandidateRegionLayout, look: Look): CatPlacement[] {
    const stage = this.stage(region, look.shape);
    // 节日：换装猫按 bust 落座（对照 Android CandidateBarView.kt:293-299，背后无前爪）。
    const festival = this.state.festival;
    const dressedMimimo = festival !== null ? festival.mimimo.catSprite() : null;
    const dressedMomo = festival !== null ? festival.momo.catSprite() : null;
    if (dressedMimimo !== null && dressedMomo !== null) {
      const places = CatSeats.ends(stage, dressedMimimo, dressedMomo);
      if (places !== null) return places;
    }
    // 【0.9.1 贴图选型】安卓 0.9.1 真机像素分析：日常状态米米莫用 lounge（趴卧，宽身）、
    // 莫莫用 rest（正坐）。两猫等可见高、聚拢玻璃右端。旧版双双 edge_peek 随 0.9.1 废弃。
    const mimimo = CatSpriteData.get('mimimo_edge_lounge')!;
    const momo = CatSpriteData.get('momo_edge_rest')!;
    return CatSeats.ends(stage, mimimo, momo) ?? [];
  }

  private drawCats(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    for (const seat of this.seats(region, look)) {
      const cat = seat.cat === Cat.MIMIMO ? 'mimimo' : 'momo';
      const motion = this.motions.get(cat);
      let pose: CatPose | null = null;
      if (motion !== undefined) pose = motion.pose(Date.now());
      const sprite = seat.sprite;
      const frame = seat.frame;
      // 组字时向候选方向倾斜（米米莫 +2.5° / 莫莫 −2.5°），叠加上摸猫 pose 的 shake/nuzzle。
      const leanTilt = this.lean * (seat.cat === Cat.MIMIMO ? 2.5 : -2.5);
      const tilt = leanTilt + (pose?.tilt ?? 0);
      let wide = pose?.wide ?? 1;
      let tall = pose?.tall ?? 1;
      // 按在猫身上时压扁（对照 Android drawCat:377 的 squash）。
      if (this.pressedCats.has(cat)) {
        wide *= 1.06;
        tall *= 0.93;
      }
      ctx.save();
      // 【纯净版】不再裁剪玻璃内侧。此前 clipOutsideGlass 用 evenodd 把玻璃内部整块挖空，
      // 导致猫身主体被裁掉、只剩探出玻璃边缘的爪子轮廓（真机反馈「只有爪子、主体显示不出来」）。
      // 现在整只猫完整绘制在候选栏上，先确认贴图能正确显示，后续再按需恢复裁切。
      this.catTransform(ctx, seat, tilt, wide, tall);
      const pm = this.pixelFor(sprite.name);
      if (pm !== undefined) {
        this.drawCatImage(ctx, pm, sprite, frame);
      } else {
        // 贴图尚未解码时的降级占位，避免空白。
        const fx = frame.left + (sprite.left + sprite.right) / 2 * frame.width;
        const fy = frame.top + (sprite.top + sprite.bottom) / 2 * frame.height;
        const rw = (sprite.right - sprite.left) * frame.width / 2;
        const rh = (sprite.bottom - sprite.top) * frame.height / 2;
        ctx.fillStyle = look.candidateText;
        ctx.globalAlpha = 0.85;
        ctx.beginPath();
        ctx.ellipse(fx, fy, rw * 0.72, rh * 0.62, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
      }
      ctx.restore();

      // 前爪搭在玻璃上（对照 Android drawCat 第 388-399 行）：玻璃内再画一次，
      // 裁剪到每只圆爪的椭圆轮廓。深色黑猫的爪子也叠暖色光晕。
      if (pm !== undefined) {
        ctx.save();
        this.clipInsideGlass(ctx, look, region);
        this.pawOvalsClip(ctx, seat);
        this.catTransform(ctx, seat, tilt, wide, tall);
        if (look.dark && cat === 'mimimo') {
          ctx.save();
          ctx.shadowBlur = 2.2 * region.scale;
          ctx.shadowColor = withAlpha('#FFEDD6', 0.6);
          this.drawCatImage(ctx, pm, sprite, frame);
          ctx.restore();
        }
        this.drawCatImage(ctx, pm, sprite, frame);
        ctx.restore();
      }
    }
  }

  /** 候选行左侧柔光带（对照 iOS CandidateRegionView L143-153）：米米莫黑猫身上垫光带。 */
  private drawLightBand(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    if (!region.cats || !look.cats || look.dark) return;
    const seats = this.seats(region, look);
    const mimimo = seats.find((s) => s.cat === Cat.MIMIMO);
    if (mimimo === undefined) return;
    const band = contentBand(look.shape, region.glass.height);
    const cy = region.glass.top + (band.low + band.high) / 2;
    // 从行左端延伸到米米莫右缘 + 10*unit（对照 iOS lightBand 公式）。
    const span = (mimimo.visible.left + mimimo.visible.width) + 10 * region.scale - region.row.left;
    if (span <= 0) return;
    const pillTop = cy - region.pillHeight / 2;
    ctx.save();
    roundRect(ctx, region.row.left, pillTop, span, region.pillHeight, region.pillHeight / 2);
    ctx.clip();
    // 纵向渐变：中间亮、上下淡出，模拟玻璃高光而不是一块实心白条
    // （鸿蒙 Canvas 无 iOS LiquidGlass 的真实高光材质，纯色 50% 白在玻璃上呈突兀白斑）。
    const vgrad = ctx.createLinearGradient(0, pillTop, 0, pillTop + region.pillHeight);
    vgrad.addColorStop(0, '#00FFFFFF');
    vgrad.addColorStop(0.5, '#4DFFFFFF');   // 中心 30% 白
    vgrad.addColorStop(1, '#00FFFFFF');
    // 横向：前 60% 保持，后 40% 淡出（对照 iOS mask black 0 → black 0.6 → clear 1）。
    const hgrad = ctx.createLinearGradient(region.row.left, 0, region.row.left + span, 0);
    hgrad.addColorStop(0, '#FFFFFFFF');
    hgrad.addColorStop(0.6, '#FFFFFFFF');
    hgrad.addColorStop(1, '#00FFFFFF');
    ctx.fillStyle = vgrad;
    ctx.fillRect(region.row.left, pillTop, span, region.pillHeight);
    // 用横向渐变做二次遮罩效果：在右 40% 上覆盖一层背景色的反向渐变以淡出。
    ctx.globalCompositeOperation = 'destination-out';
    ctx.fillStyle = hgrad;
    ctx.fillRect(region.row.left, pillTop, span, region.pillHeight);
    ctx.globalCompositeOperation = 'source-over';
    ctx.restore();
  }

  /** 摸猫喷发的粒子（对照 Android CandidateBarView.drawParticles L514-538）。 */
  private drawParticles(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    if (this.particles.length === 0) return;
    const seats = this.seats(region, look);
    const now = Date.now();
    for (const p of this.particles) {
      const t = (now - p.start) / p.span;
      const seat = seats.find((s) => s.cat === p.cat);
      const box = seat?.visible;
      if (t >= 1 || box === undefined) continue;
      // 从朝候选那侧的脸喷出：米米莫靠右、莫莫靠左。
      const cx = p.cat === Cat.MIMIMO ? box.left + box.width * 0.78 : box.left + box.width * 0.22;
      const ease = 1 - (1 - t) * (1 - t);
      const x = cx + p.drift * ease;
      const y = box.top + 6 - 15 * ease;
      ctx.save();
      ctx.globalAlpha = 1 - t;
      const size = p.size * (0.4 + 0.6 * ease);
      ctx.translate(x, y);
      ctx.rotate(p.drift * 1.4 * ease * Math.PI / 180);
      switch (p.kind) {
        case 0: Glyphs.heart(ctx, 0, 0, size, p.color); break;
        case 1: Glyphs.paw(ctx, 0, 0, size, p.color); break;
        case 2: Glyphs.note(ctx, 0, 0, size, p.color); break;
        default: Glyphs.sparkle(ctx, 0, 0, size, p.color); break;
      }
      ctx.restore();
    }
  }
  private catTransform(ctx: CanvasRenderingContext2D, seat: CatPlacement,
    tilt: number, wide: number, tall: number): void {
    if (tilt !== 0) {
      ctx.translate(0, seat.reach * Math.abs(Math.sin(tilt * Math.PI / 180)));
      ctx.translate(seat.anchorX, seat.anchorY);
      ctx.rotate(tilt * Math.PI / 180);
      ctx.translate(-seat.anchorX, -seat.anchorY);
    }
    if (wide !== 1 || tall !== 1) {
      ctx.translate(seat.anchorX, seat.anchorY);
      ctx.scale(wide, tall);
      ctx.translate(-seat.anchorX, -seat.anchorY);
    }
  }

  /** 把裁剪区设为「玻璃之内」，用于前爪搭在玻璃上。 */
  private clipInsideGlass(ctx: CanvasRenderingContext2D, look: Look,
    region: CandidateRegionLayout): void {
    tracePath(ctx, look.shape, region.glass);
    ctx.clip();
  }

  /** 玻璃上每只前爪下的软阴影（对照 Android pawShadows）。 */
  private pawShadows(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    ctx.save();
    this.clipInsideGlass(ctx, look, region);
    ctx.fillStyle = look.dark ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.20)';
    ctx.shadowBlur = 1.5;
    ctx.shadowColor = look.dark ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.20)';
    for (const seat of this.seats(region, look)) {
      for (const paw of seat.paws) {
        const left = paw.left + 1;
        const right = paw.left + paw.width - 1;
        const top = paw.bottom - 1.5;
        const bottom = paw.bottom + 1.5;
        ctx.beginPath();
        ctx.ellipse((left + right) / 2, (top + bottom) / 2, (right - left) / 2,
          (bottom - top) / 2, 0, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.shadowBlur = 0;
    ctx.restore();
  }

  /** 每只前爪的圆爪椭圆裁剪（对照 Android CandidateBarView.kt:305-312 的 paws Path）。 */
  private pawOvalsClip(ctx: CanvasRenderingContext2D, seat: CatPlacement): void {
    ctx.beginPath();
    for (const paw of seat.sprite.paws) {
      const cx = seat.frame.left + paw.x * seat.frame.width;
      const w = 2 * paw.halfWidth * seat.frame.width + 0.8;
      const bottom = seat.anchorY + paw.depth * seat.frame.height + 0.4;
      const h = Math.max(2 * paw.depth * seat.frame.height, 0.7 * w) + 0.4;
      ctx.ellipse(cx, (bottom - h) + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
    }
    ctx.clip();
  }

  /** 猫贴图整图缩放到 frame（与 Android drawBitmap(bitmap, null, frame) 对齐）。
   *
   * 注意：rawfile 的猫 PNG 是 @3x 实际像素（peek=192×192），sprite.width/height 与 frame 是 1x 逻辑
   * vp（64×64）。真机验证（API 12+，Pura X / density 3.0）：
   *   - dest.x / dest.y 按 vp 坐标解释（与路径/文字一致，随画布拉伸）；
   *   - dest.width / dest.height 却按物理像素 1:1 解释（不随画布拉伸）。
   * 因此宽度/高度必须乘 pxRatio 折算回物理像素才能得到 vp 语义的大小；
   * 左上角坐标保持 vp 原值（乘了反而飞出画布——这正是「猫消失只剩爪影」的根因）。
   */
  private drawCatImage(ctx: CanvasRenderingContext2D, pm: image.PixelMap,
    sprite: CatSprite, frame: Box): void {
    const info = pm.getImageInfoSync();
    const sw = info.size.width;   // 物理像素，如 192
    const sh = info.size.height;
    const k = this.pxRatio();
    ctx.drawImage(pm, 0, 0, sw, sh,
      frame.left, frame.top, frame.width * k, frame.height * k);
  }

  /** 节日右端饰簇（对照 Android drawFestivalEnd）：玻璃上、猫与候选下。 */
  private drawFestivalEnd(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    const festival = this.state.festival;
    if (festival === null || festival.right === null) return;
    const pm = this.festivalPixels.get(festival.right.image);
    if (pm === undefined) return;
    const band = contentBand(look.shape, region.glass.height);
    const arrowRight = region.chevron.left + region.chevron.width / 2 +
      CandidateRegionLayout.ARROW_WIDTH / 2;
    const box = Festivals.placeRight(festival.right, region.glass, [band.low, band.high],
      region.width, arrowRight);
    if (box === null) return;
    const info = pm.getImageInfoSync();
    const k = this.pxRatio();
    ctx.drawImage(pm, 0, 0, info.size.width, info.size.height,
      box.left, box.top, box.width * k, box.height * k);
  }

  /** 把裁剪区设为「玻璃之外」，用于猫身下缘藏进玻璃。 */
  private clipOutsideGlass(ctx: CanvasRenderingContext2D, look: Look,
    region: CandidateRegionLayout): void {
    // 用 evenodd 在整块画布上挖掉玻璃轮廓。rect 左/上也留 80 余量：
    // 猫 frame 顶部（anchorY - anchorY*height）可能是负 y（猫头探到候选栏上缘之外），
    // 若 rect 从 (0,0) 起会把负坐标的猫头顶误裁。
    ctx.rect(-80, -80, region.width + 160, region.height + 160);
    tracePath(ctx, look.shape, region.glass);
    ctx.clip('evenodd');
  }

  private drawRow(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    const st = this.state;
    const row = region.row;
    const band = contentBand(look.shape, region.glass.height);
    const cy = region.glass.top + (band.low + band.high) / 2;
    const font = region.fontSize;
    ctx.font = `${font}vp sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';

    const items: CandidateItem[] = [];
    let x = 4;
    const gap = 6;
    const maxText = region.maximumCandidateWidth - 24;

    // 先把整行排出来（内容坐标），再按 barScroll 平移绘制——
    // 对应 Android 的 contentWidth / maxScroll，候选多了可以横向拖动。
    if (st.candidates.length > 0) {
      for (const i of st.visibleIndices) {
        const c = st.candidates[i];
        if (c === undefined) continue;
        const japanese = c.kind === 'JAPANESE_WORD' || c.kind === 'MIXED' || c.kind === 'MIXED_PREFIX' || c.kind === 'KANA';
        const mark = japanese && st.japaneseMarks ? font * 0.45 + 3 : 0;
        const measure = ctx.measureText(c.text).width;
        // 超宽候选截中段；pill 宽度按截断后文本算，绘制也必须画截断文本——
        // 否则长候选文字溢出 pill、与相邻候选叠在一起（用户反馈「打字很长时候选
        // 字符混在一起」）。
        const shown = measure > maxText - mark ? truncateMiddle(c.text, ctx, maxText - mark) : c.text;
        const width = Math.max(region.pillHeight, ctx.measureText(shown).width + 24 + mark);
        items.push(new CandidateItem(i, 0, shown, width, japanese && st.japaneseMarks));
        x += width + gap;
      }
    } else if (st.predictions.length > 0) {
      // 【剪贴板芯片 round 61】预测行首位常驻「粘贴」：点击经
      // sendExtendAction(PASTE) 让聚焦编辑框自己执行系统粘贴 —— 输入法无需
      // READ_PASTEBOARD（system_basic ACL 受限权限）即可用上剪贴板内容。
      const pasteIcon = font * 0.66;
      const pasteW = Math.max(region.pillHeight,
        ctx.measureText(CLIPBOARD_PASTE_LABEL).width + pasteIcon + 4 + 26);
      items.push(new CandidateItem(0, 3, CLIPBOARD_PASTE_LABEL, pasteW, false));
      x += pasteW + gap;
      for (let i = 0; i < st.predictions.length; i++) {
        const text = st.predictions[i];
        const width = Math.max(region.pillHeight, ctx.measureText(text).width + 22);
        items.push(new CandidateItem(i, 1, text, width, false));
        x += width + gap;
      }
    } else if (st.punctuation.length > 0) {
      for (let i = 0; i < st.punctuation.length; i++) {
        items.push(new CandidateItem(i, 2, st.punctuation[i], 34, false));
        x += 34 + 2;
      }
    }
    this.barContentWidth = x - gap;
    this.barMaxScroll = Math.max(0, x - gap - row.width);
    if (this.barScroll > this.barMaxScroll) this.barScroll = this.barMaxScroll;
    if (this.barScroll < 0) this.barScroll = 0;

    // 状态标签（空闲时靠右）。
    const needStatus = items.length === 0 && st.status.length > 0;
    if (needStatus) {
      ctx.font = `${region.statusFontSize}vp sans-serif`;
      ctx.fillStyle = withAlpha(look.candidateSecondary, 0.8);
      const w = ctx.measureText(st.status).width;
      ctx.fillText(st.status, row.left + row.width - w - 8, cy);
      ctx.font = `${font}vp sans-serif`;
      return;
    }

    // 内容坐标从 0 起，绘制时减去 barScroll，并裁到候选行区域内。
    ctx.save();
    ctx.beginPath();
    ctx.rect(row.left, row.top - 2, row.width, row.height + 4);
    ctx.clip();
    let cx = row.left + 4 - this.barScroll;
    let n = 0;
    for (const item of items) {
      if (cx > row.left + row.width || cx + item.width < row.left) { cx += item.width + gap; n++; continue; }
      const pillTop = cy - region.pillHeight / 2;
      const selected = item.kind === 0 && item.index === st.highlighted;
      const pressed = n === this.pressedCandidate;
      if (selected) {
        // 【iOS 风格】选中胶囊平滑滑动（segmented-control 式 240ms ease-out）：
        // 首次出现不滑；同列表内高亮变化时从旧位置滑过来。
        let px = cx;
        let pw = item.width;
        const slide = this.pillSlideX(cx, item.width);
        if (slide !== null) { px = slide[0]; pw = slide[1]; }
        PillPainter.draw(ctx, px, pillTop, pw, region.pillHeight, look.pill, look.dark, true);
      } else if (pressed || item.kind !== 0) {
        // 安卓：按下时叠 0.22（浅色）/0.30（深色）的底，预测与标点常态就有 0.10/0.14 的浅底。
        const alpha = pressed ? (look.dark ? 0.30 : 0.22) : (look.dark ? 0.14 : 0.10);
        ctx.fillStyle = withAlpha(look.pill[1], alpha);
        roundRect(ctx, cx, pillTop, item.width, region.pillHeight, region.pillHeight / 2);
        ctx.fill();
      }
      ctx.fillStyle = selected ? '#FFFFFFFF' :
        (item.kind === 2 ? look.candidateSecondary : look.candidateText);
      // 按下时内容缩到 0.95（以项中心为基准），抬手才提交。
      if (pressed) {
        ctx.save();
        const pcx = cx + item.width / 2;
        ctx.translate(pcx, cy);
        ctx.scale(0.95, 0.95);
        ctx.translate(-pcx, -cy);
      }
      const textW = ctx.measureText(item.text).width;
      const markW = item.japanese ? font * 0.45 + 3 : 0;
      if (item.kind === 3) {
        // 粘贴芯片：图标 + 文字成簇居中。
        const iconSize = font * 0.66;
        const clusterW = iconSize + 4 + textW;
        const contentLeft = cx + (item.width - clusterW) / 2;
        Glyphs.clipboard(ctx, contentLeft + iconSize / 2, cy, iconSize, look.candidateText);
        ctx.fillText(item.text, contentLeft + iconSize + 4, cy);
      } else {
        ctx.fillText(item.text, cx + (item.width - textW - markW) / 2, cy);
      }
      if (item.japanese) {
        const pawX = cx + (item.width - textW - markW) / 2 + textW + 3 + font * 0.225;
        Glyphs.paw(ctx, pawX, cy - font * 0.05, font * 0.45, selected ? '#D9FFFFFF' : look.candidateSecondary);
      }
      if (pressed) ctx.restore();
      cx += item.width + gap;
      n++;
    }
    // 两端渐隐（对照 Android drawRow 的 fadeRowEnds）：内容超宽时在行两端擦淡，而非硬裁字符。
    if (this.barMaxScroll > 0.5) this.fadeRowEnds(ctx, row);
    ctx.restore();
  }

  /**
   * 候选行左右端渐隐（对照 Android CandidateBarView.fadeRowEnds）。
   * 用 destination-out 合成 + 线性渐变擦淡，避免候选行内容在两端被硬切。
   */
  private fadeRowEnds(ctx: CanvasRenderingContext2D, row: Box): void {
    const top = row.top - 2;
    const bottom = row.top + row.height + 2;
    const fade = 18;
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';
    if (this.barScroll > 0.5) {
      const g = ctx.createLinearGradient(row.left, 0, row.left + fade, 0);
      g.addColorStop(0, 'rgba(0,0,0,1)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g;
      ctx.fillRect(row.left, top, fade, bottom - top);
    }
    if (this.barScroll < this.barMaxScroll - 0.5) {
      const g = ctx.createLinearGradient(row.left + row.width - fade, 0, row.left + row.width, 0);
      g.addColorStop(0, 'rgba(0,0,0,0)');
      g.addColorStop(1, 'rgba(0,0,0,1)');
      ctx.fillStyle = g;
      ctx.fillRect(row.left + row.width - fade, top, fade, bottom - top);
    }
    ctx.restore();
  }

  private drawChevron(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    const st = this.state;
    if (!st.canExpand && !st.expanded) return;
    const band = contentBand(look.shape, region.glass.height);
    const cy = region.glass.top + (band.low + band.high) / 2;
    const box = region.chevron;
    Glyphs.chevron(ctx, box.left + box.width / 2, cy, CandidateRegionLayout.ARROW_WIDTH, st.expanded, look.candidateText);
  }

  private drawToast(ctx: CanvasRenderingContext2D, region: CandidateRegionLayout, look: Look): void {
    const band = contentBand(look.shape, region.glass.height);
    const cy = region.glass.top + (band.low + band.high) / 2;
    const font = region.fontSize * 0.75;
    const hearts = this.toastHearts;
    const pink = '#FFED6B80';
    // 淡入 180ms、淡出 200ms（对照 Android toastAlpha L540-545）。
    const now = Date.now();
    const age = now - this.toastStart;
    const duration = this.toastExpires - this.toastStart;
    const fadeIn = Math.min(1, age / 180);
    const alpha = Math.min(Math.min(1, age / 180), Math.min(1, (duration - age) / 200));
    // 弹跳进入：180ms 内从 0.86 放大到 1.0（对照 Android drawToast L567-569）。
    const scale = 0.86 + 0.14 * fadeIn;
    // 图标宽度：进度 5 颗爱心 = 5*12+4；单颗大爱心 = 18（对照 Android drawToast L562）。
    const iconWidth = hearts >= 0 ? CatAffection.PETS_TO_SWITCH * 12 + 4 : 18;
    ctx.font = `${font}vp sans-serif`;
    const textW = ctx.measureText(this.toastText).width;
    const h = 30;
    const w = Math.min(region.row.width + 20, textW + iconWidth + 30);
    const cx = (region.row.left + region.chevron.left + region.chevron.width) / 2;
    ctx.save();
    // ArkUI Canvas scale 只收 (x,y)，围绕 (cx,cy) 缩放需手动平移（对照 Android canvas.scale(s,s,cx,cy)）。
    ctx.translate(cx, cy);
    ctx.scale(scale, scale);
    ctx.translate(-cx, -cy);
    // 底（pressPaint）+ emphasis 强调层（pill.second，对照 Android drawToast L571-574）。
    ctx.fillStyle = withAlpha(look.dark ? '#1F1E21' : '#FAF2E6', 0.92 * alpha);
    roundRect(ctx, cx - w / 2, cy - h / 2, w, h, h / 2);
    ctx.fill();
    ctx.fillStyle = withAlpha(look.pill[1], (this.toastEmphasis ? 0.20 : 0.10) * alpha);
    roundRect(ctx, cx - w / 2, cy - h / 2, w, h, h / 2);
    ctx.fill();
    // 爱心（对照 Android drawToast L575-588）。
    let x = cx - w / 2 + 13;
    if (hearts >= 0) {
      for (let i = 0; i < CatAffection.PETS_TO_SWITCH; i++) {
        const lit = i < hearts;
        Glyphs.heart(ctx, x + 5, cy, 10, withAlpha(lit ? pink : look.candidateSecondary, alpha * (lit ? 1.0 : 0.45)));
        x += 12;
      }
      x += 4;
    } else if (this.toastText.length > 0) {
      Glyphs.heart(ctx, x + 6, cy, 12, withAlpha(pink, alpha));
      x += 18;
    }
    // 文本（超宽尾部省略，对照 Android ellipsize END）。
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = withAlpha(look.candidateText, alpha);
    const room = cx + w / 2 - 12 - x;
    ctx.fillText(truncateMiddle(this.toastText, ctx, room > 0 ? room : 0), x, cy);
    ctx.restore();
  }

  drawKeys(): void {
    const ctx = this.keyCtx2d;
    // 先把键高撑到面板剩余空间，再取 placements：drawKeys 与 keyAt 必须用同一套
    // 几何，否则画出来的键和能点到的键错位（点哪都不提交）。
    this.fitKeysToPanel();
    const w = this.kbWidth;
    const look = this.state.keyboard;
    const keySet = this.keySet;
    const placements = this.placements;
    const metrics = this.metrics;
    if (keySet === null) return;
    const total = this.keysAreaHeight();

    // 背景渐变（对应 Android KeyboardView.kt:158 的 LinearGradient）：
    // 【质感 round 60-8】三段式——上 30% 保持顶色再向底色加深，比直线渐变
    // 更有「整块材料」的厚重感。
    // 底板应用玻璃造型（用户反馈「地板没有应用玻璃形态」）：上沿按
    // 造型起伏（胶囊平直圆角/波浪 S 形/云朵鼓包），其余三边贴面板边缘。
    const bg = ctx.createLinearGradient(0, 0, 0, total);
    bg.addColorStop(0, look.keyboardTop);
    bg.addColorStop(0.3, look.keyboardTop);
    bg.addColorStop(1, look.keyboardBottom);
    ctx.fillStyle = bg;
    const shapeH = Math.min(total, 56);
    ctx.beginPath();
    ctx.moveTo(0, total);
    ctx.lineTo(0, shapeH);
    const steps = 48;
    for (let i = 0; i <= steps; i++) {
      const x = w * i / steps;
      ctx.lineTo(x, glassTop(look.shape, x, w, shapeH));
    }
    ctx.lineTo(w, total);
    ctx.closePath();
    ctx.fill();

    // 展开面板：覆盖键区的候选网格，不画按键。
    if (this.state.expanded && this.state.composing) {
      this.drawPanel(ctx, total);
      return;
    }

    const cursorMode = this.touches?.cursorMode ?? false;
    for (let r = 0; r < keySet.rows.length; r++) {
      const rowKeys = keySet.rows[r];
      const rowPlaces = placements[r];
      for (let c = 0; c < rowKeys.length; c++) {
        const key = rowKeys[c];
        const place = rowPlaces[c];
        if (place === undefined) continue;
        const pressed = this.touches?.isPressed(r, c) ?? false;
        this.drawKey(ctx, key, place.frame, pressed, cursorMode, look, metrics);
      }
    }

    // 气泡（对照 Android PreviewOverlay.drawBalloon）。
    this.balloons.forEach((b: BalloonEntry) => {
      this.drawBalloon(ctx, b.key, b.frame, b.fontSize, look);
    });

    // 长按备选条（对照 Android PreviewOverlay.drawStrip：阴影 + 选中项 accent 高亮底 + 白字 + 超宽缩字号）。
    if (this.alternates !== null) {
      const a = this.alternates;
      const box = a.strip.box;
      const cell = a.strip.cell;
      // 投影 + 圆角底（对照 shadow()：模糊 4、下移 2、黑 0.45/0.20；圆角 11）。
      ctx.save();
      ctx.shadowBlur = 4;
      ctx.shadowOffsetY = 2;
      ctx.shadowColor = withAlpha('#000000', look.dark ? 0.45 : 0.20);
      ctx.fillStyle = look.balloonFace;
      roundRect(ctx, box.left, box.top, box.width, box.height, 11);
      ctx.fill();
      ctx.restore();
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (let i = 0; i < a.options.length; i++) {
        const left = a.strip.cellLeft(i);
        const cellX = left + cell / 2;
        if (i === a.selected) {
          // 选中项高亮底（对照 drawStrip L118-121：accent 圆角矩形 + 白字）。
          ctx.fillStyle = look.accent;
          roundRect(ctx, left + 1, box.top + 5, cell - 2, box.height - 10, 8);
          ctx.fill();
          ctx.fillStyle = '#FFFFFFFF';
        } else {
          ctx.fillStyle = look.keyText;
        }
        // 超宽选项缩字号（对照 drawStrip L127-129）。
        const wide = ctx.measureText(a.options[i]).width;
        const fontSize = wide > cell - 4 ? 24 * (cell - 4) / wide : 24;
        ctx.font = `${fontSize}vp sans-serif`;
        ctx.fillText(a.options[i], cellX, box.top + box.height / 2);
      }
    }
  }

  // ---------------------------------------------------------------- 展开面板

  private static readonly PANEL_ROW = 46;
  private static readonly PANEL_TOP = 6;
  private static readonly PANEL_GAP = 4;

  /** 重新排展开面板的候选网格（对应 Android ExpandedPanelView.relayout）。 */
  private layoutPanel(): void {
    const w = this.kbWidth;
    if (w <= 0) return;
    const margin = 10;
    const usable = w - 2 * margin;
    const quarter = (usable - 3 * MeowpuutKeyboard.PANEL_GAP) / 4;
    const list: PanelCell[] = [];
    const candidates = this.state.candidates;
    const japaneseMarks = this.state.japaneseMarks;
    let x = 0;
    let y = MeowpuutKeyboard.PANEL_TOP;
    let columnsUsed = 0;
    for (let i = 0; i < candidates.length; i++) {
      const c = candidates[i];
      const japanese = isJapanese(c) && japaneseMarks;
      // 量文本自然宽度；用 18vp 字体，与 Android bold.measureText 一致。
      const natural = this.panelMeasure(c.text) + 28 + (japanese ? 18 * 0.45 + 6 : 0);
      const columns = Math.min(4, Math.max(1, Math.ceil((natural + MeowpuutKeyboard.PANEL_GAP) / (quarter + MeowpuutKeyboard.PANEL_GAP))));
      if (columnsUsed + columns > 4) {
        y += MeowpuutKeyboard.PANEL_ROW;
        x = 0;
        columnsUsed = 0;
      }
      const cellW = columns * quarter + (columns - 1) * MeowpuutKeyboard.PANEL_GAP;
      const room = cellW - 28 - (japanese ? 18 * 0.45 + 6 : 0);
      const shown = natural > cellW ? this.panelEllipsize(c.text, room) : c.text;
      list.push(new PanelCell(i, margin + x, y, cellW, shown, japanese));
      x += cellW + MeowpuutKeyboard.PANEL_GAP;
      columnsUsed += columns;
    }
    this.panelCells = list;
    this.panelContentHeight = y + MeowpuutKeyboard.PANEL_ROW + MeowpuutKeyboard.PANEL_TOP;
    this.panelScroll = Math.max(0, Math.min(this.panelScroll, this.panelMaxScroll()));
  }

  private panelMaxScroll(): number {
    const h = this.keysAreaHeight();
    return Math.max(0, this.panelContentHeight - h);
  }

  private panelMeasure(text: string): number {
    const ctx = this.keyCtx2d;
    ctx.font = '18vp sans-serif';
    return ctx.measureText(text).width;
  }

  private panelEllipsize(text: string, room: number): string {
    if (room <= 0) return '';
    this.keyCtx2d.font = '18vp sans-serif';
    return truncateMiddle(text, this.keyCtx2d, room);
  }

  private panelCellAt(x: number, y: number): number {
    const cy = y + this.panelScroll;
    const cells = this.panelCells;
    for (let i = 0; i < cells.length; i++) {
      const cell = cells[i];
      if (x >= cell.left && x < cell.left + cell.width && cy >= cell.top && cy < cell.top + MeowpuutKeyboard.PANEL_ROW) {
        return i;
      }
    }
    return -1;
  }

  private panelNeedMore(): void {
    if (this.panelScroll > this.panelMaxScroll() - 3 * MeowpuutKeyboard.PANEL_ROW) {
      // 对应 Android ExpandedPanelView.maybeNeedMore → onNeedMore。
      // 鸿蒙端候选列表由 MeowpuutAbility 一次性取回，暂无需追加；预留回调。
    }
  }

  /** 展开面板的触控：点候选 + 纵向拖动 + 惯性（对应 Android onTouchEvent）。 */
  private handlePanelTouch(event: TouchEvent): void {
    for (const change of event.changedTouches) {
      const x = change.x;
      const y = change.y;
      if (change.type === TouchType.Down) {
        this.panelDragId = change.id;
        this.panelDownY = y;
        this.panelDownScroll = this.panelScroll;
        this.panelDragging = false;
        this.panelPressed = this.panelCellAt(x, y);
        this.panelVel = 0;
        this.panelLastY = y;
        this.panelLastT = Date.now();
        this.drawTick++;
      } else if (change.type === TouchType.Move) {
        if (change.id !== this.panelDragId) continue;
        if (!this.panelDragging && Math.abs(y - this.panelDownY) > 6) {
          this.panelDragging = true;
          this.panelPressed = -1;
        }
        if (this.panelDragging) {
          const now = Date.now();
          const dt = now - this.panelLastT;
          if (dt > 0) {
            this.panelVel = (y - this.panelLastY) / dt;
          }
          this.panelLastY = y;
          this.panelLastT = now;
          this.panelScroll = Math.max(0, Math.min(this.panelDownScroll - (y - this.panelDownY), this.panelMaxScroll()));
          this.panelNeedMore();
          this.drawTick++;
        }
      } else if (change.type === TouchType.Up || change.type === TouchType.Cancel) {
        if (change.id !== this.panelDragId) continue;
        if (this.panelDragging) {
          // 抬手惯性。
          this.startPanelFling(this.panelVel);
        } else if (change.type === TouchType.Up) {
          const n = this.panelCellAt(x, y);
          if (n >= 0) this.onCandidateEvt?.(this.panelCells[n].index);
        }
        this.panelDragId = -1;
        this.panelPressed = -1;
        this.panelDragging = false;
        this.drawTick++;
      }
    }
  }

  /** 展开面板纵向惯性滚动（用定时器近似 OverScroller.fling）。 */
  private startPanelFling(vel: number): void {
    // vel 是 px/ms，转成每帧位移；负速度向上滑。
    let v = vel * 16;
    const decay = 0.92;
    const step = (): void => {
      v *= decay;
      if (Math.abs(v) < 0.3) return;
      this.panelScroll = Math.max(0, Math.min(this.panelScroll - v, this.panelMaxScroll()));
      this.panelNeedMore();
      this.drawTick++;
      this.postPanelFling(step);
    };
    this.postPanelFling(step);
  }

  private postPanelFling(action: () => void): void {
    const id = ++this.timerCounter;
    this.timers.set(id, setTimeout(() => { this.timers.delete(id); action(); }, 16));
  }

  /** 绘制展开面板（对应 Android ExpandedPanelView.onDraw）。 */
  private drawPanel(ctx: CanvasRenderingContext2D, total: number): void {
    const look = this.state.keyboard;
    const w = this.kbWidth;
    this.layoutPanel();
    const h = total;

    // 不透明底（没有背景模糊，按键会像鬼影透出来）。
    ctx.fillStyle = look.dark ? 'rgb(40,38,42)' : 'rgb(246,245,249)';
    roundRect(ctx, 4, 2, w - 4, h - 2, 15);
    ctx.fill();
    // 上左打光的边框。
    ctx.strokeStyle = withAlpha(look.rim, look.dark ? 0.6 : 0.95);
    ctx.lineWidth = 1;
    roundRect(ctx, 4, 2, w - 4, h - 2, 15);
    ctx.stroke();

    ctx.save();
    roundRect(ctx, 4, 2, w - 4, h - 2, 15);
    ctx.clip();
    ctx.translate(0, -this.panelScroll);

    for (let n = 0; n < this.panelCells.length; n++) {
      const cell = this.panelCells[n];
      if (cell.top + MeowpuutKeyboard.PANEL_ROW < this.panelScroll || cell.top > this.panelScroll + h) continue;
      const top = cell.top + 3;
      const cellH = MeowpuutKeyboard.PANEL_ROW - 6;
      const selected = cell.index === this.state.highlighted;
      if (selected) {
        PillPainter.draw(ctx, cell.left, top, cell.width, cellH, look.pill, look.dark, false);
      } else if (n === this.panelPressed) {
        ctx.fillStyle = withAlpha(look.pill[1], look.dark ? 0.30 : 0.22);
        roundRect(ctx, cell.left, top, cell.width, cellH, cellH / 2);
        ctx.fill();
      }
      ctx.font = selected ? '500 18vp sans-serif' : '18vp sans-serif';
      ctx.fillStyle = selected ? '#FFFFFFFF' : look.candidateText;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      const markW = cell.japanese ? 18 * 0.45 + 6 : 0;
      const textW = ctx.measureText(cell.shown).width;
      const tx = cell.left + (cell.width - textW - markW) / 2 + textW / 2;
      const cy = top + cellH / 2;
      ctx.fillText(cell.shown, tx, cy);
      if (cell.japanese) {
        ctx.fillStyle = selected ? withAlpha('#FFFFFFFF', 0.85) : look.candidateSecondary;
        Glyphs.paw(ctx, tx + textW / 2 + 6 + 18 * 0.225, cy, 18 * 0.45, ctx.fillStyle);
      }
      // 行间细线。
      if (cell.left < 11 && cell.top > MeowpuutKeyboard.PANEL_TOP) {
        ctx.fillStyle = withAlpha(look.dark ? '#FFFFFFFF' : '#FF000000', look.dark ? 0.08 : 0.06);
        ctx.fillRect(16, cell.top - 0.25, w - 16, 0.5);
      }
    }

    if (this.state.candidates.length === 0) {
      // 【UX round 63】空状态：淡爪印 + 主文案，比一行灰字更有温度。
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.save();
      ctx.globalAlpha = 0.45;
      Glyphs.paw(ctx, w / 2, h / 2 - 24, 22, look.candidateSecondary);
      ctx.restore();
      ctx.fillStyle = look.candidateSecondary;
      ctx.font = '16vp sans-serif';
      ctx.fillText(this.state.keyCtx.simplified ? '暂无候选' : '暫無候選', w / 2, h / 2 + 10);
    }
    ctx.restore();
  }

  private drawKey(ctx: CanvasRenderingContext2D, key: Key, frame: Box, pressed: boolean,
    cursorMode: boolean, look: Look, m: KeyMetrics): void {
    let fillTop: string;
    let fillBottom: string;
    if (key.style === KeyStyle.UTILITY) {
      fillTop = fillBottom = look.keyUtility;
    } else if (key.style === KeyStyle.ACCENT) {
      // 强调键纯色填充（对照 Android KeysView.kt:132），不套键面渐变。
      fillTop = fillBottom = look.accent;
    } else {
      fillTop = look.keyFaceTop;
      fillBottom = look.keyFaceBottom;
    }
    // 按下态（对照 Android KeysView.kt:131-137）。
    if (pressed) {
      if (key.style === KeyStyle.ACCENT) {
        fillTop = fillBottom = lighten(look.accent, 0.15);
      } else if (key.style === KeyStyle.UTILITY) {
        fillTop = fillBottom = look.keyPressed;
      } else if (!key.preview || this.idiom === Idiom.TABLET) {
        // 手机竖屏 + 有预览的字符键靠弹气泡、不加深键面；平板或无预览才加深。
        fillTop = fillBottom = look.keyCharacterPressed;
      }
    }
    // 【UX round 63】按下微缩：没有气泡反馈的键（功能键/无预览字符键/平板）按下时
    // 键帽向中心收缩 2%/3%，与加深色叠加出「按下去」的触觉感；
    // 命中区与气泡仍锚定原 frame，不受影响。
    let f = frame;
    if (pressed && (!key.preview || this.idiom === Idiom.TABLET)) {
      const dx = frame.width * 0.02;
      const dy = frame.height * 0.03;
      f = new Box(frame.left + dx, frame.top + dy, frame.width - dx * 2, frame.height - dy * 2);
    }
    // 键面自上而下的柔和明暗过渡（对应 Android KeysView.kt:117 的 LinearGradient）。
    let fill: string | CanvasGradient = fillTop;
    if (fillTop !== fillBottom) {
      const grad = ctx.createLinearGradient(0, f.top, 0, f.top + f.height);
      grad.addColorStop(0, fillTop);
      grad.addColorStop(1, fillBottom);
      fill = grad;
    }
    ctx.fillStyle = fill;
    // 键帽玻璃形态（用户反馈「键帽没有应用玻璃形态」）：圆角随造型变化——
    // 胶囊=默认小圆角，波浪=更圆的胶囊，云朵=中等圆角（不对称鼓包对单键太碎）。
    const shapeR = look.shape === GlassShape.WAVE
      ? Math.min(f.height / 2, m.cornerRadius * 1.35)
      : look.shape === GlassShape.CLOUD
        ? Math.min(f.height / 2, m.cornerRadius * 1.18)
        : m.cornerRadius;
    // 底部 1dp 实心底边（对照 Android KeysView.kt:127-129 的 crisp bottom edge）
    // + 【质感 round 60-8】键帽软投影：一次 roundRect 同时得到硬底边与向下的
    // 柔和落影（浅色紫灰 0.10 / 深色黑 0.22，blur 3、下偏 1.5），键区有立体层次。
    ctx.save();
    ctx.shadowBlur = 3;
    ctx.shadowOffsetY = 1.5;
    ctx.shadowColor = look.dark ? 'rgba(0,0,0,0.22)' : 'rgba(61,41,69,0.10)';
    ctx.fillStyle = look.keyShadow;
    roundRect(ctx, f.left, f.top + 1, f.width, f.height, shapeR);
    ctx.fill();
    ctx.restore();
    // 键面。空格移光标时键面半透明、标签隐藏（对照 Android KeysView.kt:138,146）。
    if (cursorMode) ctx.globalAlpha = 170 / 255;
    ctx.fillStyle = fill;
    roundRect(ctx, f.left, f.top, f.width, f.height, shapeR);
    ctx.fill();
    if (cursorMode) ctx.globalAlpha = 1;

    // 【质感 round 60-8】键帽上缘高光：1.2dp 内嵌描边，顶部亮、往下渐隐
    // （浅色 0.34 / 深色 0.14），像键帽顶部受光。按下态不画（按下整体变暗）。
    if (!pressed) {
      ctx.save();
      roundRect(ctx, f.left, f.top, f.width, f.height, shapeR);
      ctx.clip();
      const rimGrad = ctx.createLinearGradient(0, f.top, 0, f.top + f.height * 0.5);
      rimGrad.addColorStop(0, withAlpha('#FFFFFFFF', look.dark ? 0.14 : 0.34));
      rimGrad.addColorStop(1, withAlpha('#FFFFFFFF', 0));
      ctx.strokeStyle = rimGrad;
      ctx.lineWidth = 1.2;
      roundRect(ctx, f.left + 0.6, f.top + 0.6, f.width - 1.2, f.height - 1.2,
        Math.max(1, shapeR - 0.8));
      ctx.stroke();
      ctx.restore();
    }

    // 标签（光标模式下隐藏，让用户知道当前在移光标而非打字）。
    if (cursorMode) return;

    // 标签。
    const isUtility = key.style === KeyStyle.UTILITY || key.style === KeyStyle.ACCENT;
    const size = key.fontSize ?? m.letterFont;
    // 非字符键与空格键用较小的 utility 字号（对照 Android KeysView.kt:173）。
    let fontSize = (key.style !== KeyStyle.CHARACTER || key.action.kind === 'space')
      ? Math.min(size, m.utilityFont + 1) : size;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const labelColor = key.style === KeyStyle.ACCENT ? '#FFFFFFFF'
      : (key.enabled ? look.keyText : look.keyTextDisabled);
    ctx.fillStyle = labelColor;
    const cx = f.left + f.width / 2;

    if (key.icon !== null) {
      ctx.font = `${fontSize}vp sans-serif`;
      this.drawIcon(ctx, key.icon, cx, f.top + f.height / 2, fontSize, labelColor);
    } else {
      // 超宽标签缩字号（对照 Android:179）。
      ctx.font = `${fontSize}vp sans-serif`;
      const maxWidth = f.width - 8;
      const w = ctx.measureText(key.label).width;
      if (w > maxWidth) {
        fontSize *= maxWidth / w;
        ctx.font = `${fontSize}vp sans-serif`;
      }
      // 小写字母略上移，视觉居中（对照 Android:176）。
      const lowerLift = (key.isCharacter && key.label.length === 1 && isLowercase(key.label[0]))
        ? f.height * 0.04 : 0;
      // 九键数字键：主标上移，角标字母组画在键底部（对照 iOS 九键样式）。
      if (key.sublabel !== null) {
        const mainY = f.top + f.height * 0.36;
        ctx.fillText(key.label, cx, mainY);
        const sub = key.sublabel;
        ctx.font = `${Math.max(9, fontSize * 0.38)}vp sans-serif`;
        ctx.globalAlpha = 0.66;
        ctx.fillText(sub, cx, f.top + f.height * 0.78);
        ctx.globalAlpha = 1;
      } else {
        ctx.fillText(key.label, cx, f.top + f.height / 2 - lowerLift);
      }
    }
  }

  /** 按键气泡字号（对照 Android KeysView.showBalloon）：平板返回 null 不弹，横屏 28、多字符 24、否则 34。 */
  balloonFont(key: Key): number | null {
    if (this.idiom === Idiom.TABLET) return null;
    return this.idiom === Idiom.PHONE_LANDSCAPE ? 28
      : key.label.length > 1 ? 24
      : BALLOON_FONT;
  }

  /** 按键气泡开关（对应 Android keyPopups，默认开）。供触摸主机在 showBalloon 前判断。 */
  keyPopupsEnabled(): boolean {
    return this.state.keyboard.keyPopups;
  }

  /** 按键气泡（对照 Android PreviewOverlay.drawBalloon）：S 曲线收拢 + 投影 + 描边。 */
  private drawBalloon(ctx: CanvasRenderingContext2D, key: Key, frame: Box, fontSize: number, look: Look): void {
    const bubble = KeyBalloon.bubble(frame, this.kbWidth, this.idiom);
    this.balloonPath(ctx, frame, bubble, this.metrics.cornerRadius);
    // 投影 + 填充（对照 shadow()：模糊 4、下移 2、黑 0.45/0.20）。
    ctx.save();
    ctx.shadowBlur = 4;
    ctx.shadowOffsetY = 2;
    ctx.shadowColor = withAlpha('#000000', look.dark ? 0.45 : 0.20);
    ctx.fillStyle = look.balloonFace;
    ctx.fill();
    ctx.restore();
    // 细描边（对照 drawBalloon 第 97-100 行）。
    ctx.strokeStyle = withAlpha(look.dark ? '#FFFFFF' : '#000000', look.dark ? 0.10 : 0.06);
    ctx.lineWidth = 0.5;
    ctx.stroke();
    // 标签，位置略高于气泡中心（对照 cy = top + height * 0.46）。
    // 字号由 showBalloon 按 idiom/多字符分支计算后传入（对照 Android KeysView.showBalloon）。
    ctx.font = `${fontSize}vp sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = look.keyText;
    ctx.fillText(key.label, bubble.left + bubble.width / 2, bubble.top + bubble.height * 0.46);
  }

  /** 键身经 S 曲线收拢到圆角气泡的轮廓（对照 Android balloonPath）。 */
  private balloonPath(ctx: CanvasRenderingContext2D, key: Box, bubble: Box, keyRadius: number): void {
    const keyRight = key.left + key.width;
    const bubbleRight = bubble.left + bubble.width;
    const r = Math.min(12, bubble.width / 4);
    const k = Math.min(keyRadius, key.width / 3);
    const low = key.top + Math.min(9, key.height * 0.22);
    const high = bubble.bottom - Math.min(10, bubble.height * 0.2);
    const middle = (low + high) / 2;
    ctx.beginPath();
    ctx.moveTo(key.left + k, key.bottom);
    ctx.quadraticCurveTo(key.left, key.bottom, key.left, key.bottom - k);
    ctx.lineTo(key.left, low);
    ctx.bezierCurveTo(key.left, middle, bubble.left, middle, bubble.left, high);
    ctx.lineTo(bubble.left, bubble.top + r);
    ctx.quadraticCurveTo(bubble.left, bubble.top, bubble.left + r, bubble.top);
    ctx.lineTo(bubbleRight - r, bubble.top);
    ctx.quadraticCurveTo(bubbleRight, bubble.top, bubbleRight, bubble.top + r);
    ctx.lineTo(bubbleRight, high);
    ctx.bezierCurveTo(bubbleRight, middle, keyRight, middle, keyRight, low);
    ctx.lineTo(keyRight, key.bottom - k);
    ctx.quadraticCurveTo(keyRight, key.bottom, keyRight - k, key.bottom);
    ctx.closePath();
  }

  private drawIcon(ctx: CanvasRenderingContext2D, icon: KeyIcon, cx: number, cy: number,
    size: number, color: string): void {
    ctx.fillStyle = color;
    switch (icon) {
      case KeyIcon.SHIFT:
        // 空心上箭头（未开启大写）。
        Glyphs.shift(ctx, cx, cy, size * 1.25, false, false, color);
        break;
      case KeyIcon.SHIFT_ON:
        // 实心上箭头（单次大写），无锁定横条。
        Glyphs.shift(ctx, cx, cy, size * 1.25, true, false, color);
        break;
      case KeyIcon.CAPS_LOCK:
        // 实心上箭头 + 底部锁定横条。
        Glyphs.shift(ctx, cx, cy, size * 1.25, true, true, color);
        break;
      case KeyIcon.DELETE:
        Glyphs.delete(ctx, cx, cy, size, color);
        break;
      case KeyIcon.GLOBE:
        Glyphs.globe(ctx, cx, cy, size, color);
        break;
    }
  }
}

function truncateMiddle(text: string, ctx: CanvasRenderingContext2D, room: number): string {
  if (room <= 0) return '';
  if (ctx.measureText(text).width <= room) return text;
  const ellipsis = '…';
  const ell = ctx.measureText(ellipsis).width;
  let lo = 0, hi = text.length;
  while (lo < hi) {
    const mid = Math.floor((lo + hi + 1) / 2);
    if (ctx.measureText(text.substring(0, mid)).width + ell <= room) lo = mid;
    else hi = mid - 1;
  }
  const k = lo;
  return k <= 0 ? ellipsis : text.substring(0, k) + ellipsis;
}

function makeEmptyState(): KeyboardState {
  const look = new Look(false, GlassShape.CAPSULE, Palette.ROSE, GlassStrength.BALANCED, true);
  return new KeyboardState(
    look,
    new KeyContext(InputMode.ZHUYIN, false, 0, ShiftState.OFF, false, false, '空格', '换行', false, true, false),
    [],
    [],
    0,
    [],
    [],
    '',
    false,
    false,
    false,
    true,
  );
}