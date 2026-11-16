/**
 * 【鸿蒙增强】九键拼音（T9）引擎。
 *
 * Android 0.9.1 与 iOS 版都没有九键（PARITY round 56 核实：APK 设置页显示 4 档
 * 但 Rust 核心 session.key() 拼音分支只收 a-z，数字串无法解码，原实现把九键降级
 * 成全键拼音——用户点名「九键拼音没实现」）。本文件在 ArkTS 侧补齐：
 *
 * 1. T9 映射：2=abc 3=def 4=ghi 5=jkl 6=mno 7=pqrs 8=tuv 9=wxyz。
 * 2. 数字串 → 合法拼音音节切分（DP 按音节的数字编码切，一段编码可对应多音节）。
 * 3. 每个切分展开成字母组合（一个编码段可对应多个音节字母，组合数受 CAP 保护），
 *    逐组合在 shadow session 上 key() 重放 → 取引擎候选 → 合并去重排序。
 *
 * shadow session 复用同一 pinyin lexicon（sessionCreate 可多开，Arc 共享），
 * 由 Composer 持有；这里只做纯计算与候选合成。
 */
import { Candidate, CandidateKind } from './Types';
import { NativeEngine } from './NativeEngine';

/** 每个数字键的字母（标准九键）。 */
const T9_MAP: Map<string, string> = new Map<string, string>([
  ['2', 'abc'], ['3', 'def'], ['4', 'ghi'], ['5', 'jkl'],
  ['6', 'mno'], ['7', 'pqrs'], ['8', 'tuv'], ['9', 'wxyz'],
]);

/**
 * 合法拼音音节表（不带声调，404 个）。按字母序写死——引擎词库的 reading
 * 都由这些音节组成；表外切分（如 "jv"）不可能是词库读音。
 */
const SYLLABLES: string[] = [
  'a', 'ai', 'an', 'ang', 'ao', 'ba', 'bai', 'ban', 'bang', 'bao', 'bei', 'ben', 'beng',
  'bi', 'bian', 'biao', 'bie', 'bin', 'bing', 'bo', 'bu', 'ca', 'cai', 'can', 'cang',
  'cao', 'ce', 'cen', 'ceng', 'cha', 'chai', 'chan', 'chang', 'chao', 'che', 'chen',
  'cheng', 'chi', 'chong', 'chou', 'chu', 'chua', 'chuai', 'chuan', 'chuang', 'chui',
  'chun', 'chuo', 'ci', 'cong', 'cou', 'cu', 'cuan', 'cui', 'cun', 'cuo', 'da', 'dai',
  'dan', 'dang', 'dao', 'de', 'dei', 'den', 'deng', 'di', 'dia', 'dian', 'diao', 'die',
  'ding', 'diu', 'dong', 'dou', 'du', 'duan', 'dui', 'dun', 'duo', 'e', 'ei', 'en',
  'eng', 'er', 'fa', 'fan', 'fang', 'fei', 'fen', 'feng', 'fo', 'fou', 'fu', 'ga',
  'gai', 'gan', 'gang', 'gao', 'ge', 'gei', 'gen', 'geng', 'gong', 'gou', 'gu', 'gua',
  'guai', 'guan', 'guang', 'gui', 'gun', 'guo', 'ha', 'hai', 'han', 'hang', 'hao',
  'he', 'hei', 'hen', 'heng', 'hong', 'hou', 'hu', 'hua', 'huai', 'huan', 'huang',
  'hui', 'hun', 'huo', 'ji', 'jia', 'jian', 'jiang', 'jiao', 'jie', 'jin', 'jing',
  'jiong', 'jiu', 'ju', 'juan', 'jue', 'jun', 'ka', 'kai', 'kan', 'kang', 'kao', 'ke',
  'kei', 'ken', 'keng', 'kong', 'kou', 'ku', 'kua', 'kuai', 'kuan', 'kuang', 'kui',
  'kun', 'kuo', 'la', 'lai', 'lan', 'lang', 'lao', 'le', 'lei', 'leng', 'li', 'lia',
  'lian', 'liang', 'liao', 'lie', 'lin', 'ling', 'liu', 'lo', 'long', 'lou', 'lu',
  'luan', 'lun', 'luo', 'lv', 'ma', 'mai', 'man', 'mang', 'mao', 'me', 'mei', 'men',
  'meng', 'mi', 'mian', 'miao', 'mie', 'min', 'ming', 'miu', 'mo', 'mou', 'mu', 'na',
  'nai', 'nan', 'nang', 'nao', 'ne', 'nei', 'nen', 'neng', 'ni', 'nian', 'niang',
  'niao', 'nie', 'nin', 'ning', 'niu', 'nong', 'nou', 'nu', 'nuan', 'nuo', 'nv', 'o',
  'ou', 'pa', 'pai', 'pan', 'pang', 'pao', 'pei', 'pen', 'peng', 'pi', 'pian', 'piao',
  'pie', 'pin', 'ping', 'po', 'pou', 'pu', 'qi', 'qian', 'qiang', 'qiao', 'qie', 'qin',
  'qing', 'qiong', 'qiu', 'qu', 'quan', 'que', 'qun', 'ran', 'rang', 'rao', 're', 'ren',
  'reng', 'ri', 'rong', 'rou', 'ru', 'rua', 'ruan', 'rui', 'run', 'ruo', 'sa', 'sai',
  'san', 'sang', 'sao', 'se', 'sen', 'seng', 'sha', 'shai', 'shan', 'shang', 'shao',
  'she', 'shei', 'shen', 'sheng', 'shi', 'shou', 'shu', 'shua', 'shuai', 'shuan',
  'shuang', 'shui', 'shun', 'shuo', 'si', 'song', 'sou', 'su', 'suan', 'sui', 'sun',
  'suo', 'ta', 'tai', 'tan', 'tang', 'tao', 'te', 'teng', 'ti', 'tian', 'tiao', 'tie',
  'ting', 'tong', 'tou', 'tu', 'tuan', 'tui', 'tun', 'tuo', 'wa', 'wai', 'wan', 'wang',
  'wei', 'wen', 'weng', 'wo', 'wu', 'xi', 'xia', 'xian', 'xiang', 'xiao', 'xie', 'xin',
  'xing', 'xiong', 'xiu', 'xu', 'xuan', 'xue', 'xun', 'ya', 'yan', 'yang', 'yao', 'ye',
  'yi', 'yin', 'ying', 'yo', 'yong', 'you', 'yu', 'yuan', 'yue', 'yun', 'za', 'zai',
  'zan', 'zang', 'zao', 'ze', 'zei', 'zen', 'zeng', 'zha', 'zhai', 'zhan', 'zhang',
  'zhao', 'zhe', 'zhen', 'zheng', 'zhong', 'zhou', 'zhu', 'zhua', 'zhuai', 'zhuan',
  'zhuang', 'zhui', 'zhun', 'zhuo', 'zi', 'zong', 'zou', 'zu', 'zuan', 'zui', 'zun',
  'zuo',
];

