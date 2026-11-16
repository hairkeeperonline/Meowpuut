/**
 * 按键定义与布局（对应 Android ime/Keys.kt，与 iOS KeyboardKeys.swift 同排布）。
 */
import { InputMode } from '../engine/Types';
import { RowAlignment, RowSpec, Idiom } from './Geometry';
import { Words } from './Theme';

// --- KeyAction class hierarchy (replaces object literal union type) ---

export class KeyAction {
  readonly kind: string;
  constructor(kind: string) {
    this.kind = kind;
  }
}

export class KeyActionEngine extends KeyAction {
  readonly code: number;
  constructor(code: number) {
    super('engine');
    this.code = code;
  }
}

export class KeyActionText extends KeyAction {
  readonly text: string;
  constructor(text: string) {
    super('text');
    this.text = text;
  }
}

export class KeyActionPage extends KeyAction {
  readonly page: number;
  constructor(page: number) {
    super('page');
    this.page = page;
  }
}

export class KeyActionShift extends KeyAction {
  constructor() {
    super('shift');
  }
}

export class KeyActionDelete extends KeyAction {
  constructor() {
    super('delete');
  }
}

export class KeyActionSpace extends KeyAction {
  constructor() {
    super('space');
  }
}

export class KeyActionReturn extends KeyAction {
  constructor() {
    super('return');
  }
}

export class KeyActionGlobe extends KeyAction {
  constructor() {
    super('globe');
  }
}

export class KeyActionToggleEnglish extends KeyAction {
  constructor() {
    super('toggleEnglish');
  }
}

export enum KeyStyle { CHARACTER, UTILITY, ACCENT }
export enum KeyIcon { SHIFT, SHIFT_ON, CAPS_LOCK, DELETE, GLOBE }
export enum ShiftState { OFF, ONCE, LOCKED }

export class Key {
  readonly action: KeyAction;
  readonly label: string;
  readonly icon: KeyIcon | null;
  readonly style: KeyStyle;
  readonly alternates: string[];
  readonly preview: boolean;
  readonly enabled: boolean;
  readonly fontSize: number | null;
  readonly spoken: string;
  /** 九键数字键的角标字母组（如 "abc"）；其余布局为 null。 */
  sublabel: string | null = null;

  constructor(action: KeyAction, label: string, icon: KeyIcon | null = null,
    style: KeyStyle = KeyStyle.CHARACTER, alternates: string[] = [], preview: boolean = true,
    enabled: boolean = true, fontSize: number | null = null, spoken: string = label) {
    this.action = action;
    this.label = label;
    this.icon = icon;
    this.style = style;
    this.alternates = alternates;
    this.preview = preview;
    this.enabled = enabled;
    this.fontSize = fontSize;
    this.spoken = spoken;
  }

  get isCharacter(): boolean { return this.action.kind === 'engine' || this.action.kind === 'text'; }
  get rollsOver(): boolean { return this.isCharacter || this.action.kind === 'space'; }
}

export function keyActionEquals(a: KeyAction | null, b: KeyAction | null): boolean {
  if (a === null || b === null) return a === b;
  if (a.kind !== b.kind) return false;
  switch (a.kind) {
    case 'engine':
      return (b instanceof KeyActionEngine) && (a instanceof KeyActionEngine) && b.code === a.code;
    case 'text':
      return (b instanceof KeyActionText) && (a instanceof KeyActionText) && b.text === a.text;
    case 'page':
      return (b instanceof KeyActionPage) && (a instanceof KeyActionPage) && b.page === a.page;
    default: return true;
  }
}

export class KeySet {
  readonly rows: Key[][];
  readonly specs: RowSpec[];
  readonly referenceColumns: number;
  readonly page: number;
  constructor(rows: Key[][], specs: RowSpec[], referenceColumns: number, page: number = 0) {
    this.rows = rows;
    this.specs = specs;
    this.referenceColumns = referenceColumns;
    this.page = page;
  }
}

