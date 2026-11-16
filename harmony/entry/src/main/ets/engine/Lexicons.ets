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
  /** 独立英文引擎句柄（mimo_en.bin 的 MPNEnglish，0 = 未加载）。 */
  private english: number = 0;
  /** 当前会话是否九键（null = 未加载；与 loadedPinyin 一起决定会话复用）。 */
  private loadedNineKey: boolean | null = null;
  private loadedPinyin: boolean | null = null;
  private generation: number = 0;
  private _japanese: JapaneseWords = JapaneseWords.EMPTY;

  constructor(context: common.Context) {
    this.context = context;
  }

  get japanese(): JapaneseWords { return this._japanese; }

  /** ABC 模式用的英文引擎句柄（无则 0）。 */
  englishEngine(): number { return this.english; }

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
    // 九键拼音（PINYIN9）与全键拼音共用拼音词库；九键用引擎原生九键会话，
    // 两种会话类型不同（数字组字 vs 字母组字），切换模式必须重建会话。
    const pinyin = mode === InputMode.PINYIN || mode === InputMode.PINYIN9;
    const nineKey = mode === InputMode.PINYIN9;
    if (this.session !== 0 && this.loadedPinyin === pinyin && this.loadedNineKey === nineKey) {
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
    let newEnglish = 0;
    if (lex !== 0) {
      let pairs = false;
      try {
        const pairData = await this.context.resourceManager.getRawFileContent('lexicon/mimo_pairs.bin');
        pairs = NativeEngine.attachPairs(lex, pairData);
      } catch (e) {
        console.warn(`${TAG}: word-pair table unavailable`);
      }
      // 【内核更换 round 62】拼音/九键词库挂英文词（mimo_en.bin）：拼音与九键
      // 打字可直接出英文词（排在中文之后，屏蔽词永不主动出）。必须在创建
      // 会话之前挂（引擎不接受已有会话的词库再挂英文词）。
      // 【round 64 真机修复】引擎句柄先存局部变量：此前直接赋 this.english，
      // 而下方 swap 前的 this.release() 会把它 englishClose 清零——每次加载
      // 英文引擎都被立即销毁，英文预测行（ABC 模式）从未真正可用。
      if (pinyin) {
        try {
          const enData = await this.context.resourceManager.getRawFileContent('lexicon/mimo_en.bin');
          const en = NativeEngine.attachEnglish(lex, enData);
          // 同一份字节再开独立的英文引擎句柄（copy=1，引擎自行复制），
          // 供 ABC 模式的补全/纠错/下一词预测使用。
          newEnglish = NativeEngine.englishOpen(enData);
          console.info(`${TAG}: english words attached: ${en}, engine words ${NativeEngine.englishWordCount(newEnglish)}`);
        } catch (e) {
          console.warn(`${TAG}: mimo_en.bin unavailable, english words off`);
        }
      }
      // 【内核更换 round 62】九键拼音用引擎原生九键会话（数字 2-9 直接组字，
      // 解码、候选、部分消耗全部由引擎处理，替代原 ArkTS T9 组合展开层）。
      newSession = mode === InputMode.PINYIN9
        ? NativeEngine.nineKeySessionCreate(lex)
        : NativeEngine.sessionCreate(lex);
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
      // 中途被新加载取代：刚打开的英文引擎也要销毁（它已复制字节、独立于词库）。
      if (newEnglish !== 0) NativeEngine.englishClose(newEnglish);
      return;
    }
    this.release();
    this.lexicon = lex;
    this.session = newSession;
    // release 已关掉旧引擎，这里才接管新引擎（见上方修复说明）。
    this.english = newEnglish;
    this.loadedPinyin = lex !== 0 ? pinyin : null;
    this.loadedNineKey = lex !== 0 && newSession !== 0 ? nineKey : null;
    ready(newSession);
  }

  release(): void {
    if (this.session !== 0) NativeEngine.sessionDestroy(this.session);
    if (this.lexicon !== 0) NativeEngine.lexiconDestroy(this.lexicon);
    if (this.english !== 0) NativeEngine.englishClose(this.english);
    this.session = 0;
    this.english = 0;
    this.lexicon = 0;
    this.loadedPinyin = null;
    this.loadedNineKey = null;
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