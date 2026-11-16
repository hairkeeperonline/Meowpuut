/**
 * 设置页（对应 Android SettingsActivity）。
 * 提供启用输入法的引导、输入模式/配色/形状等偏好设置。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { inputMethod, InputMethodSubtype } from '@kit.IMEKit';
import { uiMaterial } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { InputMode } from '../engine/Types';
import { Prefs } from '../ui/Prefs';
import { Palette, Tone, GlassStrength, Look } from '../ui/Theme';
import { GlassShape, traceOutline } from '../ui/GlassOutline';
import { Box } from '../ui/Geometry';
import { display } from '@kit.ArkUI';

/** 输入法启用状态（对照 Android SettingsActivity.updateStatus）。 */
enum ImeStatus {
  OFF = 0,
  ENABLED = 1,
  SELECTED = 2,
}

@Entry
@Component
struct SettingsPage {
  @State private ready: boolean = false;
  @State mode: InputMode = InputMode.ZHUYIN;
  @State simplified: boolean = true;
  @State shape: GlassShape = GlassShape.CAPSULE;
  @State tone: Tone = Tone.SYSTEM;
  @State palette: Palette = Palette.ROSE;
  @State strength: GlassStrength = GlassStrength.BALANCED;
  @State cats: boolean = true;
  @State festivals: boolean = true;
  @State haptics: boolean = true;
  @State sound: boolean = false;
  // —— APK 0.9.1 新增字段 ——
  @State keyPopups: boolean = true;
  @State hapticStrength: string = 'strong';
  @State keySound: string = 'system';
  @State keySoundVolume: number = 100;
  @State keyboardHeight: string = 'standard';
  @State effects: string = 'standard';
  @State keyboardPosition: string = 'bottom';
  /** 候选栏预览里的两只猫贴图（米米莫黑猫 + 莫莫暹罗猫），从 rawfile 解码。 */
  @State private leftCat: image.PixelMap | undefined = undefined;
  @State private rightCat: image.PixelMap | undefined = undefined;
  /** 输入法启用状态（对照 Android 的 setup_off/enabled/selected）。 */
  @State private imeStatus: ImeStatus = ImeStatus.OFF;
  /** 第三方授权弹窗控制器（懒创建，内容在打开时读取）。 */
  private licenseDialog: CustomDialogController | null = null;

  private prefs: Prefs = new Prefs();
  /**
   * 鸿蒙 7.0 的沉浸式材质。设置页顶部标题区用它做成悬浮玻璃，
   * 让页面滚动的内容从玻璃下面透出来。设备不支持时留空，退回普通底色。
   */
  private headerMaterial: uiMaterial.Material | undefined = undefined;