export class KeyContext {
  readonly mode: InputMode;
  readonly english: boolean;
  readonly page: number;
  readonly shift: ShiftState;
  readonly simplified: boolean;
  readonly needsGlobe: boolean;
  readonly spaceTitle: string;
  readonly returnTitle: string;
  readonly returnAccent: boolean;
  readonly returnEnabled: boolean;
  readonly expanded: boolean;

  constructor(mode: InputMode, english: boolean, page: number, shift: ShiftState, simplified: boolean,
    needsGlobe: boolean, spaceTitle: string, returnTitle: string, returnAccent: boolean,
    returnEnabled: boolean, expanded: boolean = false) {
    this.mode = mode;
    this.english = english;
    this.page = page;
    this.shift = shift;
    this.simplified = simplified;
    this.needsGlobe = needsGlobe;
    this.spaceTitle = spaceTitle;
    this.returnTitle = returnTitle;
    this.returnAccent = returnAccent;
    this.returnEnabled = returnEnabled;
    this.expanded = expanded;
  }
}

function keyCtxEquals(a: KeyContext, b: KeyContext): boolean {
  return a.mode === b.mode && a.english === b.english && a.page === b.page && a.shift === b.shift &&
    a.simplified === b.simplified && a.needsGlobe === b.needsGlobe && a.spaceTitle === b.spaceTitle &&
    a.returnTitle === b.returnTitle && a.returnAccent === b.returnAccent &&
    a.returnEnabled === b.returnEnabled && a.expanded === b.expanded;
}

// --- ZhuyinKey class (replaces [string, string] tuple) ---

class ZhuyinKey {
  readonly symbol: string;
  readonly raw: string;
  constructor(symbol: string, raw: string) {
    this.symbol = symbol;
    this.raw = raw;
  }
}

function makeZhuyinRow(pairs: string[][]): ZhuyinKey[] {
  const result: ZhuyinKey[] = [];
  for (let i = 0; i < pairs.length; i++) {
    result.push(new ZhuyinKey(pairs[i][0], pairs[i][1]));
  }
  return result;
}

const ZHUYIN_ROWS: ZhuyinKey[][] = [
  makeZhuyinRow([['ㄅ', '1'], ['ㄉ', '2'], ['ˇ', '3'], ['ˋ', '4'], ['ㄓ', '5'], ['ˊ', '6'], ['˙', '7'], ['ㄚ', '8'], ['ㄞ', '9'], ['ㄢ', '0'], ['ㄦ', '-']]),
  makeZhuyinRow([['ㄆ', 'q'], ['ㄊ', 'w'], ['ㄍ', 'e'], ['ㄐ', 'r'], ['ㄔ', 't'], ['ㄗ', 'y'], ['ㄧ', 'u'], ['ㄛ', 'i'], ['ㄟ', 'o'], ['ㄣ', 'p']]),
  makeZhuyinRow([['ㄇ', 'a'], ['ㄋ', 's'], ['ㄎ', 'd'], ['ㄑ', 'f'], ['ㄕ', 'g'], ['ㄘ', 'h'], ['ㄨ', 'j'], ['ㄜ', 'k'], ['ㄠ', 'l'], ['ㄤ', ';']]),
  makeZhuyinRow([['ㄈ', 'z'], ['ㄌ', 'x'], ['ㄏ', 'c'], ['ㄒ', 'v'], ['ㄖ', 'b'], ['ㄙ', 'n'], ['ㄩ', 'm'], ['ㄝ', ','], ['ㄡ', '.'], ['ㄥ', '/']]),
];

// --- Helper to build Map<string, string[]> (replaces Record<string, string[]>) ---

function buildAccentMap(): Map<string, string[]> {
  const m = new Map<string, string[]>();
  m.set('a', ['à', 'á', 'â', 'ä', 'æ', 'ã', 'å', 'ā']);
  m.set('c', ['ç', 'ć', 'č']);
  m.set('e', ['è', 'é', 'ê', 'ë', 'ē', 'ė', 'ę']);
  m.set('i', ['î', 'ï', 'í', 'ī', 'į', 'ì']);
  m.set('l', ['ł']);
  m.set('n', ['ñ', 'ń']);
  m.set('o', ['ô', 'ö', 'ò', 'ó', 'œ', 'ø', 'ō', 'õ']);
  m.set('s', ['ß', 'ś', 'š']);
  m.set('u', ['û', 'ü', 'ù', 'ú', 'ū']);
  m.set('y', ['ÿ']);
  m.set('z', ['ž', 'ź', 'ż']);
  return m;
}

