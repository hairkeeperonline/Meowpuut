/**
 * 词库加载（对应 Android engine/Lexicons.kt）。拼音和注音从同一份 mimo_base.bin 加载，
 * 通过 resourceManager 读成 Uint8Array 交给原生引擎原地读。日文词表从 native-japanese.tsv。
 */
import { InputMode } from './Types';
import { NativeEngine } from './NativeEngine';
import { JapaneseWords, BestEntry } from './JapaneseWords';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const TAG = 'Meowpuut';

export class Lexicons {
  private context: common.Context;
  private lexicon: number = 0;
  private session: number = 0;
  /** 九键 T9 查询用 shadow 会话（同一词库第二个 session）。 */
  private t9Shadow: number = 0;
  private loadedPinyin: boolean | null = null;
  private generation: number = 0;
  private _japanese: JapaneseWords = JapaneseWords.EMPTY;

  constructor(context: common.Context) {
    this.context = context;
  }

  get japanese(): JapaneseWords { return this._japanese; }

  /**
   * 为 [mode] 打开词库会话（日语模式返回 0，因为日语不需要中文词库）。
   * ready 回调拿到会话句柄（失败为 0）。
   */
  async open(mode: InputMode, ready: (session: number) => void): Promise<void> {
    const token = ++this.generation;
    if (mode === InputMode.JAPANESE) {
      this.release();
      await this.loadJapanese();
      if (token === this.generation) ready(0);
      return;
    }
    // 九键拼音（PINYIN9）与全键拼音共用拼音词库（T9 组合在 ArkTS 侧展开成字母序列）。
    const pinyin = mode === InputMode.PINYIN || mode === InputMode.PINYIN9;
    if (this.session !== 0 && this.loadedPinyin === pinyin) {
      ready(this.session);
      return;
    }
    await this.loadJapanese();
    const started = Date.now();
    let lex = 0;
    try {
      // 用异步 getRawFileContent（Promise），避免大词库文件阻塞主线程。
      const data = await this.context.resourceManager.getRawFileContent('lexicon/mimo_base.bin');
      lex = NativeEngine.lexiconCreateFromBase(data, pinyin);
    } catch (e) {
      console.error(`${TAG}: lexicon unavailable`, (e as BusinessError).message);
      lex = 0;
    }
    let newSession = 0;
    if (lex !== 0) {
      let pairs = false;
      try {
        const pairData = await this.context.resourceManager.getRawFileContent('lexicon/mimo_pairs.bin');
        pairs = NativeEngine.attachPairs(lex, pairData);
      } catch (e) {
        console.warn(`${TAG}: word-pair table unavailable`);
      }
      newSession = NativeEngine.sessionCreate(lex);
      let mixed = 0;
      if (pinyin && newSession !== 0) {
        const best: BestEntry[] = this._japanese.best();
        for (let bi = 0; bi < best.length; bi++) {
          const entry = best[bi];
          if (NativeEngine.addJapaneseWord(newSession, entry.reading, entry.text, entry.weight)) mixed++;
        }
      }
      console.info(`${TAG}: lexicon ${pinyin ? 'pinyin' : 'zhuyin'} ready in ${Date.now() - started} ms, ` +
        `${Math.floor(NativeEngine.lexiconHeapBytes(lex) / 1024)} KiB, word pairs ${pairs ? 'on' : 'off'}, ` +
        `${mixed} Japanese words for mixed typing`);
    }
    if (token !== this.generation) {
      if (newSession !== 0) NativeEngine.sessionDestroy(newSession);
      if (lex !== 0) NativeEngine.lexiconDestroy(lex);
      return;
    }
    this.release();
    this.lexicon = lex;
    this.session = newSession;
    this.loadedPinyin = lex !== 0 ? pinyin : null;
    // 九键 shadow：同一词库再开一个查询专用 session（sessionCreate 多开安全，Arc 共享）。
    if (lex !== 0 && pinyin) {
      this.t9Shadow = NativeEngine.sessionCreate(lex);
    } else {
      this.t9Shadow = 0;
    }
    ready(newSession);
  }

  release(): void {
    if (this.session !== 0) NativeEngine.sessionDestroy(this.session);
    if (this.t9Shadow !== 0) NativeEngine.sessionDestroy(this.t9Shadow);
    if (this.lexicon !== 0) NativeEngine.lexiconDestroy(this.lexicon);
    this.session = 0;
    this.t9Shadow = 0;
    this.lexicon = 0;
    this.loadedPinyin = null;
  }

  /** 九键 T9 查询会话（无则 0）。 */
  t9Session(): number {
    return this.t9Shadow;
  }

  shutdown(): void {
    this.generation++;
    this.release();
  }

  private async loadJapanese(): Promise<void> {
    if (this._japanese.size > 0) return;
    try {
      const bytes = await this.context.resourceManager.getRawFileContent('lexicon/native-japanese.tsv');
      const text = this.bytesToString(bytes);
      this._japanese = JapaneseWords.parse(text);
    } catch (e) {
      console.warn(`${TAG}: Japanese word list unavailable`);
      this._japanese = JapaneseWords.EMPTY;
    }
    console.info(`${TAG}: mimo-jp: ${this._japanese.size} readings`);
  }

  private bytesToString(bytes: Uint8Array): string {
    // native-japanese.tsv 是 UTF-8；不能逐字节 fromCharCode（那样按 Latin-1 拆字节，
    // 日文假名/汉字会变成 mojibake）。必须用 TextDecoder 做真正的 UTF-8 解码。
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }
}