/**
 * Round 65 ③ 仿真：物理 Shift / CapsLock 状态机。
 * 把 KeyStates.Capitalization + MeowpuutAbility 的物理键处理器、
 * requiresInputView 的 shift getter 逐行移植到 Node，验证 11 条时序。
 * 运行：node tools/sim-shift.mjs   （全部通过退出码 0）
 */

const ShiftState = { OFF: 'OFF', ONCE: 'ONCE', LOCKED: 'LOCKED' };
const DOUBLE_TAP_MS = 300;

class Capitalization {
  constructor() {
    this._state = ShiftState.OFF;
    this.lastTap = -1;
    this.manual = false;
    this.declinedAutomatic = false;
  }
  get state() { return this._state; }

  tap(now) {
    if (this._state !== ShiftState.LOCKED && this.lastTap >= 0 && now >= this.lastTap &&
      now - this.lastTap <= DOUBLE_TAP_MS) {
      this._state = ShiftState.LOCKED;
      this.manual = true;
      this.lastTap = -1;
      return;
    }
    switch (this._state) {
      case ShiftState.OFF: this._state = ShiftState.ONCE; this.manual = true; this.lastTap = now; break;
      case ShiftState.ONCE:
        this._state = ShiftState.OFF; this.declinedAutomatic = !this.manual; this.manual = false; this.lastTap = now; break;
      case ShiftState.LOCKED: this._state = ShiftState.OFF; this.manual = false; this.lastTap = -1; break;
    }
  }

  letterTyped() {
    if (this._state === ShiftState.ONCE) { this._state = ShiftState.OFF; this.manual = false; }
    this.lastTap = -1;
    this.declinedAutomatic = false;
  }

  /** round 65 ③ 新增：只把 ONCE 降为 OFF，保留 lastTap（双击判定依赖它）。 */
  releaseShift() {
    if (this._state === ShiftState.ONCE) {
      this._state = ShiftState.OFF;
      this.manual = false;
    }
  }

  setLocked(on) {
    if (on) {
      this._state = ShiftState.LOCKED;
      this.manual = true;
      this.lastTap = -1;
      this.declinedAutomatic = false;
    } else if (this._state === ShiftState.LOCKED) {
      this._state = ShiftState.OFF;
      this.manual = false;
      this.lastTap = -1;
    }
  }

  reset() {
    this._state = ShiftState.OFF;
    this.manual = false;
    this.lastTap = -1;
    this.declinedAutomatic = false;
  }
}

/** MeowpuutAbility 状态：shiftHeld + caps + shift getter + 物理键处理。 */
class Ability {
  constructor() { this.caps = new Capitalization(); this.shiftHeld = false; }
  /** 与 Ability.shift getter 逐字一致。 */
  get shift() {
    return (this.caps.state === ShiftState.OFF && this.shiftHeld) ? ShiftState.ONCE : this.caps.state;
  }
  hwShiftDown(now) {
    this.caps.tap(now);
    this.shiftHeld = true;
  }
  hwShiftUp() {
    this.shiftHeld = false;
    this.caps.releaseShift();
  }
  hwCapsLock() {
    this.caps.setLocked(this.caps.state !== ShiftState.LOCKED);
  }
  /** 软键盘路径（onShiftDown/onShiftUp）作为对照。 */
  softShiftDown(now) { this.caps.tap(now); this.shiftHeld = true; }
  softShiftUp(typed) {
    this.shiftHeld = false;
    if (typed && this.caps.state !== ShiftState.LOCKED) this.caps.reset();
  }
  typeLetter() { this.caps.letterTyped(); }
}

