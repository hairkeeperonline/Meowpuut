/**
 * Shift 与删除重复规则（对应 Android ime/KeyStates.kt，与 iOS 同规则）。
 */
import { ShiftState } from './Keys';

/** Shift：一次点击大写下一个字母，双击锁定。 */
export class Capitalization {
  private _state: ShiftState = ShiftState.OFF;
  private lastTap: number = -1;
  private manual: boolean = false;
  private declinedAutomatic: boolean = false;

  get state(): ShiftState { return this._state; }

  tap(now: number): void {
    if (this._state !== ShiftState.LOCKED && this.lastTap >= 0 && now >= this.lastTap &&
      now - this.lastTap <= Capitalization.DOUBLE_TAP_MS) {
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

  letterTyped(): void {
    if (this._state === ShiftState.ONCE) { this._state = ShiftState.OFF; this.manual = false; }
    this.lastTap = -1;
    this.declinedAutomatic = false;
  }

  applyAutomatic(capitalize: boolean): void {
    if (this._state === ShiftState.LOCKED) return;
    if (capitalize) {
      if (this._state === ShiftState.OFF && !this.declinedAutomatic) { this._state = ShiftState.ONCE; this.manual = false; }
    } else {
      this.declinedAutomatic = false;
      if (this._state === ShiftState.ONCE && !this.manual) this._state = ShiftState.OFF;
    }
  }

  reset(): void {
    this._state = ShiftState.OFF;
    this.manual = false;
    this.lastTap = -1;
    this.declinedAutomatic = false;
  }

  /**
   * 【round 65 ③】物理 CapsLock 同步：直接设置/取消锁定态，不走双击时序。
   * on=true → LOCKED（软键盘 shift 键显示锁定图标）；on=false 且当前 LOCKED → OFF。
   */
  setLocked(on: boolean): void {
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

  /**
   * 【round 65 ③】物理 Shift 松手复位：ONCE → OFF，但**保留 lastTap**。
   * 不能用 reset()——那会清掉 lastTap，导致「点一下松手、再点一下」永远
   * 凑不成双击、LOCKED 永远进不去。这里只撤销「松手后不应残留大写」的问题。
   */
  releaseShift(): void {
    if (this._state === ShiftState.ONCE) {
      this._state = ShiftState.OFF;
      this.manual = false;
    }
  }

  static readonly DOUBLE_TAP_MS = 300;
}

/** 按住删除的节奏。 */
export enum DeleteStep { CHARACTER, WORD, WAIT }

export class DeleteRepeat {
  static readonly INITIAL_DELAY_MS = 420;
  static readonly INTERVAL_MS = 83;
  static readonly WORD_THRESHOLD = 26;
  static readonly TICKS_PER_WORD = 3;

  static step(count: number): DeleteStep {
    if (count < DeleteRepeat.WORD_THRESHOLD) return DeleteStep.CHARACTER;
    if ((count - DeleteRepeat.WORD_THRESHOLD) % DeleteRepeat.TICKS_PER_WORD === 0) return DeleteStep.WORD;
    return DeleteStep.WAIT;
  }
}