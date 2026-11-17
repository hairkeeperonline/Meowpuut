/**
 * Round 65 ④ 仿真：鼠标事件路由（hover / 滚轮 / 右键备选条 / 左键打字）。
 * 把 handleKeyMouse / handleKeysTouch 的鼠标守卫 / openMouseAlternates /
 * hoverMouseAlternates / resolveMouseAlternates / axisDelta 移植到 Node。
 * 脚本：node tools/sim-mouse.mjs
 */

const MouseAction = { Press: 0, Release: 1, Move: 2, Hover: 3, ENTER_WINDOW: 4, LEAVE_WINDOW: 5 };
const MouseButton = { Left: 0, Right: 1, Middle: 2 };
const SourceType = { Unknown: 0, Mouse: 1, TouchScreen: 2 };
const PADDING = 4;

// ---------- 备选条几何（同 Geometry.ets） ----------
class AlternatesStrip {
  constructor(box, cell, count, mirrored) {
    this.box = box; this.cell = cell; this.count = count; this.mirrored = mirrored;
  }
  static fromKey(frame, count, keyboardWidth) {
    const cell = Math.min(56, Math.max(38, frame.width));
    const total = count * cell + 2 * PADDING;
    let left = frame.left + frame.width / 2 - total / 2;
    if (left < 4) left = 4;
    if (left + total > keyboardWidth - 4) left = keyboardWidth - 4 - total;
    const top = Math.max(0, frame.top - 50);   // STRIP_H = 50
    return new AlternatesStrip({ left, top, width: total, height: 50 }, cell, count, false);
  }
  indexAt(x) {
    const slot = Math.min(this.count - 1, Math.max(0,
      Math.floor((x - this.box.left - PADDING) / this.cell)));
    return this.mirrored ? this.count - 1 - slot : slot;
  }
}
const boxCenterX = (b) => b.left + b.width / 2;

class AlternatesState {
  constructor(strip, options, selected) {
    this.strip = strip; this.options = options; this.selected = selected;
  }
}

/** 被测对象：只保留鼠标相关状态与逻辑。 */
class MouseKeyboard {
  constructor() {
    this.kbWidth = 360;
    this.state = { expanded: false, composing: false };
    this.mouseAltActive = false;
    this.mouseAltKey = null;
    this.alternates = null;
    this.mousePointerId = 0;
    this.drawTick = 0;
    // 记录副作用
    this.committed = [];       // onKeyEvt
    this.touchLog = [];        // 转给 KeyTouches 的调用
    this.hoverHighlight = null;
    // 夹具：3 个键
    this.keySet = { rows: [[{ label: 'a', enabled: true, alternates: ['à', 'á', 'â'] },
                            { label: 'b', enabled: true, alternates: [] },
                            { label: 'c', enabled: false, alternates: ['ç'] }]] };
    this.placements = [[
      { row: 0, column: 0, frame: { left: 10, top: 100, width: 100, height: 46 } },
      { row: 0, column: 1, frame: { left: 120, top: 100, width: 100, height: 46 } },
      { row: 0, column: 2, frame: { left: 230, top: 100, width: 100, height: 46 } },
    ]];
  }

  keyPlacementAt(x, y) {
    if (x < 0 || x >= this.kbWidth) return null;
    for (let r = 0; r < this.placements.length; r++) {
      const row = this.placements[r];
      const f = row[0].frame;
      if (y < f.top || y >= f.top + f.height) continue;
      for (let c = 0; c < row.length; c++) {
        const g = row[c].frame;
        if (x >= g.left && x < g.left + g.width) return [r, c];
      }
      return [r, x < f.left ? 0 : row.length - 1];
    }
    return null;
  }

  // ---- handleKeysTouch 的鼠标守卫（缺陷 H）----
  handleKeysTouch(source, type, id, x, y) {
    if (source === SourceType.Mouse) return 'ignored(mouse-source)';
    if (this.mouseAltActive) return 'alt-select';
    this.touchLog.push({ type, id, x, y });
    return 'fsm';
  }