function buildSymbolAlternatesMap(): Map<string, string[]> {
  const m = new Map<string, string[]>();
  m.set('-', ['-', '–', '—', '•']);
  m.set('/', ['/', '\\']);
  m.set('$', ['$', '¢', '£', '€', '¥', '₩']);
  m.set('&', ['&', '§']);
  m.set('"', ['"', '\u201C', '\u201D', '\u201E', '\u00BB', '\u00AB']);
  m.set('.', ['.', '…']);
  m.set('?', ['?', '¿']);
  m.set('!', ['!', '¡']);
  m.set("'", ["'", '\u2018', '\u2019', '`']);
  m.set('%', ['%', '‰']);
  m.set('0', ['0', '°']);
  m.set('=', ['=', '≠', '≈']);
  m.set('。', ['。', '．']);
  m.set('，', ['，', '、']);
  m.set('\u201C', ['\u201C', '\u201D', '\u300C', '\u300D', '\u300E', '\u300F']);
  m.set('（', ['（', '【', '〔', '《']);
  m.set('）', ['）', '】', '〕', '》']);
  m.set('¥', ['¥', '$', '€', '£']);
  return m;
}

const ACCENTS: Map<string, string[]> = buildAccentMap();
const SYMBOL_ALTERNATES: Map<string, string[]> = buildSymbolAlternatesMap();

// --- Build Set by adding elements (replaces new Set([...])) ---

function buildAutoReturnMarks(): Set<string> {
  const s = new Set<string>();
  s.add('，'); s.add('。'); s.add('？'); s.add('！'); s.add('、'); s.add('；'); s.add('：');
  s.add(','); s.add('.'); s.add('?'); s.add('!'); s.add(';'); s.add(':'); s.add("'"); s.add('"');
  return s;
}

const AUTO_RETURN_MARKS: Set<string> = buildAutoReturnMarks();

// --- BottomRowResult class (replaces [Key[], RowSpec] tuple return) ---

class BottomRowResult {
  readonly keys: Key[];
  readonly spec: RowSpec;
  constructor(keys: Key[], spec: RowSpec) {
    this.keys = keys;
    this.spec = spec;
  }
}

// --- Array helper functions (replace spread operator) ---

function arrayOfFill(count: number, value: number): number[] {
  const arr: number[] = [];
  for (let i = 0; i < count; i++) {
    arr.push(value);
  }
  return arr;
}

function concatArrays<T>(...arrays: T[][]): T[] {
  const result: T[] = [];
  for (let i = 0; i < arrays.length; i++) {
    const arr = arrays[i];
    for (let j = 0; j < arr.length; j++) {
      result.push(arr[j]);
    }
  }
  return result;
}

function stringToCharArray(s: string): string[] {
  // 按码点切分（emoji 是代理对，charAt 会把一个 emoji 撕成两个烂字符；
  // ArkTS 严格模式不保证 Array.from(string) 的迭代语义，这里手写代理对合并）。
  const arr: string[] = [];
  let i = 0;
  while (i < s.length) {
    const code = s.charCodeAt(i);
    // 高代理项 D800-DBFF 且后跟低代理项 DC00-DFFF → 合成一个码点。
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
      const next = s.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        arr.push(s.substring(i, i + 2));
        i += 2;
        continue;
      }
    }
    arr.push(s.charAt(i));
    i += 1;
  }
  return arr;
}

export class KeyBuilder {
  static readonly zhuyin = ZHUYIN_ROWS;

  static get accents(): Map<string, string[]> { return ACCENTS; }
  static get symbolAlternates(): Map<string, string[]> { return SYMBOL_ALTERNATES; }
  static get autoReturnMarks(): Set<string> { return AUTO_RETURN_MARKS; }

