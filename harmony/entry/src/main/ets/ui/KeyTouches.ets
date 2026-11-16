/**
 * 触控状态机（对应 Android ime/KeyTouches.kt，与 iOS 同规则，docs/DESIGN.md §6）。
 * 纯逻辑，不碰 UI；由 KeysView 喂入触点与定时器。
 */
import { Box, boxCenterX, boxRight } from './Geometry';
import { Key, KeyAction, KeyActionEngine, KeyActionText, KeyActionPage,
  KeyActionShift, KeyActionDelete, KeyActionSpace, KeySet, keyActionEquals } from './Keys';
import { KeyPlacement, AlternatesStrip } from './Geometry';
import { DeleteRepeat, DeleteStep } from './KeyStates';

export interface KeyListener {
  onKeyDown(key: Key): void;
  onKey(key: Key, text: string | null): void;
  onDelete(word: boolean): void;
  onShiftDown(): void;
  onShiftUp(typed: boolean): void;
  onPage(page: number): void;
  onCursorStart(): void;
  onCursorMove(steps: number): void;
  onCursorEnd(): void;
  onTick(): void;
}

export interface TouchHost {
  post(delayMs: number, action: () => void): number;
  cancel(id: number): void;
  showBalloon(id: number, key: Key, frame: Box): void;
  hideBalloon(id: number): void;
  showAlternates(strip: AlternatesStrip, options: string[], selected: number): void;
  selectAlternate(index: number): void;
  hideAlternates(): void;
  clearVisuals(): void;
  redraw(): void;
}

enum Mode { KEY, ALTERNATES, CURSOR, SHIFT, PAGE, DELETE, INERT }

/** keyAt 返回的命中结果（替代元组 [number, number]）。 */
class KeyHit {
  readonly row: number;
  readonly column: number;
  constructor(row: number, column: number) { this.row = row; this.column = column; }
}

class Pointer {
  id: number;
  row: number;
  column: number;
  key: Key;
  frame: Box;
  x: number;
  mode: Mode = Mode.KEY;
  committed: boolean = false;
  typed: boolean = false;
  slid: boolean = false;
  originPage: number = 0;
  holdId: number = -1;
  options: string[] = [];
  strip: AlternatesStrip | null = null;
  selected: number = 0;
  cursorAnchor: number = 0;
  cursorSteps: number = 0;

  constructor(id: number, row: number, column: number, key: Key, frame: Box, x: number) {
    this.id = id; this.row = row; this.column = column; this.key = key; this.frame = frame; this.x = x;
  }

  get pressing(): boolean {
    switch (this.mode) {
      case Mode.KEY: return !this.committed;
      case Mode.DELETE: return true;
      case Mode.SHIFT: case Mode.PAGE: return this.slid;
      default: return false;
    }
  }
}

export class KeyTouches {
  private host: TouchHost;
  listener: KeyListener | null = null;
  private keySet: KeySet | null = null;
  private placements: KeyPlacement[][] = [];
  private width: number = 0;
  private pointers: Map<number, Pointer> = new Map();
  private deleteRepeat: number = -1;
  /** 连删链的世代号（startDelete 自增、stopDelete 失活、tick 闭包校验）。 */
  private deleteRun: number = 0;
  private deleteCount: number = 0;
  private _cursorMode: boolean = false;

  constructor(host: TouchHost) { this.host = host; }

  get cursorMode(): boolean { return this._cursorMode; }
  get active(): boolean { return this.pointers.size > 0; }

  layout(set: KeySet, placements: KeyPlacement[][], width: number, sameShape: boolean): void {
    this.keySet = set;
    this.placements = placements;
    this.width = width;
    if (!sameShape) {
      this.pointers.forEach((p: Pointer) => {
        if (p.mode !== Mode.SHIFT && p.mode !== Mode.PAGE) {
          this.retire(p);
        } else if (p.slid) {
          this.host.hideBalloon(p.id);
          p.slid = false;
        }
      });
    } else {
      this.pointers.forEach((p: Pointer) => {
        if (!p.pressing) return;
        const current = this.keyOf(p.row, p.column);
        if (current === null) return;
        if (keyActionEquals(current.action, p.key.action) && current !== p.key) {
          p.key = current;
          this.showPressed(p);
        }
      });
    }
  }