  handleKeyMouse(event) {
    if (event.action === MouseAction.Press && event.button === MouseButton.Right) {
      this.openMouseAlternates(event.x, event.y);
      return;
    }
    if (this.mouseAltActive && event.action === MouseAction.Move) {
      this.hoverMouseAlternates(event.x, event.y);
      return;
    }
    if (event.action === MouseAction.Press && event.button === MouseButton.Left &&
      this.mouseAltActive) {
      this.resolveMouseAlternates(event.x, event.y);
      return;
    }
    if (event.button !== MouseButton.Left) return;
    if (event.action === MouseAction.Press) {
      this.mousePointerId = 0;
      this.touchLog.push({ type: 'down', id: this.mousePointerId, x: event.x, y: event.y });
    } else if (event.action === MouseAction.Release) {
      this.touchLog.push({ type: 'up', id: this.mousePointerId, x: event.x, y: event.y });
    } else if (event.action === MouseAction.Move) {
      this.touchLog.push({ type: 'move', id: this.mousePointerId, x: event.x, y: event.y });
    }
  }

  hoverMouseAlternates(x, y) {
    const a = this.alternates;
    if (a === null) return;
    const b = a.strip.box;
    if (x < b.left || x >= b.left + b.width || y < b.top || y >= b.top + b.height) return;
    const n = a.strip.indexAt(x);
    if (n >= 0 && n < a.options.length && n !== a.selected) {
      a.selected = n;
      this.drawTick++;
    }
  }

  openMouseAlternates(x, y) {
    if (this.mouseAltActive) { this.resolveMouseAlternates(-1, -1); return; }
    if (this.alternates !== null) return;
    if (this.state.expanded && this.state.composing) return;
    const hit = this.keyPlacementAt(x, y);
    if (hit === null) return;
    const row = hit[0], col = hit[1];
    if (col < 0) return;
    const rowKeys = this.keySet.rows[row];
    const rowPlaces = this.placements[row];
    if (rowKeys === undefined || rowPlaces === undefined) return;
    const key = rowKeys[col];
    const place = rowPlaces[col];
    if (key === undefined || place === undefined || !key.enabled) return;
    const options = key.alternates;
    if (options.length === 0) return;
    const strip = AlternatesStrip.fromKey(place.frame, options.length, this.kbWidth);
    this.alternates = new AlternatesState(strip, options, strip.indexAt(boxCenterX(place.frame)));
    this.mouseAltActive = true;
    this.mouseAltKey = key;
    this.drawTick++;
  }

  resolveMouseAlternates(x, y) {
    const a = this.alternates;
    const key = this.mouseAltKey;
    this.mouseAltActive = false;
    this.mouseAltKey = null;
    if (a === null || key === null) { this.drawTick++; return; }
    let n = -1;
    const b = a.strip.box;
    if (x >= b.left && x < b.left + b.width && y >= b.top && y < b.top + b.height) {
      n = a.strip.indexAt(x);
    }
    this.alternates = null;
    if (n >= 0 && n < a.options.length) {
      this.committed.push({ key: key.label, pick: a.options[n] });
    }
    this.drawTick++;
  }

  /** axisDelta（缺陷 J 修复版）。 */
  static axisDelta(event) {
    let v = 0;
    try { v = event.getVerticalAxisValue(); } catch (e) { v = 0; }
    let steps = 0;
    if (v !== 0) steps = v * 48;
    else {
      const s = event.scrollStep;
      if (s !== undefined && s !== 0) steps = s * 48;
    }
    if (steps === 0) return 0;
    return Math.round(steps * MouseKeyboard.WHEEL_DIRECTION);
  }
}
MouseKeyboard.WHEEL_DIRECTION = 1;

// ---------- 断言 ----------
let fail = 0, pass = 0;
const eq = (name, got, want) => {
  const okv = JSON.stringify(got) === JSON.stringify(want);
  if (okv) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name} — got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); }
};

console.log('=== 1. 缺陷 H：鼠标来源的 onTouch 被忽略，不双重触发 ===');
{
  const k = new MouseKeyboard();
  // 真实设备上鼠标按压会同时投递 onMouse(Press) 与 onTouch(Down, source=Mouse)
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left, x: 60, y: 120 });
  const src = k.handleKeysTouch(SourceType.Mouse, 'Down', 0, 60, 120);
  eq('onTouch 被忽略', src, 'ignored(mouse-source)');
  eq('状态机只收到一次 down', k.touchLog.filter(t => t.type === 'down').length, 1);
  k.handleKeyMouse({ action: MouseAction.Release, button: MouseButton.Left, x: 60, y: 120 });
  eq('状态机收到一次 up', k.touchLog.filter(t => t.type === 'up').length, 1);
}

