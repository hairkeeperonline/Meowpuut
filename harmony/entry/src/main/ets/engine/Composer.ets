/**
 * 一次组字（对应 Android engine/Composer.kt）。拼音和注音走 Rust 核心，
 * 日语（罗马字转假名）在这里处理。所有调用都在主线程。
 */
import { Candidate, CandidateKind, CoreCandidate, Edit, InputMode } from './Types';
import { NativeEngine } from './NativeEngine';
import { JapaneseWords } from './JapaneseWords';
import { Romaji } from './Romaji';
import { CandidateMerge } from './CandidateMerge';

const FIRST_BATCH = 48;
const TONES = ' 6347';
const TONE_MARKS: Map<string, string> = new Map([
  ['6', 'ˊ'], ['3', 'ˇ'], ['4', 'ˋ'], ['7', '˙'], [' ', 'ˉ'],
]);

export class Composer {
  japaneseWords: JapaneseWords = JapaneseWords.EMPTY;

  private _mode: InputMode = InputMode.ZHUYIN;
  private _simplified: boolean = false;

  private session: number = 0;
  private maxInput: number = 64;
  private raw: string = '';
  private coreTotal: number = 0;
  private coreFetched: number = 0;

  private _candidates: Candidate[] = [];
  private _highlighted: number = 0;
  private _preedit: string = '';

  /** 【真机反馈 ⑨】组字串内光标位（0..raw.length）。-1 = 未设置（跟串尾，原行为）。 */
  private _cursor: number = -1;

  get mode(): InputMode { return this._mode; }

  get simplified(): boolean { return this._simplified; }
  set simplified(value: boolean) {
    if (this._simplified === value) return;
    this._simplified = value;
    if (this.session !== 0) {
      NativeEngine.setSimplified(this.session, value);
      if (this.raw.length > 0) this.rebuild();
    }
  }

  get candidates(): Candidate[] { return this._candidates; }
  get highlighted(): number { return this._highlighted; }
  set highlighted(v: number) { this._highlighted = v; }
  get preedit(): string { return this._preedit; }

  get composing(): boolean { return this.raw.length > 0; }
  /** 当前组合中的原始串（调试用）。 */
  get rawPreview(): string { return this.raw; }
  get input(): string { return this.raw; }
  get moreAvailable(): boolean { return this.coreFetched < this.coreTotal; }

  /** 【真机反馈 ⑨】光标位置（供 UI 画光标竖线）；-1 或越界视为串尾。 */
  get cursor(): number {
    return this._cursor >= 0 && this._cursor <= this.raw.length ? this._cursor : this.raw.length;
  }
  set cursor(value: number) {
    this._cursor = Math.max(0, Math.min(value, this.raw.length));
  }
  /** 清除光标（回到「跟串尾」行为）。 */
  clearCursor(): void { this._cursor = -1; }

  /** 日语不需要词库；中文要等引擎会话。 */
  get ready(): boolean { return this._mode === InputMode.JAPANESE || this.session !== 0; }

  attach(mode: InputMode, session: number): void {
    this.session = 0;
    this.clear();
    this._mode = mode;
    // 九键模式收到的就是引擎原生九键会话（Lexicons 按 mode 创建）。
    this.session = mode === InputMode.JAPANESE ? 0 : session;
    if (this.session !== 0) {
      this.maxInput = Math.max(8, NativeEngine.maxInputBytes());
      NativeEngine.setSimplified(this.session, this._simplified);
    }
  }

  detach(): void {
    this.clear();
    this.session = 0;
  }

  type(code: number): Edit {
    const c = String.fromCharCode(code);
    // 【真机反馈 ⑨】光标在组字串中间时：插入到光标处并整串重放引擎。
    // 不走各模式 type* 的「尾追 + 单键喂引擎」快速路径——中间插入无法用
    // 单键表达，必须 clear + 重放。仅光标确实在中间（0 < cursor < raw.length）
    // 才走此路径；光标在尾/未设置时保持原有高效路径不变。
    if (this._cursor > 0 && this._cursor < this.raw.length) {
      return this.insertAtCursor(c);
    }
    switch (this._mode) {
      case InputMode.PINYIN: return this.typePinyin(c);
      // 九键拼音：数字 2-9 直接进引擎原生九键会话（解码在 Rust 核心里）。
      case InputMode.PINYIN9: return this.typePinyin9(c);
      case InputMode.ZHUYIN: return this.typeZhuyin(c);
      case InputMode.JAPANESE: return this.typeJapanese(c);
      default: return { handled: false, commit: '' };
    }
  }

