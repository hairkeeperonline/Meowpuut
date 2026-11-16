/**
 * 输入法服务（对应 Android ime/MeowpuutIME.kt）。
 * 使用 IME Kit 的 InputMethodExtensionAbility：inputStart 拿到 KeyboardController
 * 与 InputClient，通过 createPanel 把 ArkUI 键盘渲染进软键盘面板。
 */
import { InputMethodExtensionAbility, inputMethodEngine, InputMethodSubtype } from '@kit.IMEKit';
import { ConfigurationConstant, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { util } from '@kit.ArkTS';
import { vibrator } from '@kit.SensorServiceKit';
import { KeyCode, KeyEvent as InputKeyEvent, Action } from '@kit.InputKit';

import { Composer } from '../engine/Composer';
import { Lexicons } from '../engine/Lexicons';
import { InputMode, Edit, Candidate } from '../engine/Types';
import { CandidateMerge } from '../engine/CandidateMerge';
import { JapaneseWords } from '../engine/JapaneseWords';
import { KeySounds, KeySoundKind } from '../engine/KeySounds';
import { Prefs } from '../ui/Prefs';
import { Look, Palette, Tone, GlassStrength, parseColor } from '../ui/Theme';
import { GlassShape } from '../ui/GlassOutline';
import { CandidateRegionLayout, keyMetricsOf, Idiom, resolveIdiom } from '../ui/Geometry';
import { ShiftState, KeyContext, Key, KeyActionEngine, KeyActionText, KeyActionPage } from '../ui/Keys';
import { Capitalization } from '../ui/KeyStates';
import { TextUnits } from '../ui/TextUnits';
import { Festivals, FestivalLoaded, FestivalWardrobe, FestivalTheme } from '../ui/Festivals';
import { MeowpuutKeyboard, KeyboardState } from '../ui/MeowpuutKeyboard';
import { KeyboardHost, KeyboardCallbacks } from '../ui/KeyboardHost';
import { CatAffection, CatOutcomeHappy, CatOutcomePleased } from '../ui/Cats';

const QUICK_MARKS = ['，', '。', '？', '！', '、'];
const AUTO_RETURN_MARKS = new Set(['，', '。', '？', '！', '、', '；', '：', ',', '.', '?', '!', ';', ':', "'", '"']);
/** 注音模式下物理键盘可键入的注音键位（对应 Android MeowpuutIME.kt ZHUYIN_KEYS）。 */
const ZHUYIN_KEYS = '1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-';
/** 注音组字状态下可再键入的声调/数字/空格（对应 Android 的 " 6347"）。 */
const ZHUYIN_COMPOSING_KEYS = ' 6347';

class AbilityCallbacks implements KeyboardCallbacks {
  private ability: MeowpuutAbility;
  constructor(ability: MeowpuutAbility) { this.ability = ability; }
  onKeyDown(key: Key): void { this.ability.keyFeedback(key.action.kind); }
  onKey(key: Key, text: string | null): void { this.ability.dispatchKey(key, text); }
  onDelete(word: boolean): void { this.ability.onDelete(word); }
  onShiftDown(): void { this.ability.onShiftDown(); }
  onShiftUp(typed: boolean): void { this.ability.onShiftUp(typed); }
  onPage(page: number): void { this.ability.onPage(page); }
  onCursorStart(): void { this.ability.onCursorStart(); }
  onCursorMove(steps: number): void { this.ability.onCursorMove(steps); }
  onCursorEnd(): void { this.ability.predictions = []; this.ability.refreshKeyboard(); }
  onTick(): void { this.ability.tickFeedback(); }
  onCandidate(index: number): void { this.ability.onCandidate(index); }
  onPrediction(text: string): void { this.ability.onPrediction(text); }
  onPunctuation(mark: string): void { this.ability.onPunctuation(mark); }
  onToggleExpanded(): void { this.ability.onToggleExpanded(); }
  onPet(cat: string): void { this.ability.onPet(cat); }
  onDragPanel(dx: number, dy: number): void { this.ability.dragPanel(dx, dy); }
  onHide(): void { this.ability.hideByPullDown(); }
}

export default class MeowpuutAbility extends InputMethodExtensionAbility {
  private ability: inputMethodEngine.InputMethodAbility = inputMethodEngine.getInputMethodAbility();
  private kbController: inputMethodEngine.KeyboardController | null = null;
  private inputClient: inputMethodEngine.InputClient | null = null;
  private panel: inputMethodEngine.Panel | null = null;
  /** 最近一次面板高度（悬浮切换宽度时保持高度不变）。 */
  private lastPanelHeight: number = 0;

  private prefs: Prefs = new Prefs();
  private lexicons: Lexicons | null = null;
  private composer: Composer = new Composer();
  private look: Look = new Look(false, GlassShape.CAPSULE, Palette.ROSE, GlassStrength.BALANCED, true);
  /** 按键音效（对应 Android playSoundEffect + assets/key-sounds）。懒初始化。 */
  private keySounds: KeySounds | null = null;

  private festivals: FestivalLoaded = Festivals.EMPTY;
  private festivalWardrobe: FestivalWardrobe = new FestivalWardrobe(true);
  /** 今日节日主题（已解析；图片由键盘 lazily 加载），无则 null。 */
  private festivalTheme: FestivalTheme | null = null;

  private english = false;
  private page = 0;
  private numericField = false;
  private expanded = false;
  private loading = false;
  private lexiconFailed = false;
  private opening: InputMode | null = null;
  private sessionMode: InputMode | null = null;
  /**
   * 系统输入法子类型给出的模式。本机上 setSubtype 回调不带 id，
   * 所以只能启动时用 getCurrentInputMethodSubtype 主动查一次。
   * 它比 prefs 可靠——prefs 在另一进程改的值这边读不到。
   */
  private subtypeMode: InputMode | null = null;
  private shiftHeld = false;
  /** 当前编辑框是否存在非零选区（对照 Android onDelete 里 getSelectedText 检查）。 */
  private hasSelection = false;
  /** 上次按空格的时刻，用于「双击空格输入句号」。 */
  private lastSpaceAt = 0;
  /** 物理键盘：已被 keyDown 消费的键，keyUp 时不再上抛（对应 Android consumedKeys）。 */
  private consumedKeys: Set<number> = new Set<number>();
  /** 物理键盘事件源（KeyboardDelegate），onCreate 时注册。 */
  private hwDelegate: inputMethodEngine.KeyboardDelegate | null = null;
  predictions: string[] = [];
  private pending: number[] = [];
  private caps = new Capitalization();
  private host: KeyboardHost = KeyboardHost.get();
  private affection: CatAffection = new CatAffection();
  /** prefs 初始化完成后 resolve，createPanel 前要等它。 */
  private ready: Promise<void> = Promise.resolve();

  get mode(): InputMode { return this.subtypeMode ?? this.prefs.mode; }
  get chineseActive(): boolean { return !this.english && this.mode !== InputMode.JAPANESE; }
  get shift(): ShiftState {
    return (this.caps.state === ShiftState.OFF && this.shiftHeld) ? ShiftState.ONCE : this.caps.state;
  }

  /** 重新读一遍偏好。设置页在另一个进程里改的值，靠这个同步过来。 */
  private async reloadPrefs(): Promise<void> {
    const ctx = this.context as common.Context;
    if (ctx === undefined || ctx === null) return;
    const before = this.mode;
    // 每次唤起都重新问一次系统当前子类型：用户在设置里换模式后
    // 这里能立刻跟上，不依赖跨进程 prefs（那条路在本机读不到）。
    try {
      const s = inputMethod.getCurrentInputMethodSubtype();
      const m = MeowpuutAbility.modeOfSubtype(s === undefined ? '' : s.id);
      if (m !== null) this.subtypeMode = m;
    } catch (e) {
      // 取不到就沿用已有值。
    }
    try {
      await this.prefs.init(ctx);
    } catch (e) {
      hilog.warn(0x0000, 'MeowpuutIME', 'reloadPrefs failed');
      return;
    }
    this.composer.simplified = this.prefs.simplified;
    this.applyLook();
    const after = this.mode;
    hilog.info(0x0000, 'MeowpuutIME', `prefs reloaded mode ${before} -> ${after}`);
    if (after !== before || this.sessionMode !== after) {
      this.sessionMode = null;
      this.openLexicon();
    }
    this.refreshKeyboard();
  }

  onCreate(want: Want): void {
    const ctx = this.context as common.Context;
    hilog.info(0x0000, 'MeowpuutIME', 'onCreate start');
    this.host.resourceManager = ctx.resourceManager;
    this.installHostCallbacks();
    // 【跨进程设置同步】文件通道（filesDir/preferences XML）在 main 与 inputMethod
    // 进程间被沙盒隔离（真机实测同一路径互不可见），改用系统公共事件广播：
    // 设置页进程 publish、本进程订阅，收到全量快照后热应用——键盘弹着也能立即生效。
    this.prefs.subscribe(() => {
      const before = this.mode;
      this.composer.simplified = this.prefs.simplified;
      this.applyLook();
      this.applyPanelPosition();
      const after = this.mode;
      if (after !== before || this.sessionMode !== after) {
        this.sessionMode = null;
        this.openLexicon();
      }
      this.refreshKeyboard();
    });
    // 订阅软键盘显示/隐藏与子类型切换。
    this.ability.on('inputStart', (kbController: inputMethodEngine.KeyboardController,
      inputClient: inputMethodEngine.InputClient) => {
      hilog.info(0x0000, 'MeowpuutIME', 'inputStart fired');
      this.kbController = kbController;
      this.inputClient = inputClient;
      this.composer.clear();
      this.expanded = false;
      // 字段类型自动识别（对应 Android onStartInputView）：数字/电话/日期字段
      // 与密码/邮箱/URL 字段自动切英文，数字类还直接停在符号页。
      this.detectFieldType();
      this.caps.reset();
      this.shiftHeld = false;
      this.openLexicon();
      // 组字预览能力探测（对照官方 KikaInputMethod）：编辑框不支持预览时直接跳过，
      // 避免每次按键都发一次注定失败的 IPC。同时把预览样式设为下划线（同安卓组字下划线）。
      this.previewSupported = true;
      this.previewLength = 0;
      try {
        const attr = inputClient.getEditorAttributeSync();
        this.previewSupported = attr.isTextPreviewSupported;
      } catch (e) {
        this.previewSupported = true;
      }
      try {
        const style: Record<string, inputMethodEngine.CommandDataType> = { 'previewTextStyle': 'underline' };
        inputClient.sendPrivateCommand(style).catch(() => {});
      } catch (e) {
        // 私有指令不被支持时忽略。
      }
      // 设置页在另一个进程里改了偏好（输入模式、外观等），本进程的 Prefs
      // 是 onCreate 时读的快照，不会自己更新。这里必须「等」重新读完再建面板，
      // 否则第一次唤起仍会用旧的输入模式（行数 5/4 也不同，面板高度会错）。
      this.reloadPrefs().then(() => {
        this.ensurePanel();
        this.refreshKeyboard();
      }).catch(() => {
        this.ensurePanel();
        this.refreshKeyboard();
      });
    });
    this.ability.on('inputStop', () => {
      hilog.info(0x0000, 'MeowpuutIME', 'inputStop fired');
      this.finishComposition();
      this.composer.clear();
      this.expanded = false;
    });
    // 面板显隐跟随系统请求（官方要求的配对处理）。
    this.ability.on('keyboardShow', () => {
      hilog.info(0x0000, 'MeowpuutIME', 'keyboardShow');
      if (this.panel !== null) this.panel.show().catch(() => {});
    });
    this.ability.on('keyboardHide', () => {
      hilog.info(0x0000, 'MeowpuutIME', 'keyboardHide');
      if (this.panel !== null) this.panel.hide().catch(() => {});
    });
    this.ability.on('setSubtype', (subtype: InputMethodSubtype) => {
      hilog.info(0x0000, 'MeowpuutIME',
        `setSubtype fired: id=${subtype === undefined ? 'undef' : subtype.id} ` +
        `locale=${subtype === undefined ? 'undef' : subtype.locale}`);
      // 子类型决定输入模式（注音/拼音/日文）。这是设置页跨进程通知输入法的
      // 唯一可靠通道——两个进程的 preferences / filesDir 是独立的沙箱视图，
      // 直接读文件拿不到对方的改动。
      const mode = MeowpuutAbility.modeOfSubtype(subtype === undefined ? '' : subtype.id);
      if (mode !== null && mode !== this.mode) {
        this.subtypeMode = mode;
        this.prefs.mode = mode;
        this.sessionMode = null;
        this.openLexicon();
        // 行数随之改变（注音 5 行 / 日文拼音 4 行），面板要重算高度。
        this.resizePanel().catch(() => {});
      }
      this.applyLook();
      this.refreshKeyboard();
    });
    // 物理键盘（外接实体键盘）事件：对应 Android onKeyDown/onKeyUp/typeHardware。
    // KeyboardDelegate.on('keyEvent') 拿到的是 @ohos.multimodalInput.keyEvent 的
    // KeyEvent（含 unicodeChar / ctrlKey / shiftKey 等），足以复刻完整硬键盘输入。
    try {
      this.hwDelegate = inputMethodEngine.getKeyboardDelegate();
      this.hwDelegate.on('keyEvent', (ev: InputKeyEvent) => {
        return this.hardwareKeyEvent(ev);
      });
      // 光标/选区变化：对应 Android onUpdateSelection——组字时若光标被用户移走，
      // 清空未完成的组字，避免候选栏挂着过时的组字。
      this.hwDelegate.on('selectionChange',
        (oldBegin: number, oldEnd: number, newBegin: number, newEnd: number) => {
          // 跟踪选区状态：onDelete 时若有选区，应先删选区（对照 Android getSelectedText）。
          this.hasSelection = newBegin !== newEnd;
          // 预览同步（setPreviewText/finishTextPreview）本身会让光标移动并回调 selectionChange，
          // 若把它当成「用户把光标移走」而清空组字，会出现「每输一个字母前一个就消失」的致命回归
          // （真机取证：PV 日志里第二键 wasC=false，raw 被本回调清掉）。一次按键可能触发不止一个
          // 回调，因此用时间窗抑制：预览调用后 SELF_DRIVEN_MS 内的选区变化一律视为自驱动。
          if (this.composer.composing && this.lastPreviewAt > 0 &&
            Date.now() - this.lastPreviewAt < MeowpuutAbility.SELF_DRIVEN_MS) {
            return;
          }
          if (this.composer.composing && (newBegin !== oldBegin || newEnd !== oldEnd)) {
            // 用户真把光标移走了：先把预览落地成普通文本（对齐 Android 的 composing 文本
            // 留在原处变成非组字文本），再清组字状态——否则预览悬空，后续 {-1/-1} 更新
            // 会作用在过期的预览区上，新字母插不进新光标位置。
            if (this.previewSupported && this.inputClient !== null) {
              try {
                this.lastPreviewAt = Date.now();
                this.inputClient.finishTextPreview();
              } catch (e) {
                // 落地失败也继续清组字，避免候选栏挂着过时状态。
              }
            }
            this.composer.clear();
            this.expanded = false;
            this.refreshKeyboard();
          }
        });
      hilog.info(0x0000, 'MeowpuutIME', 'hardware keyboard delegate registered');
    } catch (e) {
      hilog.warn(0x0000, 'MeowpuutIME', 'getKeyboardDelegate failed, no hardware keys');
    }
    this.ready = this.prefs.init(ctx).then(() => {
      hilog.info(0x0000, 'MeowpuutIME', 'prefs ready');
      // 模式以系统输入法子类型为准：setSubtype 回调在本机上不带 id，
      // 而 getCurrentInputMethodSubtype 能拿到真实的 MeowpuutZhuyin/Pinyin/Japanese。
      try {
        const s = inputMethod.getCurrentInputMethodSubtype();
        const m = MeowpuutAbility.modeOfSubtype(s === undefined ? '' : s.id);
        hilog.info(0x0000, 'MeowpuutIME', `current subtype id=${s === undefined ? 'undef' : s.id} -> ${m}`);
        if (m !== null) this.subtypeMode = m;
      } catch (e) {
        hilog.warn(0x0000, 'MeowpuutIME', 'getCurrentInputMethodSubtype failed');
      }
      this.lexicons = new Lexicons(ctx);
      this.composer.simplified = this.prefs.simplified;
      try {
        const text = this.readRawFileText(Festivals.MANIFEST);
        this.festivals = Festivals.parse(text);
      } catch (e) {
        this.festivals = Festivals.EMPTY;
      }
      this.applyLook();
      // 初始化按键音效（懒加载 SoundPool，失败静默不影响输入）。
      if (this.keySounds === null) {
        this.keySounds = new KeySounds(ctx);
        this.keySounds.init();
      }
      this.keySounds?.configure(this.prefs.keySound, this.prefs.keySoundVolume);
      this.openLexicon();
      // prefs 就绪后如果面板已存在，补一次刷新，避免空白键盘。
      if (this.panel !== null) this.refreshKeyboard();
    }).catch((e: Error) => {
      hilog.error(0x0000, 'MeowpuutIME', `prefs init failed: ${e.message}`);
    });
  }

  /** 子类型 id → 输入模式，对不上返回 null。 */
  private static modeOfSubtype(id: string): InputMode | null {
    switch (id) {
      case 'MeowpuutZhuyin': return InputMode.ZHUYIN;
      case 'MeowpuutPinyin': return InputMode.PINYIN;
      case 'MeowpuutPinyin9': return InputMode.PINYIN9;
      case 'MeowpuutJapanese': return InputMode.JAPANESE;
      default: return null;
    }
  }

  onDestroy(): void {
    this.composer.detach();
    this.lexicons?.shutdown();
  }

  onStop(): void {
    this.inputClient = null;
    this.kbController = null;
  }

  // ---------------------------------------------------------------- 面板

  private async ensurePanel(): Promise<void> {
    if (this.panel !== null) {
      hilog.info(0x0000, 'MeowpuutIME', 'panel already exists');
      // 面板复用时行数可能变了（注音 5 行 / 日文拼音 4 行），重算一次高度。
      await this.resizePanel();
      return;
    }
    // 等 prefs 就绪：否则首帧拿不到 Theme/Festivals，键盘可能整块空白。
    await this.ready;
    if (this.panel !== null) return;
    const ctx = this.context as common.ExtensionContext;
    const panelInfo: inputMethodEngine.PanelInfo = {
      type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
      flag: inputMethodEngine.PanelFlag.FLG_FIXED,
    };
    try {
      hilog.info(0x0000, 'MeowpuutIME', 'createPanel begin');
      const panel = await this.ability.createPanel(ctx, panelInfo);
      this.panel = panel;
      hilog.info(0x0000, 'MeowpuutIME', 'createPanel ok, setUiContent');
      panel.setUiContent('pages/KeyboardPage');
      // 面板默认高度是 1px，不 resize 的话窗口撑不开，看起来就像"唤不起来"。
      await this.resizePanel();
      // 键盘位置（贴底/悬浮）——prefs 里已是悬浮时创建即悬浮。
      await this.applyPanelPosition();
      // 官方流程要求显式 show()，否则面板只是被创建但不会显示。
      await panel.show();
      hilog.info(0x0000, 'MeowpuutIME', 'setUiContent + show done');
      this.refreshKeyboard();
    } catch (e) {
      hilog.error(0x0000, 'MeowpuutIME', `createPanel failed: ${JSON.stringify(e)}`);
    }
  }

  /** 【候选栏下拉收起】收起面板（下次聚焦重新弹出）。 */
  hideByPullDown(): void {
    if (this.panel !== null) {
      this.panel.hide().catch(() => {});
      hilog.info(0x0000, 'MeowpuutIME', 'keyboard hidden by candidate-bar pull-down');
    }
  }

  /** 悬浮面板当前位置（拖动累计用）。 */
  private floatX: number = 0;
  private floatY: number = 0;

  /** 悬浮拖动把手高度（vp）。 */
  private static readonly DRAG_HANDLE_VP = 32;

  /**
   * 悬浮态面板高度 = 键盘高度 + 拖动把手（真机反馈 round 60-3：悬浮时把手行
   * 挤占键盘内容高度，「最底层被截断」）。把手渲染在 KeyboardPage 顶部 32vp。
   */
  private floatingPanelHeight(): number {
    const disp: display.Display = display.getDefaultDisplaySync();
    const density = disp.densityDPI / 160;
    return this.lastPanelHeight + Math.round(MeowpuutAbility.DRAG_HANDLE_VP * density);
  }

  /** 【悬浮键盘】拖动把手：增量移动面板（按面板真实宽高钳制，右/下缘不越屏）。 */
  dragPanel(dx: number, dy: number): void {
    if (this.panel === null || this.prefs.keyboardPosition !== 'floating') return;
    const disp: display.Display = display.getDefaultDisplaySync();
    // 面板真实尺寸（悬浮宽度 = 屏宽-48，高度 = 键盘高 + 把手高）。
    const panelW = Math.min(disp.width, Math.round(90 * (disp.densityDPI / 160)) > disp.width - 48
      ? disp.width : disp.width - 48);
    const panelH = this.floatingPanelHeight();
    // 左边距和上边距最小 0；右边/下边不允许越出屏幕（显示不全修复）。
    const nx = Math.max(0, Math.min(disp.width - panelW, this.floatX + dx));
    const ny = Math.max(0, Math.min(disp.height - panelH, this.floatY + dy));
    this.floatX = nx;
    this.floatY = ny;
    this.panel.moveTo(nx, ny).catch(() => {});
  }

  /**
   * 【键盘位置】bottom=贴底（FLG_FIXED）/ floating=悬浮（FLG_FLOATING + moveTo 抬高）。
   * 悬浮键盘：panel 宽度保持全宽（>288vp 不会触发系统迷你布局），通过 moveTo
   * 把面板抬离底部 220px，用户可在键盘顶部拖动条拖动（KeyboardPage 里的 handle）。
   */
  private async applyPanelPosition(): Promise<void> {
    if (this.panel === null) return;
    const floating = this.prefs.keyboardPosition === 'floating';
    this.host.draggable = floating;
    // AppStorage 双向绑定：KeyboardPage 的 @StorageLink 会立即重渲染显示/隐藏把手。
    AppStorage.setOrCreate('meowpuutDraggable', floating);
    try {
      this.panel.changeFlag(floating
        ? inputMethodEngine.PanelFlag.FLG_FLOATING
        : inputMethodEngine.PanelFlag.FLG_FIXED);
      if (floating) {
        const disp: display.Display = display.getDefaultDisplaySync();
        // 悬浮卡片视觉：左右各留 24px 边距（面板宽度收窄 48px），顶部抬到
        // 约 22% 屏高，四周都有可见留白，像一张浮在应用上的卡片。
        const margin = 24;
        const w = Math.max(90 * (disp.densityDPI / 160), disp.width - margin * 2);
        const panelH = this.floatingPanelHeight();
        await this.panel.resize(Math.round(w), panelH);
        const x = margin;
        // 初始位置：顶部 22% 屏高，但保证面板底部不越出屏幕（显示不全修复）。
        const maxY = Math.max(margin, disp.height - panelH - margin);
        const y = Math.min(Math.round(disp.height * 0.22), maxY);
        this.floatX = x;
        this.floatY = y;
        await this.panel.moveTo(x, y);
        hilog.info(0x0000, 'MeowpuutIME', `panel floating ${Math.round(w)}px, moved to (${x},${y})`);
      } else {
        hilog.info(0x0000, 'MeowpuutIME', 'panel fixed (bottom)');
      }
    } catch (e) {
      hilog.warn(0x0000, 'MeowpuutIME', `applyPanelPosition failed: ${JSON.stringify(e)}`);
    }
  }

  /** 按窗口宽度与键盘版式算出面板高度并提交给系统。 */
  private async resizePanel(): Promise<void> {
    if (this.panel === null) return;
    const disp: display.Display = display.getDefaultDisplaySync();
    const width: number = disp.width;
    const density: number = disp.densityDPI / 160;
    const dpWidth: number = width / density;
    // 直接用真实布局类算出候选栏高度和单行键高，避免手算常量与实现脱节。
    // resolveIdiom 的签名是 (屏幕高度, 最小宽度)；这里键盘宽度即最小宽度。
    const screenH: number = disp.height / density;
    const idiom: Idiom = resolveIdiom(screenH, dpWidth);
    const region = new CandidateRegionLayout(dpWidth, idiom, this.prefs.cats);
    const metrics = keyMetricsOf(idiom, dpWidth, this.mode === InputMode.ZHUYIN ? 5 : 4);
    // 注音 5 行、其余 4 行。
    const rows: number = this.mode === InputMode.ZHUYIN ? 5 : 4;
    const keysDp: number = metrics.topPadding + rows * metrics.keyHeight +
      Math.max(0, rows - 1) * metrics.rowGap + metrics.bottomPadding;
    // 键盘高度（对应 Android keyboardHeight：short/standard/tall）。
    // 缩放键区高度；KeyboardView.fitKeysToPanel 会根据 panel 实际高度再撑满键高，
    // 故 panel 与键盘绘制保持一致的缩放。
    const scaledKeys: number = keysDp * this.look.heightScale;
    const dpHeight: number = region.height + scaledKeys;
    const height: number = Math.round(dpHeight * density);
    this.lastPanelHeight = height;
    try {
      // 悬浮态保持收窄的宽度（卡片边距）+ 把手高度（否则把手挤掉底行）。
      const w = this.prefs.keyboardPosition === 'floating'
        ? Math.max(90 * density, width - 48) : width;
      const h = this.prefs.keyboardPosition === 'floating'
        ? this.floatingPanelHeight() : height;
      await this.panel.resize(w, h);
      hilog.info(0x0000, 'MeowpuutIME',
        `panel resized ${width}x${height} dp=${dpHeight.toFixed(1)} (${rows}行, 候选栏${region.height.toFixed(1)})`);
    } catch (e) {
      hilog.error(0x0000, 'MeowpuutIME', `panel resize failed: ${JSON.stringify(e)}`);
    }
  }

  // ---------------------------------------------------------------- 提交/删除

  private commit(text: string): void {
    if (text.length === 0 || this.inputClient === null) return;
    try {
      this.inputClient.insertTextSync(text);
    } catch (e) {
      // 回退到异步接口。
      this.inputClient.insertText(text);
    }
  }

  /**
   * 删除光标前的文字（普通退格），对应 Android deleteSurroundingText(count, 0)。
   * 重要：HarmonyOS 输入法框架的方向命名与 Android 相反——
   * deleteForward 删光标「前」、deleteBackward 删光标「后」（见 SDK d.ts 注释 +
   * metasequoiaime/msime PR #6272 真机实测）。故这里退格要用 deleteForwardSync。
   */
  private deleteBackward(count: number): void {
    if (this.inputClient === null) return;
    try {
      this.inputClient.deleteForwardSync(count);
    } catch (e) {
      this.inputClient.deleteForward(count);
    }
  }

  private moveCursor(steps: number): void {
    if (this.inputClient === null) return;
    const direction = steps < 0
      ? inputMethodEngine.Direction.CURSOR_LEFT
      : inputMethodEngine.Direction.CURSOR_RIGHT;
    try {
      for (let i = 0; i < Math.abs(steps); i++) {
        this.inputClient.moveCursorSync(direction);
      }
    } catch (e) {
      // 某些编辑框不支持逐格移动光标，忽略。
    }
  }

  private getTextBeforeCursor(length: number): string {
    if (this.inputClient === null) return '';
    try {
      // 注意命名反直觉（SDK d.ts L1230/L1279 官方文档）：
      //   getForwardSync  = 取光标「前」的文字（Obtains the text BEFORE the cursor）
      //   getBackwardSync = 取光标「后」的文字（Obtains the text AFTER the cursor）
      // 此处要取光标前，必须用 getForwardSync；错用 getBackwardSync 会导致光标在文末时
      // 取到空串，进而误判「光标前无文字」去删光标后（文末无字）→ 退格删不掉最后一个字符。
      return this.inputClient.getForwardSync(length);
    } catch (e) {
      return '';
    }
  }

  /**
   * 依编辑器字段类型自动切英文/符号页（对应 Android onStartInputView 的 inputType 检测）。
   * 数字/电话/日期字段 → 英文 + 符号页；密码/邮箱/URL 字段 → 英文。
   */
  private detectFieldType(): void {
    // 每次开始输入新字段先回到默认（英文关、字母页），再按字段类型决定。
    this.english = false;
    this.page = 0;
    if (this.inputClient === null) { this.numericField = false; return; }
    let pattern: number = inputMethodEngine.PATTERN_TEXT;
    try {
      pattern = this.inputClient.getEditorAttributeSync().inputPattern;
    } catch (e) {
      pattern = inputMethodEngine.PATTERN_TEXT;
    }
    const numeric = pattern === inputMethodEngine.PATTERN_NUMBER ||
      pattern === inputMethodEngine.PATTERN_PHONE ||
      pattern === inputMethodEngine.PATTERN_DATETIME ||
      pattern === inputMethodEngine.PATTERN_NUMBER_DECIMAL ||
      pattern === inputMethodEngine.PATTERN_ONE_TIME_CODE ||
      pattern === inputMethodEngine.PATTERN_ONE_TIME_CODE_NUMBER;
    const latin = pattern === inputMethodEngine.PATTERN_PASSWORD ||
      pattern === inputMethodEngine.PATTERN_PASSWORD_SCREEN_LOCK ||
      pattern === inputMethodEngine.PATTERN_PASSWORD_NUMBER ||
      pattern === inputMethodEngine.PATTERN_USER_NAME ||
      pattern === inputMethodEngine.PATTERN_NEW_PASSWORD ||
      pattern === inputMethodEngine.PATTERN_EMAIL ||
      pattern === inputMethodEngine.PATTERN_URI;
    this.numericField = numeric;
    if (numeric) {
      this.english = true;
      this.page = 1;
    } else if (latin) {
      this.english = true;
      this.page = 0;
    }
  }

  private editorAction(): void {
    if (this.inputClient === null) return;
    let keyType = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
    try {
      keyType = this.inputClient.getEditorAttributeSync().enterKeyType;
    } catch (e) {
      keyType = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
    }
    // 与 returnTitle() 保持一致：UNSPECIFIED / NEWLINE 都视为「换行」，插入换行符；
    // 其余（SEND/SEARCH/GO/DONE/NEXT/PREVIOUS）触发编辑器动作（对应 Android performEditorAction）。
    // 对照 Android enter()：action!=NONE && action!=UNSPECIFIED && !noAction → performEditorAction，否则 sendKeyChar('\n')。
    const newline = keyType === inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED ||
      keyType === inputMethodEngine.ENTER_KEY_TYPE_NEWLINE;
    if (newline) {
      this.commit('\n');
    } else {
      // 【实测】sendKeyFunction 的参数在当前框架实现里被直接 cast 成 EnterKeyType 透传给应用
      // （InputMethodController::SendFunctionKey → EnterKeyType(functionKey)），
      // 因此传固定值 1 会被当成 EnterKeyType(1)=NONE，微信等 RichEditor 应用收不到 SEND 语义，
      // 只能按默认动作换行。这里改为传入编辑框自己声明的 enterKeyType（微信=4=SEND），
      // 让参数与编辑框期望的动作一致。失败时退回文档写明的确认键 1。
      this.inputClient.sendKeyFunction(keyType).catch((e: BusinessError) => {
        hilog.warn(0x0000, 'MeowpuutIME', `sendKeyFunction(${keyType}) failed: ${e.code}, retry with 1`);
        this.inputClient?.sendKeyFunction(1).catch(() => {});
      });
    }
  }

  // ---------------------------------------------------------------- 引擎

  private applyEdit(edit: Edit, wasComposing: boolean, resetPanel: boolean = false): void {
    const nowComposing = this.composer.composing;
    // 预览同步必须先于 commit：组字结束选候选时，预览区承载「把 nihao 换成汉字」的动作，
    // 若先 insertText 汉字，finishTextPreview 会把残留的 nihao 也落地，导致「你好 nihao」错乱。
    this.syncComposingText(wasComposing, edit.commit);
    if (edit.commit.length > 0) {
      // 只要这次按键序列开始时处于组字态且预览可用，上屏动作就由 syncComposingText 的预览链完成：
      //   - 组字结束：setPreviewText(commit)+finishTextPreview 落地（预览区承载「nihao→汉字」替换）；
      //   - 分词（commit 后仍组字）：三步链 落地已选字+开剩余组字新预览。
      // 其余情况（非组字直接 commit、编辑框不支持预览）走 insertText 兜底，保证汉字绝不丢失。
      const committedViaPreview = wasComposing && this.previewSupported;
      if (!committedViaPreview) {
        this.commit(edit.commit);
      }
    }
    if (!nowComposing) {
      this.expanded = false;
      if (edit.commit.length > 0) {
        this.updatePredictions();
        if (wasComposing) this.host.commit();
      }
    }
    this.refreshKeyboard(resetPanel);
  }

  private previewLength: number = 0;

  /**
   * 预览同步自驱动选区变化的抑制窗口（毫秒）。
   * setPreviewText / finishTextPreview 会让编辑框光标移动并回调 on('selectionChange')；
   * 该回调原本用于「用户把光标移走时清空未完成组字」，若不加区分会把输入法自己造成的
   * 光标移动也当成用户操作，从而每敲一个字母就把上一个字母的组字状态清掉。
   * 预览调用后该窗口内的选区变化一律视为自驱动，不触发组字清理。
   */
  private static readonly SELF_DRIVEN_MS: number = 700;

  /** 最近一次预览 API 调用的时间戳（0 = 尚未调用过）。 */
  private lastPreviewAt: number = 0;

  /** 预览操作串行队列：保证跨按键的 setPreviewText/finishTextPreview 严格按序执行。 */
  private previewChain: Promise<void> = Promise.resolve();

  /** 组字预览开关。 */
  private static readonly PREVIEW_ENABLED: boolean = true;

  /** 当前编辑框是否支持文本预览（isTextPreviewSupported 探测结果）。 */
  private previewSupported: boolean = true;

  /**
   * 组字预览：把当前原始串（如 nihao）显示在输入框，选择候选后替换成汉字，
   * 与 Android applyEdit 的 setComposingText / commitText 状态机对齐。
   *
   * 【语义依据】本地 SDK @ohos.inputMethodEngine.d.ts 官方注释（权威，非二手）：
   *   setPreviewText(text, range)：
   *     - {start:-1, end:-1}        → 替换整个预览区（官方为「更新组字」设计的语义）
   *     - start === end             → 在 start 处插入 text
   *     - start !== end             → 用 text 替换 [start, end) 区间
   *     - 已有预览时 range 不得超出预览区；无预览时 range 不得超出文本框
   *   finishTextPreview()           → 预览文本「落地」（上屏为正式文本）
   *   另有官方示例 KikaInputMethod：sendKeyFunction 后紧跟 finishTextPreview 让预测词落地。
   *
   * 因此：
   *   - 组字中      → setPreviewText(preedit, {-1,-1}) 维护预览区为当前组字显示（带下划线）
   *   - 组字结束+commit → setPreviewText(commit, {-1,-1}) 把预览区换成汉字，再 finishTextPreview() 落地
   *   - 组字结束无commit → setPreviewText('', {-1,-1}) 清空预览 + finishTextPreview() 固化空（丢弃，对齐 commitText("",1)）
   * 全程不依赖 insertText 与预览区的隐式交互，语义精确对齐 Android 的 commitText 替换 composing region。
   * 注：组字显示用 composer.preedit（对齐 Android setComposingText(preedit)），拼音/注音/日语/英文四模式
   * 各自正确——拼音 preedit=raw，注音 preedit=带声调注音，日语 preedit=罗马字读音。
   */
  private syncComposingText(wasComposing: boolean, commitText: string): void {
    if (!MeowpuutAbility.PREVIEW_ENABLED) return;
    if (this.inputClient === null || !this.previewSupported) return;
    const nowComposing = this.composer.composing;
    // 对齐 Android applyEdit 的 setComposingText(composer.preedit, 1)：组字显示的是 preedit，
    // 而非 raw。两者在拼音模式相同（preedit=raw），但注音模式 preedit=带声调注音（NativeEngine.preedit）、
    // 日语模式 preedit=罗马字读音（Romaji.reading），必须用 preedit 才能在四种模式下都对齐。
    const preedit = this.composer.preedit;
    const client = this.inputClient;
    const range = { start: -1, end: -1 } as inputMethodEngine.Range;
    // 构造本次按键的预览操作配方。跨按键的 IPC 必须严格按序执行（分词链有「替换→落地→开新预览」
    // 三步，若被下一键的 setPreviewText 插队，{-1,-1} 的「沿用当前预览范围」语义会作用在错误的
    // 预览状态上），因此所有配方进入串行队列逐个执行。
    let ops: Array<() => Promise<void>> = [];
    if (nowComposing && commitText.length > 0) {
      // 分词（如 nihao 选「你」剩 hao）：预览区换成已选字 → 落地 → 剩余组字在光标处开新预览。
      // 对齐 Android commitText(commit) 结束旧 composing 后 setComposingText(preedit) 开新的。
      this.previewLength = preedit.length;
      ops = [
        () => client.setPreviewText(commitText, range),
        () => client.finishTextPreview(),
        () => client.setPreviewText(preedit, range),
      ];
    } else if (nowComposing) {
      // 组字中：预览区 = preedit（{-1,-1} 沿用当前预览范围：首次=光标处插入，之后=整区替换）。
      this.previewLength = preedit.length;
      ops = [() => client.setPreviewText(preedit, range)];
    } else if (wasComposing && commitText.length > 0) {
      // 组字结束且要上屏汉字：把预览区换成汉字，再落地。
      this.previewLength = 0;
      ops = [
        () => client.setPreviewText(commitText, range),
        () => client.finishTextPreview(),
      ];
    } else if (wasComposing) {
      // 组字结束且无提交（退格删空、取消等）：把预览区清空再落地。
      // 不能直接 finishTextPreview()——它会「固化」预览内容（把残留字符上屏），而退格删空
      // 需要的是「丢弃」（对齐 Android commitText("", 1) 清空 composing）。
      this.previewLength = 0;
      ops = [
        () => client.setPreviewText('', range),
        () => client.finishTextPreview(),
      ];
    }
    if (ops.length === 0) return;
    // 预览 API 会移动光标并回调 selectionChange，打开自驱动抑制窗口（一次按键可能触发多个回调）。
    this.lastPreviewAt = Date.now();
    const run = (): Promise<void> => {
      let p: Promise<void> = Promise.resolve();
      for (const op of ops) {
        p = p.then(() => {
          if (!this.previewSupported) return;
          this.lastPreviewAt = Date.now();
          return op();
        });
      }
      return p;
    };
    this.previewChain = this.previewChain.then(run).catch(() => {
      // 预览失败（编辑框不支持等）：置为不可用，后续走 insertText 兜底，不影响正常上屏。
      this.previewSupported = false;
    });
  }

  private finishComposition(): void {
    if (!this.composer.composing) return;
    let guard = 0;
    while (this.composer.composing && guard++ < 32) {
      const edit = this.composer.chooseHighlighted();
      if (!edit.handled) {
        this.applyEdit({ handled: true, commit: this.composer.takeLiteral() }, true);
        break;
      }
      this.applyEdit(edit, true);
    }
  }

  private updatePredictions(): void {
    if (this.chineseActive) {
      const before = this.getTextBeforeCursor(8);
      this.predictions = this.composer.predictions(before);
    } else {
      this.predictions = [];
    }
  }

  private typeEngine(code: number, alternate: string | null, asTyped: boolean = false): void {
    if (alternate !== null) {
      this.finishComposition();
      this.commit(alternate);
      this.letterTyped();
      return;
    }
    const upper = !asTyped && this.shift !== ShiftState.OFF && (this.english || this.mode !== InputMode.ZHUYIN);
    const c = upper ? String.fromCharCode(code).toUpperCase().charCodeAt(0) : code;
    if (this.english) {
      this.commit(String.fromCharCode(c));
      this.letterTyped();
      return;
    }
    if (!this.composer.ready) {
      if (this.lexiconFailed) {
        if (this.mode === InputMode.PINYIN) this.commit(String.fromCharCode(c));
        else if (this.mode === InputMode.PINYIN9 && c >= 50 && c <= 57) this.commit(String.fromCharCode(c));
        return;
      }
      this.pending.push(c);
      if (!asTyped) this.letterTyped();
      this.openLexicon();
      return;
    }
    const wasComposing = this.composer.composing;
    const edit = this.composer.type(c);
    if (!edit.handled) {
      this.finishComposition();
      this.commit(String.fromCharCode(c));
      return;
    }
    this.predictions = [];
    this.applyEdit(edit, wasComposing);
    if (!asTyped) this.letterTyped();
  }

  private typeSymbol(text: string): void {
    this.finishComposition();
    this.commit(text);
    if (this.page > 0 && !this.numericField && AUTO_RETURN_MARKS.has(text)) this.page = 0;
    this.predictions = [];
    this.refreshKeyboard();
  }

  private space(): void {
    if (this.composer.composing) {
      this.applyEdit(this.composer.space(), true);
      return;
    }
    const now = Date.now();
    if (now - this.lastSpaceAt < 320 && this.doubleSpacePeriod()) {
      this.lastSpaceAt = 0;
      return;
    }
    this.commit(' ');
    this.lastSpaceAt = now;
    this.predictions = [];
    this.updateAutoCaps();
    this.refreshKeyboard();
  }

  /** 字母或数字之后连按两下空格，替换成句号（英文 `. `，中文 `。`）。 */
  private doubleSpacePeriod(): boolean {
    const before = this.getTextBeforeCursor(2);
    if (before.length < 2 || before.charAt(1) !== ' ') return false;
    const ch = before.charAt(0);
    if (!isLetterOrDigit(ch)) return false;
    this.deleteBackward(1);
    this.commit(this.english || ch.charCodeAt(0) < 128 ? '. ' : '。');
    this.updateAutoCaps();
    this.refreshKeyboard();
    return true;
  }

  private enter(): void {
    if (this.composer.composing) {
      this.applyEdit(this.composer.chooseHighlighted(), true);
      return;
    }
    this.editorAction();
    this.predictions = [];
    this.updateAutoCaps();
    this.refreshKeyboard();
  }

  onDelete(word: boolean): void {
    if (this.composer.composing) {
      this.applyEdit(this.composer.backspace(), true);
      return;
    }
    if (this.predictions.length > 0) {
      this.predictions = [];
      this.refreshKeyboard();
    }
    // 有选中文本时，退格应删除选区内容（对照 Android onDelete 的 getSelectedText→commitText("",1)）。
    // HarmonyOS 无 getSelectedText，改用 selectionChange 回调跟踪 hasSelection。
    if (this.hasSelection) {
      this.deleteBackward(1);
      this.hasSelection = false;
      return;
    }
    const before = this.getTextBeforeCursor(word ? 48 : 16);
    if (before.length === 0) {
      // 光标前没有可删的字符（已在文本开头）。
      // 【重要】这里绝不能退化成「删光标后」——退格只能删光标前的字符，
      // 删光标后会让用户丢失光标之后的文字（真机实测曾复现：'全球ab、我' → '全球ab、'，
      // 光标后的「我」被删掉）。若焦点区确实有可删内容但取不到光标前文本，
      // 用 deleteForwardSync 兜底（按 SDK 语义它同样是删光标「前」），失败则直接不动。
      try {
        this.inputClient?.deleteForwardSync(1);
      } catch (e) {
        // 无可用接口时保持原文本不变，宁可不删也不误删光标后内容。
      }
      return;
    }
    const count = word ? TextUnits.wordLength(before) : TextUnits.lastGrapheme(before);
    this.deleteBackward(Math.max(1, count));
    if (this.english) this.updateAutoCaps();
  }

  private letterTyped(): void {
    const before = this.shift;
    this.caps.letterTyped();
    if (this.shift !== before) this.refreshKeyboard();
  }

  /**
   * 英文句首自动大写。HarmonyOS 没有 getCursorCapsMode，改用光标前文本自判：
   * 光标在开头、或紧邻的前一个非空白字符是句末标点/换行时视为句首。
   */
  private updateAutoCaps(): void {
    const before = this.shift;
    const wanted = this.english && this.cursorAtSentenceStart();
    this.caps.applyAutomatic(wanted);
    if (this.shift !== before) this.refreshKeyboard();
  }

  /** 判断光标是否处于句首（用于英文自动大写）。 */
  private cursorAtSentenceStart(): boolean {
    if (this.inputClient === null) return false;
    const before = this.getTextBeforeCursor(64);
    // 向前找到最后一个非空白字符。
    let i = before.length - 1;
    while (i >= 0 && (before.charAt(i) === ' ' || before.charAt(i) === '\t')) i--;
    if (i < 0) return true; // 开头或全空白。
    const c = before.charAt(i);
    return c === '\n' || c === '.' || c === '!' || c === '?' || c === '。' || c === '！' || c === '？';
  }

  private toggleEnglish(): void {
    this.finishComposition();
    this.english = !this.english;
    this.page = 0;
    this.caps.reset();
    this.predictions = [];
    this.refreshKeyboard();
  }

  /**
   * 地球键：结束当前组字，并轮换到下一个子类型（注音 → 拼音 → 日语 → 注音）。
   * 对应 Android 版 globe 键的语义。
   */
  private switchKeyboard(): void {
    this.finishComposition();
    this.switchSubtype();
  }

  /** 在自己的注音/全键拼音/九键拼音/日语子类型之间轮换（供设置页与地球键调用）。 */
  switchSubtype(): void {
    const order: string[] = ['MeowpuutZhuyin', 'MeowpuutPinyin', 'MeowpuutPinyin9', 'MeowpuutJapanese'];
    const current: string = this.mode === InputMode.PINYIN ? 'MeowpuutPinyin'
      : this.mode === InputMode.PINYIN9 ? 'MeowpuutPinyin9'
        : this.mode === InputMode.JAPANESE ? 'MeowpuutJapanese' : 'MeowpuutZhuyin';
    const next: string = order[(order.indexOf(current) + 1) % order.length];
    const target: InputMethodSubtype = {
      id: next,
      name: next,
      locale: next === 'MeowpuutJapanese' ? 'ja-JP'
        : next === 'MeowpuutZhuyin' ? 'zh-TW' : 'zh-CN',
      language: next === 'MeowpuutJapanese' ? 'ja'
        : next === 'MeowpuutZhuyin' ? 'zh-Hant' : 'zh-Hans',
      mode: 'lower',
    };
    inputMethod.switchCurrentInputMethodSubtype(target).then((ok: boolean) => {
      hilog.info(0x0000, 'MeowpuutIME', `switchSubtype -> ${next}: ${ok}`);
    }).catch((e: Error) => {
      hilog.warn(0x0000, 'MeowpuutIME', `switchSubtype failed: ${e.message}`);
    });
  }

  onPage(p: number): void {
    if (this.page === p) return;
    this.page = p;
    this.refreshKeyboard();
  }

  onShiftDown(): void {
    this.caps.tap(Date.now());
    this.shiftHeld = true;
    this.refreshKeyboard();
  }

  onShiftUp(typed: boolean): void {
    this.shiftHeld = false;
    if (typed && this.caps.state !== ShiftState.LOCKED) this.caps.reset();
    this.refreshKeyboard();
  }

  /**
   * 按键触觉反馈 + 音效（对应 Android MeowpuutIME.onKeyDown 的 KEYBOARD_TAP 震动
   * + AudioManager.playSoundEffect）。震动已接入；音效用 SoundPool 播 key-sounds WAV。
   */
  keyFeedback(kind: string): void {
    // 振动强度（对应 Android hapticStrength：light/medium/strong），
    // 用 startVibration 的 HapticFeedback 预设表达真正的振幅差异。
    if (this.prefs.haptics) {
      const strength = this.prefs.hapticStrength;
      const ms = strength === 'light' ? 8 : strength === 'strong' ? 16 : 12;
      this.vibrateBrief(ms, strength, 'key-press');
    }
    // 按键音效：keySound 非 system/off 时播自定义 WAV；system 档交给系统按键音，off 档静音。
    // 音效独立于震动：即便震动关闭，仍按 keySound 设置播放。
    if (this.prefs.keySound !== 'system' && this.prefs.keySound !== 'off' && this.keySounds !== null) {
      const sk = MeowpuutAbility.kindToSound(kind);
      if (sk !== null) this.keySounds.play(sk);
    }
  }

  /** 键动作 kind → 音效分类（不可归类返回 null）。 */
  private static kindToSound(kind: string): KeySoundKind | null {
    switch (kind) {
      case 'delete': return KeySoundKind.DELETE;
      case 'space': return KeySoundKind.SPACE;
      case 'return': return KeySoundKind.RETURN;
      case 'engine':
      case 'text':
      case 'shift':
      case 'globe':
      case 'toggleEnglish':
      case 'page':
        return KeySoundKind.KEY;
      default: return null;
    }
  }

  /** 删除/翻页节拍触觉反馈（对应 Android onTick 的 CLOCK_TICK）。 */
  tickFeedback(): void {
    if (!this.prefs.haptics) return;
    const strength = this.prefs.hapticStrength;
    const ms = strength === 'light' ? 5 : strength === 'strong' ? 11 : 8;
    this.vibrateBrief(ms, strength, 'tick');
  }

  /**
   * 触觉反馈：用 startVibration 的 HapticFeedback 预设 + intensity 表达真正的振幅分档
   * （light→EFFECT_SOFT/medium→EFFECT_HARD/strong→EFFECT_SHARP），而非仅靠时长微调。
   * 对照 Android MeowpuutIME 的 hapticStrength 三档触感差异。
   */
  private vibrateBrief(ms: number, strength: string, tag: string): void {
    try {
      const effectId = strength === 'light' ? 'haptic.effect.soft'
        : strength === 'strong' ? 'haptic.effect.sharp' : 'haptic.effect.hard';
      const intensity = strength === 'light' ? 40 : strength === 'strong' ? 100 : 70;
      // usage 固定 physicalFeedback（键盘触感场景）；effectId 用 HapticFeedback 预设，
      // 部分设备不支持该预设时回退到 vibrate(ms) 时长振动。
      if (vibrator.isSupportEffectSync(effectId)) {
        vibrator.startVibration({
          type: 'preset',
          effectId: effectId,
          count: 1,
          intensity: intensity,
        }, { usage: 'physicalFeedback' });
      } else {
        vibrator.vibrate(ms);
      }
    } catch (e) {
      // 某些 isolate 环境或模拟器无振子，静默失败不影响输入。
      try {
        vibrator.vibrate(ms);
      } catch (e2) {
        // 彻底静默。
      }
    }
  }

  onCursorStart(): void {
    this.finishComposition();
    this.predictions = [];
    this.refreshKeyboard();
  }

  onCursorMove(steps: number): void {
    this.moveCursor(steps);
  }

  onCandidate(index: number): void {
    const wasComposing = this.composer.composing;
    this.applyEdit(this.composer.choose(index), wasComposing, true);
    // 选候选时的音效（对应 Android playSoundEffect(KEYBOARD_TAP) / pick 音效）。
    if (this.prefs.keySound !== 'system' && this.prefs.keySound !== 'off' && this.keySounds !== null) {
      this.keySounds.play(KeySoundKind.PICK);
    }
  }

  onPrediction(text: string): void {
    this.commit(text);
    this.updatePredictions();
    this.refreshKeyboard();
  }

  onPunctuation(mark: string): void {
    this.commit(mark);
    this.predictions = [];
    this.refreshKeyboard();
  }

  onToggleExpanded(): void {
    if (!this.composer.composing && !this.expanded) return;
    this.expanded = !this.expanded;
    if (this.expanded && this.composer.candidates.length < 120) this.composer.loadMore();
    this.refreshKeyboard(true);
  }

  private onNeedMore(): void {
    if (this.composer.loadMore()) this.refreshKeyboard();
  }

  onPet(cat: string): void {
    const simplified = this.prefs.simplified;
    const w = (s1: string, s2: string) => simplified ? s2 : s1;
    // 对照 Android CandidateBarView.pet（L711-719）：拍米米莫（黑猫）只撒粒子、只做弹跳，
    // **不参与 affection 计数**，也不触发简繁切换；只有莫莫（橘猫）走5下切简繁。
    if (cat === 'mimimo') {
      this.host.announceCat('mimimo', '', -1);
      return;
    }
    const outcome = this.affection.pet(Date.now());
    let toast: string;
    let hearts = -1;
    if (outcome instanceof CatOutcomeHappy) {
      this.prefs.simplified = !simplified;
      const nowSimple = this.prefs.simplified;
      toast = nowSimple ? w('已切換為简体中文', '已切换为简体中文') : w('已切換為繁體中文', '已切换为繁体中文');
      // 非中文输入模式（英文/日文）下切换对中文生效，附注提醒（对照 Android MeowpuutIME.kt:633）。
      if (!this.chineseActive) toast += nowSimple ? '（中文输入生效）' : '（中文輸入生效）';
      this.composer.simplified = nowSimple;
      this.refreshKeyboard();
    } else if (outcome instanceof CatOutcomePleased) {
      // 对照 Android CandidateBarView.kt:722：只有 count >= 2 才显示「再摸 N 下」提示与爱心进度条，
      // 拍第 1 下不出提示（避免第一下就弹）。
      if (outcome.count >= 2) {
        hearts = outcome.count;
        const left = CatAffection.PETS_TO_SWITCH - outcome.count;
        toast = simplified ? `再摸 ${left} 下，切换为繁体` : `再摸 ${left} 下，切換為简体`;
      } else {
        toast = '';
      }
    } else {
      toast = '';
    }
    this.host.announceCat(cat, toast, hearts);
  }

  // ---------------------------------------------------------------- 词库

  private openLexicon(): void {
    const target = this.mode;
    if (this.opening === target || (this.sessionMode === target && this.composer.ready)) return;
    if (this.sessionMode !== target) this.composer.detach();
    this.opening = target;
    this.loading = target !== InputMode.JAPANESE;
    this.lexiconFailed = false;
    // 看门狗：Lexicons.open 在并发代次被顶掉时会提前 return 而不触发回调，
    // 导致 loading 永久为 true（界面一直「词库载入中」）。超时后兜底解除 loading。
    const watchdog = setTimeout(() => {
      if (this.loading && this.opening === target) {
        hilog.warn(0x0000, 'MeowpuutIME', 'lexicon open timeout, release loading state');
        this.loading = false;
        this.opening = null;
        this.lexiconFailed = true;
        this.refreshKeyboard();
      }
    }, 3000);
    this.lexicons?.open(target, (session: number) => {
      clearTimeout(watchdog);
      this.opening = null;
      this.loading = false;
      this.lexiconFailed = target !== InputMode.JAPANESE && session === 0;
      this.composer.japaneseWords = this.lexicons ? this.lexicons.japanese : JapaneseWords.EMPTY;
      this.composer.attach(target, session);
      // 九键 shadow 查询会话（pinyin 词库时 Lexicons 已备好）。
      this.composer.attachT9Shadow(this.lexicons !== null ? this.lexicons.t9Session() : 0);
      this.sessionMode = target;
      const queued = this.pending.slice();
      this.pending = [];
      if (!this.lexiconFailed) for (const code of queued) this.typeEngine(code, null, true);
      this.refreshKeyboard();
    });
    this.refreshKeyboard();
  }

  private applyLook(): void {
    const dark = this.prefs.tone === Tone.DARK ||
      (this.prefs.tone === Tone.SYSTEM &&
        this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // 节日装扮开关（prefs.festivals）实时同步到 wardrobe.on：关掉开关即不生效节日主题。
    this.festivalWardrobe.on = this.prefs.festivals;
    const festival = Festivals.theme(Festivals.today(), this.festivals, this.festivalWardrobe);
    this.festivalTheme = festival;
    const festivalPill = festival !== null
      ? parseColor((dark ? festival.colors.dark : festival.colors.light)[festival.colors.light.length - 1])
      : null;
    this.look = new Look(dark, this.prefs.shape, this.prefs.palette, this.prefs.strength,
      this.prefs.cats, festivalPill, false, this.prefs.keyPopups, this.prefs.keyboardHeight,
      this.prefs.effects);
  }

  private readRawFileText(path: string): string {
    const bytes = this.context.resourceManager.getRawFileContentSync(path);
    return this.bytesToString(bytes);
  }

  private bytesToString(bytes: Uint8Array): string {
    // festivals.json 是 UTF-8，含节日名（春節/春节 等），必须 TextDecoder 正确解码。
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  // ---------------------------------------------------------------- 展示

  private spaceTitle(): string {
    if (!this.composer.composing) return this.english ? 'space' : '空格';
    const w = (s1: string, s2: string) => this.prefs.simplified ? s2 : s1;
    switch (this.mode) {
      case InputMode.PINYIN:
      case InputMode.PINYIN9: return this.composer.candidates.length > 0 ? w('選詞', '选词') : '原文＋空格';
      case InputMode.JAPANESE: return w('選詞', '选词');
      case InputMode.ZHUYIN: {
        const last = this.composer.input.charAt(this.composer.input.length - 1);
        return ' 6347'.includes(last) ? w('選詞', '选词') : w('一聲', '一声');
      }
      default: return '空格';
    }
  }

  private returnTitle(): [string, boolean] {
    const w = (s1: string, s2: string) => this.prefs.simplified ? s2 : s1;
    if (this.composer.composing) return [w('確認', '确认'), false];
    let keyType = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
    try {
      keyType = this.inputClient?.getEditorAttributeSync().enterKeyType ??
        inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
    } catch (e) {
      keyType = inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
    }
    switch (keyType) {
      case inputMethodEngine.ENTER_KEY_TYPE_SEARCH: return [w('搜尋', '搜索'), true];
      case inputMethodEngine.ENTER_KEY_TYPE_SEND: return [w('傳送', '发送'), true];
      case inputMethodEngine.ENTER_KEY_TYPE_GO: return ['前往', true];
      case inputMethodEngine.ENTER_KEY_TYPE_DONE: return ['完成', true];
      case inputMethodEngine.ENTER_KEY_TYPE_NEXT: return ['下一步', true];
      case inputMethodEngine.ENTER_KEY_TYPE_PREVIOUS: return ['上一步', false];
      default: return [w('換行', '换行'), false];
    }
  }

  private status(): string {
    const w = (s1: string, s2: string) => this.prefs.simplified ? s2 : s1;
    if (this.loading) return w('詞庫載入中', '词库载入中');
    if (this.lexiconFailed && !this.english) return w('詞庫無法載入', '词库无法载入');
    if (this.english) return 'English';
    const script = this.prefs.simplified ? '简体' : '繁體';
    switch (this.mode) {
      case InputMode.JAPANESE: return '日本語';
      case InputMode.PINYIN: return `拼音 · ${script}`;
      case InputMode.PINYIN9: return `九键 · ${script}`;
      case InputMode.ZHUYIN: return `注音 · ${script}`;
      default: return script;
    }
  }

  refreshKeyboard(resetPanel: boolean = false): void {
    this.host.push(this.buildState(), resetPanel);
  }

  private installHostCallbacks(): void {
    this.host.callbacks = new AbilityCallbacks(this);
  }

  // ---------------------------------------------------------------- hardware keys

  /**
   * 物理键盘事件入口（对应 Android onKeyDown/onKeyUp 的合并分发）。
   * 返回 true 表示事件被消费，false 表示交还系统默认处理。
   */
  private hardwareKeyEvent(ev: InputKeyEvent): boolean {
    if (ev.action === Action.UP) {
      const code = ev.key.code;
      const consumed = this.consumedKeys.delete(code);
      return consumed;
    }
    if (ev.action !== Action.DOWN) return false;
    const keyCode = ev.key.code;
    // Ctrl/Alt/Logo(meta) 组合键交还系统（对应 Android 的 isCtrlPressed/isAltPressed/isMetaPressed）。
    if (ev.ctrlKey || ev.altKey || ev.logoKey || this.english) return false;
    const composing = this.composer.composing;
    let handled = false;
    switch (keyCode) {
      case KeyCode.KEYCODE_SPACE:
        if (composing) { this.space(); handled = true; }
        break;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        if (composing) { this.enter(); handled = true; }
        break;
      case KeyCode.KEYCODE_DEL:
        if (composing) { this.onDelete(false); handled = true; }
        break;
      case KeyCode.KEYCODE_ESCAPE:
        if (composing) {
          // Harmony 的组字只在候选栏显示、尚未写入输入框，直接清空内部状态并刷新即可。
          // （Android 需要 commitText("", 1) 清 composing span，这里无此概念。）
          this.composer.clear();
          this.expanded = false;
          this.refreshKeyboard();
          handled = true;
        }
        break;
      case KeyCode.KEYCODE_DPAD_LEFT:
      case KeyCode.KEYCODE_DPAD_RIGHT:
        if (composing) {
          this.moveHighlight(keyCode === KeyCode.KEYCODE_DPAD_LEFT ? -1 : 1);
          handled = true;
        }
        break;
      default:
        handled = this.typeHardware(ev);
    }
    if (handled) this.consumedKeys.add(keyCode);
    return handled;
  }

  /** 物理键盘字母/数字键入（对应 Android typeHardware）。 */
  private typeHardware(ev: InputKeyEvent): boolean {
    const unicode = ev.unicodeChar;
    if (unicode === 0) return false;
    const c = String.fromCharCode(unicode);
    if (this.composer.composing) {
      let digit = -1;
      if (this.mode === InputMode.PINYIN && c >= '1' && c <= '9') {
        digit = c.charCodeAt(0) - '1'.charCodeAt(0);
      } else if (this.mode === InputMode.PINYIN9 && c >= '2' && c <= '9' && this.composer.ready) {
        // 物理键盘九键：数字 2-9 直接进 T9 组字。
        this.typeEngine(c.charCodeAt(0), null, true);
        return true;
      } else if (this.mode === InputMode.ZHUYIN && ev.shiftKey) {
        digit = '!@#$%^&*('.indexOf(c);
      }
      if (digit >= 0) {
        const vis = this.visibleCandidates();
        if (digit < vis.length) this.onCandidate(vis[digit]);
        return true;
      }
    }
    let accepted = false;
    switch (this.mode) {
      case InputMode.PINYIN:
        accepted = (isAsciiLetter(c) && c.charCodeAt(0) < 128) || (c === "'" && this.composer.composing);
        break;
      case InputMode.PINYIN9:
        accepted = c >= '2' && c <= '9';
        break;
      case InputMode.JAPANESE:
        accepted = (isAsciiLetter(c) && c.charCodeAt(0) < 128) || (c === '-' && this.composer.composing);
        break;
      case InputMode.ZHUYIN:
        accepted = ZHUYIN_KEYS.indexOf(c) >= 0 || (ZHUYIN_COMPOSING_KEYS.indexOf(c) >= 0 && this.composer.composing);
        break;
    }
    if (!accepted) {
      if (this.composer.composing) this.finishComposition();
      return false;
    }
    this.typeEngine(c.charCodeAt(0), null, true);
    return true;
  }

  /** 当前可视候选的下标列表（对应 Android visibleCandidates）。 */
  private visibleCandidates(): number[] {
    const all = this.composer.candidates;
    if (this.mode === InputMode.PINYIN && !this.english) return CandidateMerge.collapsed(all);
    return all.map((_: Candidate, i: number) => i);
  }

  /** 方向键移动候选高亮（对应 Android moveHighlight）。 */
  private moveHighlight(delta: number): void {
    const visible = this.visibleCandidates();
    if (visible.length === 0) return;
    const position = Math.max(0, visible.indexOf(this.composer.highlighted));
    this.composer.highlighted = visible[(position + delta + visible.length) % visible.length];
    this.refreshKeyboard();
  }

  dispatchKey(key: Key, text: string | null): void {
    const action = key.action;
    if (action instanceof KeyActionEngine) {
      this.typeEngine(action.code, text);
    } else if (action instanceof KeyActionText) {
      this.typeSymbol(text ?? action.text);
    } else if (action instanceof KeyActionPage) {
      this.onPage(action.page);
    } else {
      switch (action.kind) {
        case 'shift': this.caps.tap(Date.now()); this.refreshKeyboard(); break;
        case 'delete': this.onDelete(false); break;
        case 'space': this.space(); break;
        case 'return': this.enter(); break;
        case 'globe': this.switchKeyboard(); break;
        case 'toggleEnglish': this.toggleEnglish(); break;
        default: break;
      }
    }
  }

  private buildState(): KeyboardState {
    const all = this.composer.candidates;
    const visible = this.visibleCandidates();
    const rt = this.returnTitle();
    const keyCtx = new KeyContext(this.mode, this.english, this.page, this.shift,
      this.prefs.simplified, !this.english, this.spaceTitle(), rt[0], rt[1], true,
      this.expanded && this.composer.composing);
    return new KeyboardState(
      this.look,
      keyCtx,
      all,
      visible,
      this.composer.highlighted,
      this.composer.composing ? [] : this.predictions,
      (!this.composer.composing && this.predictions.length === 0 &&
        this.chineseActive && !this.loading) ? QUICK_MARKS : [],
      this.status(),
      this.expanded,
      this.composer.composing && all.length > 0,
      this.composer.composing,
      this.mode === InputMode.PINYIN || this.mode === InputMode.PINYIN9,
      this.festivalTheme,
    );
  }
}

/** 是否字母或数字（用于双击空格句号判断）。 */
function isLetterOrDigit(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return (code >= 48 && code <= 57) || // 0-9
    (code >= 65 && code <= 90) ||     // A-Z
    (code >= 97 && code <= 122);      // a-z
}

/** 是否 ASCII 字母（对应 Android Kotlin 的 c.isLetter() && c.code < 128）。 */
function isAsciiLetter(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return (code >= 65 && code <= 90) || // A-Z
    (code >= 97 && code <= 122);      // a-z
}