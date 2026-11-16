/**
 * 原生引擎的加载与封装（对应 Android engine/NativeEngine.kt）。
 * 词库以 Uint8Array 传入（由上层用 resourceManager 读取 rawfile）。
 */
/**
 * NAPI 模块用 napi_module_register 自注册，模块名 "meowpuut"，
 * 库文件是 libmeowpuut_napi.so。ArkTS 侧要按「默认导入整个模块」写，
 * 不能用具名导入——具名导入会去找 .so 的导出符号，
 * 报 "does not provide an export name 'meowpuut'"，中文引擎整块失效。
 */
import meowpuut from 'libmeowpuut_napi.so';

export class NativeEngine {
  static readonly KEY_BACKSPACE = 0xff08;
  static readonly KEY_RETURN = 0xff0d;
  static readonly KEY_ESCAPE = 0xff1b;

  static readonly KIND_EXACT = 1;

  static lexiconCreateFromBase(data: Uint8Array, pinyin: boolean): number {
    return meowpuut.lexiconCreateFromBase(data, pinyin);
  }

  static attachPairs(lexicon: number, data: Uint8Array): boolean {
    return meowpuut.attachPairs(lexicon, data);
  }

  static lexiconDestroy(lexicon: number): void {
    meowpuut.lexiconDestroy(lexicon);
  }

  static lexiconHeapBytes(lexicon: number): number {
    return meowpuut.lexiconHeapBytes(lexicon);
  }

  static sessionCreate(lexicon: number): number {
    return meowpuut.sessionCreate(lexicon);
  }

  static sessionDestroy(session: number): void {
    meowpuut.sessionDestroy(session);
  }

  static maxInputBytes(): number {
    return meowpuut.maxInputBytes();
  }

  static key(session: number, key: number): boolean {
    return meowpuut.key(session, key);
  }

  static setSimplified(session: number, simplified: boolean): void {
    meowpuut.setSimplified(session, simplified);
  }

  static clear(session: number): void {
    meowpuut.clear(session);
  }

  static choose(session: number, index: number): boolean {
    return meowpuut.choose(session, index);
  }

  static input(session: number): string {
    return meowpuut.input(session);
  }

  static preedit(session: number): string {
    return meowpuut.preedit(session);
  }

  static takeCommitted(session: number): string {
    return meowpuut.takeCommitted(session);
  }

  static candidateCount(session: number): number {
    return meowpuut.candidateCount(session);
  }

  static candidates(session: number, start: number, count: number): string[] {
    return meowpuut.candidates(session, start, count);
  }

  /** 每个候选两个数字：消耗的输入字节数、MPNCandidateKind。 */
  static candidateDetails(session: number, start: number, count: number): number[] {
    return meowpuut.candidateDetails(session, start, count);
  }

  static addJapaneseWord(session: number, reading: string, text: string, weight: number): boolean {
    return meowpuut.addJapaneseWord(session, reading, text, weight);
  }

  static mixedPinyin(session: number, reading: string, simplified: boolean): string {
    return meowpuut.mixedPinyin(session, reading, simplified);
  }

  static mixedPinyinPrefix(session: number, reading: string, simplified: boolean): string[] | null {
    return meowpuut.mixedPinyinPrefix(session, reading, simplified);
  }

  static predict(session: number, context: string, limit: number): string[] {
    return meowpuut.predict(session, context, limit);
  }

  // ---------------- 新内核（Meowpuut-Core 0.8） ----------------

  /** 原生九键会话：数字 2-9 直接进组字，解码由引擎完成（替代 ArkTS T9 展开）。 */
  static nineKeySessionCreate(lexicon: number): number {
    return meowpuut.nineKeySessionCreate(lexicon);
  }

  /** 用户手写形态的未提交输入（拼音/九键 = 敲的键，注音 = 带调符号）。 */
  static inputText(session: number): string {
    return meowpuut.inputText(session);
  }

  /** 该词是否属于「永不主动出」名单（学习词过滤用）。 */
  static textNoSuggest(session: number, text: string): boolean {
    return meowpuut.textNoSuggest(session, text);
  }

  /** 给中文词库挂英文词（拼音/九键打字可出英文词，排在中文之后）。 */
  static attachEnglish(lexicon: number, data: Uint8Array): boolean {
    return meowpuut.attachEnglish(lexicon, data);
  }

  /** 英文引擎常量（对应 meowpuut.h）。 */
  static readonly ENGLISH_SHIFT = 1;
  static readonly ENGLISH_CAPS_LOCK = 2;
  static readonly ENGLISH_KIND_EXACT = 1;
  static readonly ENGLISH_KIND_COMPLETION = 2;
  static readonly ENGLISH_KIND_CORRECTION = 3;
  static readonly ENGLISH_KIND_PREDICTION = 4;
  static readonly ENGLISH_KIND_LETTERS = 5;

  static englishOpen(data: Uint8Array): number {
    return meowpuut.englishOpen(data);
  }

  static englishClose(english: number): void {
    meowpuut.englishClose(english);
  }

  static englishWordCount(english: number): number {
    return meowpuut.englishWordCount(english);
  }

  /** 完成词：返回 [text0, kind0, text1, kind1, ...] 平铺数组。 */
  static englishComplete(english: number, prefix: string, before: string | null, flags: number): Array<string | number> {
    return meowpuut.englishComplete(english, prefix, before, flags);
  }

  /** 纠错（词不在词库时，dont -> don't）。 */
  static englishCorrect(english: number, word: string, before: string | null, flags: number): Array<string | number> {
    return meowpuut.englishCorrect(english, word, before, flags);
  }

  /** 空格后的下一个词预测。 */
  static englishPredict(english: number, before: string, flags: number): Array<string | number> {
    return meowpuut.englishPredict(english, before, flags);
  }

  /** 九键数字串的英文词（65 -> OK, 4663 -> good/home/gone）。 */
  static englishNineKey(english: number, digits: string, before: string | null, flags: number): Array<string | number> {
    return meowpuut.englishNineKey(english, digits, before, flags);
  }

  /** 该词是否在屏蔽词名单。 */
  static englishIsBlocked(english: number, word: string): boolean {
    return meowpuut.englishIsBlocked(english, word);
  }
}