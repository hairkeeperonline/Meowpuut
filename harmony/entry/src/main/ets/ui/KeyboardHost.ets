/**
 * 键盘与输入法服务之间的桥。ability 在创建面板时把自己的回调挂进来，
 * KeyboardPage 从这里取用并渲染 MeowpuutKeyboard。
 */
import { KeyboardState } from './MeowpuutKeyboard';
import { Key } from './Keys';
import { resourceManager } from '@kit.LocalizationKit';

export class HostSnapshot {
  state: KeyboardState | null;
  token: number;
  reset: boolean;
  constructor(state: KeyboardState | null, token: number, reset: boolean) {
    this.state = state;
    this.token = token;
    this.reset = reset;
  }
}

export class PetSnapshot {
  cat: string;
  toast: string;
  /** 摸猫进度（0..PETS_TO_SWITCH-1）画爱心；-1 表示无进度（Happy/惰态）。 */
  hearts: number;
  token: number;
  constructor(cat: string, toast: string, hearts: number, token: number) {
    this.cat = cat;
    this.toast = toast;
    this.hearts = hearts;
    this.token = token;
  }
}

export class AnnounceSnapshot {
  text: string;
  token: number;
  constructor(text: string, token: number) {
    this.text = text;
    this.token = token;
  }
}

export interface KeyboardCallbacks {
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
  onCandidate(index: number): void;
  onPrediction(text: string): void;
  onPunctuation(mark: string): void;
  onToggleExpanded(): void;
  onPet(cat: string): void;
}

/** 键盘状态由 ability 写入，页面读取后渲染。 */
export class KeyboardHost {
  private static instance: KeyboardHost | null = null;

  static get(): KeyboardHost {
    if (KeyboardHost.instance === null) KeyboardHost.instance = new KeyboardHost();
    return KeyboardHost.instance;
  }

  callbacks: KeyboardCallbacks | null = null;
  resourceManager: resourceManager.ResourceManager | null = null;
  private state: KeyboardState | null = null;
  private refreshToken: number = 0;
  private resetFlag: boolean = false;
  private committedToken: number = 0;
  private petToken: number = 0;
  private petCat: string = '';
  private petToast: string = '';
  private petHearts: number = -1;
  private announceToken: number = 0;
  private announceText: string = '';

  /** ability 侧调用，把最新状态推给页面。 */
  push(state: KeyboardState, resetPanel: boolean): void {
    this.state = state;
    this.resetFlag = resetPanel;
    this.refreshToken++;
  }

  /** 组字提交后，米米莫低头摇头。 */
  commit(): void {
    this.committedToken++;
  }

  /** 摸猫：cat 为猫名字，toast 为提示文案（可能为空串），hearts 为进度爱心数（-1 无）。 */
  announceCat(cat: string, toast: string, hearts: number = -1): void {
    this.petCat = cat;
    this.petToast = toast;
    this.petHearts = hearts;
    this.petToken++;
  }

  announce(text: string): void {
    this.announceText = text;
    this.announceToken++;
  }

  /** 页面侧读取。 */
  take(): HostSnapshot {
    return new HostSnapshot(this.state, this.refreshToken, this.resetFlag);
  }

  takeCommitted(): number { return this.committedToken; }
  takePet(): PetSnapshot {
    return new PetSnapshot(this.petCat, this.petToast, this.petHearts, this.petToken);
  }
  takeAnnounce(): AnnounceSnapshot { return new AnnounceSnapshot(this.announceText, this.announceToken); }
}