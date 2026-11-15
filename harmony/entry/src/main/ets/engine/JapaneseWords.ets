/**
 * 审过的日语词表（native-japanese.tsv，每行 `readings|text|weight`，readings 逗号分隔）。
 * 对应 Android engine/JapaneseWords.kt。
 */
import { Romaji } from './Romaji';

/** 一个词条：文字 + 权重。 */
export class WordEntry {
  readonly text: string;
  readonly weight: number;
  constructor(text: string, weight: number) { this.text = text; this.weight = weight; }
}

/** best() 返回的一条：读音 + 文字 + 权重。 */
export class BestEntry {
  readonly reading: string;
  readonly text: string;
  readonly weight: number;
  constructor(reading: string, text: string, weight: number) {
    this.reading = reading;
    this.text = text;
    this.weight = weight;
  }
}

export class JapaneseWords {
  private byReading: Map<string, WordEntry[]>;
  /**
   * 假名 → 读音。查表时若罗马字与键对不上（例如 `simimasai` 按训令式拼作
   * 「しみまさい」而词表键是 `sumimasen`），就把输入先折成假名再按假名查，
   * 让「按读音打字」的用户也能命中。对应 Android 版没有的增强，但只在不命中时兜底，
   * 不改变原有精确匹配的结果。
   */
  private byKana: Map<string, string[]>;

  private constructor(byReading: Map<string, WordEntry[]>, byKana: Map<string, string[]>) {
    this.byReading = byReading;
    this.byKana = byKana;
  }

  /** 一个读音的最强词，或 null。 */
  word(reading: string): string | null {
    const list = this.byReading.get(reading);
    return list !== undefined && list.length > 0 ? list[0].text : null;
  }

  /** 假名反查读音：`しみません` → `sumimasen`。查不到返回 null。 */
  readingOfKana(kana: string): string | null {
    const list = this.byKana.get(kana);
    return list !== undefined && list.length > 0 ? list[0] : null;
  }

  /**
   * 用一个「可能不是标准罗马字」的输入取候选：先精确查，查不到再折成假名查，
   * 最后按「近音」宽松匹配（容忍 si/su、ma/me 这类常见混淆）。
   * `toKana` 由调用方传入（Romaji.reading），避免这个文件依赖 Romaji 之外的东西。
   */
  wordsLoose(key: string, toKana: (s: string) => string): string[] {
    const exact = this.byReading.get(key);
    if (exact !== undefined && exact.length > 0) {
      const out: string[] = [];
      for (let i = 0; i < exact.length; i++) out.push(exact[i].text);
      return out;
    }
    const kana = toKana(key);
    const reading = this.readingOfKana(kana);
    if (reading !== null) {
      const list = this.byReading.get(reading);
      if (list !== undefined) {
        const out: string[] = [];
        for (let i = 0; i < list.length; i++) out.push(list[i].text);
        return out;
      }
    }
    // 假名兜底到此为止：不做编辑距离之类的模糊匹配，
    // 否则 simimasai 会误配到「小さい」这种完全无关的词（实测过）。
    return [];
  }

  /** 一个读音的所有词，强到弱。 */
  words(reading: string): string[] {
    const list = this.byReading.get(reading);
    if (list === undefined) return [];
    const out: string[] = [];
    for (let i = 0; i < list.length; i++) {
      out.push(list[i].text);
    }
    return out;
  }

  /** 每个读音的最强词，用于引擎的中日混打解码。 */
  best(): BestEntry[] {
    const keys: string[] = [];
    this.byReading.forEach((_value: WordEntry[], key: string) => { keys.push(key); });
    keys.sort();
    const out: BestEntry[] = [];
    for (let i = 0; i < keys.length; i++) {
      const reading = keys[i];
      const list = this.byReading.get(reading);
      if (list !== undefined && list.length > 0) {
        out.push(new BestEntry(reading, list[0].text, list[0].weight));
      }
    }
    return out;
  }

  get size(): number {
    return this.byReading.size;
  }

  static readonly EMPTY = new JapaneseWords(new Map<string, WordEntry[]>(), new Map<string, string[]>());

  static parse(text: string): JapaneseWords {
    const map = new Map<string, WordEntry[]>();
    const kanaMap = new Map<string, string[]>();
    const lines = text.split('\n');
    for (let li = 0; li < lines.length; li++) {
      let line = lines[li];
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.length === 0 || line.startsWith('#')) continue;
      const parts = line.split('|');
      if (parts.length < 3) continue;
      const weight = parseInt(parts[2].trim(), 10);
      if (isNaN(weight)) continue;
      const word = parts[1];
      if (word.length === 0) continue;
      const readings = parts[0].split(',');
      for (let ri = 0; ri < readings.length; ri++) {
        const key = readings[ri].trim().toLowerCase();
        if (key.length === 0) continue;
        let list = map.get(key);
        if (list === undefined) { list = []; map.set(key, list); }
        let found = false;
        for (let wi = 0; wi < list.length; wi++) {
          if (list[wi].text === word) { found = true; break; }
        }
        if (!found) list.push(new WordEntry(word, weight));
        // 假名索引：把标准读音折成假名，高权重的读音优先。
        const kana = Romaji.reading(key);
        if (kana.length > 0) {
          let klist = kanaMap.get(kana);
          if (klist === undefined) { klist = []; kanaMap.set(kana, klist); }
          if (!klist.includes(key)) klist.push(key);
        }
      }
    }
    const result = new Map<string, WordEntry[]>();
    map.forEach((list: WordEntry[], key: string) => {
      list.sort((a: WordEntry, b: WordEntry) => b.weight - a.weight);
      result.set(key, list);
    });
    // 同一假名可能对应多个读音，按该读音的最强词权重排序。
    kanaMap.forEach((keys: string[], kana: string) => {
      keys.sort((a: string, b: string) => JapaneseWords.topWeight(result, b) - JapaneseWords.topWeight(result, a));
    });
    return new JapaneseWords(result, kanaMap);
  }

  private static topWeight(map: Map<string, WordEntry[]>, key: string): number {
    const list = map.get(key);
    return list !== undefined && list.length > 0 ? list[0].weight : 0;
  }
}