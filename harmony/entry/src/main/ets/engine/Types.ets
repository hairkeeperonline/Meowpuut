/**
 * 引擎的类型和候选数据结构（对应 Android engine/Candidates.kt）。
 */

/** 输入模式。 */
export enum InputMode {
  PINYIN = 'pinyin',
  ZHUYIN = 'zhuyin',
  JAPANESE = 'japanese',
  /** 九键拼音（APK 0.9.1 新增）：设置页显示层已对齐，T9 引擎与 3×4 数字键盘暂未实现，
   *  选择后引擎降级到全键拼音（见 SettingsPage 注释 + PARITY round 56）。 */
  PINYIN9 = 'pinyin9',
}

export function inputModeOf(key: string | undefined | null): InputMode {
  if (key === InputMode.PINYIN) return InputMode.PINYIN;
  if (key === InputMode.ZHUYIN) return InputMode.ZHUYIN;
  if (key === InputMode.JAPANESE) return InputMode.JAPANESE;
  if (key === InputMode.PINYIN9) return InputMode.PINYIN9;
  return InputMode.ZHUYIN;
}

/** 候选来源。 */
export enum CandidateKind {
  CHINESE = 'CHINESE',
  JAPANESE_WORD = 'JAPANESE_WORD',
  MIXED = 'MIXED',
  MIXED_PREFIX = 'MIXED_PREFIX',
  KANA = 'KANA',
  LITERAL = 'LITERAL',
}

/** 一个候选。coreIndex 指向引擎自己的列表；consumed 是选它消耗的输入字节数。 */
export interface Candidate {
  text: string;
  kind: CandidateKind;
  coreIndex: number;
  consumed: number;
}

export function isJapanese(c: Candidate): boolean {
  return c.kind === CandidateKind.JAPANESE_WORD || c.kind === CandidateKind.MIXED ||
    c.kind === CandidateKind.MIXED_PREFIX || c.kind === CandidateKind.KANA;
}

/** 引擎报出的一个中文候选。 */
export interface CoreCandidate {
  text: string;
  index: number;
  consumed: number;
  exact: boolean;
}

/** 一次按键动作的结果：是否被处理，以及要送入编辑框的文本。 */
export interface Edit {
  handled: boolean;
  commit: string;
}