  /**
   * 【下拉收起判定】当前是否有指针落在「按键」上（字符/删除/翻页等任意键）。
   * 下拉手势只要不是从按键上发起（缝隙、边距、候选栏空白处）就允许收起键盘。
   */
  anyPointerOnKey(): boolean {
    let on = false;
    this.pointers.forEach((p: Pointer) => {
      if (p.mode !== Mode.INERT && p.mode !== Mode.CURSOR) on = true;
    });
    return on;
  }

  isPressed(row: number, column: number): boolean {
    let found = false;
    this.pointers.forEach((p: Pointer) => {
      if (p.pressing && p.row === row && p.column === column) found = true;
    });
    return found;
  }

  private keyAt(x: number, y: number): KeyHit | null {
    for (let ri = 0; ri < this.placements.length; ri++) {
      const row = this.placements[ri];
      const first = row.length > 0 ? row[0] : null;
      if (first === null) continue;
      if (y < first.hitFrame.top || y >= first.hitFrame.bottom) continue;
      for (let ci = 0; ci < row.length; ci++) {
        const key = row[ci];
        if (x >= key.hitFrame.left && x < boxRight(key.hitFrame)) return new KeyHit(key.row, key.column);
      }
      const end = x < first.hitFrame.left ? first : row[row.length - 1];
      return new KeyHit(end.row, end.column);
    }
    return null;
  }

  private keyOf(row: number, column: number): Key | null {
    const r = this.keySet?.rows[row];
    return r ? r[column] ?? null : null;
  }

  private frameOf(row: number, column: number): Box | null {
    return this.placements[row]?.[column]?.frame ?? null;
  }

  down(id: number, x: number, y: number): void {
    const existing = this.pointers.get(id);
    if (existing !== undefined) this.retire(existing);
    this.pointers.delete(id);
    const hit = this.keyAt(x, y);
    if (hit === null) return;
    const row = hit.row;
    const column = hit.column;
    const key = this.keyOf(row, column);
    const frame = this.frameOf(row, column);
    if (key === null || frame === null) return;
    // 收集当前所有指针并提前提交（替代 [...this.pointers.values()]）。
    const earlierList: Pointer[] = [];
    this.pointers.forEach((p: Pointer) => { earlierList.push(p); });
    for (let i = 0; i < earlierList.length; i++) this.commitEarly(earlierList[i]);
    const p = new Pointer(id, row, column, key, frame, x);
    this.pointers.set(id, p);
    this.begin(p);
    this.host.redraw();
  }

  private begin(p: Pointer): void {
    const key = p.key;
    if (!key.enabled) { p.mode = Mode.INERT; return; }
    this.listener?.onKeyDown(key);
    const action = key.action;
    if (action instanceof KeyActionEngine || action instanceof KeyActionText) {
      this.showPressed(p);
      this.scheduleAlternates(p);
    } else if (action instanceof KeyActionSpace) {
      this.scheduleHold(p, KeyTouches.CURSOR_DELAY, () => this.enterCursor(p));
    } else if (action instanceof KeyActionDelete) {
      p.mode = Mode.DELETE;
      this.startDelete();
    } else if (action instanceof KeyActionShift) {
      p.mode = Mode.SHIFT;
      this.listener?.onShiftDown();
    } else if (action instanceof KeyActionPage) {
      p.mode = Mode.PAGE;
      p.originPage = this.keySet?.page ?? 0;
      this.listener?.onPage(action.page);
    }
  }

  private commitEarly(p: Pointer): void {
    if (p.committed || p.mode !== Mode.KEY || !p.key.rollsOver) return;
    this.cancelHold(p);
    this.host.hideBalloon(p.id);
    this.commit(p, null);
    p.mode = Mode.INERT;
  }

