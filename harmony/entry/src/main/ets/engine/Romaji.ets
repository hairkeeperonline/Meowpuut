/**
 * 罗马字 → 假名（对应 Android engine/Romaji.kt，同一张表）。
 */

class Pair {
  first: string;
  second: string;
  constructor(first: string, second: string) {
    this.first = first;
    this.second = second;
  }
}

export class Romaji {
  private static kana: Map<string, string> = Romaji.buildKana();

  private static buildKana(): Map<string, string> {
    const map = new Map<string, string>();
    const rows: string[] = [
      'a i u e o|あいうえお', 'ka ki ku ke ko|かきくけこ', 'sa shi su se so|さしすせそ',
      'ta chi tsu te to|たちつてと', 'na ni nu ne no|なにぬねの', 'ha hi fu he ho|はひふへほ',
      'ma mi mu me mo|まみむめも', 'ya yu yo|やゆよ', 'ra ri ru re ro|らりるれろ', 'wa wo|わを',
      'ga gi gu ge go|がぎぐげご', 'za ji zu ze zo|ざじずぜぞ', 'da di du de do|だぢづでど',
      'ba bi bu be bo|ばびぶべぼ', 'pa pi pu pe po|ぱぴぷぺぽ', 'va vi vu ve vo|ゔぁ,ゔぃ,ゔ,ゔぇ,ゔぉ',
      'xa xi xu xe xo|ぁぃぅぇぉ', 'xya xyu xyo|ゃゅょ', 'xtsu|っ', 'xwa|ゎ',
    ];
    for (let r = 0; r < rows.length; r++) {
      const row = rows[r];
      const sep = row.indexOf('|');
      const keys = row.substring(0, sep);
      const kanaText = row.substring(sep + 1);
      let values: string[];
      if (kanaText.includes(',')) {
        values = kanaText.split(',');
      } else {
        values = [];
        for (let ci = 0; ci < kanaText.length; ci++) {
          values.push(kanaText.charAt(ci));
        }
      }
      const keyList = keys.split(' ');
      for (let ki = 0; ki < keyList.length; ki++) {
        map.set(keyList[ki], values[ki]);
      }
    }
    const prefixes: Pair[] = [
      new Pair('ky', 'き'), new Pair('gy', 'ぎ'), new Pair('sh', 'し'), new Pair('ch', 'ち'),
      new Pair('ny', 'に'), new Pair('hy', 'ひ'), new Pair('by', 'び'), new Pair('py', 'ぴ'),
      new Pair('my', 'み'), new Pair('ry', 'り'), new Pair('j', 'じ'),
    ];
    const smalls: Pair[] = [new Pair('a', 'ゃ'), new Pair('u', 'ゅ'), new Pair('o', 'ょ'), new Pair('e', 'ぇ')];
    for (let pi = 0; pi < prefixes.length; pi++) {
      const prefix = prefixes[pi].first;
      const base = prefixes[pi].second;
      for (let si = 0; si < smalls.length; si++) {
        const vowel = smalls[si].first;
        const small = smalls[si].second;
        map.set(prefix + vowel, base + small);
      }
    }
    const aliases = new Map<string, string>();
    aliases.set('si', 'shi');
    aliases.set('ti', 'chi');
    aliases.set('tu', 'tsu');
    aliases.set('hu', 'fu');
    aliases.set('zi', 'ji');
    aliases.set('sya', 'sha');
    aliases.set('syu', 'shu');
    aliases.set('syo', 'sho');
    aliases.set('tya', 'cha');
    aliases.set('tyu', 'chu');
    aliases.set('tyo', 'cho');
    aliases.set('cya', 'cha');
    aliases.set('cyu', 'chu');
    aliases.set('cyo', 'cho');
    aliases.set('zya', 'ja');
    aliases.set('zyu', 'ju');
    aliases.set('zyo', 'jo');
    aliases.set('jya', 'ja');
    aliases.set('jyu', 'ju');
    aliases.set('jyo', 'jo');
    aliases.set('xtu', 'xtsu');
    aliases.forEach((standard: string, alias: string) => {
      const v = map.get(standard);
      if (v !== undefined) map.set(alias, v);
    });
    // 把 x 开头的键复制成 l 开头（小写假名）。
    const xKeys: string[] = [];
    const xVals: string[] = [];
    map.forEach((v: string, k: string) => {
      if (k.startsWith('x')) {
        xKeys.push(k);
        xVals.push(v);
      }
    });
    for (let xi = 0; xi < xKeys.length; xi++) {
      map.set('l' + xKeys[xi].substring(1), xVals[xi]);
    }
    const extra = new Map<string, string>();
    extra.set('fa', 'ふぁ');
    extra.set('fi', 'ふぃ');
    extra.set('fe', 'ふぇ');
    extra.set('fo', 'ふぉ');
    extra.set('wi', 'うぃ');
    extra.set('we', 'うぇ');
    extra.set('who', 'うぉ');
    extra.set('she', 'しぇ');
    extra.set('che', 'ちぇ');
    extra.set('thi', 'てぃ');
    extra.set('dhi', 'でぃ');
    extra.set('twu', 'とぅ');
    extra.set('dwu', 'どぅ');
    extra.set('fyu', 'ふゅ');
    extra.set('ye', 'いぇ');
    extra.forEach((v: string, k: string) => {
      map.set(k, v);
    });
    return map;
  }

  /** 罗马字 → 平假名。 */
  static reading(raw: string): string {
    const input = raw.toLowerCase();
    let out = '';
    let position = 0;
    while (position < input.length) {
      const key = input.charAt(position);
      const next = position + 1 < input.length ? input.charAt(position + 1) : null;
      if (key === '-') { out += 'ー'; position++; continue; }
      if (key === "'") { position++; continue; }
      if (key === 'n') {
        if (next === "'") { out += 'ん'; position += 2; continue; }
        if (next === null) { out += 'ん'; position++; continue; }
        if (next === 'n') {
          out += 'ん';
          position += (position + 2 === input.length) ? 2 : 1;
          continue;
        }
        if (!'aiueoy'.includes(next)) { out += 'ん'; position++; continue; }
      }
      if (next !== null && key === next && !'aiueon'.includes(key)) {
        out += 'っ'; position++; continue;
      }
      let matched = false;
      for (let count = Math.min(4, input.length - position); count >= 1; count--) {
        const value = Romaji.kana.get(input.substring(position, position + count));
        if (value !== undefined) { out += value; position += count; matched = true; break; }
      }
      if (!matched) { out += key; position++; }
    }
    return out;
  }

  /** 平假名 → 片假名。 */
  static katakana(hiragana: string): string {
    let out = '';
    for (let i = 0; i < hiragana.length; i++) {
      const c = hiragana.charAt(i);
      const code = c.charCodeAt(0);
      if ((code >= 0x3041 && code <= 0x3096) || c === 'ゝ' || c === 'ゞ') {
        out += String.fromCharCode(code + 0x60);
      } else {
        out += c;
      }
    }
    return out;
  }

  /** 是否全是假名。 */
  static isKana(text: string): boolean {
    if (text.length === 0) return false;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (!(code >= 0x3040 && code <= 0x30FF)) return false;
    }
    return true;
  }
}