  /** 造一份沉浸式材质；设备不支持就返回 undefined，调用方按普通背景渲染。 */
  private static makeMaterial(): uiMaterial.Material | undefined {
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) return undefined;
      const options: uiMaterial.ImmersiveOptions = {
        style: uiMaterial.ImmersiveStyle.THIN,
      };
      return new uiMaterial.ImmersiveMaterial(options);
    } catch (e) {
      return undefined;
    }
  }

  aboutToAppear(): void {
    this.headerMaterial = SettingsPage.makeMaterial();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.prefs.init(ctx).then(() => {
      this.mode = this.prefs.mode;
      this.simplified = this.prefs.simplified;
      this.shape = this.prefs.shape;
      this.tone = this.prefs.tone;
      this.palette = this.prefs.palette;
      this.strength = this.prefs.strength;
      this.cats = this.prefs.cats;
      this.festivals = this.prefs.festivals;
      this.haptics = this.prefs.haptics;
      this.sound = this.prefs.sound;
      this.keyPopups = this.prefs.keyPopups;
      this.hapticStrength = this.prefs.hapticStrength;
      this.keySound = this.prefs.keySound;
      this.keySoundVolume = this.prefs.keySoundVolume;
      this.keyboardHeight = this.prefs.keyboardHeight;
      this.effects = this.prefs.effects;
      this.keyboardPosition = this.prefs.keyboardPosition;
      this.ready = true;
      // 【跨进程对齐兜底】设置加载完成后把整份当前值推给输入法进程：
      // IME 冷启动早于设置页打开时会落后，这里主动全量广播一次补齐。
      this.prefs.publishSnapshot();
    });
    this.loadPreviewCats();
    this.updateStatus();
    // 【真机反馈 round 60-1】系统切换输入法（如切到小艺）后状态行仍显示
    // 「当前使用的键盘是喵扑」——updateStatus 原来只在 aboutToAppear 跑一次。
    // 修复：订阅系统 imeChange 事件 + 页面回前台（onPageShow）时重查。
    try {
      inputMethod.getInputMethodSetting().on('imeChange', this.imeChangeCb);
    } catch (e) {
      // 低版本无事件时依赖 onPageShow 刷新兜底。
    }
  }

  /** imeChange 回调：实例箭头函数保持稳定引用（off 时要用同一个函数）。 */
  private imeChangeCb: () => void = (): void => {
    this.updateStatus();
  };

  onPageShow(): void {
    this.updateStatus();
  }

  aboutToDisappear(): void {
    try {
      inputMethod.getInputMethodSetting().off('imeChange', this.imeChangeCb);
    } catch (e) {
      // 未订阅成功时 off 抛错可忽略。
    }
  }

  /** 解码候选栏预览的两只猫贴图（米米莫黑猫 + 莫莫暹罗猫，均 edge_peek 探头姿态）。 */
  private loadPreviewCats(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const rm = ctx.resourceManager;
    const load = (name: string, slot: 'left' | 'right'): void => {
      try {
        const bytes = rm.getRawFileContentSync(`cats/${name}.png`);
        const src = image.createImageSource(bytes.buffer as ArrayBuffer);
        src.createPixelMap((err: BusinessError, pm: image.PixelMap) => {
          if (err === undefined && pm !== undefined) {
            if (slot === 'left') this.leftCat = pm;
            else this.rightCat = pm;
          }
        });
      } catch (e) {
        // 贴图加载失败则退化回 emoji 占位。
      }
    };
    load('mimimo_edge_peek', 'left');
    load('momo_edge_peek', 'right');
  }

  /** 候选词选中态高亮 pill 色（对应 Android 的深酒红 accent）。 */
  private accent(): string {
    const look = new Look(this.tone === Tone.DARK, this.shape, this.palette, this.strength, this.cats);
    return look.accent;
  }

  /**
   * 候选栏预览内层候选条的玻璃轮廓顶点（随「造型」变化，对应 Android CandidateBarView 的
   * GlassOutline：胶囊=直边圆角、波浪=正弦丝带、云朵=云朵形）。返回 [x,y] 顶点数组供 Polygon 组件使用。
   */
  private barGlassPoints(width: number, height: number): number[][] {
    const pts = traceOutline(this.shape, new Box(0, 0, width, height), 0);
    const out: number[][] = [];
    for (const p of pts) {
      out.push([p.x, p.y]);
    }
    return out;
  }

  /** 候选栏预览内层候选条尺寸（vp）：宽=屏宽-外层 padding-两只猫，高对齐键盘候选栏玻璃 46vp。 */
  private barInnerSize(): number[] {
    const screenW = px2vp(display.getDefaultDisplaySync().width);
    const width = Math.max(200, screenW - 16 - 92);
    return [width, 46];
  }

  /** 查询输入法启用状态，显示「未启用 / 已启用 / 当前使用」。 */
  private updateStatus(): void {
    try {
      const setting = inputMethod.getInputMethodSetting();
      const current = inputMethod.getCurrentInputMethod();
      const enabled = setting.getInputMethodsSync(true).some(
        (p) => p.name === 'com.krysta1ll.meowpuut.ohos');
      if (current.name === 'com.krysta1ll.meowpuut.ohos') {
        this.imeStatus = ImeStatus.SELECTED;
      } else if (enabled) {
        this.imeStatus = ImeStatus.ENABLED;
      } else {
        this.imeStatus = ImeStatus.OFF;
      }
    } catch (e) {
      this.imeStatus = ImeStatus.OFF;
    }
  }

  /** 当前状态行的提示文案（对照 Android 的 setup_off/enabled/selected）。 */
  private statusText(): string {
    switch (this.imeStatus) {
      case ImeStatus.SELECTED: return '当前使用的键盘是喵扑。';
      case ImeStatus.ENABLED: return '喵扑已启用。在系统设置的输入法页面选择喵扑。';
      default: return '喵扑还没有启用。先在系统设置的「屏幕键盘」里开启喵扑，再切换过去。';
    }
  }

  /** 打开第三方授权弹窗。 */
  private showLicenses(): void {
    this.licenseDialog = new CustomDialogController({
      builder: LicenseDialog({}),
      autoCancel: true,
    });
    this.licenseDialog.open();
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor('#8A8A8E')
      .margin({ top: 20, bottom: 8, left: 4 })
  }

  @Builder
  note(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor('#8A8A8E')
      .opacity(0.7)
      .width('100%')
      .margin({ top: 4, bottom: 6, left: 4 })
  }

  @Builder
  rowCheck(label: string, checked: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(16).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange((v: boolean) => onChange(v))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  /** 单选下拉行（label + Select），对应 Android 的 RadioGroup 风格设置项。 */
  @Builder
  rowSelect(label: string, options: string[], selectedIndex: number,
    onSelect: (index: number) => void) {
    Row() {
      Text(label).fontSize(16).layoutWeight(1)
      Select(this.selectOptions(options))
        .selected(selectedIndex)
        .value(options[selectedIndex])
        .onSelect((index: number) => onSelect(index))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 把字符串数组转成 SelectOption[]，显式类型避免 arkts-no-untyped-obj-literals。 */
  private selectOptions(values: string[]): SelectOption[] {
    const out: SelectOption[] = [];
    for (const v of values) {
      out.push({ value: v } as SelectOption);
    }
    return out;
  }

  /** 滑块行（label + 当前值 + Slider），对应 Android 的振动强度/音效音量。enabled=false 时置灰禁用。 */
  @Builder
  rowSlider(label: string, valueText: string, value: number, min: number, max: number,
    onChange: (v: number) => void, enabled: boolean = true) {
    Column() {
      Row() {
        Text(label).fontSize(16).layoutWeight(1)
        Text(valueText).fontSize(15).fontColor(enabled ? '#8A8A8E' : '#C7C7CC')
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .enabled(enabled)
        .selectedColor(enabled ? '#FF0A59F7' : '#FFC7C7CC')
        .trackColor(enabled ? '#FFE5E5EA' : '#FFE5E5EA')
        .blockColor(enabled ? '#FFFFFFFF' : '#FFC7C7CC')
        .onChange((v: number) => onChange(v))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 禁用的滑块行（label + 当前值 + 灰色禁用 Slider），对应 Android 的自定义音效音量 SeekBar（enabled=false 占位）。 */
  @Builder
  rowSliderDisabled(label: string, valueText: string, value: number, min: number, max: number) {
    Column() {
      Row() {
        Text(label).fontSize(16).layoutWeight(1)
        Text(valueText).fontSize(15).fontColor('#8A8A8E')
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .enabled(false)
        .selectedColor('#FFC7C7CC')
        .trackColor('#FFE5E5EA')
        .blockColor('#FFC7C7CC')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /** 振动强度行（内联引用 @State，振动开关关闭时滑块置灰禁用，对应 Android 联动）。 */
  @Builder
  hapticStrengthRow() {
    Column() {
      Row() {
        Text('振动强度').fontSize(16).layoutWeight(1)
        Text(this.hapticStrength === 'light' ? '轻柔' : this.hapticStrength === 'strong' ? '强' : '标准')
          .fontSize(15)
          .fontColor(this.haptics ? '#8A8A8E' : '#C7C7CC')
      }
      .width('100%')
      Slider({ value: this.hapticStrength === 'light' ? 0 : this.hapticStrength === 'strong' ? 2 : 1,
        min: 0, max: 2, step: 1 })
        .width('100%')
        .margin({ top: 8 })
        .enabled(this.haptics)
        .selectedColor(this.haptics ? '#FF0A59F7' : '#FFC7C7CC')
        .trackColor('#FFE5E5EA')
        .blockColor(this.haptics ? '#FFFFFFFF' : '#FFC7C7CC')
        .onChange((v: number) => {
          this.hapticStrength = v === 0 ? 'light' : v === 2 ? 'strong' : 'medium';
          this.prefs.hapticStrength = this.hapticStrength;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

/** 候选栏预览（对应 Android BarPreview）：两只猫扒在候选栏两端 + 示例候选词，随配色/造型实时刷新。 */
  @Builder
  barPreview() {
    Column() {
      // 外层候选栏（对应 Android 的双层圆角横条：外浅灰白 + 内近白候选条）。
      Row() {
        // 左猫：黑猫米米莫（edge_peek 探头姿态），搭在候选条左端。
        Image(this.leftCat)
          .width(46)
          .height(46)
          .objectFit(ImageFit.Contain)
        // 候选词示例（内层近白候选条）：底层用 Polygon 画随「造型」变化的玻璃轮廓，上层叠候选词。
        Stack({ alignContent: Alignment.Start }) {
          // 玻璃轮廓：胶囊=直边圆角、波浪=正弦丝带、云朵=云朵形（对照 Android GlassOutline）。
          Polygon({ width: this.barInnerSize()[0], height: this.barInnerSize()[1] })
            .points(this.barGlassPoints(this.barInnerSize()[0], this.barInnerSize()[1]))
            .fill('#FFF4F4F6')
          Row({ space: 8 }) {
            // 选中态：accent 高亮 pill + 白字。
            Text('你好')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFFFF')
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .backgroundColor(this.accent())
              .borderRadius(12)
            // 第二个候选随简繁切换：简体「您好」/ 繁体「妳好」（对照 Android samples）。
            Text(this.simplified ? '您好' : '妳好')
              .fontSize(16)
              .fontColor('#FF171415')
            Text('你好呀')
              .fontSize(16)
              .fontColor('#FF171415')
          }
          .padding({ left: 10, right: 10 })
        }
        .layoutWeight(1)
        .height(46)
        // 右猫：暹罗猫莫莫，下方是展开箭头（chevron ⌄，对应 Android 候选栏最右端）。
        Column({ space: 0 }) {
          Image(this.rightCat)
            .width(46)
            .height(46)
            .objectFit(ImageFit.Contain)
          Text('⌄')
            .fontSize(16)
            .fontColor('#FF171415')
            .margin({ top: 0 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .backgroundColor('#FFEEF0F2')
      .borderRadius(18)
    }
    .width('100%')
    .margin({ top: 8, bottom: 8 })
  }

  build() {
    // 材质只允许挂在 Navigation 标题栏 / TabBar 里（系统会校验作用域，
    // 挂在普通 Column 上会打 "Material inactive: out of scope" 并静默不生效）。
    Navigation() {
      Column() {
        // 品牌标题由 Navigation 标题栏承载（「喵扑 Meowpuut」），此处不再重复。
        Scroll() {
          Column() {
          // 添加键盘引导（对照 Android setup_title / setup_open_settings / setup_pick）。
          Column() {
            Text('添加键盘')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            // 状态行（对照 Android 的 updateStatus）。
            Text(this.statusText())
              .fontSize(14)
              .fontColor(this.imeStatus === ImeStatus.SELECTED ? '#34C759' : '#8A8A8E')
              .width('100%')
              .margin({ top: 12 })
            // 单个按钮：打开系统设置的输入法管理页（系统页里可直接切换键盘）。
            Row({ space: 8 }) {
              Button('打开键盘设置')
                .layoutWeight(1)
                .height(44)
                .onClick(() => {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  // uri "set_input" 是系统设置的输入法切换页入口。
                  ctx.startAbility({
                    bundleName: 'com.huawei.hmos.settings',
                    abilityName: 'com.huawei.hmos.settings.MainAbility',
                    uri: 'set_input'
                  }).catch((e: BusinessError) => {
                    // 部分机型/版本没有该入口时，退回到设置首页，避免按钮点了没反应。
                    ctx.startAbility({
                      bundleName: 'com.huawei.hmos.settings',
                      abilityName: 'com.huawei.hmos.settings.MainAbility'
                    }).catch(() => {});
                  });
                })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          this.sectionTitle('输入')
          Column() {
            Row() {
              Text('输入方式').fontSize(16).layoutWeight(1)
              Select([{ value: '注音' }, { value: '全键拼音' }, { value: '九键拼音' }, { value: '日本語' }])
                .selected(this.mode === InputMode.ZHUYIN ? 0 : this.mode === InputMode.PINYIN ? 1 :
                  this.mode === InputMode.PINYIN9 ? 2 : 3)
                .value(this.mode === InputMode.ZHUYIN ? '注音' : this.mode === InputMode.PINYIN ? '全键拼音' :
                  this.mode === InputMode.PINYIN9 ? '九键拼音' : '日本語')
                .onSelect((index: number) => {
                  this.mode = index === 0 ? InputMode.ZHUYIN : index === 1 ? InputMode.PINYIN :
                    index === 2 ? InputMode.PINYIN9 : InputMode.JAPANESE;
                  this.prefs.mode = this.mode;
                  // 通过系统子类型切换通知输入法进程（跨进程 preferences 不互通，
                  // 但 switchCurrentInputMethodSubtype 会触发 setSubtype 回调）。
                  // 九键拼音（index 2）：T9 纯 ArkTS 实现（T9.ets 数字→音节切分→
                  // 影子会话重放），subtype 走 Pinyin9（加载拼音词库，见 PARITY round 57）。
                  const subtypeId = index === 0 ? 'MeowpuutZhuyin'
                    : index === 1 ? 'MeowpuutPinyin' : index === 2 ? 'MeowpuutPinyin9' : 'MeowpuutJapanese';
                  // name 必须是 bundle 名（系统注册时就是这么填的），
                  // 填成 subtypeId 会导致切换被拒绝、IME 收到 id=undefined。
                  const subtype: InputMethodSubtype = {
                    id: subtypeId,
                    name: 'com.krysta1ll.meowpuut.ohos',
                    locale: index === 3 ? 'ja-JP' : (index === 0 ? 'zh-TW' : 'zh-CN'),
                    language: index === 3 ? 'ja' : (index === 0 ? 'zh-Hant' : 'zh-Hans'),
                    mode: 'lower',
                  };
                  inputMethod.switchCurrentInputMethodSubtype(subtype)
                    .catch((e: BusinessError) => {
                      console.warn(`Meowpuut: switch subtype ${subtypeId} failed ${e.message}`);
                    });
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ bottom: 8 })

          this.rowSelect('中文', ['繁體', '简体'],
            this.simplified ? 1 : 0,
            (index: number) => {
              this.simplified = index === 1;
              this.prefs.simplified = this.simplified;
            })
          this.note('在键盘上连续轻摸莫莫五下，也能切换简体／繁体。')

          // 试打（对照 Android try_title，在「输入」之后）。
          this.sectionTitle('试打')
          TextArea({ placeholder: '在这里试打' })
            .width('100%')
            .height(96)

          this.sectionTitle('外观')

          // —— APK 0.9.1 外观 section 顺序对齐：候选栏预览 / 视觉特效 / 键盘高度 / 键盘位置 ——
          this.barPreview()

          // 视觉特效：Android 为三段式 SeekBar（轻量/标准/极致），Harmony 用 3 档 Slider。
          // 注意：@Builder 参数按值传递不响应 @State 变化（真机实测 valueText 不刷新），
          // 这里内联展开，文本直接绑定 this.effects 保证档位变化即时可见。
          Column() {
            Row() {
              Text('视觉特效').fontSize(16).layoutWeight(1)
              Text(this.effects === 'lightweight' ? '轻量' : this.effects === 'extreme' ? '极致' : '标准')
                .fontSize(15).fontColor('#8A8A8E')
            }
            .width('100%')
            Slider({ value: this.effects === 'lightweight' ? 0 : this.effects === 'extreme' ? 2 : 1, min: 0, max: 2, step: 1 })
              .width('100%')
              .margin({ top: 8 })
              .selectedColor('#FF0A59F7')
              .trackColor('#FFE5E5EA')
              .blockColor('#FFFFFFFF')
              .onChange((v: number) => {
                this.effects = v === 0 ? 'lightweight' : v === 2 ? 'extreme' : 'standard';
                this.prefs.effects = this.effects;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          this.note('轻量减少动效。极致让候选栏、键帽和底板更通透。')

          this.rowSelect('键盘高度',
            ['较矮', '标准', '较高'],
            this.keyboardHeight === 'short' ? 0 : this.keyboardHeight === 'tall' ? 2 : 1,
            (index: number) => {
              this.keyboardHeight = index === 0 ? 'short' : index === 2 ? 'tall' : 'standard';
              this.prefs.keyboardHeight = this.keyboardHeight;
            })

          // 键盘位置（Android 0.9.1 两档：贴底 / 悬浮）。
          // 悬浮：panel 切 FLG_FLOATING + moveTo 抬高，键盘顶部带拖动条可拖动（真机验证）。
          this.rowSelect('键盘位置',
            ['贴底', '悬浮'],
            this.keyboardPosition === 'floating' ? 1 : 0,
            (index: number) => {
              this.keyboardPosition = index === 1 ? 'floating' : 'bottom';
              this.prefs.keyboardPosition = this.keyboardPosition;
            })

          Column() {
            Row() {
              Text('造型').fontSize(16).layoutWeight(1)
              Select([{ value: '胶囊' }, { value: '波浪' }, { value: '云朵' }])
                .selected(this.shape === GlassShape.CAPSULE ? 0 : this.shape === GlassShape.WAVE ? 1 : 2)
                .value(this.shape === GlassShape.CAPSULE ? '胶囊' : this.shape === GlassShape.WAVE ? '波浪' : '云朵')
                .onSelect((index: number) => {
                  this.shape = index === 0 ? GlassShape.CAPSULE : index === 1 ? GlassShape.WAVE : GlassShape.CLOUD;
                  this.prefs.shape = this.shape;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })

            Divider().color('#E5E5EA').margin({ left: 16 })

            Row() {
              Text('色调').fontSize(16).layoutWeight(1)
              Select([{ value: '跟随系统' }, { value: '浅色' }, { value: '深色' }])
                .selected(this.tone === Tone.SYSTEM ? 0 : this.tone === Tone.LIGHT ? 1 : 2)
                .value(this.tone === Tone.SYSTEM ? '跟随系统' : this.tone === Tone.LIGHT ? '浅色' : '深色')
                .onSelect((index: number) => {
                  this.tone = index === 0 ? Tone.SYSTEM : index === 1 ? Tone.LIGHT : Tone.DARK;
                  this.prefs.tone = this.tone;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })

            Divider().color('#E5E5EA').margin({ left: 16 })

            Row() {
              Text('色系').fontSize(16).layoutWeight(1)
              Select([{ value: '玫瑰奶茶' }, { value: '海盐蓝' }, { value: '鼠尾草绿' },
                { value: '雾紫' }, { value: '琥珀蜜' }, { value: '石墨' }])
                .selected(this.palette === Palette.ROSE ? 0 : this.palette === Palette.OCEAN ? 1 :
                  this.palette === Palette.SAGE ? 2 : this.palette === Palette.LAVENDER ? 3 :
                  this.palette === Palette.AMBER ? 4 : 5)
                .value(this.palette === Palette.ROSE ? '玫瑰奶茶' : this.palette === Palette.OCEAN ? '海盐蓝' :
                  this.palette === Palette.SAGE ? '鼠尾草绿' : this.palette === Palette.LAVENDER ? '雾紫' :
                  this.palette === Palette.AMBER ? '琥珀蜜' : '石墨')
                .onSelect((index: number) => {
                  const list = [Palette.ROSE, Palette.OCEAN, Palette.SAGE,
                    Palette.LAVENDER, Palette.AMBER, Palette.GRAPHITE];
                  this.palette = list[index];
                  this.prefs.palette = this.palette;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })

            Divider().color('#E5E5EA').margin({ left: 16 })

            Row() {
              Text('玻璃强度').fontSize(16).layoutWeight(1)
              Select([{ value: '柔和' }, { value: '标准' }, { value: '通透' }])
                .selected(this.strength === GlassStrength.SOFT ? 0 :
                  this.strength === GlassStrength.BALANCED ? 1 : 2)
                .value(this.strength === GlassStrength.SOFT ? '柔和' :
                  this.strength === GlassStrength.BALANCED ? '标准' : '通透')
                .onSelect((index: number) => {
                  this.strength = index === 0 ? GlassStrength.SOFT :
                    index === 1 ? GlassStrength.BALANCED : GlassStrength.VIVID;
                  this.prefs.strength = this.strength;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          this.rowCheck('米米莫与莫莫', this.cats, (v: boolean) => {
            this.cats = v;
            this.prefs.cats = v;
          })
          this.rowCheck('节日装扮', this.festivals, (v: boolean) => {
            this.festivals = v;
            this.prefs.festivals = v;
          })
          this.note('节日期间，米米莫和莫莫会换上节日的衣服。')

          // —— 按键反馈 section（对应 Android feedback_title）——
          this.sectionTitle('按键反馈')
          this.rowCheck('按键气泡', this.keyPopups, (v: boolean) => {
            this.keyPopups = v;
            this.prefs.keyPopups = v;
          })
          this.rowCheck('振动', this.haptics, (v: boolean) => {
            this.haptics = v;
            this.prefs.haptics = v;
          })
          this.hapticStrengthRow()
          this.rowSelect('按键声',
            ['关闭', '系统', '水滴', '木琴', '玻璃', '毛毡', '五声', '泛音'],
            this.keySound === 'off' ? 0 : this.keySound === 'system' ? 1 :
              this.keySound === 'water' ? 2 : this.keySound === 'xylophone' ? 3 :
                this.keySound === 'glass' ? 4 : this.keySound === 'felt' ? 5 :
                  this.keySound === 'penta' ? 6 : 7,
            (index: number) => {
              this.keySound = index === 0 ? 'off' : index === 1 ? 'system' :
                index === 2 ? 'water' : index === 3 ? 'xylophone' :
                  index === 4 ? 'glass' : index === 5 ? 'felt' :
                    index === 6 ? 'penta' : 'overtone';
              this.prefs.keySound = this.keySound;
            })
          // 自定义音效音量：Android 为 enabled=false 的 SeekBar（100% 禁用占位）。
          this.rowSliderDisabled('自定义音效音量', '100%', 100, 0, 100)

          // 第三方授权：Android 为卡片外的玫瑰藕粉纯文字链接（无按钮背景、无 chevron、无版本号）。
          Row() {
            Text('第三方授权')
              .fontSize(16)
              .fontColor(this.accent())
              .onClick(() => this.showLicenses())
          }
          .width('100%')
          .margin({ top: 16, bottom: 40 })
        }
        .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F2F2F7')
    }
    .title('喵扑 Meowpuut', {
      // 沉浸式材质：标题栏像悬浮玻璃，内容滚过时透出真实模糊。
      systemMaterial: this.headerMaterial,
    })
    .titleMode(NavigationTitleMode.Full)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
  }
}

/**
 * 第三方授权弹窗（对照 Android SettingsActivity.showLicenses）。
 * 读取 rawfile/licenses 下的许可文件并展示；无文件时给出说明。
 */
@CustomDialog
struct LicenseDialog {
  controller?: CustomDialogController;
  @State private text: string = '';

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const rm = ctx.resourceManager;
      const files = rm.getRawFileListSync('licenses').sort();
      const parts: string[] = [];
      for (const name of files) {
        const bytes = rm.getRawFileContentSync(`licenses/${name}`);
        const body = util.TextDecoder.create('utf-8').decodeToString(bytes);
        parts.push(`■ ${name}\n\n${body}`);
      }
      this.text = parts.length > 0
        ? parts.join('\n\n')
        : '暂无第三方授权清单。';
    } catch (e) {
      this.text = '暂无第三方授权清单。';
    }
  }

  build() {
    Column() {
      Scroll() {
        Text(this.text)
          .fontSize(12)
          .lineHeight(18)
          .width('100%')
          .copyOption(CopyOptions.LocalDevice)
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      Button('关闭')
        .height(44)
        .margin({ top: 12 })
        .onClick(() => {
          if (this.controller) this.controller.close();
        })
    }
    .width('100%')
    .height('80%')
    .padding(16)
  }
}