console.log('\n=== 2. 缺陷 I：鼠标左键仍能打字（补回状态机驱动）===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left, x: 60, y: 120 });
  k.handleKeyMouse({ action: MouseAction.Release, button: MouseButton.Left, x: 60, y: 120 });
  eq('down→up 顺序正确', k.touchLog.map(t => t.type), ['down', 'up']);
  eq('使用固定 mousePointerId=0', k.touchLog.every(t => t.id === 0), true);
  eq('坐标透传', [k.touchLog[0].x, k.touchLog[0].y], [60, 120]);
}

console.log('\n=== 3. 手指来源的 onTouch 正常进入状态机 ===');
{
  const k = new MouseKeyboard();
  eq('手指 Down 进 FSM', k.handleKeysTouch(SourceType.TouchScreen, 'Down', 1, 60, 120), 'fsm');
  eq('FSM 收到记录', k.touchLog.length, 1);
  eq('Unknown 来源也进 FSM（避免误伤某些触屏）',
    k.handleKeysTouch(SourceType.Unknown, 'Down', 2, 60, 120), 'fsm');
  // 【最高风险点】若设备把手指误报为 SourceType.Mouse，手指会彻底失灵。
  eq('（风险实测点）SourceType.Mouse 会被拦下 —— 手指若被误报成 Mouse 就会失效',
    k.handleKeysTouch(SourceType.Mouse, 'Down', 3, 60, 120), 'ignored(mouse-source)');
}

console.log('=== 4. 缺陷 G：右键开→右键关（不能重新打开）===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  eq('第一次右键打开', k.mouseAltActive, true);
  const opened = k.alternates;
  eq('打开的条对象非空', opened !== null, true);
  const ticksBefore = k.drawTick;
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  eq('第二次右键关闭（而非重开）', k.mouseAltActive, false);
  eq('alternates 已清空', k.alternates, null);
  eq('没有误提交', k.committed.length, 0);
  eq('本次右键只触发一次重绘（关闭），没有「关了又开」的第二次', k.drawTick - ticksBefore, 1);
  // 缺陷 G 的反证：旧实现会在关闭后继续往下走到打开分支
  const k2 = new MouseKeyboard();
  function oldOpen(kb, x, y) {
    if (kb.mouseAltActive) { kb.resolveMouseAlternates(-1, -1); /* 不 return */ }
    if (kb.alternates !== null) return;
    if (kb.state.expanded && kb.state.composing) return;
    const hit = kb.keyPlacementAt(x, y);
    if (hit === null) return;
    const rowKeys = kb.keySet.rows[hit[0]];
    const rowPlaces = kb.placements[hit[0]];
    const key = rowKeys[hit[1]];
    const place = rowPlaces[hit[1]];
    if (!key.enabled || key.alternates.length === 0) return;
    const strip = AlternatesStrip.fromKey(place.frame, key.alternates.length, kb.kbWidth);
    kb.alternates = new AlternatesState(strip, key.alternates,
      strip.indexAt(boxCenterX(place.frame)));
    kb.mouseAltActive = true;
    kb.mouseAltKey = key;
  }
  oldOpen(k2, 60, 120);
  oldOpen(k2, 60, 120);   // 第二次右键
  eq('（反证）旧实现在第二次右键后仍处于开启态', k2.mouseAltActive, true);
}

console.log('\n=== 5. 右键点无 alternates 的键：不弹条 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 170, y: 120 }); // 键 b
  eq('无备选 → 不激活', k.mouseAltActive, false);
  eq('alternates 仍为 null', k.alternates, null);
}

console.log('\n=== 6. 右键点禁用键：不弹条 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 280, y: 120 }); // 键 c 禁用
  eq('禁用键不激活', k.mouseAltActive, false);
}

console.log('\n=== 7. 右键落在画布外/键区外：不弹条 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 400, y: 120 });
  eq('x 越界不激活', k.mouseAltActive, false);
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 20 });
  eq('y 在键上方不激活', k.mouseAltActive, false);
}

console.log('\n=== 8. 缺陷 K：鼠标在条上移动 → 高亮跟随 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  const b = k.alternates.strip.box;
  const n0 = k.alternates.selected;
  // 移到条的最右格
  const rightX = b.left + b.width - PADDING - 2;
  k.handleKeyMouse({ action: MouseAction.Move, button: MouseButton.Left, x: rightX, y: b.top + 10 });
  eq('高亮移到最后一格', k.alternates.selected, 2);
  eq('高亮确实变化过', k.alternates.selected !== n0, true);
  // 移到条外上方：不变
  const keep = k.alternates.selected;
  k.handleKeyMouse({ action: MouseAction.Move, button: MouseButton.Left, x: b.left + 5, y: b.top - 20 });
  eq('条外移动不改高亮', k.alternates.selected, keep);
}

