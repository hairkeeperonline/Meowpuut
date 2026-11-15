/**
 * 设置（对应 Android ime/Prefs.kt）。
 *
 * 持久化用了两套通道，原因是鸿蒙的 Preferences 有进程内缓存：
 * 设置页（UIAbility 进程）改了值，输入法扩展（另一个进程）再调
 * getPreferences 拿到的还是它自己进程里的旧副本，表现为「改完模式键盘没反应」。
 *
 * 所以这里额外把整份设置镜像到 filesDir 下的一个 JSON 文件：
 * - Preferences 负责常规读写（同一进程内即时生效）；
 * - 镜像文件负责同一进程内「重启后不丢」与「绕开 Preferences 进程内缓存」。
 *
 * 注意（2026-11-14 真机实测）：两个进程的 el2 filesDir（路径字符串相同，
 * 都是 /data/storage/el2/base/haps/entry/files）是**进程隔离**的，镜像文件
 * **不能跨进程同步**——main 进程读 pinyin、inputMethod 进程读 japanese，同一路径。
 * 跨进程同步输入模式的唯一可靠通道是系统 subtype 机制
 * （switchCurrentInputMethodSubtype → setSubtype 回调），镜像文件只做本进程内持久化。
 */
import { InputMode, inputModeOf } from '../engine/Types';
import { GlassShape, glassShapeOf } from './GlassOutline';
import { Palette, paletteOf, Tone, toneOf, GlassStrength, glassStrengthOf } from './Theme';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

const MIRROR = 'meowpuut-settings.json';

export class Prefs {
  static readonly MODE = 'mode';
  static readonly SIMPLIFIED = 'simplified';
  static readonly SHAPE = 'shape';
  static readonly TONE = 'tone';
  static readonly PALETTE = 'palette';
  static readonly STRENGTH = 'strength';
  static readonly CATS = 'cats';
  static readonly FESTIVALS = 'festivals';
  static readonly HAPTICS = 'haptics';
  static readonly SOUND = 'sound';
  // 以下为 APK 0.9.1 相对仓库新增/重命名的字段（round 40 从 classes.dex 提取）。
  static readonly KEY_POPUPS = 'keyPopups';          // 按键气泡开关
  static readonly HAPTIC_STRENGTH = 'hapticStrength'; // 振动强度（light/medium/strong）
  static readonly KEY_SOUND = 'keySound';            // 按键声（system/xylophone/felt/water/overtone）
  static readonly KEY_SOUND_VOLUME = 'keySoundVolume'; // 自定义音效音量 0-100
  static readonly KEYBOARD_HEIGHT = 'keyboardHeight'; // 键盘高度（short/standard/tall）
  static readonly EFFECTS = 'effects';               // 视觉特效（lightweight/standard/extreme）

  private store: preferences.Preferences | null = null;
  private pending: Map<string, string | number | boolean> = new Map();
  private changeListeners: Array<(key: string) => void> = [];

  /** 跨进程镜像的绝对路径；拿不到 filesDir 时为 null（退化成纯 Preferences）。 */
  private mirrorPath: string | null = null;
  /** 上一次读/写镜像时的原始文本，用来判断别的进程有没有改过。 */
  private mirrorRaw: string = '';
  /** 镜像内容的内存副本（读同步、写时整份落盘）。 */
  private mirror: Map<string, string | number | boolean> = new Map();

  /** 在拿到 Context 后调用一次。 */
  async init(context: common.Context): Promise<void> {
    const options: preferences.Options = { name: 'meowpuut' };
    try {
      // 先删掉旧实例：鸿蒙的 Preferences 每个进程各有一份内存副本，
      // 不重新取就永远看不到别的进程写入的值。
      if (this.store !== null) {
        try {
          await this.store.flush();
        } catch (e) {
          // 忽略：旧实例可能已经失效。
        }
        this.store = null;
      }
      this.store = await preferences.getPreferences(context, options);
    } catch (e) {
      this.store = null;
    }
    this.mirrorPath = Prefs.resolveMirror(context);
    // 镜像优先：文件里的值比本进程 Preferences 缓存新。
    this.loadMirror();
    // 镜像读不到时，退一步直接读 Preferences 落盘的 XML——
    // 两个进程共享这个文件，但各自的 getPreferences 内存副本不会刷新。
    if (this.mirror.size === 0) this.loadPrefsXml(context);
    const pending = this.pending;
    this.pending = new Map();
    let wrote = false;
    pending.forEach((value: string | number | boolean, key: string) => {
      this.applyValue(key, value);
      wrote = true;
    });
    // 只有真的有待写入的值才落盘。否则空的 mirror 会把另一个进程
    // 已经写好的设置整份覆盖掉（这正是改完模式键盘不生效的原因之一）。
    if (wrote) this.saveMirror();
  }

  private static resolveMirror(context: common.Context): string | null {
    try {
      return `${context.filesDir}/${MIRROR}`;
    } catch (e) {
      return null;
    }
  }