  /** 【真机反馈 ⑨】组字串中间插入一个字符并重放引擎。 */
  private insertAtCursor(c: string): Edit {
    if (this._mode === InputMode.JAPANESE) {
      const ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '-' || c === "'";
      if (!ok) return { handled: false, commit: '' };
      if (this.raw.length >= 80) return { handled: true, commit: '' };
    } else {
      if (this.session === 0) return { handled: false, commit: '' };
      if (this.raw.length >= this.maxInput) return { handled: true, commit: '' };
    }
    const pos = this._cursor;
    this.raw = this.raw.substring(0, pos) + c + this.raw.substring(pos);
    this._cursor = pos + 1;
    if (this._mode !== InputMode.JAPANESE && this.session !== 0) this.replay();
    this.rebuild();
    return { handled: true, commit: '' };
  }

  /** 九键数字输入：数字 2-9 与分词符 ' 直接进引擎原生九键会话（解码在 Rust 核心）。
   *  round 64 真机修复：撇号此前被 2-9 检查拒收（handled=false → 触发 finishComposition
   *  提交顶候选），而 Rust nine_key 会话原生支持 SEPARATOR（raw "94'26" → 在位 2 切分，
   *  跨段解码出西安这类候选——对齐安卓九键分词行为）。引擎侧只在数字后接受撇号，
   *  传参被拒时仍返回 handled=false 走旧路径，语义不变。 */
  private typePinyin9(c: string): Edit {
    if (this.session === 0) return { handled: false, commit: '' };
    const digit = c >= '2' && c <= '9';
    const separator = c === "'" && this.raw.length > 0 && !this.raw.endsWith("'");
    if (!digit && !separator) return { handled: false, commit: '' };
    if (this.raw.length >= 12) return { handled: true, commit: '' };
    if (!NativeEngine.key(this.session, c.charCodeAt(0))) {
      return { handled: false, commit: '' };
    }
    this.raw += c;
    const pending = NativeEngine.takeCommitted(this.session);
    this.syncRaw();
    this.rebuild();
    return { handled: true, commit: pending };
  }

  private typePinyin(c: string): Edit {
    if (this.session === 0) return { handled: false, commit: '' };
    const letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    const separator = c === "'" && this.raw.length > 0 && !this.raw.endsWith("'");
    if (!letter && !separator) return { handled: false, commit: '' };
    let pending = '';
    if (this.raw.length >= this.maxInput) {
      pending = this.raw;
      this.resetCore();
      if (separator) return { handled: true, commit: pending };
    }
    if (!NativeEngine.key(this.session, c.toLowerCase().charCodeAt(0))) {
      return { handled: pending.length > 0, commit: pending };
    }
    this.raw += c;
    pending += NativeEngine.takeCommitted(this.session);
    this.syncRaw();
    this.rebuild();
    return { handled: true, commit: pending };
  }

  private typeZhuyin(c: string): Edit {
    if (this.session === 0) return { handled: false, commit: '' };
    let pending = '';
    if (this.raw.length >= this.maxInput) {
      const tone = TONE_MARKS.get(c);
      if (tone !== undefined) {
        if (TONES.includes(this.raw.charAt(this.raw.length - 1))) return { handled: true, commit: '' };
        const text = this.preedit + tone;
        this.resetCore();
        return { handled: true, commit: text };
      }
      pending = this.preedit;
      this.resetCore();
    }
    if (!NativeEngine.key(this.session, c.charCodeAt(0))) {
      return { handled: pending.length > 0, commit: pending };
    }
    this.raw += c;
    pending += NativeEngine.takeCommitted(this.session);
    this.syncRaw();
    this.rebuild();
    return { handled: true, commit: pending };
  }