  move(id: number, x: number, y: number): void {
    const p = this.pointers.get(id);
    if (p === undefined) return;
    p.x = x;
    switch (p.mode) {
      case Mode.KEY: {
        if (p.committed || !p.key.isCharacter) return;
        const hit = this.keyAt(x, y);
        if (hit === null) return;
        const row = hit.row;
        const column = hit.column;
        if (row === p.row && column === p.column) return;
        const next = this.keyOf(row, column);
        if (next === null || !next.isCharacter || !next.enabled) return;
        p.row = row; p.column = column; p.key = next;
        const frame = this.frameOf(row, column);
        if (frame !== null) p.frame = frame;
        this.showPressed(p);
        this.scheduleAlternates(p);
        this.host.redraw();
        break;
      }
      case Mode.ALTERNATES: {
        const index = p.strip ? p.strip.indexAt(x) : -1;
        if (index < 0) return;
        if (index !== p.selected) {
          p.selected = index;
          this.host.selectAlternate(index);
          this.listener?.onTick();
        }
        break;
      }
      case Mode.CURSOR: this.moveCursor(p); break;
      case Mode.SHIFT: case Mode.PAGE: this.slide(p, x, y); break;
      default: break;
    }
  }

  private slide(p: Pointer, x: number, y: number): void {
    const hit = this.keyAt(x, y);
    const next = hit !== null ? this.keyOf(hit.row, hit.column) : null;
    if (hit !== null && next !== null && next.isCharacter && next.enabled) {
      if (p.slid && hit.row === p.row && hit.column === p.column && next === p.key) return;
      p.slid = true;
      p.row = hit.row; p.column = hit.column; p.key = next;
      const frame = this.frameOf(p.row, p.column);
      if (frame !== null) p.frame = frame;
      this.showPressed(p);
      this.host.redraw();
    } else if (p.slid) {
      this.host.hideBalloon(p.id);
      p.slid = false;
      this.host.redraw();
    }
  }

  up(id: number, x: number, y: number): void {
    const p = this.pointers.get(id);
    if (p === undefined) return;
    this.pointers.delete(id);
    p.x = x;
    this.cancelHold(p);
    this.host.hideBalloon(p.id);
    const mode = p.mode;
    switch (mode) {
      case Mode.KEY:
        if (!p.committed) {
          const hit = this.keyAt(x, y);
          const same = hit !== null && hit.row === p.row && hit.column === p.column;
          if (p.key.rollsOver || same) this.commit(p, null);
        }
        break;
      case Mode.ALTERNATES:
        this.host.hideAlternates();
        if (!p.committed) this.commit(p, p.options[p.selected] ?? null);
        break;
      case Mode.CURSOR:
        this._cursorMode = false;
        this.listener?.onCursorEnd();
        break;
      case Mode.DELETE: this.stopDelete(); break;
      case Mode.SHIFT:
        if (p.slid && !p.committed) this.commit(p, null);
        this.listener?.onShiftUp(p.typed);
        break;
      case Mode.PAGE:
        if (p.slid && !p.committed) {
          this.commit(p, null);
          this.listener?.onPage(p.originPage);
        }
        break;
      default: break;
    }
    p.mode = Mode.INERT;
    this.host.redraw();
  }

  private commit(p: Pointer, text: string | null): void {
    p.committed = true;
    const key = p.key;
    if (key.isCharacter) {
      if (p.mode === Mode.SHIFT) p.typed = true;
      this.pointers.forEach((other: Pointer) => {
        if (other.mode === Mode.SHIFT) other.typed = true;
      });
    }
    this.listener?.onKey(key, text);
  }

  private retire(p: Pointer): void {
    this.cancelHold(p);
    this.host.hideBalloon(p.id);
    const mode = p.mode;
    p.mode = Mode.INERT;
    switch (mode) {
      case Mode.ALTERNATES: this.host.hideAlternates(); break;
      case Mode.CURSOR:
        this._cursorMode = false;
        this.listener?.onCursorEnd();
        break;
      case Mode.DELETE: this.stopDelete(); break;
      case Mode.SHIFT: this.listener?.onShiftUp(p.typed); break;
      default: break;
    }
  }

  cancelAll(): void {
    // 收集所有指针再逐个 retire（替代 [...this.pointers.values()]）。
    const allPointers: Pointer[] = [];
    this.pointers.forEach((p: Pointer) => { allPointers.push(p); });
    for (let i = 0; i < allPointers.length; i++) this.retire(allPointers[i]);
    this.pointers.clear();
    this.stopDelete();
    this.host.clearVisuals();
    this.host.redraw();
  }

  private showPressed(p: Pointer): void {
    if (p.key.preview && p.key.isCharacter) this.host.showBalloon(p.id, p.key, p.frame);
    else this.host.hideBalloon(p.id);
  }

