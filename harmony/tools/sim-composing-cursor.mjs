// 真机反馈 ⑨ 仿真：组字串光标定位 + 中间退格 + 中间插入。
// 验证 wobini → 点 b → 退格 → 打 a → woaini 的字符串操作序列。
// 纯字符串操作，不依赖引擎（引擎路径已在 Composer 内由 replay 保证）。
const cases = [];
let pass = 0, fail = 0;
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) pass++; else { fail++; cases.push(`✗ ${name}: got=${JSON.stringify(got)} want=${JSON.stringify(want)}`); }
}

// —— 复刻 Composer 的光标逻辑（与 Composer.ets 的 type/backspace 一致）——
class Sim {
  constructor() { this.raw = ''; this.cur = -1; }
  get cursor() { return this.cur >= 0 && this.cur <= this.raw.length ? this.cur : this.raw.length; }
  set cursor(v) { this.cur = Math.max(0, Math.min(v, this.raw.length)); }
  type(c) {
    if (this.cur > 0 && this.cur < this.raw.length) {
      const pos = this.cur;
      this.raw = this.raw.substring(0, pos) + c + this.raw.substring(pos);
      this.cur = pos + 1;
      return true;
    }
    this.raw += c;
    if (this.cur >= 0) this.cur = this.raw.length;
    return true;
  }
  backspace() {
    if (this.raw.length === 0) return false;
    const pos = this.cursor;
    if (pos === 0) return true; // 光标在串首
    if (pos < this.raw.length) {
      this.raw = this.raw.substring(0, pos - 1) + this.raw.substring(pos);
      this.cur = pos - 1;
      return true;
    }
    this.raw = this.raw.substring(0, this.raw.length - 1);
    this.cur = this.raw.length;
    return true;
  }
}

// 用户场景：wobini → 点 b（光标到 b 后=3）→ 退格（删 b）→ 打 a → woaini
{
  const s = new Sim();
  'wobini'.split('').forEach(c => s.type(c));
  check('初始串', s.raw, 'wobini');
  check('初始光标(-1=串尾)', s.cursor, 6);
  s.cursor = 3; // 点 b 后
  check('点b后光标', s.cursor, 3);
  s.backspace();
  check('退格删b', s.raw, 'woini');
  check('退格后光标', s.cursor, 2);
  s.type('a');
  check('打a插入', s.raw, 'woaini');
  check('打a后光标', s.cursor, 3);
}

// 光标在串首退格：无操作
{
  const s = new Sim();
  'abc'.split('').forEach(c => s.type(c));
  s.cursor = 0;
  s.backspace();
  check('串首退格不动', s.raw, 'abc');
  check('串首退格后光标', s.cursor, 0);
}

// 光标在串中连续退格两次
{
  const s = new Sim();
  'abcde'.split('').forEach(c => s.type(c));
  s.cursor = 3; // cd 之间
  s.backspace(); // 删 c → abde
  check('中退×1', s.raw, 'abde');
  s.backspace(); // 删 b → ade
  check('中退×2', s.raw, 'ade');
  check('中退×2后光标', s.cursor, 1);
}

// 中间插入多个字符
{
  const s = new Sim();
  'wni'.split('').forEach(c => s.type(c));
  s.cursor = 1; // w|ni
  s.type('o'); s.type('a'); s.type('i');
  check('连插3字符', s.raw, 'woaini');
  check('连插后光标', s.cursor, 4);
}

// 光标清除后回到串尾行为
{
  const s = new Sim();
  'abc'.split('').forEach(c => s.type(c));
  s.cursor = 1;
  s.cur = -1; // clearCursor
  s.backspace();
  check('清光标后退格=串尾退格', s.raw, 'ab');
  check('清光标后退格光标', s.cursor, 2);
}

// 空串退格
{
  const s = new Sim();
  check('空串退格handled', s.backspace(), false);
}

// 光标越界 clamp
{
  const s = new Sim();
  'ab'.split('').forEach(c => s.type(c));
  s.cursor = 99;
  check('越界光标clamp', s.cursor, 2);
  s.cursor = -5;
  check('负光标clamp', s.cursor, 0);
}

// —— 汇总 ——
console.log(`通过 ${pass} / ${pass + fail}`);
cases.forEach(c => console.log(c));
if (fail > 0) { console.log('=== 结果：有失败 ==='); process.exit(1); }
console.log(`=== 结果：全部通过（通过 ${pass}）===`);