  private typeJapanese(c: string): Edit {
    const ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '-' || c === "'";
    if (!ok) return { handled: false, commit: '' };
    if (this.raw.length >= 80) return { handled: true, commit: '' };
    this.raw += c;
    this.rebuild();
    return { handled: true, commit: '' };
  }

  space(): Edit {
    if (this.raw.length === 0) return { handled: false, commit: '' };
    switch (this._mode) {
      case InputMode.ZHUYIN:
        return TONES.includes(this.raw.charAt(this.raw.length - 1)) ? this.chooseHighlighted() : this.typeZhuyin(' ');
      case InputMode.PINYIN:
      case InputMode.PINYIN9:
        return this.candidates.length > 0 ? this.chooseHighlighted() : { handled: true, commit: this.takeLiteral() + ' ' };
      case InputMode.JAPANESE:
        return this.chooseHighlighted();
      default:
        return { handled: false, commit: '' };
    }
  }

  backspace(): Edit {
    if (this.raw.length === 0) return { handled: false, commit: '' };
    // 【真机反馈 ⑨】光标在组字串中间时删光标前的字符；光标在串首（0）时无字符可删。
    const pos = this.cursor;
    if (pos === 0) return { handled: true, commit: '' };
    if (pos < this.raw.length) {
      // 中间删除：raw 去掉 [pos-1]，重放引擎（不能只发 KEY_BACKSPACE——那删的是串尾）。
      this.raw = this.raw.substring(0, pos - 1) + this.raw.substring(pos);
      this._cursor = pos - 1;
      if (this._mode !== InputMode.JAPANESE && this.session !== 0) {
        if (this.raw.length === 0) NativeEngine.clear(this.session);
        else this.replay();
      }
      this.rebuild();
      return { handled: true, commit: '' };
    }
    // 光标在串尾：原有快速路径（单键退格，不需重放）。
    this.raw = this.raw.substring(0, this.raw.length - 1);
    this._cursor = this.raw.length;
    if (this._mode !== InputMode.JAPANESE && this.session !== 0) {
      if (this.raw.length === 0) {
        NativeEngine.clear(this.session);
      } else {
        NativeEngine.key(this.session, NativeEngine.KEY_BACKSPACE);
        NativeEngine.takeCommitted(this.session);
        if (NativeEngine.input(this.session) !== this.coreText(this.raw)) this.replay();
      }
    }
    this.rebuild();
    return { handled: true, commit: '' };
  }

  chooseHighlighted(): Edit {
    const idx = Math.min(Math.max(0, this._highlighted), Math.max(0, this.candidates.length - 1));
    return this.choose(idx);
  }

  choose(index: number): Edit {
    const c = index >= 0 && index < this.candidates.length ? this.candidates[index] : null;
    if (c === null) {
      return this.raw.length === 0 ? { handled: false, commit: '' } : { handled: true, commit: this.takeLiteral() };
    }
    switch (c.kind) {
      case CandidateKind.CHINESE: {
        if (this.session === 0 || !NativeEngine.choose(this.session, c.coreIndex)) {
          return { handled: false, commit: '' };
        }
        const text = NativeEngine.takeCommitted(this.session);
        const rest = NativeEngine.input(this.session);
        if (rest.length === 0) { this.raw = ''; this._cursor = -1; } else this.keepSuffix(rest);
        this.rebuild();
        return { handled: true, commit: text };
      }
      case CandidateKind.MIXED_PREFIX: {
        const consumed = Math.min(c.consumed, this.raw.length);
        const rest = this.raw.substring(consumed);
        this.resetCore();
        this.raw = rest;
        this.replay();
        this.rebuild();
        return { handled: true, commit: c.text };
      }
      default: {
        this.resetCore();
        return { handled: true, commit: c.text };
      }
    }
  }

  takeLiteral(): string {
    // 九键的「原样上屏」= 数字串本身（raw 即数字）。
    const text = this._mode === InputMode.ZHUYIN ? this.preedit : this.raw;
    this.resetCore();
    return text;
  }

