/**
 * 软键盘面板页面（setUiContent 的目标）。渲染 MeowpuutKeyboard，
 * 触控动作经 KeyboardHost 回调回输入法服务。
 */
import { MeowpuutKeyboard } from '../ui/MeowpuutKeyboard';
import { KeyboardHost } from '../ui/KeyboardHost';
import { Key } from '../ui/Keys';

@Entry
@Component
struct KeyboardPage {
  private host: KeyboardHost = KeyboardHost.get();

  build() {
    Column() {
      MeowpuutKeyboard({
        onKeyDownEvt: (key: Key) => this.host.callbacks?.onKeyDown(key),
        onKeyEvt: (key: Key, text: string | null) => this.host.callbacks?.onKey(key, text),
        onDeleteEvt: (word: boolean) => this.host.callbacks?.onDelete(word),
        onShiftDownEvt: () => this.host.callbacks?.onShiftDown(),
        onShiftUpEvt: (typed: boolean) => this.host.callbacks?.onShiftUp(typed),
        onPageEvt: (page: number) => this.host.callbacks?.onPage(page),
        onCursorStartEvt: () => this.host.callbacks?.onCursorStart(),
        onCursorMoveEvt: (steps: number) => this.host.callbacks?.onCursorMove(steps),
        onCursorEndEvt: () => this.host.callbacks?.onCursorEnd(),
        onTickEvt: () => this.host.callbacks?.onTick(),
        onCandidateEvt: (index: number) => this.host.callbacks?.onCandidate(index),
        onPredictionEvt: (text: string) => this.host.callbacks?.onPrediction(text),
        onPunctuationEvt: (mark: string) => this.host.callbacks?.onPunctuation(mark),
        onToggleExpandedEvt: () => this.host.callbacks?.onToggleExpanded(),
        onPetEvt: (cat: string) => this.host.callbacks?.onPet(cat),
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}