/**
 * 猫咪的互动（对应 Android ime/Cats.kt）：连续抚摸切换简繁、抚摸动画。
 */
import { Cat } from './CatStage';

// ArkTS 不允许对象字面量作为类型声明，改用类层次。
export class CatOutcomePleased {
  readonly kind: string = 'pleased';
  readonly count: number;
  constructor(count: number) { this.count = count; }
}

export class CatOutcomeHappy {
  readonly kind: string = 'happy';
}

export class CatOutcomeResting {
  readonly kind: string = 'resting';
}

export type CatOutcome = CatOutcomePleased | CatOutcomeHappy | CatOutcomeResting;

export class CatAffection {
  private _pets: number = 0;
  private lastPet: number = -1;
  private restUntil: number = -1;

  get pets(): number { return this._pets; }

  pet(now: number): CatOutcome {
    if (this.restUntil >= 0 && now < this.restUntil) return new CatOutcomeResting();
    this.restUntil = -1;
    if (this.lastPet >= 0 && now - this.lastPet > CatAffection.WINDOW_MS) this._pets = 0;
    this.lastPet = now;
    this._pets++;
    if (this._pets < CatAffection.PETS_TO_SWITCH) return new CatOutcomePleased(this._pets);
    this._pets = 0;
    this.lastPet = -1;
    this.restUntil = now + CatAffection.REST_MS;
    return new CatOutcomeHappy();
  }

  static readonly PETS_TO_SWITCH = 5;
  static readonly WINDOW_MS = 1600;
  static readonly REST_MS = 1200;
}

export class CatMotion {
  readonly cat: Cat;
  readonly start: number;
  private timeScale: number;
  private span: number;

  constructor(cat: Cat, start: number, timeScale: number = 1) {
    this.cat = cat;
    this.start = start;
    this.timeScale = timeScale;
    this.span = cat === Cat.MIMIMO ? 520 : 560;
  }

  /** 返回一次动作的姿势（wide/tall/tilt），或 null（已结束）。 */
  pose(now: number): CatPose | null {
    const t = (now - this.start) / this.timeScale;
    if (t < 0 || t > this.span) return null;
    const pose = new CatPose();
    if (this.cat === Cat.MIMIMO) {
      pose.tall = CatMotion.track(t, CatMotion.DUCK_TIMES, CatMotion.DUCK_TALL, true);
      pose.wide = CatMotion.track(t, CatMotion.DUCK_TIMES, CatMotion.DUCK_WIDE, true);
      pose.tilt = CatMotion.track(t, CatMotion.SHAKE_TIMES, CatMotion.SHAKE, false);
    } else {
      pose.tall = CatMotion.track(t, CatMotion.LIFT_TIMES, CatMotion.LIFT, true);
      pose.tilt = CatMotion.track(t, CatMotion.NUZZLE_TIMES, CatMotion.NUZZLE, false);
    }
    return pose;
  }

  private static track(t: number, durations: number[], values: number[], spring: boolean): number {
    let elapsed = 0;
    for (let i = 0; i < durations.length; i++) {
      const d = durations[i];
      if (t <= elapsed + d) {
        const u = Math.min(1, Math.max(0, (t - elapsed) / d));
        const last = i === durations.length - 1;
        const eased = (last && spring)
          ? 1 - Math.exp(-6.0 * u) * Math.cos(1.6 * Math.PI * u)
          : (u * u * (3 - 2 * u));
        return values[i] + (values[i + 1] - values[i]) * eased;
      }
      elapsed += d;
    }
    return values[values.length - 1];
  }

  static readonly DUCK_TIMES = [80, 260, 180];
  static readonly DUCK_TALL = [1, 0.86, 0.88, 1];
  static readonly DUCK_WIDE = [1, 1.05, 1.04, 1];
  static readonly SHAKE_TIMES = [80, 100, 100, 90, 150];
  static readonly SHAKE = [0, -5, 4.5, -3, 1.5, 0];
  static readonly LIFT_TIMES = [170, 220, 170];
  static readonly LIFT = [1, 1.05, 1.04, 1];
  static readonly NUZZLE_TIMES = [170, 110, 110, 170];
  static readonly NUZZLE = [0, -6, -3.5, -6, 0];
}

export class CatPose {
  wide: number = 1;
  tall: number = 1;
  tilt: number = 0;
}