let fail = 0, pass = 0;
const eq = (name, got, want) => {
  if (got === want) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name} — got ${got}, want ${want}`); }
};

console.log('=== 1. 物理 Shift 单击：按下大写一次，松手回 OFF ===');
{
  const a = new Ability();
  eq('初始 OFF', a.shift, ShiftState.OFF);
  a.hwShiftDown(1000);
  eq('按下后 ONCE（软键盘 shift 键点亮）', a.shift, ShiftState.ONCE);
  a.hwShiftUp();
  eq('松手后回 OFF（缺陷 D 修复目标：不残留大写）', a.shift, ShiftState.OFF);
  a.typeLetter();
  eq('松手后打字不受影响', a.shift, ShiftState.OFF);
}

console.log('\n=== 2. 按住 Shift 期间打字：字母大写，松手后回 OFF ===');
{
  const a = new Ability();
  a.hwShiftDown(1000);
  eq('按住期间 ONCE', a.shift, ShiftState.ONCE);
  a.typeLetter();  // 系统在此读出 unicodeChar 为大写
  eq('打一个字母后 caps 已 OFF，但 shiftHeld 仍 true → getter 返回 ONCE',
    a.shift, ShiftState.ONCE);
  a.typeLetter();
  eq('连打第二个字母仍是 ONCE（按住 Shift 连打大写，符合物理键盘直觉）',
    a.shift, ShiftState.ONCE);
  a.hwShiftUp();
  eq('松手后回 OFF', a.shift, ShiftState.OFF);
}

console.log('\n=== 3. 物理 Shift 双击：进入 LOCKED（缺陷 E 修复核心）===');
{
  const a = new Ability();
  a.hwShiftDown(1000);
  a.hwShiftUp();          // 第一次单击松手
  eq('第一次松手后 OFF', a.shift, ShiftState.OFF);
  a.hwShiftDown(1200);    // 200ms 后再按，落在 300ms 双击窗口内
  eq('第二次按下进入 LOCKED', a.shift, ShiftState.LOCKED);
  a.hwShiftUp();
  eq('LOCKED 不受松手影响', a.shift, ShiftState.LOCKED);
  a.typeLetter();
  eq('LOCKED 下打字仍锁定', a.shift, ShiftState.LOCKED);
}

console.log('\n=== 4. 双击窗口外不误锁 ===');
{
  const a = new Ability();
  a.hwShiftDown(1000);
  a.hwShiftUp();
  a.hwShiftDown(1400);    // 400ms > 300ms
  eq('超过双击窗口，第二次按下只到 ONCE', a.shift, ShiftState.ONCE);
  a.hwShiftUp();
  eq('松手回 OFF', a.shift, ShiftState.OFF);
}

console.log('\n=== 5. 若用 reset() 代替 releaseShift()，双击将被破坏（反证缺陷 E）===');
{
  // 用 reset 的变体复现旧错误
  class BadAbility extends Ability {
    hwShiftUp() { this.shiftHeld = false; this.caps.reset(); }
  }
  const bad = new BadAbility();
  bad.hwShiftDown(1000);
  bad.hwShiftUp();
  bad.hwShiftDown(1200);  // 期望 LOCKED
  eq('（反证）reset 版第二次按下无法进入 LOCKED', bad.shift, ShiftState.ONCE);
}

console.log('\n=== 6. 物理 CapsLock：拨动开关 ===');
{
  const a = new Ability();
  a.hwCapsLock();
  eq('第一次按下 → LOCKED', a.shift, ShiftState.LOCKED);
  a.hwCapsLock();
  eq('第二次按下 → OFF', a.shift, ShiftState.OFF);
  a.hwCapsLock();
  eq('第三次按下 → LOCKED', a.shift, ShiftState.LOCKED);
}

console.log('\n=== 7. LOCKED 态下按物理 Shift：解除锁定但按住期间仍提示 ONCE ===');
{
  const a = new Ability();
  a.hwCapsLock();               // LOCKED
  a.hwShiftDown(2000);
  // tap 在 LOCKED 态走 case LOCKED → OFF（与软键盘一致：锁定态再按一次解除锁定）；
  // 但此刻 shiftHeld=true，getter 按设计返回 ONCE——用户正按着 Shift，提示大写是
  // **正确**的，不该期望 OFF。
  eq('LOCKED 下按 Shift → caps 解除锁定，getter 因按住而返回 ONCE', a.shift, ShiftState.ONCE);
  eq('caps 内部状态确已解除锁定', a.caps.state, ShiftState.OFF);
  a.hwShiftUp();
  eq('松手后彻底 OFF', a.shift, ShiftState.OFF);
  a.typeLetter();
  eq('解除后打字不再大写', a.shift, ShiftState.OFF);
}

console.log('\n=== 8. 软键盘与物理路径的语义差异（有意为之，不是缺陷）===');
{
  // 软键盘 shift 是「点一下锁定下一个字母」：松手(typed=false)必须保留 ONCE，
  // 由下一个字母的 letterTyped() 清掉。
  const soft = new Ability();
  soft.softShiftDown(1000);
  const softDown = soft.shift;
  soft.softShiftUp(false);
  const softUpNoType = soft.shift;
  const softTyped = new Ability();
  softTyped.softShiftDown(1000);
  softTyped.typeLetter();
  softTyped.softShiftUp(true);
  const softUpTyped = softTyped.shift;

  // 物理 shift 是「按住才生效」：松手必须立刻回 OFF，否则会残留大写。
  const hw = new Ability();
  hw.hwShiftDown(1000);
  const hwDown = hw.shift;
  hw.hwShiftUp();
  const hwUp = hw.shift;

  eq('按下态两者一致（都提示 ONCE）', hwDown, softDown);
  eq('软键盘松手未打字 → 保留 ONCE（等下一个字母）', softUpNoType, ShiftState.ONCE);
  eq('软键盘打完字松手 → OFF', softUpTyped, ShiftState.OFF);
  eq('物理松手 → 立刻 OFF（按住语义，缺陷 D 修复目标）', hwUp, ShiftState.OFF);
}

console.log('\n=== 9. 新输入会话重置 ===');
{
  const a = new Ability();
  a.hwCapsLock();
  eq('会话内 LOCKED', a.shift, ShiftState.LOCKED);
  a.caps.reset(); a.shiftHeld = false;   // onStartInputView 的行为
  eq('新会话从 OFF 开始（不继承物理锁定）', a.shift, ShiftState.OFF);
}

console.log('\n=== 10. 状态迁移完备性：任意序列后状态恒为三值之一 ===');
{
  const states = new Set(Object.values(ShiftState));
  let bad = 0;
  for (let seed = 0; seed < 300; seed++) {
    const a = new Ability();
    let now = 1000;
    for (let i = 0; i < 60; i++) {
      // 伪随机但可复现的序列
      const pick = (seed * 31 + i * 17) % 6;
      now += (seed * 7 + i * 13) % 250;
      switch (pick) {
        case 0: a.hwShiftDown(now); break;
        case 1: a.hwShiftUp(); break;
        case 2: a.hwCapsLock(); break;
        case 3: a.typeLetter(); break;
        case 4: a.softShiftDown(now); a.softShiftUp(false); break;
        default: break;
      }
      if (!states.has(a.shift)) bad++;
      // shiftHeld 与 caps 不得同时表示「按住且锁定」的矛盾
      if (a.shift === ShiftState.LOCKED && a.shiftHeld && a.caps.state !== ShiftState.LOCKED) bad++;
    }
  }
  eq('300 条随机序列 × 60 步：状态恒合法', bad, 0);
}

console.log('\n=== 11. 双击在任意时间戳下不会因时间倒退而误判 ===');
{
  const a = new Ability();
  a.hwShiftDown(5000);
  a.hwShiftUp();
  a.hwShiftDown(4000);   // now < lastTap：tap 内部有 now >= lastTap 守卫
  eq('时间倒退时不误锁（守卫 now >= lastTap 生效）', a.shift, ShiftState.ONCE);
}

console.log(`\n=== 结果：${fail === 0 ? '全部通过' : fail + ' 项失败'}（通过 ${pass}）===`);
process.exit(fail === 0 ? 0 : 1);