  /** 读镜像文件；失败就当没有。 */
  private loadMirror(): void {
    if (this.mirrorPath === null) return;
    try {
      const raw = fileIo.readTextSync(this.mirrorPath);
      this.mirrorRaw = raw;
      this.parseInto(raw);
    } catch (e) {
      // 首次运行没有文件，属正常情况。
    }
  }

  /**
   * 直接解析 Preferences 落盘的 XML。
   *
   * 设置页和输入法扩展是两个进程，各自持有一份 Preferences 内存副本，
   * 谁都不回读磁盘。但底层文件是同一个，所以这里绕过 API 直接读文件，
   * 才能拿到另一个进程写下的新值。
   */
  private loadPrefsXml(context: common.Context): void {
    let path: string | null = null;
    try {
      path = `${(context as common.ExtensionContext).preferencesDir}/meowpuut`;
    } catch (e) {
      return;
    }
    try {
      const xml = fileIo.readTextSync(path);
      const re = /<string key="([^"]+)">([^<]*)<\/string>/g;
      const next = new Map<string, string | number | boolean>();
      let m: RegExpExecArray | null = re.exec(xml);
      while (m !== null) {
        next.set(m[1], m[2]);
        m = re.exec(xml);
      }
      const intRe = /<int key="([^"]+)" value="(-?\d+)"\/>/g;
      let n: RegExpExecArray | null = intRe.exec(xml);
      while (n !== null) {
        next.set(n[1], Number.parseInt(n[2], 10));
        n = intRe.exec(xml);
      }
      const boolRe = /<boolean key="([^"]+)" value="(true|false)"\/>/g;
      let b: RegExpExecArray | null = boolRe.exec(xml);
      while (b !== null) {
        next.set(b[1], b[2] === 'true');
        b = boolRe.exec(xml);
      }
      if (next.size > 0) {
        this.mirror = next;
      }
    } catch (e) {
      console.warn(`Meowpuut: prefs xml read failed ${path}`);
    }
  }

  /** 把 JSON 文本解析进内存副本；解析失败时保留已有内容。 */
  private parseInto(raw: string): void {    try {
      const obj = JSON.parse(raw) as Record<string, string | number | boolean>;
      const next = new Map<string, string | number | boolean>();
      for (const key of Object.keys(obj)) {
        const v = obj[key];
        if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
          next.set(key, v);
        }
      }
      // 解析成功才替换，避免文件暂时为空/半写时把已有设置抹掉。
      if (next.size > 0) this.mirror = next;
    } catch (e) {
      // 文件正在被重写，保持内存值。
    }
  }

  /**
   * 别的进程可能刚改过设置：内容变了就重新加载。
   * 直接比对文件内容而不是 mtime——mtime 精度不稳，而且两个进程
   * 可能在同一毫秒内写完，靠时间戳会漏掉更新。
   */
  private syncMirror(): void {
    if (this.mirrorPath === null) return;
    try {
      const raw = fileIo.readTextSync(this.mirrorPath);
      if (raw === this.mirrorRaw) return;
      this.mirrorRaw = raw;
      this.parseInto(raw);
    } catch (e) {
      // 文件不存在：保持内存值。
    }
  }

  private saveMirror(): void {
    if (this.mirrorPath === null) return;
    // 空 mirror 不落盘：那会覆盖掉另一个进程写好的设置。
    if (this.mirror.size === 0) return;
    try {
      const obj: Record<string, string | number | boolean> = {};
      this.mirror.forEach((v: string | number | boolean, k: string) => { obj[k] = v; });
      const raw = JSON.stringify(obj);
      const file = fileIo.openSync(this.mirrorPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, raw);
      } finally {
        fileIo.closeSync(file);
      }
      this.mirrorRaw = raw;
    } catch (e) {
      const err = e as BusinessError;
      console.warn(`Meowpuut: settings mirror write failed ${err.message}`);
    }
  }

  /** 同时写镜像和 Preferences。 */
  private applyValue(key: string, value: string | number | boolean): void {
    this.mirror.set(key, value);
    if (this.store !== null) {
      this.store.put(key, value as preferences.ValueType).then(() => this.store?.flush()).catch(() => {});
    }
  }

  onChange(listener: (key: string) => void): void {
    this.changeListeners.push(listener);
  }

  private notify(key: string): void {
    for (const l of this.changeListeners) l(key);
  }

  private put(key: string, value: string | boolean | number): void {
    if (this.store === null && this.mirrorPath === null) {
      this.pending.set(key, value);
    } else {
      this.applyValue(key, value);
      this.saveMirror();
    }
    this.notify(key);
  }

  private getString(key: string, def: string | null): string | null {
    this.syncMirror();
    const v = this.mirror.get(key);
    if (typeof v === 'string') return v;
    if (this.store !== null) {
      const s = this.store.getSync(key, def) as string | null;
      if (typeof s === 'string') return s;
    }
    const p = this.pending.get(key);
    return typeof p === 'string' ? p : def;
  }

  private getBoolean(key: string, def: boolean): boolean {
    this.syncMirror();
    const v = this.mirror.get(key);
    if (typeof v === 'boolean') return v;
    if (this.store !== null) {
      const b = this.store.getSync(key, def) as boolean;
      if (typeof b === 'boolean') return b;
    }
    const p = this.pending.get(key);
    return typeof p === 'boolean' ? p : def;
  }

  get mode(): InputMode {
    return inputModeOf(this.getString(Prefs.MODE, null));
  }
  set mode(value: InputMode) { this.put(Prefs.MODE, value); }

  /** 简体/繁體（对应 Android simplified，APK 0.9.1 fresh 默认简体=true）。 */
  get simplified(): boolean { return this.getBoolean(Prefs.SIMPLIFIED, true); }
  set simplified(value: boolean) { this.put(Prefs.SIMPLIFIED, value); }

  get shape(): GlassShape { return glassShapeOf(this.getString(Prefs.SHAPE, null)); }
  set shape(value: GlassShape) { this.put(Prefs.SHAPE, value); }

  get tone(): Tone { return toneOf(this.getString(Prefs.TONE, null)); }
  set tone(value: Tone) { this.put(Prefs.TONE, value); }

  get palette(): Palette { return paletteOf(this.getString(Prefs.PALETTE, null)); }
  set palette(value: Palette) { this.put(Prefs.PALETTE, value); }

  get strength(): GlassStrength { return glassStrengthOf(this.getString(Prefs.STRENGTH, null)); }
  set strength(value: GlassStrength) { this.put(Prefs.STRENGTH, value); }

  get cats(): boolean { return this.getBoolean(Prefs.CATS, true); }
  set cats(value: boolean) { this.put(Prefs.CATS, value); }

  get festivals(): boolean { return this.getBoolean(Prefs.FESTIVALS, true); }
  set festivals(value: boolean) { this.put(Prefs.FESTIVALS, value); }

  get haptics(): boolean { return this.getBoolean(Prefs.HAPTICS, true); }
  set haptics(value: boolean) { this.put(Prefs.HAPTICS, value); }

  get sound(): boolean { return this.getBoolean(Prefs.SOUND, false); }
  set sound(value: boolean) { this.put(Prefs.SOUND, value); }

  // —— APK 0.9.1 新增字段 ——

  /** 按键气泡（对应 Android keyPopups，默认开）。 */
  get keyPopups(): boolean { return this.getBoolean(Prefs.KEY_POPUPS, true); }
  set keyPopups(value: boolean) { this.put(Prefs.KEY_POPUPS, value); }

  /** 振动强度（对应 Android hapticStrength：light/medium/strong，默认 strong 与 Android 0.9.1 一致）。 */
  get hapticStrength(): string {
    const v = this.getString(Prefs.HAPTIC_STRENGTH, null);
    return v === 'light' || v === 'medium' ? v : 'strong';
  }
  set hapticStrength(value: string) { this.put(Prefs.HAPTIC_STRENGTH, value); }

  /** 按键声模式（对应 Android keySound 8 档：off/system/water/xylophone/glass/felt/penta/overtone，默认 system）。 */
  get keySound(): string {
    const v = this.getString(Prefs.KEY_SOUND, null);
    return v === 'off' || v === 'water' || v === 'xylophone' || v === 'glass' || v === 'felt' ||
      v === 'penta' || v === 'overtone' ? v : 'system';
  }
  set keySound(value: string) { this.put(Prefs.KEY_SOUND, value); }

  /** 自定义音效音量 0-100（对应 Android keySoundVolume，默认 100）。 */
  get keySoundVolume(): number {
    const v = this.getString(Prefs.KEY_SOUND_VOLUME, null);
    const n = v === null ? -1 : Number.parseInt(v, 10);
    return Number.isNaN(n) || n < 0 ? 100 : n;
  }
  set keySoundVolume(value: number) { this.put(Prefs.KEY_SOUND_VOLUME, `${value}`); }

  /** 键盘高度（对应 Android keyboardHeight：short/standard/tall，默认 standard）。 */
  get keyboardHeight(): string {
    const v = this.getString(Prefs.KEYBOARD_HEIGHT, null);
    return v === 'short' || v === 'tall' ? v : 'standard';
  }
  set keyboardHeight(value: string) { this.put(Prefs.KEYBOARD_HEIGHT, value); }

  /** 视觉特效（对应 Android effects：lightweight/standard/extreme，默认 standard）。 */
  get effects(): string {
    const v = this.getString(Prefs.EFFECTS, null);
    return v === 'lightweight' || v === 'extreme' ? v : 'standard';
  }
  set effects(value: string) { this.put(Prefs.EFFECTS, value); }
}