/** 音节数字编码 → 音节列表（构建一次）。 */
const CODE_TO_SYLLABLES: Map<string, string[]> = buildCodeMap();

function t9Key(c: string): string {
  const map = T9_MAP;
  const keys = ['2', '3', '4', '5', '6', '7', '8', '9'];
  for (let i = 0; i < keys.length; i++) {
    const letters = map.get(keys[i]) ?? '';
    if (letters.indexOf(c) >= 0) return keys[i];
  }
  return '';
}

function buildCodeMap(): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (let idx = 0; idx < SYLLABLES.length; idx++) {
    const s = SYLLABLES[idx];
    let codeStr = '';
    for (let i = 0; i < s.length; i++) codeStr += t9Key(s.charAt(i));
    const existing = out.get(codeStr);
    if (existing === undefined) out.set(codeStr, [s]);
    else existing.push(s);
  }
  return out;
}

/** 一个数字编码切分序列（每段是音节数字编码）。 */

/** 字母组合展开的上限：避免长输入组合爆炸。 */
const COMBO_CAP = 24;
/** 每个组合从引擎取的候选数。 */
const PER_COMBO_CANDIDATES = 8;
/** 组字框里显示的切分上限。 */
const SPLIT_CAP = 12;

/** 单个字母组合的查询结果（用于组合间排序）。 */
class T9ComboResult {
  splitLen: number;
  bestKind: number;
  texts: string[];
  spellingLen: number;
  constructor(splitLen: number, bestKind: number, texts: string[], spellingLen: number) {
    this.splitLen = splitLen;
    this.bestKind = bestKind;
    this.texts = texts;
    this.spellingLen = spellingLen;
  }
}

