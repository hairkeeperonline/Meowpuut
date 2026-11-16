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
  /** 原生九键会话（round 62 内核更换）：数字 2-9 直接组字，解码在引擎里。 */
  nineKeySessionCreate(lexicon: number): number;
  sessionDestroy(session: number): void;
  maxInputBytes(): number;
  /** 喂一个 ASCII 按键（或 X11 编辑键码）；返回是否被引擎接受。 */
  key(session: number, key: number): boolean;
  setSimplified(session: number, simplified: boolean): void;
  clear(session: number): void;
  choose(session: number, index: number): boolean;
  input(session: number): string;
  /** 用户手写形态的未提交输入（拼音/九键 = 敲的键，注音 = 带调符号）。 */
  inputText(session: number): string;
  preedit(session: number): string;
  /** 取得并清空引擎已提交的文本。 */
  takeCommitted(session: number): string;
  /** 该词是否属于「永不主动出」名单（学习词过滤用）。 */
  textNoSuggest(session: number, text: string): boolean;
  candidateCount(session: number): number;
  candidates(session: number, start: number, count: number): string[];
  /** 每个候选两个数字：消耗的输入字节数、MPNCandidateKind。 */
  candidateDetails(session: number, start: number, count: number): number[];
  addJapaneseWord(session: number, reading: string, text: string, weight: number): boolean;
  mixedPinyin(session: number, reading: string, simplified: boolean): string;
  /** {text, consumed} 的完整前导片段，或 null。 */
  mixedPinyinPrefix(session: number, reading: string, simplified: boolean): string[] | null;
  predict(session: number, context: string, limit: number): string[];
  /** 给中文（拼音/九键）词库挂英文词（mimo_en.bin）；必须在创建会话之前挂。 */
  attachEnglish(lexicon: number, data: Uint8Array): boolean;
  /** 打开英文引擎（mimo_en.bin，内部复制字节）；失败返回 0。 */
  englishOpen(data: Uint8Array): number;
  englishClose(english: number): void;
  englishWordCount(english: number): number;
  /** 补全：返回 [text0, kind0, text1, kind1, ...] 平铺数组；before 传 null 表示无上文。 */
  englishComplete(english: number, prefix: string, before: string | null, flags: number): Array<string | number>;
  /** 纠错（词不在词库时，dont -> don't）。 */
  englishCorrect(english: number, word: string, before: string | null, flags: number): Array<string | number>;
  /** 空格后的下一词预测。 */
  englishPredict(english: number, before: string, flags: number): Array<string | number>;
  /** 九键数字串的英文词（65 -> OK, 4663 -> good/home/gone）。 */
  englishNineKey(english: number, digits: string, before: string | null, flags: number): Array<string | number>;
  /** 该词是否在屏蔽词名单。 */
  englishIsBlocked(english: number, word: string): boolean;
}

/** 从 @ohos native 模块加载；模块名与 CMakeLists 的 add_library 一致。 */
export declare const meowpuut: MeowpuutNative;
