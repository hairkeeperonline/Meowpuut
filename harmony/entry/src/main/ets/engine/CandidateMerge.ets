/**
 * 候选排序与合并（对应 Android engine/Candidates.kt 的 CandidateMerge）。
 */
import { Candidate, CandidateKind, CoreCandidate, isJapanese } from './Types';
import { Romaji } from './Romaji';

export class CandidateMerge {
  /**
   * 拼音组字的候选排序（docs/DESIGN.md §4）：中文在前，一个日语解释靠前，
   * 原始字母保持在可及处，其余日语读法排到第一页之后。
   */
  static pinyin(
    input: string,
    typed: string,
    chinese: CoreCandidate[],
    japaneseWord: string | null,
    mixedWhole: string | null,
    mixedPrefix: [string, number] | null,
    kana: string | null,
    moreJapanese: string[] = [],
  ): Candidate[] {
    const length = input.length;
    const list: Candidate[] = [];
    const seen = new Set<string>();
    for (const c of chinese) {
      if (c.text.length > 0 && !seen.has(c.text)) {
        seen.add(c.text);
        list.push({ text: c.text, kind: CandidateKind.CHINESE, coreIndex: c.index, consumed: c.consumed });
      }
    }
    const top = chinese.length > 0 ? chinese[0] : undefined;
    const topComplete = top !== undefined && top.exact && top.consumed >= length;

    let best: Candidate | null = null;
    if (japaneseWord !== null && !seen.has(japaneseWord)) {
      best = { text: japaneseWord, kind: CandidateKind.JAPANESE_WORD, coreIndex: -1, consumed: length };
    } else if (mixedWhole !== null && mixedWhole.length > 0 && !seen.has(mixedWhole)) {
      best = { text: mixedWhole, kind: CandidateKind.MIXED, coreIndex: -1, consumed: length };
    } else if (mixedPrefix !== null && !seen.has(mixedPrefix[0]) &&
      mixedPrefix[1] >= 1 && mixedPrefix[1] < length) {
      best = { text: mixedPrefix[0], kind: CandidateKind.MIXED_PREFIX, coreIndex: -1, consumed: mixedPrefix[1] };
    }
    if (best !== null) {
      seen.add(best.text);
      let position: number;
      if (list.length === 0) {
        position = 0;
      } else if (best.consumed >= length && !topComplete) {
        position = 0;
      } else {
        position = Math.min(2, list.length);
      }
      list.splice(position, 0, best);
    }

    const extras: Candidate[] = [];
    if (mixedPrefix !== null && mixedPrefix[1] >= 1 && mixedPrefix[1] < length &&
      !seen.has(mixedPrefix[0])) {
      seen.add(mixedPrefix[0]);
      extras.push({ text: mixedPrefix[0], kind: CandidateKind.MIXED_PREFIX, coreIndex: -1, consumed: mixedPrefix[1] });
    }
    if (kana !== null && length >= 2) {
      const rk = Romaji.isKana(kana);
      if (rk) {
        if (!seen.has(kana)) { seen.add(kana); extras.push({ text: kana, kind: CandidateKind.KANA, coreIndex: -1, consumed: length }); }
        const katakana = Romaji.katakana(kana);
        if (!seen.has(katakana)) { seen.add(katakana); extras.push({ text: katakana, kind: CandidateKind.KANA, coreIndex: -1, consumed: length }); }
      }
    }
    // 同一读音的其余词（弱义项，例如「すみません」之外的「私密马赛」）和前缀/假名
    // 候选一起排到第一页之后（对照 Android：extras 从第 9 位起插入），避免收合栏
    // 被同一读音的多个日语词占满（docs/DESIGN.md §4）。
    for (const word of moreJapanese) {
      if (!seen.has(word)) {
        seen.add(word);
        extras.push({ text: word, kind: CandidateKind.JAPANESE_WORD, coreIndex: -1, consumed: length });
      }
    }

    if (typed.length > 0 && !seen.has(typed)) {
      const literal: Candidate = { text: typed, kind: CandidateKind.LITERAL, coreIndex: -1, consumed: length };
      let position: number;
      if (length === 1) {
        position = Math.min(6, list.length);
      } else if (!topComplete && best === null) {
        position = Math.min(1, list.length);
      } else {
        position = Math.min(8, list.length);
      }
      list.splice(position, 0, literal);
    }
    const insertAt = Math.min(9, list.length);
    for (let ei = extras.length - 1; ei >= 0; ei--) {
      list.splice(insertAt, 0, extras[ei]);
    }
    return list;
  }

  /** 收合列只保留一个日语候选，其余留到展开面板。 */
  static collapsed(all: Candidate[]): number[] {
    let japaneseShown = false;
    const out: number[] = [];
    for (let i = 0; i < all.length; i++) {
      const c = all[i];
      if (isJapanese(c)) {
        if (japaneseShown) continue;
        japaneseShown = true;
      }
      out.push(i);
    }
    return out;
  }
}