  clear(): void { this.resetCore(); }

  loadMore(batch: number = 96): boolean {
    if (this.session === 0 || this.coreFetched >= this.coreTotal) return false;
    const more = this.fetchCore(this.coreFetched, batch);
    const seen = new Set(this.candidates.map(c => c.text));
    const added: Candidate[] = [];
    for (const m of more) {
      if (!seen.has(m.text)) {
        seen.add(m.text);
        added.push({ text: m.text, kind: CandidateKind.CHINESE, coreIndex: m.index, consumed: m.consumed });
      }
    }
    this._candidates = this.candidates.concat(added);
    return added.length > 0;
  }

  predictions(context: string, limit: number = 8): string[] {
    if (this.session === 0 || this._mode === InputMode.JAPANESE || context.trim().length === 0) return [];
    return NativeEngine.predict(this.session, context.slice(-8), limit).filter(t => t.length > 0);
  }

  private resetCore(): void {
    this.raw = '';
    this._cursor = -1;
    if (this.session !== 0) {
      NativeEngine.clear(this.session);
      NativeEngine.takeCommitted(this.session);
    }
    this._candidates = [];
    this._preedit = '';
    this._highlighted = 0;
    this.coreTotal = 0;
    this.coreFetched = 0;
  }

  private coreText(text: string): string {
    return (this._mode === InputMode.PINYIN || this._mode === InputMode.PINYIN9) ? text.toLowerCase() : text;
  }

  private replay(): void {
    if (this.session === 0) return;
    NativeEngine.clear(this.session);
    for (const ch of this.raw) {
      NativeEngine.key(this.session, this.coreText(ch).charCodeAt(0));
    }
    NativeEngine.takeCommitted(this.session);
  }

  private keepSuffix(rest: string): void {
    const typed = this.raw;
    let suffix: string;
    if (rest.length <= typed.length && typed.slice(-rest.length).toLowerCase() === rest.toLowerCase()) {
      suffix = typed.slice(-rest.length);
    } else {
      suffix = rest;
    }
    this.raw = suffix;
    // 【真机反馈 ⑨】串被截短（选词/引擎消费了一段）：光标意义已变，清掉回串尾模式。
    this._cursor = -1;
  }

  private syncRaw(): void {
    const core = NativeEngine.input(this.session);
    if (core !== this.coreText(this.raw)) this.keepSuffix(core);
  }

  private fetchCore(start: number, count: number): CoreCandidate[] {
    const n = Math.min(count, this.coreTotal - start);
    if (n <= 0) return [];
    const texts = NativeEngine.candidates(this.session, start, n);
    const details = NativeEngine.candidateDetails(this.session, start, n);
    this.coreFetched = start + texts.length;
    const out: CoreCandidate[] = [];
    for (let i = 0; i < texts.length; i++) {
      const consumed = details[i * 2] !== undefined ? details[i * 2] : 0;
      const kind = details[i * 2 + 1] !== undefined ? details[i * 2 + 1] : 0;
      out.push({ text: texts[i], index: start + i, consumed: consumed, exact: kind === NativeEngine.KIND_EXACT });
    }
    return out;
  }

