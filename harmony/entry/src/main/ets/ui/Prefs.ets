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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';

const MIRROR = 'meowpuut-settings.json';

/** 【跨进程同步】设置广播的载荷：变更键 + 全量快照。 */
interface SettingsBroadcast {
  key: string;
  value: string | number | boolean;
  all: Record<string, string | number | boolean>;
}

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
  static readonly KEYBOARD_POSITION = 'keyboardPosition'; // 键盘位置（bottom 贴底 / floating 悬浮）

  private store: preferences.Preferences | null = null;
  /** init 时留存的 Context（诊断/二次读取用）。 */
  private ctxRef: common.Context | null = null;
  /** 【跨进程同步】公共事件订阅者（输入法进程持有）。 */
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private pending: Map<string, string | number | boolean> = new Map();
  private changeListeners: Array<(key: string) => void> = [];

  /** 跨进程镜像的绝对路径；拿不到 filesDir 时为 null（退化成纯 Preferences）。 */
  private mirrorPath: string | null = null;
  /** 上一次读/写镜像时的原始文本，用来判断别的进程有没有改过。 */
  private mirrorRaw: string = '';
  /** 镜像内容的内存副本（读同步、写时整份落盘）。 */
  private mirror: Map<string, string | number | boolean> = new Map();
  /** 上一次 syncMirror 成功读盘的时刻（ms）；500ms 内的 getter 跳过重复读盘。 */
  private lastSyncAt: number = 0;

  /** 在拿到 Context 后调用一次。 */
  async init(context: common.Context): Promise<void> {
    this.ctxRef = context;
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
    // 重新 init 后允许下一次 getter 立即同步一次镜像。
    this.lastSyncAt = 0;
    // 【跨进程同步修复】Preferences 落盘 XML 是两个进程共享的权威存储：
    // 设置页（main 进程）写入 → IME 进程的镜像文件读不到（filesDir 进程隔离），
    // 但 XML 是同一份。所以【每次 init 都读 XML 并覆盖镜像】——只在本进程没有
    // 未落盘的 pending 写入时（此时本进程才是最新权威）。之前只在镜像为空时
    // 读 XML，导致「色调/色系改了键盘不变化」。
    if (this.pending.size === 0) this.loadPrefsXml(context);
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
      hilog.info(0x0000, 'MeowpuutPrefs', `xml loaded from ${path}: ${xml.length} bytes`);
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
      hilog.warn(0x0000, 'MeowpuutPrefs', `xml read failed ${path}: ${(e as Error).message ?? e}`);
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
  /**
   * 【跨进程同步】发布设置变更公共事件。事件数据带 {key, value, all}：
   * all 是全量快照（首次/兜底用），IME 进程收到后整份覆盖，保证单调一致。
   */
  /**
   * 【全量快照】用当前实例的真实值构建（而不是 mirror——重装后 mirror 可能为空，
   * 导致广播出去的快照只有本次改动的键，IME 冷启动恢复时缺其他键）。
   */
  private snapshotAll(): Record<string, string | number | boolean> {
    const all: Record<string, string | number | boolean> = {};
    all[Prefs.MODE] = this.mode;
    all[Prefs.SIMPLIFIED] = this.simplified;
    all[Prefs.SHAPE] = this.shape;
    all[Prefs.TONE] = this.tone;
    all[Prefs.PALETTE] = this.palette;
    all[Prefs.STRENGTH] = this.strength;
    all[Prefs.CATS] = this.cats;
    all[Prefs.FESTIVALS] = this.festivals;
    all[Prefs.HAPTICS] = this.haptics;
    all[Prefs.SOUND] = this.sound;
    all[Prefs.KEY_POPUPS] = this.keyPopups;
    all[Prefs.HAPTIC_STRENGTH] = this.hapticStrength;
    all[Prefs.KEY_SOUND] = this.keySound;
    all[Prefs.KEY_SOUND_VOLUME] = this.keySoundVolume;
    all[Prefs.KEYBOARD_HEIGHT] = this.keyboardHeight;
    all[Prefs.EFFECTS] = this.effects;
    all[Prefs.KEYBOARD_POSITION] = this.keyboardPosition;
    return all;
  }

  private broadcast(key: string, value: string | number | boolean): void {
    try {
      const all = this.snapshotAll();
      if (key !== '*') all[key] = value;   // '*' = 全量广播（publishSnapshot），不注入假键。
      const params: commonEventManager.CommonEventPublishData = {
        data: JSON.stringify({ key: key, value: value, all: all }),
      };
      commonEventManager.publish('com.krysta1ll.meowpuut.SETTINGS', params, (err: Error) => {
        if (err) hilog.warn(0x0000, 'MeowpuutPrefs', `broadcast ${key} failed: ${err.message ?? err}`);
      });
    } catch (e) {
      hilog.warn(0x0000, 'MeowpuutPrefs', `broadcast throw: ${(e as Error).message ?? e}`);
    }
  }

  /**
   * 【跨进程同步】订阅设置变更（输入法进程调用）。返回 true 表示订阅成功。
   * 收到事件即把全量快照整份写回内存（不再落盘，避免回写风暴），然后触发监听器。
   */
  subscribe(onChange: (key: string) => void): boolean {
    if (this.subscriber !== null) return true;
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = {
        events: ['com.krysta1ll.meowpuut.SETTINGS'],
      };
      commonEventManager.createSubscriber(info, (err: Error, sub: commonEventManager.CommonEventSubscriber) => {
        if (err || sub === undefined || sub === null) {
          hilog.warn(0x0000, 'MeowpuutPrefs', `createSubscriber failed: ${err?.message ?? err}`);
          return;
        }
        this.subscriber = sub;
        commonEventManager.subscribe(sub, (e: Error, data: commonEventManager.CommonEventData) => {
          if (e || data === undefined || data === null) return;
          try {
            const payload = JSON.parse(data.data ?? '{}') as SettingsBroadcast;
            const next = new Map<string, string | number | boolean>();
            const all = payload.all;
            for (const k of Object.keys(all)) next.set(k, all[k]);
            // 【自环去重】快照与当前内存副本逐键全等（IME 进程自己 put 触发的
            // 广播回环）时直接返回：跳过对同值的 17 次 store.put + flush 和一次
            // onChange 重刷（put 的交互路径已同步刷新过 UI）。设置页真实广播
            // 至少一键不同，照常穿透走完整路径。
            if (next.size === this.mirror.size) {
              let same: boolean = true;
              next.forEach((v: string | number | boolean, k: string) => {
                if (this.mirror.get(k) !== v) same = false;
              });
              if (same) return;
            }
            this.mirror = next;
            hilog.info(0x0000, 'MeowpuutPrefs', `received settings broadcast: ${payload.key}=${payload.value} (${next.size} keys)`);
            // 【冷启动恢复】把广播快照持久化进本进程沙盒：IME 重启后（此时设置页
            // 进程未必活着、广播没人发）直接从这份镜像恢复，不再回退默认值。
            this.persistSnapshot(next);
            onChange(payload.key);
          } catch (err2) {
            hilog.warn(0x0000, 'MeowpuutPrefs', `broadcast parse failed: ${(err2 as Error).message ?? err2}`);
          }
        });
      });
      return true;
    } catch (e) {
      hilog.warn(0x0000, 'MeowpuutPrefs', `subscribe throw: ${(e as Error).message ?? e}`);
      return false;
    }
  }

  /**
   * 【冷启动恢复】把全量快照写进本进程 Preferences（异步、静默失败）。
   * 只在收到设置页广播时调用：广播数据永远比本进程旧值新。
   */
  private persistSnapshot(snapshot: Map<string, string | number | boolean>): void {
    if (this.store === null) return;
    snapshot.forEach((v: string | number | boolean, k: string) => {
      this.store?.put(k, v as preferences.ValueType).catch(() => {});
    });
    this.store.flush().catch(() => {});
  }

  /**
   * 【全量广播】设置页进程在 init 完成后主动调用一次，把整份当前值推给
   * 输入法进程（IME 冷启动/漂移时的对齐兜底）。
   */
  publishSnapshot(): void {
    this.broadcast('*', '*');
  }

  private syncMirror(): void {
    if (this.mirrorPath === null) return;
    // 【热路径节流】镜像文件只做本进程持久化（filesDir 进程隔离，见文件头注释），
    // 本进程写路径 saveMirror 已同步更新内存 mirrorRaw，读盘结果恒等于内存副本；
    // 这里保留读盘兜底未知第三写者，但 500ms 内只读一次，消掉每次按键
    // buildState 多次 getter 触发的真实同步文件读。
    if (Date.now() - this.lastSyncAt < 500) return;
    try {
      const raw = fileIo.readTextSync(this.mirrorPath);
      this.lastSyncAt = Date.now();
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
      // 本进程刚写盘：清零节流，允许下一次 getter 立即重新同步一次。
      this.lastSyncAt = 0;
    } catch (e) {
      const err = e as BusinessError;
      console.warn(`Meowpuut: settings mirror write failed ${err.message}`);
    }
  }

  /** 同时写镜像和 Preferences。 */
  private applyValue(key: string, value: string | number | boolean): void {
    this.mirror.set(key, value);
    if (this.store !== null) {
      this.store.put(key, value as preferences.ValueType).then(() => {
        this.store?.flush();
        // 【跨进程同步】文件通道（filesDir 镜像与 preferences XML）在 main/inputMethod
        // 两个进程间被沙盒隔离（真机实测同一路径互相不可见），改用系统公共事件广播：
        // 设置页进程发布、输入法进程订阅，收到后热更新（无需重弹键盘）。
        this.broadcast(key, value);
      }).catch(() => {});
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

  /** 键盘位置（bottom 贴底 / floating 悬浮，默认 bottom）。 */
  get keyboardPosition(): string {
    return this.getString(Prefs.KEYBOARD_POSITION, null) === 'floating' ? 'floating' : 'bottom';
  }
  set keyboardPosition(value: string) { this.put(Prefs.KEYBOARD_POSITION, value); }

  /** 视觉特效（对应 Android effects：lightweight/standard/extreme，默认 standard）。 */
  get effects(): string {
    const v = this.getString(Prefs.EFFECTS, null);
    return v === 'lightweight' || v === 'extreme' ? v : 'standard';
  }
  set effects(value: string) { this.put(Prefs.EFFECTS, value); }
}