  static build(context: KeyContext): KeySet {
    const t = new Words(context.simplified);
    const chinese = !context.english && context.mode !== InputMode.JAPANESE;
    if (context.page > 0) return KeyBuilder.symbols(context, context.page, chinese, t);
    if (!context.english && context.mode === InputMode.ZHUYIN) return KeyBuilder.zhuyinSet(context, t);
    // 九键拼音：3×4 数字键盘（2-9 每键标字母），T9 组字在引擎侧（T9.ets）。
    if (!context.english && context.mode === InputMode.PINYIN9) return KeyBuilder.nineKeySet(context, t);
    return KeyBuilder.letters(context, t);
  }

  /** 九键 3×4 布局：每键主标数字、角标字母组（标准九键，对照 iOS 九键）。 */
  private static nineKeySet(context: KeyContext, t: Words): KeySet {
    const layout: string[][] = [
      ['1', ''], ['2', 'abc'], ['3', 'def'],
      ['4', 'ghi'], ['5', 'jkl'], ['6', 'mno'],
      ['7', 'pqrs'], ['8', 'tuv'], ['9', 'wxyz'],
    ];
    const rows: Key[][] = [];
    for (let r = 0; r < 3; r++) {
      const row: Key[] = [];
      for (let c = 0; c < 3; c++) {
        const def = layout[r * 3 + c];
        if (def[0] === '1') {
          // 「1」键：标点备选（长按出 ,?! 等；点击上屏最常用句号——对照 iOS）。
          row.push(new Key(new KeyActionText('。'), '1', null, KeyStyle.CHARACTER,
            ['，', '、', '？', '！', '…', '；', '：', '“', '”', '‘', '’'], true, true, 28, '标点'));
        } else {
          row.push(KeyBuilder.nineKey(def, t));
        }
      }
      rows.push(row);
    }
    // 行 3: 标准底行（符号/切换/空格/换行）
    const symbolsKey = new Key(new KeyActionPage(1), t.pick('符號', '符号'), null, KeyStyle.UTILITY, [], false, true, 16, t.pick('符號', '符号'));
    const bottom = KeyBuilder.bottomRow(context, t, symbolsKey, KeyBuilder.toggleKey(context));
    const keyRows: Key[][] = [];
    keyRows.push(rows[0]);
    keyRows.push(rows[1]);
    keyRows.push(rows[2]);
    keyRows.push(bottom.keys);
    const specs: RowSpec[] = [];
    specs.push(new RowSpec(arrayOfFill(3, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(3, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(3, 1), RowAlignment.CENTERED));
    specs.push(bottom.spec);
    return new KeySet(keyRows, specs, 3);
  }

  /** 造一个九键数字键：主标数字，角标字母（副文本）。 */
  private static nineKey(def: string[], t: Words): Key {
    const digit = def[0];
    const letters = def[1];
    const key = new Key(new KeyActionEngine(digit.charCodeAt(0)), digit, null,
      KeyStyle.CHARACTER, [], false, true, 28, `拼音九键 ${digit}`);
    key.sublabel = letters;
    return key;
  }

  private static bottomRow(context: KeyContext, t: Words, first: Key, second: Key | null): BottomRowResult {
    const keys: Key[] = [];
    keys.push(first);
    const units: number[] = [];
    units.push(1.25);
    if (second !== null) { keys.push(second); units.push(1.25); }
    if (context.needsGlobe) {
      keys.push(new Key(new KeyActionGlobe(), '', KeyIcon.GLOBE, KeyStyle.UTILITY, [], false, true, null, t.pick('切換鍵盤', '切换键盘')));
      units.push(1.25);
    }
    keys.push(new Key(new KeyActionSpace(), context.spaceTitle, null, KeyStyle.CHARACTER, [], false, true, 16, '空格'));
    units.push(0);
    if (context.expanded) { keys.push(KeyBuilder.deleteKey(t)); units.push(1.25); }
    keys.push(new Key(new KeyActionReturn(), context.returnTitle, null,
      context.returnAccent ? KeyStyle.ACCENT : KeyStyle.UTILITY, [], false, context.returnEnabled, 16, context.returnTitle));
    units.push(2.25);
    return new BottomRowResult(keys, new RowSpec(units, RowAlignment.JUSTIFIED));
  }

  private static toggleKey(context: KeyContext): Key {
    let label: string;
    if (context.english) {
      switch (context.mode) {
        case InputMode.PINYIN: label = '拼'; break;
        case InputMode.ZHUYIN: label = 'ㄅ'; break;
        case InputMode.JAPANESE: label = 'あ'; break;
        default: label = '拼';
      }
    } else {
      label = 'ABC';
    }
    let spoken = '英文';
    if (!context.english && context.mode === InputMode.JAPANESE) spoken = '日文';
    else if (context.english) spoken = '中文';
    return new Key(new KeyActionToggleEnglish(), label, null, KeyStyle.UTILITY, [], false, true, 16, spoken);
  }

  private static deleteKey(t: Words): Key {
    return new Key(new KeyActionDelete(), '', KeyIcon.DELETE, KeyStyle.UTILITY, [], false, true, null, t.pick('刪除', '删除'));
  }

  private static letters(context: KeyContext, t: Words): KeySet {
    const upper = context.shift !== ShiftState.OFF;
    const rowStrings: string[] = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
    const rows: Key[][] = [];
    for (let ri = 0; ri < rowStrings.length; ri++) {
      const chars = stringToCharArray(rowStrings[ri]);
      const rowKeys: Key[] = [];
      for (let ci = 0; ci < chars.length; ci++) {
        const c = chars[ci];
        const label = upper ? c.toUpperCase() : c;
        const accentArr = ACCENTS.get(c);
        const alternates: string[] = [];
        if (context.english && accentArr !== undefined) {
          for (let ai = 0; ai < accentArr.length; ai++) {
            alternates.push(upper ? accentArr[ai].toUpperCase() : accentArr[ai]);
          }
        }
        rowKeys.push(new Key(new KeyActionEngine(c.charCodeAt(0)), label, null, KeyStyle.CHARACTER, alternates, true, true, null, label));
      }
      rows.push(rowKeys);
    }
    const shiftIcon = context.shift === ShiftState.OFF ? KeyIcon.SHIFT :
      (context.shift === ShiftState.ONCE ? KeyIcon.SHIFT_ON : KeyIcon.CAPS_LOCK);
    const shiftStyle = context.shift === ShiftState.OFF ? KeyStyle.UTILITY : KeyStyle.CHARACTER;
    const shiftSpoken = context.shift === ShiftState.LOCKED ? t.pick('大寫鎖定', '大写锁定') : 'Shift';
    const shift = new Key(new KeyActionShift(), '', shiftIcon, shiftStyle, [], false, true, null, shiftSpoken);
    const symbolsKey = new Key(new KeyActionPage(1), context.english ? '123' : t.pick('符號', '符号'), null, KeyStyle.UTILITY, [], false, true, 16, t.pick('符號', '符号'));
    const bottom = KeyBuilder.bottomRow(context, t, symbolsKey, KeyBuilder.toggleKey(context));

    // Build row 3: [shift, ...rows[2], deleteKey]
    const row3: Key[] = [];
    row3.push(shift);
    const r2 = rows[2];
    for (let i = 0; i < r2.length; i++) {
      row3.push(r2[i]);
    }
    row3.push(KeyBuilder.deleteKey(t));

    const keyRows: Key[][] = [];
    keyRows.push(rows[0]);
    keyRows.push(rows[1]);
    keyRows.push(row3);
    keyRows.push(bottom.keys);

    const specs: RowSpec[] = [];
    specs.push(new RowSpec(arrayOfFill(10, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(9, 1), RowAlignment.CENTERED));
    // [1.32, ...new Array(7).fill(1), 1.32]
    const row3Units: number[] = [];
    row3Units.push(1.32);
    const sevens = arrayOfFill(7, 1);
    for (let i = 0; i < sevens.length; i++) {
      row3Units.push(sevens[i]);
    }
    row3Units.push(1.32);
    specs.push(new RowSpec(row3Units, RowAlignment.SPLIT_EDGES));
    specs.push(bottom.spec);

    return new KeySet(keyRows, specs, 10);
  }

  private static zhuyinSet(context: KeyContext, t: Words): KeySet {
    const rows: Key[][] = [];
    for (let ri = 0; ri < ZHUYIN_ROWS.length; ri++) {
      const zRow = ZHUYIN_ROWS[ri];
      const keyRow: Key[] = [];
      for (let ki = 0; ki < zRow.length; ki++) {
        const zk = zRow[ki];
        keyRow.push(new Key(new KeyActionEngine(zk.raw.charCodeAt(0)), zk.symbol, null, KeyStyle.CHARACTER, [], true, true, 21, zk.symbol));
      }
      rows.push(keyRow);
    }
    // Append delete key to row 3
    const delKey = KeyBuilder.deleteKey(t);
    rows[3].push(delKey);

    const symbolsKey = new Key(new KeyActionPage(1), t.pick('符號', '符号'), null, KeyStyle.UTILITY, [], false, true, 16, t.pick('符號', '符号'));
    const bottom = KeyBuilder.bottomRow(context, t, symbolsKey, KeyBuilder.toggleKey(context));

    const keyRows: Key[][] = [];
    for (let i = 0; i < rows.length; i++) {
      keyRows.push(rows[i]);
    }
    keyRows.push(bottom.keys);

    const specs: RowSpec[] = [];
    specs.push(new RowSpec(arrayOfFill(11, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(10, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(10, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(11, 1), RowAlignment.CENTERED));
    specs.push(bottom.spec);

    return new KeySet(keyRows, specs, 11);
  }

  static symbolRows(page: number, chinese: boolean): string[][] {
    if (page === 1 && !chinese) {
      return [stringToCharArray('1234567890'), ['-', '/', ':', ';', '(', ')', '$', '&', '@', '"'], ['.', ',', '?', '!', "'"]];
    }
    if (!chinese) {
      return [['[', ']', '{', '}', '#', '%', '^', '*', '+', '='], ['_', '\\', '|', '~', '<', '>', '€', '£', '¥', '•'], ['.', ',', '?', '!', "'"]];
    }
    if (page === 1) {
      return [stringToCharArray('1234567890'), ['-', '/', '：', '；', '（', '）', '¥', '@', '\u201C', '\u201D'], ['。', '，', '、', '？', '！', '.']];
    }
    return [['【', '】', '｛', '｝', '#', '%', '^', '*', '+', '='], ['_', '—', '＼', '｜', '～', '《', '》', '€', '&', '·'], ['…', '，', '^_^', '？', '！', "'"]];
  }

  /**
   * 【鸿蒙增强】Emoji 表情页（page ≥ 3）：安卓 0.9.1 与鸿蒙现有版都没有 emoji 面板，
   * 而鸿蒙系统键盘/iOS 都有——这是用户点名的「emoji 适配」差异。
   * 每页 3 行 × 最多 10 列；page 3~6 对应 笑脸 / 手势爱心 / 动物自然 / 食物 四类。
   * 入口在符号第 2 页的切换键（「#+=」→「☺」），emoji 页内用同一颗键循环切分类。
   */
  static emojiRows(page: number): string[][] {
    const pick = (s: string): string[][] => {
      const flat = stringToCharArray(s);
      return [flat.slice(0, 10), flat.slice(10, 20), flat.slice(20, 30)];
    };
    if (page === 4) return pick('🤗🤭🤫🤔🤌🤏✌🤞🤟🤘🤙👈👉👆👇☝👍👎✊👊🤛🤜👏🙌👐🙏💪');
    if (page === 5) return pick('🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🐤🦆🦅🦉🦇🐺🐗🐴🦄🐝🐛');
    if (page === 6) return pick('🍎🍏🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🥑🍆🥔🥕🌽🌶🥒🍄🥜🍞🍖');
    return pick('😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😗😚😙🥲😋😛😜🤪😝🤑🤠🥳');
  }

  /** emoji 分类页序号（3~6）与展示名（符号页/emoji 页切换键标签）。 */
  static emojiPageLabel(page: number): string {
    if (page === 4) return '手势';
    if (page === 5) return '动物';
    if (page === 6) return '食物';
    return '笑脸';
  }

  private static symbols(context: KeyContext, page: number, chinese: boolean, t: Words): KeySet {
    const emoji = page >= 3;
    const source = emoji ? KeyBuilder.emojiRows(page) : KeyBuilder.symbolRows(page, chinese);
    const keyOf = (text: string): Key => {
      const altArr = SYMBOL_ALTERNATES.get(text);
      const alts: string[] = [];
      if (altArr !== undefined) {
        for (let i = 0; i < altArr.length; i++) {
          alts.push(altArr[i]);
        }
      }
      return new Key(new KeyActionText(text), text, null, KeyStyle.CHARACTER,
        alts, true, true, text.length > 1 ? 16 : 21, text);
    };
    // 切换键：数字页「#+=」进第 2 页；第 2 页「☺」进 emoji 分类；emoji 页循环下一分类（回 3）。
    let other: Key;
    if (emoji) {
      const next = page >= 6 ? 3 : page + 1;
      other = new Key(new KeyActionPage(next), KeyBuilder.emojiPageLabel(page), null,
        KeyStyle.UTILITY, [], false, true, 15, `表情分类：${KeyBuilder.emojiPageLabel(next)}`);
    } else if (page === 1) {
      other = new Key(new KeyActionPage(2), '#+=', null, KeyStyle.UTILITY, [], false, true, 16, t.pick('更多符號', '更多符号'));
    } else {
      other = new Key(new KeyActionPage(3), '☺', null, KeyStyle.UTILITY, [], false, true, 16, '表情');
    }
    let lettersLabel: string;
    if (context.english) lettersLabel = 'ABC';
    else if (context.mode === InputMode.ZHUYIN) lettersLabel = '注音';
    else if (context.mode === InputMode.JAPANESE) lettersLabel = 'かな';
    else lettersLabel = '拼音';
    const back = new Key(new KeyActionPage(0), lettersLabel, null, KeyStyle.UTILITY, [], false, true, 16, '字母');
    const bottom = KeyBuilder.bottomRow(context, t, back, null);
    const middle = (10 - 2 * 1.32) / source[2].length;

    // Build row 3: [other, ...source[2].map(keyOf), deleteKey]
    const mappedRow2: Key[] = [];
    const src2 = source[2];
    for (let i = 0; i < src2.length; i++) {
      mappedRow2.push(keyOf(src2[i]));
    }
    const row3: Key[] = [];
    row3.push(other);
    for (let i = 0; i < mappedRow2.length; i++) {
      row3.push(mappedRow2[i]);
    }
    row3.push(KeyBuilder.deleteKey(t));

    // Build row 0 and row 1
    const mappedRow0: Key[] = [];
    const src0 = source[0];
    for (let i = 0; i < src0.length; i++) {
      mappedRow0.push(keyOf(src0[i]));
    }
    const mappedRow1: Key[] = [];
    const src1 = source[1];
    for (let i = 0; i < src1.length; i++) {
      mappedRow1.push(keyOf(src1[i]));
    }

    const keyRows: Key[][] = [];
    keyRows.push(mappedRow0);
    keyRows.push(mappedRow1);
    keyRows.push(row3);
    keyRows.push(bottom.keys);

    // Build specs row 3 units: [1.32, ...fill(source[2].length, middle), 1.32]
    const row3Units: number[] = [];
    row3Units.push(1.32);
    const middles = arrayOfFill(source[2].length, middle);
    for (let i = 0; i < middles.length; i++) {
      row3Units.push(middles[i]);
    }
    row3Units.push(1.32);

    const specs: RowSpec[] = [];
    specs.push(new RowSpec(arrayOfFill(10, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(arrayOfFill(10, 1), RowAlignment.CENTERED));
    specs.push(new RowSpec(row3Units, RowAlignment.JUSTIFIED));
    specs.push(bottom.spec);

    return new KeySet(keyRows, specs, 10, page);
  }
}

export { keyCtxEquals };