export class T9 {
  /** 数字串是否全部是九键按键 2-9。 */
  static isDigits(s: string): boolean {
    if (s.length === 0) return false;
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      if (c < '2' || c > '9') return false;
    }
    return true;
  }

  /**
   * 数字串 → 全部合法切分（编码段序列），完全消耗输入。
   * 结果按「段数少优先，长音节优先」粗排，切分上限 SPLIT_CAP。
   */
  static splits(digits: string): string[][] {
    const n = digits.length;
    if (n === 0) return [];
    // reach[i] = 到达位置 i 的切分列表
    const reach: string[][][] = [];
    for (let i = 0; i <= n; i++) reach.push([]);
    reach[0].push([]);
    for (let i = 0; i < n; i++) {
      const here = reach[i];
      if (here.length === 0) continue;
      for (let len = 1; len <= 6 && i + len <= n; len++) {
        const seg = digits.substring(i, i + len);
        if (!CODE_TO_SYLLABLES.has(seg)) continue;
        const next = reach[i + len];
        for (let p = 0; p < here.length; p++) {
          const path = here[p];
          const copy = path.slice(0);
          copy.push(seg);
          if (next.length <= SPLIT_CAP * 4) next.push(copy);
        }
      }
    }
    let out = reach[n];
    // 短切分（音节数少）优先：更可能是用户意图的多字词。
    out = out.slice(0);
    out.sort((a: string[], b: string[]): number => a.length - b.length);
    if (out.length > SPLIT_CAP) out = out.slice(0, SPLIT_CAP);
    return out;
  }

  /**
   * 一个切分 → 字母组合（笛卡尔积，每段从编码取音节）。
   * 每段内音节按「常见度」排序（硬编码频率序：a>o>e>i>u>v>…；辅音组短的优先），
   * 笛卡尔积按字典序即近似按常见度。返回拼音串（直接连接，不加分隔符——
   * 引擎 reading 不带分隔符，boundary 不影响 sounds 匹配）。
   */
  static combos(segments: string[]): string[] {
    let combos: string[] = [''];
    for (let i = 0; i < segments.length; i++) {
      const sylls = CODE_TO_SYLLABLES.get(segments[i]) ?? [];
      if (sylls.length === 0) return [];
      // 段内排序：短的音节优先（完整拼音键入的默认习惯），同长按字母序。
      const sorted = sylls.slice(0);
      sorted.sort((a: string, b: string): number =>
        a.length !== b.length ? a.length - b.length : (a < b ? -1 : 1));
      const next: string[] = [];
      for (let c = 0; c < combos.length; c++) {
        for (let s = 0; s < sorted.length; s++) {
          next.push(combos[c] + sorted[s]);
          if (next.length >= COMBO_CAP) break;
        }
        if (next.length >= COMBO_CAP) break;
      }
      combos = next;
    }
    return combos;
  }

  /**
   * 数字串的组字预编辑显示：「ni hao」式分段拼音（取第一个切分的首选音节）。
   */
  static preeditText(digits: string): string {
    const splits = T9.splits(digits);
    if (splits.length === 0) return digits;
    const parts: string[] = [];
    const first = splits[0];
    for (let i = 0; i < first.length; i++) {
      const sylls = CODE_TO_SYLLABLES.get(first[i]) ?? [''];
      parts.push(sylls[0]);
    }
    return parts.join(' ');
  }

  /**
   * 主查询：数字串 → 候选列表。shadow 是一个可随意重放的引擎会话
   * （Composer 在 attach 时创建的查询专用 session，与主 session 共用词库）。
   * 返回按以下优先级合并的候选：完全消耗输入的短切分 > 完全消耗的长切分 > 前缀消耗。
   */
  static query(digits: string, shadow: number, simplified: boolean): Candidate[] {
    if (shadow === 0 || digits.length === 0) return [];
    const splits = T9.splits(digits);
    if (splits.length === 0) return [];
    NativeEngine.setSimplified(shadow, simplified);

    // 两轮策略：先对每个组合打分（首候选的引擎 kind：EXACT=完整拼写高频词），
    // 再按「切分段数少 → 组合首候选更优」的顺序合并候选 —— 否则 mi-gan 这类
    // 同长度歧义组合会淹没 ni-hao 的「你好」（真机验证 64426 首选必须是 你好）。
    const results: T9ComboResult[] = [];
    for (let si = 0; si < splits.length; si++) {
      const combos = T9.combos(splits[si]);
      for (let ci = 0; ci < combos.length; ci++) {
        const spelling = combos[ci];
        if (spelling.length === 0) continue;
        NativeEngine.clear(shadow);
        for (let k = 0; k < spelling.length; k++) {
          NativeEngine.key(shadow, spelling.charCodeAt(k));
        }
        NativeEngine.takeCommitted(shadow);
        const count = NativeEngine.candidateCount(shadow);
        const take = Math.min(PER_COMBO_CANDIDATES, count);
        if (take <= 0) continue;
        const texts = NativeEngine.candidates(shadow, 0, take);
        const details = NativeEngine.candidateDetails(shadow, 0, 1);
        const bestKind = details.length >= 2 ? details[1] : 0;
        results.push(new T9ComboResult(splits[si].length, bestKind, texts, spelling.length));
      }
    }
    // 排序：切分段数少优先（更可能是词），然后首候选 EXACT 优先，然后原遍历序（稳定）。
    results.sort((a: T9ComboResult, b: T9ComboResult): number => {
      if (a.splitLen !== b.splitLen) return a.splitLen - b.splitLen;
      if (a.bestKind !== b.bestKind) return b.bestKind - a.bestKind;
      return 0;
    });
    const ranked: Candidate[] = [];
    const seen = new Set<string>();
    for (let ri = 0; ri < results.length; ri++) {
      const r = results[ri];
      for (let t = 0; t < r.texts.length; t++) {
        const text = r.texts[t];
        if (text.length === 0 || seen.has(text)) continue;
        seen.add(text);
        ranked.push({ text: text, kind: CandidateKind.CHINESE, coreIndex: -1, consumed: r.spellingLen });
      }
    }
    // cap 总数，保序（组合优先级已在排序里体现）。
    return ranked.slice(0, 64);
  }
}