  private rebuild(): void {
    this._highlighted = 0;
    if (this.raw.length === 0) {
      this._candidates = [];
      this._preedit = '';
      this.coreTotal = 0;
      this.coreFetched = 0;
      return;
    }
    switch (this._mode) {
      case InputMode.PINYIN9: {
        // 【内核更换 round 62】九键解码全部在引擎里：preedit 由引擎渲染
        // （首选拼音切分 + 首选候选拼写），候选按 coreIndex 指向引擎列表，
        // 选词支持部分消耗（引擎处理剩余数字继续组字）。
        this._preedit = NativeEngine.preedit(this.session);
        this.coreTotal = NativeEngine.candidateCount(this.session);
        this.coreFetched = 0;
        const core = this.fetchCore(0, FIRST_BATCH);
        const seen = new Set<string>();
        const out: Candidate[] = [];
        for (const c of core) {
          if (!seen.has(c.text)) {
            seen.add(c.text);
            out.push({ text: c.text, kind: CandidateKind.CHINESE, coreIndex: c.index, consumed: c.consumed });
          }
        }
        // 没有中文候选时兜底显示数字串本身（可上屏数字）。
        if (out.length === 0) {
          out.push({ text: this.raw, kind: CandidateKind.LITERAL, coreIndex: -1, consumed: this.raw.length });
        }
        this._candidates = out;
        break;
      }
      case InputMode.PINYIN: {
        this._preedit = this.raw;
        this.coreTotal = NativeEngine.candidateCount(this.session);
        this.coreFetched = 0;
        const chinese = this.fetchCore(0, FIRST_BATCH);
        const lower = this.raw.toLowerCase();
        const reading = lower.replace(/'/g, '');
        // wordsLoose：先按标准罗马字精确查，不命中再按假名读音兜底
        // （这样 simimasai / sumimasen 这类不同拼法都能出「すみません」）。
        const japanese = this.japaneseWords.wordsLoose(reading, (s: string) => Romaji.reading(s));
        const word = japanese.length > 0 ? japanese[0] : null;
        // 同一读音在词表里可能挂多个词（「すみません」+ 中文音译「私密马赛」），
        // 其余作为 moreJapanese 交给 CandidateMerge，与 Android 一样排到第一页之后。
        const wordExtras: string[] = [];
        for (let i = 1; i < japanese.length; i++) wordExtras.push(japanese[i]);
        const whole = (word === null && reading.length >= 2)
          ? (NativeEngine.mixedPinyin(this.session, lower, this._simplified) || null) : null;
        let prefix: [string, number] | null = null;
        if (reading.length >= 3) {
          const p = NativeEngine.mixedPinyinPrefix(this.session, lower, this._simplified);
          if (p !== null) prefix = [p[0], parseInt(p[1], 10) || 0];
        }
        this._candidates = CandidateMerge.pinyin(
          lower, this.raw, chinese, word, whole, prefix,
          Romaji.reading(reading), wordExtras);
        break;
      }
      case InputMode.ZHUYIN: {
        this._preedit = NativeEngine.preedit(this.session);
        this.coreTotal = NativeEngine.candidateCount(this.session);
        this.coreFetched = 0;
        const core = this.fetchCore(0, FIRST_BATCH);
        const seen = new Set<string>();
        const out: Candidate[] = [];
        for (const c of core) {
          if (!seen.has(c.text)) {
            seen.add(c.text);
            out.push({ text: c.text, kind: CandidateKind.CHINESE, coreIndex: c.index, consumed: c.consumed });
          }
        }
        this._candidates = out;
        break;
      }
      case InputMode.JAPANESE: {
        const reading = Romaji.reading(this.raw);
        this._preedit = reading;
        const katakana = Romaji.katakana(reading);
        const list: Candidate[] = [];
        for (const w of this.japaneseWords.wordsLoose(this.raw.toLowerCase(), (s: string) => Romaji.reading(s))) {
          list.push({ text: w, kind: CandidateKind.JAPANESE_WORD, coreIndex: -1, consumed: this.raw.length });
        }
        list.push({ text: reading, kind: CandidateKind.KANA, coreIndex: -1, consumed: this.raw.length });
        list.push({ text: katakana, kind: CandidateKind.KANA, coreIndex: -1, consumed: this.raw.length });
        const typed = this.raw;
        const allCaps = /[A-Za-z]/.test(typed) && typed === typed.toUpperCase();
        if (allCaps) {
          const filtered = list.filter(c => c.text !== katakana);
          filtered.unshift({ text: katakana, kind: CandidateKind.KANA, coreIndex: -1, consumed: this.raw.length });
          this._candidates = this.distinctBy(filtered);
        } else {
          this._candidates = this.distinctBy(list);
        }
        break;
      }
    }
  }

  private distinctBy(list: Candidate[]): Candidate[] {
    const seen = new Set<string>();
    const out: Candidate[] = [];
    for (const c of list) {
      if (!seen.has(c.text)) { seen.add(c.text); out.push(c); }
    }
    return out;
  }
}