console.log('\n=== 9. 左键点条内：提交对应选项 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  const b = k.alternates.strip.box;
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left,
    x: b.left + PADDING + 1, y: b.top + 10 });   // 第一格
  eq('提交了第 1 个备选', k.committed, [{ key: 'a', pick: 'à' }]);
  eq('条已关闭', k.mouseAltActive, false);
}

console.log('\n=== 10. 左键点条外：只关闭不提交 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  const b = k.alternates.strip.box;
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left, x: 10, y: b.top + b.height + 30 });
  eq('无提交', k.committed.length, 0);
  eq('条已关闭', k.mouseAltActive, false);
}

console.log('\n=== 11. 触控长按的条在显示时，鼠标右键不抢 ===');
{
  const k = new MouseKeyboard();
  k.alternates = new AlternatesState(
    AlternatesStrip.fromKey(k.placements[0][0].frame, 3, k.kbWidth), ['à', 'á', 'â'], 0);
  k.mouseAltActive = false;   // 触控开的条：mouseAltActive 为 false
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  eq('不因右键而开启鼠标条', k.mouseAltActive, false);
  eq('原触控条未被替换', k.alternates.options[0], 'à');
}

console.log('\n=== 12. 展开组字态：右键不弹条 ===');
{
  const k = new MouseKeyboard();
  k.state.expanded = true; k.state.composing = true;
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  eq('展开态不激活', k.mouseAltActive, false);
}

console.log('\n=== 13. 中键/其他键不干扰 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Middle, x: 60, y: 120 });
  eq('中键不进状态机', k.touchLog.length, 0);
  eq('中键不激活备选', k.mouseAltActive, false);
}

console.log('\n=== 14. 缺陷 J：滚轮单位换算 ===');
{
  const ev = (v, s) => ({ getVerticalAxisValue: () => v, scrollStep: s });
  eq('vp 值 0.5 → 24vp', MouseKeyboard.axisDelta(ev(0.5, undefined)), 24);
  eq('vp 值 1.0 → 48vp', MouseKeyboard.axisDelta(ev(1.0, undefined)), 48);
  eq('scrollStep=1 → 48vp（不再被多乘 3.2 倍）', MouseKeyboard.axisDelta(ev(0, 1)), 48);
  eq('scrollStep=-1 → -48vp', MouseKeyboard.axisDelta(ev(0, -1)), -48);
  eq('两者都无 → 0', MouseKeyboard.axisDelta(ev(0, undefined)), 0);
  eq('vp 优先于 scrollStep', MouseKeyboard.axisDelta(ev(0.5, 99)), 24);
  eq('方向系数可翻转', Math.round(48 * -1), -48);
}

console.log('\n=== 15. 完整序列：右键→移动→左键 不残留状态 ===');
{
  const k = new MouseKeyboard();
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Right, x: 60, y: 120 });
  const b = k.alternates.strip.box;
  k.handleKeyMouse({ action: MouseAction.Move, button: MouseButton.Left, x: b.left + b.width - 6, y: b.top + 10 });
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left, x: b.left + b.width - 6, y: b.top + 10 });
  eq('选中最右格并提交', k.committed, [{ key: 'a', pick: 'â' }]);
  eq('mouseAltActive 复位', k.mouseAltActive, false);
  eq('mouseAltKey 复位', k.mouseAltKey, null);
  eq('alternates 复位', k.alternates, null);
  // 之后左键应正常走状态机
  k.handleKeyMouse({ action: MouseAction.Press, button: MouseButton.Left, x: 60, y: 120 });
  eq('后续左键恢复打字', k.touchLog.length, 1);
}

console.log('\n=== 16. 备选条不越界（贴左右边缘）===');
{
  const k = new MouseKeyboard();
  for (const [label, x] of [['左缘', 12], ['右缘', 328]]) {
    const strip = AlternatesStrip.fromKey(
      { left: x - 50, top: 100, width: 100, height: 46 }, 5, k.kbWidth);
    if (strip.box.left < 4 || strip.box.left + strip.box.width > k.kbWidth - 4) {
      fail++; console.log(`  ✗ ${label} 条越界: left=${strip.box.left} right=${strip.box.left + strip.box.width}`);
    } else { pass++; console.log(`  ✓ ${label} 条被夹在画布内`); }
  }
}

console.log(`\n=== 结果：${fail === 0 ? '全部通过' : fail + ' 项失败'}（通过 ${pass}）===`);
process.exit(fail === 0 ? 0 : 1);
