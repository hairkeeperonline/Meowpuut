/**
 * 删除键要删掉多少字符（对应 Android ime/TextUnits.kt）。
 * 鸿蒙侧没有 ICU 的 BreakIterator 直通，这里用近似实现：
 * 按 Unicode 码点（含 emoji 的组合序列）逐字，中文按整词粗略切分。
 */
export class TextUnits {
  /** 串尾一个用户感知字符（码点簇）占的 UTF-16 单元数。 */
  static lastGrapheme(text: string): number {
    if (text.length === 0) return 0;
    // 从串尾往前识别一个完整 grapheme cluster（对照 UAX #29 的 emoji ZWJ 序列），
    // 与 Android ICU getCharacterInstance 语义对齐：emoji 组合、`e`+变音 都算一个。
    // 结构「base (modifier)? (ZWJ base (modifier)?)*」，从右往左逐段吞并。
    let i = text.length;
    while (true) {
      // 吞修饰符（肤色/VS16/变音，依附前一个 base）。
      while (i > 0 && TextUnits.isModifier(TextUnits.codePointBefore(text, i))) {
        i = TextUnits.codePointStartBefore(text, i);
      }
      // 吞一个 base 码点。
      if (i > 0) {
        const baseCp = TextUnits.codePointBefore(text, i);
        i = TextUnits.codePointStartBefore(text, i);
        // 区域指示符成对（旗帜 emoji，UAX #29 GB8a）：两枚一起删。
        if (TextUnits.isRegionalIndicator(baseCp) && i > 0 &&
          TextUnits.isRegionalIndicator(TextUnits.codePointBefore(text, i))) {
          i = TextUnits.codePointStartBefore(text, i);
        }
      }
      // base 前是 ZWJ 则继续吞下一段，否则结束。
      if (i > 0 && TextUnits.codePointBefore(text, i) === 0x200D) {
        i = TextUnits.codePointStartBefore(text, i); // 过 ZWJ，循环吞下一个 base
        continue;
      }
      break;
    }
    return text.length - i;
  }

  /** 串尾空白和它前面的整词（中文词而非单字，近似）。 */
  static wordLength(text: string): number {
    let end = text.length;
    while (end > 0 && isWhitespace(text.charAt(end - 1))) end--;
    if (end === 0) return text.length;
    let start = end - 1;
    // 中文或日文：往回退一个「词」，按 2 个汉字一个词近似（与 ICU 不同，足够删除节奏用）。
    const c = text.charCodeAt(start);
    if (isCjk(c)) {
      let n = 0;
      while (start >= 0 && isCjk(text.charCodeAt(start)) && n < 2) { start--; n++; }
      // 一个汉字也至少删一个。
      if (n === 0) n = 1;
      return text.length - end + Math.max(1, n);
    }
    while (start > 0 && !isWhitespace(text.charAt(start - 1)) && !isCjk(text.charCodeAt(start - 1))) start--;
    return text.length - end + Math.max(1, end - start);
  }

  private static isLowSurrogate(code: number): boolean {
    return code >= 0xDC00 && code <= 0xDFFF;
  }

  private static isHighSurrogate(code: number): boolean {
    return code >= 0xD800 && code <= 0xDBFF;
  }

  /** 修饰符：肤色修饰、VS16、组合变音、围封组合、VS 选择符（依附前一个码点）。 */
  private static isModifier(cp: number): boolean {
    return (cp >= 0x1F3FB && cp <= 0x1F3FF) || cp === 0xFE0F ||
      (cp >= 0x0300 && cp <= 0x036F) || (cp >= 0x20E0 && cp <= 0x20FF) ||
      (cp >= 0xFE00 && cp <= 0xFE0F);
  }

  /** 区域指示符（旗帜 emoji 的两枚字母，U+1F1E6–U+1F1FF）。 */
  private static isRegionalIndicator(cp: number): boolean {
    return cp >= 0x1F1E6 && cp <= 0x1F1FF;
  }

  /** 返回 `index` 处之前一个码点的值；`index` 应指向某码点起点。 */
  private static codePointBefore(text: string, index: number): number {
    if (index <= 0) return -1;
    const c = text.charCodeAt(index - 1);
    if (TextUnits.isLowSurrogate(c) && index - 2 >= 0 &&
      TextUnits.isHighSurrogate(text.charCodeAt(index - 2))) {
      return 0x10000 + ((text.charCodeAt(index - 2) - 0xD800) << 10) + (c - 0xDC00);
    }
    return c;
  }

  /** 返回 `index` 处之前一个码点的起点（UTF-16 下标）。 */
  private static codePointStartBefore(text: string, index: number): number {
    if (index <= 0) return 0;
    const c = text.charCodeAt(index - 1);
    if (TextUnits.isLowSurrogate(c) && index - 2 >= 0 &&
      TextUnits.isHighSurrogate(text.charCodeAt(index - 2))) {
      return index - 2;
    }
    return index - 1;
  }
}

function isWhitespace(c: string): boolean {
  return c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\u3000';
}

function isCjk(code: number): boolean {
  return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0x3040 && code <= 0x30FF) || (code >= 0xAC00 && code <= 0xD7AF);
}