/**
 * meowpuut 原生引擎的 ArkTS 类型声明（对应 src/main/cpp/napi_init.cpp 的导出）。
 * 引擎句柄以 number 表示（底层是 64 位指针，double 编码保证不丢精度）。
 */
export interface MeowpuutNative {
  /** 从 mimo_base.bin 的 Uint8Array 加载词库；pinyin=true 取拼音词表，否则取注音。 */
  lexiconCreateFromBase(data: Uint8Array, pinyin: boolean): number;
  /** 给词库附上词对表（mimo_pairs.bin）；不属于该词库则返回 false。 */
  attachPairs(lexicon: number, data: Uint8Array): boolean;
  lexiconDestroy(lexicon: number): void;
  lexiconHeapBytes(lexicon: number): number;
  sessionCreate(lexicon: number): number;
  sessionDestroy(session: number): void;
  maxInputBytes(): number;
  /** 喂一个 ASCII 按键（或 X11 编辑键码）；返回是否被引擎接受。 */
  key(session: number, key: number): boolean;
  setSimplified(session: number, simplified: boolean): void;
  clear(session: number): void;
  choose(session: number, index: number): boolean;
  input(session: number): string;
  preedit(session: number): string;
  /** 取得并清空引擎已提交的文本。 */
  takeCommitted(session: number): string;
  candidateCount(session: number): number;
  candidates(session: number, start: number, count: number): string[];
  /** 每个候选两个数字：消耗的输入字节数、MPNCandidateKind。 */
  candidateDetails(session: number, start: number, count: number): number[];
  addJapaneseWord(session: number, reading: string, text: string, weight: number): boolean;
  mixedPinyin(session: number, reading: string, simplified: boolean): string;
  /** {text, consumed} 的完整前导片段，或 null。 */
  mixedPinyinPrefix(session: number, reading: string, simplified: boolean): string[] | null;
  predict(session: number, context: string, limit: number): string[];
}

/** 从 @ohos native 模块加载；模块名与 CMakeLists 的 add_library 一致。 */
export declare const meowpuut: MeowpuutNative;