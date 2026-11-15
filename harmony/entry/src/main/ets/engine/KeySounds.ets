/**
 * 按键音效播放（对应 Android AudioManager.playSoundEffect + assets/key-sounds）。
 * HarmonyOS 无 playSoundEffect 等价物，改用 @ohos.multimedia.media 的 SoundPool
 * 播放 rawfile/key-sounds 下的 WAV（来源：Android APK 0.9.1 assets/key-sounds）。
 *
 * 五档按键声（keySound）→ 音效集目录映射：
 *   system    → glass    （系统默认玻璃声）
 *   xylophone → marimba  （木琴）
 *   felt      → felt     （毛毡）
 *   water     → water    （水滴）
 *   overtone  → harmonic （泛音）
 *
 * 每个音效集含：key-{1..4} / delete-{1..3} / space-{1..3} / return-1 / pick-{1..3}。
 * 播放同类多个变体时随机取一个，避免机械重复。
 */
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 键动作类型（对应 Android 的 key/delete/space/return/pick 音效分类）。 */
export enum KeySoundKind {
  KEY = 'key',
  DELETE = 'delete',
  SPACE = 'space',
  RETURN = 'return',
  PICK = 'pick',
}

/** keySound 档位 → 音效集目录名（对齐 Android 8 档，off=关闭不播）。 */
const SET_DIRS: Map<string, string> = new Map([
  ['system', 'glass'],
  ['water', 'water'],
  ['xylophone', 'marimba'],
  ['glass', 'glass'],
  ['felt', 'felt'],
  ['penta', 'penta'],
  ['overtone', 'harmonic'],
]);

/** 每种键动作的 WAV 变体数量。 */
const VARIANTS: Map<KeySoundKind, number> = new Map([
  [KeySoundKind.KEY, 4],
  [KeySoundKind.DELETE, 3],
  [KeySoundKind.SPACE, 3],
  [KeySoundKind.RETURN, 1],
  [KeySoundKind.PICK, 3],
]);

export class KeySounds {
  private context: common.Context;
  private pool: media.SoundPool | null = null;
  /** soundId 缓存：key = `目录/文件名`，value = soundId。 */
  private ids: Map<string, number> = new Map();
  /** 当前音量（0-100），由 keySoundVolume 驱动。 */
  private volume: number = 100;
  /** 当前音效集目录（由 keySound 档位决定）。 */
  private setDir: string = 'glass';
  /** 按键声关闭（off）时置位，play() 直接静默。 */
  private disabled: boolean = false;
  private ready: boolean = false;

  constructor(context: common.Context) {
    this.context = context;
  }

  /** 懒初始化 SoundPool（异步，失败静默，不影响输入）。 */
  init(): void {
    if (this.ready || this.pool !== null) return;
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
      rendererFlags: 0,
    };
    media.createSoundPool(4, rendererInfo).then((pool: media.SoundPool) => {
      this.pool = pool;
      this.ready = true;
      pool.on('error', (err: BusinessError) => {
        // 音效加载/播放失败不影响输入，静默。
      });
      // SoundPool 就绪后立即预加载当前音效集，消除首次按键静音。
      this.preload();
    }).catch(() => {
      this.pool = null;
    });
  }

  /** 切换按键声档位（keySound）与音量（keySoundVolume）。 */
  configure(keySound: string, keySoundVolume: number): void {
    this.setDir = SET_DIRS.get(keySound) ?? 'glass';
    this.disabled = keySound === 'off';
    this.volume = Math.min(100, Math.max(0, keySoundVolume));
    // 切档后预加载新音效集，避免首次按键因异步 load 未完成而静音。
    this.preload();
  }

  /**
   * 预加载当前音效集的所有 WAV，让首次按键即有声。
   * load() 是异步的：这里提前触发，逐条缓存到 ids；play() 命中缓存即可立即播放。
   */
  private preload(): void {
    if (this.disabled || !this.ready || this.pool === null) return;
    if (this.setDir === 'penta') {
      // penta 无 key/delete/space 常规变体，只有 key0-key5 各 2 个数字键音。
      for (let d = 0; d < 6; d++) {
        for (let v = 1; v <= 2; v++) {
          this.loadId(`key-sounds/penta/key${d}-${v}.wav`);
        }
      }
      return;
    }
    const kinds: KeySoundKind[] = [KeySoundKind.KEY, KeySoundKind.DELETE, KeySoundKind.SPACE,
      KeySoundKind.RETURN, KeySoundKind.PICK];
    for (const kind of kinds) {
      const count = VARIANTS.get(kind) ?? 1;
      for (let v = 1; v <= count; v++) {
        this.loadId(`key-sounds/${this.setDir}/${kind}-${v}.wav`);
      }
    }
  }

  /** 播放指定键动作的音效（无可用音效时静默）。 */
  play(kind: KeySoundKind): void {
    if (this.disabled || !this.ready || this.pool === null) return;
    // penta（五声）的普通键音效用 key0-key5 数字键（九键拼音音色），其余用 key-{1..4}。
    let path: string;
    if (this.setDir === 'penta' && kind === KeySoundKind.KEY) {
      const digit = Math.floor(Math.random() * 6); // key0..key5
      const variant = 1 + Math.floor(Math.random() * 2); // keyN-1 / keyN-2
      path = `key-sounds/penta/key${digit}-${variant}.wav`;
    } else {
      const count = VARIANTS.get(kind) ?? 1;
      const variant = 1 + Math.floor(Math.random() * count);
      path = `key-sounds/${this.setDir}/${kind}-${variant}.wav`;
    }
    const sid = this.loadId(path);
    if (sid <= 0) return;
    const vol = this.volume / 100;
    try {
      this.pool.play(sid, {
        leftVolume: vol,
        rightVolume: vol,
        loop: 0,
        priority: 0,
      });
    } catch (e) {
      // 播放失败静默。
    }
  }

  /** 懒加载一个 WAV 的 soundId（缓存，失败返回 0）。 */
  private loadId(path: string): number {
    const cached = this.ids.get(path);
    if (cached !== undefined) return cached;
    let sid = 0;
    try {
      const raw = this.context.resourceManager.getRawFdSync(path);
      this.pool?.load(raw.fd, raw.offset, raw.length).then((id: number) => {
        this.ids.set(path, id);
      }).catch(() => {
        this.ids.set(path, 0);
      });
      // load 是异步的，首次播放可能还没加载完；先返回 0，下次再播。
      return 0;
    } catch (e) {
      this.ids.set(path, 0);
      return 0;
    }
  }

  release(): void {
    if (this.pool !== null) {
      try {
        this.pool.release();
      } catch (e) {
        // 忽略。
      }
      this.pool = null;
    }
    this.ids.clear();
    this.ready = false;
  }
}