  private scheduleHold(p: Pointer, delay: number, action: () => void): void {
    this.cancelHold(p);
    const holdId = this.host.post(delay, () => {
      p.holdId = -1;
      if (this.pointers.get(p.id) === p && !p.committed && p.mode === Mode.KEY) action();
    });
    p.holdId = holdId;
  }

  private cancelHold(p: Pointer): void {
    if (p.holdId >= 0) this.host.cancel(p.holdId);
    p.holdId = -1;
  }

  private scheduleAlternates(p: Pointer): void {
    this.cancelHold(p);
    if (p.key.alternates.length > 0) {
      this.scheduleHold(p, KeyTouches.ALTERNATES_DELAY, () => this.openAlternates(p));
    }
  }

  private openAlternates(p: Pointer): void {
    const options = p.key.alternates;
    if (options.length === 0 || this.width <= 0) return;
    const strip = AlternatesStrip.fromKey(p.frame, options.length, this.width);
    this.host.hideBalloon(p.id);
    p.mode = Mode.ALTERNATES;
    p.options = options;
    p.strip = strip;
    p.selected = strip.indexAt(boxCenterX(p.frame));
    this.host.showAlternates(strip, options, p.selected);
    this.listener?.onTick();
    this.host.redraw();
  }

  private enterCursor(p: Pointer): void {
    p.mode = Mode.CURSOR;
    p.cursorAnchor = p.x;
    p.cursorSteps = 0;
    this._cursorMode = true;
    this.listener?.onCursorStart();
    this.listener?.onTick();
    this.host.redraw();
  }

  private moveCursor(p: Pointer): void {
    const steps = Math.min(512, Math.max(-512, Math.floor((p.x - p.cursorAnchor) / KeyTouches.CURSOR_STEP)));
    if (steps !== p.cursorSteps) {
      const delta = steps - p.cursorSteps;
      p.cursorSteps = steps;
      this.listener?.onCursorMove(delta);
    }
  }

  private startDelete(): void {
    this.stopDelete();
    this.deleteCount = 0;
    // 【真机反馈 round 60-6】世代计数器：旧实现把「定时器 id」当 runId 传进闭包，
    // 第一次重发后 deleteRepeat 已指向新定时器，下一拍 tick 里
    // `this.deleteRepeat !== runId` 恒成立直接 return —— 连删恰好只多触发一次
    // 就断链。改用单调递增的 run 世代：整条链共享同一个 run，deleteRepeat
    // 只用于 cancel 当前挂起的定时器，两者职责分离。
    this.deleteRun++;
    const run = this.deleteRun;
    this.deleteRepeat = this.host.post(DeleteRepeat.INITIAL_DELAY_MS, () => this.deleteTick(run));
    this.listener?.onDelete(false);
  }

  private deleteTick(run: number): void {
    if (this.deleteRun !== run) return;
    this.deleteCount++;
    switch (DeleteRepeat.step(this.deleteCount)) {
      case DeleteStep.CHARACTER: this.listener?.onDelete(false); break;
      case DeleteStep.WORD: this.listener?.onDelete(true); break;
      default: break;
    }
    if (this.deleteRun === run) {
      this.deleteRepeat = this.host.post(DeleteRepeat.INTERVAL_MS, () => this.deleteTick(run));
    }
  }

  private stopDelete(): void {
    if (this.deleteRepeat >= 0) this.host.cancel(this.deleteRepeat);
    this.deleteRepeat = -1;
    // 使任何在途闭包失活（cancel 掉的定时器若已入队也不再生效）。
    this.deleteRun++;
  }

  activate(row: number, column: number): void {
    const key = this.keyOf(row, column);
    if (key === null || !key.enabled) return;
    this.listener?.onKeyDown(key);
    const action = key.action;
    if (action instanceof KeyActionShift) {
      this.listener?.onShiftDown();
      this.listener?.onShiftUp(false);
    } else if (action instanceof KeyActionDelete) {
      this.listener?.onDelete(false);
    } else if (action instanceof KeyActionPage) {
      this.listener?.onPage(action.page);
    } else {
      this.listener?.onKey(key, null);
    }
  }

  static readonly ALTERNATES_DELAY = 450;
  static readonly CURSOR_DELAY = 400;
  static readonly CURSOR_STEP = 9;
}